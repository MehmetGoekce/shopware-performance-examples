<?php

declare(strict_types=1);

/**
 * Eigene Analyzer in Shopwares Elasticsearch-Index bringen
 * Kapitel 18: Shopware 6 mit Elasticsearch
 *
 * Das Event heisst ElasticsearchIndexConfigEvent. Einen String
 * 'elasticsearch.index.settings' gibt es in Shopware nicht — ein Subscriber
 * darauf wird nie aufgerufen, und zwar ohne Fehlermeldung.
 * (Indexing/IndexCreator.php:61 dispatcht genau dieses Event, mit dem
 * kompletten Request-Body als $config.)
 *
 * Der Body sieht so aus:
 *
 *   ['settings' => ['index' => [...], 'analysis' => [...]], 'mappings' => [...]]
 *
 * Deshalb wird hier unter settings.analysis gemerged, nicht unter analysis.
 * Gemerged wird je Abschnitt (analyzer/filter/char_filter), nicht rekursiv:
 * array_merge_recursive wuerde aus zwei gleichnamigen Filterlisten eine
 * verkettete Liste machen. Shopwares eigene sw_*-Eintraege muessen erhalten
 * bleiben — fehlt sw_lowercase_normalizer, scheitert die Index-Erstellung an
 * «normalizer [sw_lowercase_normalizer] not found».
 *
 * ZWEITER SCHRITT, ohne den das hier folgenlos bleibt: Ein definierter
 * Analyzer wird von nichts benutzt. Shopware legt das .search-Subfeld je
 * Sprache an und waehlt den Analyzer ueber elasticsearch.language_analyzer_mapping
 * (ElasticsearchFieldBuilder.php:45-46). Also zusaetzlich in
 * config/packages/elasticsearch.yaml:
 *
 *   elasticsearch:
 *       language_analyzer_mapping:
 *           de: german_analyzer
 *
 * Der Schluessel ist der Sprachteil des Locale-Codes (de-DE -> de).
 *
 * NICHT enthalten: ein phonetischer Filter. `"type": "phonetic"` braucht das
 * Plugin analysis-phonetic; ohne das Plugin antwortet ES mit
 * «Unknown filter type [phonetic]» (gemessen, HTTP 400) — und weil dieser
 * Subscriber bei JEDER Index-Erstellung laeuft, scheitert dann jedes
 * `bin/console es:index`, nicht nur eine Suche.
 *
 * Getestet mit Shopware 6.6.10.6 und Elasticsearch 8.15.3.
 *
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/elasticsearch/extending-elasticsearch
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\ElasticsearchExtension;

use Shopware\Core\Content\Product\ProductDefinition;
use Shopware\Elasticsearch\Framework\Indexing\Event\ElasticsearchIndexConfigEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class CustomAnalyzerDefinition implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            ElasticsearchIndexConfigEvent::class => 'onIndexConfig',
        ];
    }

    /**
     * Ergaenzt die Analyse-Einstellungen, bevor der Index angelegt wird.
     *
     * Analyse-Einstellungen sind statisch: An einem offenen Index laesst sich
     * kein neuer Analyzer setzen (HTTP 400). Wirksam wird das hier also erst
     * beim naechsten `bin/console es:index` — Shopware legt dabei ohnehin
     * einen neuen Index <alias>_<timestamp> an.
     */
    public function onIndexConfig(ElasticsearchIndexConfigEvent $event): void
    {
        // Ohne diese Bremse landen die Analyzer auch im Admin-Index und in
        // jedem Index, den ein anderes Plugin registriert.
        if ($event->getDefinition()->getEntityDefinition()->getEntityName() !== ProductDefinition::ENTITY_NAME) {
            return;
        }

        $config = $event->getConfig();
        $analysis = $config['settings']['analysis'] ?? [];

        foreach ($this->getAnalysisSettings() as $section => $entries) {
            $analysis[$section] = array_merge($analysis[$section] ?? [], $entries);
        }

        $config['settings']['analysis'] = $analysis;

        $event->setConfig($config);
    }

    /**
     * @return array<string, array<string, array<string, mixed>>>
     */
    private function getAnalysisSettings(): array
    {
        return [
            'analyzer' => [
                // Deutscher Volltext-Analyzer fuer das .search-Subfeld.
                // Shopwares eigener sw_german_analyzer tokenisiert auf
                // whitespace und filtert nur Stoppwoerter — hier kommen
                // Normalisierung (ae/oe/ue/ss) und Stemming dazu.
                'german_analyzer' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                        'german_stop',
                        'german_normalization',
                        'german_stemmer',
                    ],
                ],

                // Autocomplete: Edge-N-Gramme beim Indexieren ...
                'autocomplete_analyzer' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                        'autocomplete_filter',
                    ],
                ],

                // ... und bewusst OHNE N-Gramme beim Suchen. Sonst wird auch
                // die Eingabe zerlegt und jedes Praefix matcht jedes Praefix.
                // Braucht im Mapping search_analyzer: autocomplete_search.
                'autocomplete_search' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                    ],
                ],

                // Exakter Treffer ohne Ruecksicht auf Gross-/Kleinschreibung:
                // ein Token pro Feldwert.
                'keyword_lowercase' => [
                    'type' => 'custom',
                    'tokenizer' => 'keyword',
                    'filter' => [
                        'lowercase',
                        'trim',
                    ],
                ],
            ],

            'filter' => [
                'german_stop' => [
                    'type' => 'stop',
                    'stopwords' => '_german_',
                ],

                // light_german stemmt vorsichtiger als german/minimal_german
                // und verliert dabei weniger Bedeutung.
                'german_stemmer' => [
                    'type' => 'stemmer',
                    'language' => 'light_german',
                ],

                // 2-15 Zeichen: darunter matcht fast alles, darueber waechst
                // der Index ohne Nutzen fuer die Eingabe im Suchschlitz.
                'autocomplete_filter' => [
                    'type' => 'edge_ngram',
                    'min_gram' => 2,
                    'max_gram' => 15,
                    'preserve_original' => true,
                ],

                // Synonyme sind absichtlich NICHT in einer Analyzer-Kette
                // verdrahtet: Index-Zeit-Synonyme erzwingen einen Reindex bei
                // jeder Listenaenderung. Wer sie braucht, haengt diesen Filter
                // an einen search_analyzer, nicht an den Index-Analyzer.
                'german_synonyms' => [
                    'type' => 'synonym',
                    'synonyms' => [
                        'notebook, laptop, mobilrechner',
                        'handy, smartphone, mobiltelefon',
                        'fernseher, tv, television',
                        'kuehlschrank, kuehlgeraet',
                        'drucker, printer',
                        'maus, mouse',
                        'tastatur, keyboard',
                    ],
                ],
            ],

            'char_filter' => [
                // Ersetzt Umlaute vor der Tokenisierung. Alternative zu
                // german_normalization, nicht Ergaenzung — beides zusammen
                // ist doppelt gemoppelt.
                'umlaut_mapping' => [
                    'type' => 'mapping',
                    'mappings' => [
                        'ä => ae',
                        'ö => oe',
                        'ü => ue',
                        'ß => ss',
                    ],
                ],
            ],
        ];
    }
}
