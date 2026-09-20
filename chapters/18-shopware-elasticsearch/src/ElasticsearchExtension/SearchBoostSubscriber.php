<?php

declare(strict_types=1);

/**
 * Relevanz beeinflussen, ohne dass es folgenlos bleibt
 * Kapitel 18: Shopware 6 mit Elasticsearch
 *
 * ERSTER WEG, und fuer Feld-Gewichte der richtige: Die Gewichte stehen in der
 * Datenbank, nicht im Code. SearchConfigLoader liest
 * product_search_config_field.ranking, ProductSearchQueryBuilder macht daraus
 * den ES-`boost` je Feld (TokenQueryBuilder.php:123-146: Match auf <feld>.search
 * mit boost = ranking, Prefix-Match mit 0.6 * ranking, .ngram mit 0.4 * ranking).
 * Gepflegt wird das im Admin unter Einstellungen > Shop > Suche. Wer nur
 * "Name wichtiger als Beschreibung" will, braucht dafuer keinen Code.
 *
 * ZWEITER WEG, dieser hier: Was sich als Feld-Gewicht nicht ausdruecken laesst
 * — etwa "die exakt eingegebene Artikelnummer ganz nach oben". Dafuer gibt es
 * ElasticsearchEntitySearcherSearchEvent. Es traegt das fertige Search-Objekt,
 * bevor der Request rausgeht (ElasticsearchEntitySearcher.php:59-73), und
 * Aenderungen daran landen im Query.
 *
 * WAS NICHT FUNKTIONIERT: eine Criteria-Extension anhaengen
 * ($criteria->addExtension('customSearchBoost', ...)). Es gibt in Shopware
 * keinen Code, der sie liest — weder ElasticsearchHelper noch CriteriaParser
 * noch TokenQueryBuilder. Die Extension faehrt mit und wird verworfen; die
 * Suche sieht danach exakt so aus wie vorher. Der Aufruf kostet nichts und
 * bewirkt nichts, und genau deshalb faellt es niemandem auf.
 *
 * DIE FALLE BEI SHOULD: Eine SHOULD-Klausel ist nur dann ein Boost, wenn im
 * selben bool schon eine MUST-Klausel steht. Ohne MUST setzt Elasticsearch
 * minimum_should_match auf 1 — die Klausel genuegt dann allein, und die Suche
 * findet jedes Produkt, auf das sie zutrifft. Hier ist der Term-Query von
 * Shopware die MUST-Klausel (gemessen: `{"bool":{"must":[...],"should":[...]}}`
 * ohne minimum_should_match), deshalb ist der Zusatz reine Bewertung. Wer
 * diesen Code auf einen anderen Einstiegspunkt umhaengt, muss das nachpruefen.
 *
 * Getestet mit Shopware 6.6.10.6 und Elasticsearch 8.15.3.
 *
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/elasticsearch/extending-elasticsearch
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\ElasticsearchExtension;

use OpenSearchDSL\Query\Compound\BoolQuery;
use OpenSearchDSL\Query\TermLevel\TermQuery;
use Shopware\Core\Content\Product\ProductDefinition;
use Shopware\Elasticsearch\Framework\DataAbstractionLayer\Event\ElasticsearchEntitySearcherSearchEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class SearchBoostSubscriber implements EventSubscriberInterface
{
    /**
     * Die Zahl ist relativ zu den Rankings aus dem Admin. Die Vorgabe einer
     * frischen 6.6-Installation (product_search_config_field.ranking):
     * productNumber 1000, customSearchKeywords 800, name 700,
     * manufacturerNumber/ean/manufacturer.name je 500. 5000 hebt den exakten
     * Treffer damit deutlich ueber jeden Teiltreffer.
     */
    private const BOOST_PRODUCT_NUMBER_EXACT = 5000.0;

    /**
     * Lieferbare Produkte leicht bevorzugen. Bewusst klein: ein grosser Wert
     * hier schlaegt die Textrelevanz und sortiert am Suchbegriff vorbei.
     */
    private const BOOST_AVAILABLE = 1.5;

    public static function getSubscribedEvents(): array
    {
        return [
            ElasticsearchEntitySearcherSearchEvent::class => 'onSearch',
        ];
    }

    public function onSearch(ElasticsearchEntitySearcherSearchEvent $event): void
    {
        if ($event->getDefinition()->getEntityName() !== ProductDefinition::ENTITY_NAME) {
            return;
        }

        $term = trim((string) $event->getCriteria()->getTerm());

        // Ohne Suchbegriff ist das hier ein Listing (Kategorie, Filter,
        // Store-API-Abfrage). Dort gibt es keine MUST-Textklausel, an die
        // sich ein SHOULD anhaengen liesse — siehe die Falle oben.
        if ($term === '') {
            return;
        }

        $search = $event->getSearch();

        // productNumber ist ein keyword-Feld mit sw_lowercase_normalizer.
        // Der Term-Query wird NICHT analysiert; der Vergleichswert muss
        // deshalb selbst klein geschrieben sein, sonst trifft er nie.
        $search->addQuery(
            new TermQuery('productNumber', mb_strtolower($term), ['boost' => self::BOOST_PRODUCT_NUMBER_EXACT]),
            BoolQuery::SHOULD
        );

        // `available` pflegt Shopware selbst (Bestand und isCloseout);
        // `stock` waere die rohe Zahl und im Closeout-Fall irrefuehrend.
        $search->addQuery(
            new TermQuery('available', true, ['boost' => self::BOOST_AVAILABLE]),
            BoolQuery::SHOULD
        );
    }
}
