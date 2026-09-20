<?php

declare(strict_types=1);

/**
 * Custom-Fields im Produkt-Mapping typisieren
 * Kapitel 18: Shopware 6 mit Elasticsearch
 *
 * Das Event betrifft ausschliesslich Custom Fields. Es landet unter
 * customFields.<languageId>.<name> — beliebige Felder auf oberster Ebene
 * lassen sich damit NICHT anlegen.
 *
 * Die Namen unten sind Namen von Custom Fields, nicht die gleichnamigen
 * Produktfelder. Das Produkt hat ean und manufacturerNumber bereits auf
 * oberster Ebene; was hier gesetzt wird, ist ein Custom Field, das zufaellig
 * denselben Namen traegt.
 *
 * setMapping(string $field, string $type): $type ist eine
 * CustomFieldTypes::*-Konstante, KEIN Elasticsearch-Typ. Shopware uebersetzt
 * in CustomFieldUpdater::getTypeFromCustomFieldType():
 *
 *   INT -> long | FLOAT -> double | BOOL -> boolean | DATETIME -> date
 *   TEXT|HTML -> keyword + .search/.ngram | PRICE|JSON -> object
 *   alles andere -> derselbe keyword-Block
 *
 * Falle: 'integer' ist keine Konstante und faellt still in den
 * default-Zweig (bricht Range und Sortierung). Richtig ist
 * CustomFieldTypes::INT (Wert 'int'). Eine keyword-Konstante gibt es nicht;
 * der Literal-String 'keyword' funktioniert nur ueber denselben
 * default-Zweig — das ist das De-facto-Muster der Community, kein
 * typisierter Vertrag.
 *
 * Was der default-Zweig erzeugt, ist kein nacktes keyword-Feld, sondern
 * KEYWORD_FIELD + SEARCH_FIELD: keyword mit sw_lowercase_normalizer plus die
 * Subfelder .search (sw_whitespace_analyzer) und .ngram (sw_ngram_analyzer).
 * Gemessen am angelegten Index, nicht nur am Quelltext.
 *
 * Die Event-Klasse traegt @internal. Sie ist der Weg, den die Shopware-
 * Entwicklerdoku zeigt, steht aber nicht unter Rueckwaertskompatibilitaets-
 * Garantie — beim Versionssprung nachsehen.
 *
 * Getestet mit Shopware 6.6.10.6 und Elasticsearch 8.15.3.
 *
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/elasticsearch/extending-elasticsearch
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\ElasticsearchExtension;

use Shopware\Core\Content\Product\ProductDefinition;
use Shopware\Core\System\CustomField\CustomFieldTypes;
use Shopware\Elasticsearch\Event\ElasticsearchCustomFieldsMappingEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class ProductMappingExtension implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            ElasticsearchCustomFieldsMappingEvent::class => 'onProductMapping',
        ];
    }

    /**
     * Wirksam beim Anlegen des Index, also beim naechsten
     * `bin/console es:index`.
     *
     * Nicht wirksam dagegen, wenn spaeter ein Custom Field angelegt wird:
     * CustomFieldUpdater haengt es an die bestehenden Indizes an und liest
     * dafuer den Typ direkt aus der Datenbank (mapCustomFieldsToEsTypes),
     * ohne dieses Event zu feuern. Das Feld traegt dann den DB-Typ, nicht
     * den hier gesetzten — bis zum naechsten Reindex.
     */
    public function onProductMapping(ElasticsearchCustomFieldsMappingEvent $event): void
    {
        if ($event->getEntity() !== ProductDefinition::ENTITY_NAME) {
            return;
        }

        // Eigene Sortiernummer -> ES "long" (Range und Sortierung)
        $event->setMapping('customSortValue', CustomFieldTypes::INT);

        // Zeichenketten fuer den exakten Treffer -> keyword-Block ueber den
        // default-Zweig.
        $event->setMapping('productNumberExact', 'keyword');
        $event->setMapping('ean', 'keyword');
        $event->setMapping('manufacturerNumber', 'keyword');
        $event->setMapping('searchKeywords', 'keyword');

        // Bewertung als Ganzzahl (0-500 fuer 0.0-5.0) -> ES "long"
        $event->setMapping('ratingScaled', CustomFieldTypes::INT);
    }
}
