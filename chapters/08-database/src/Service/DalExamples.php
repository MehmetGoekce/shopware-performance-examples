<?php

declare(strict_types=1);

/**
 * DAL-Beispiele aus Kapitel 8, Abschnitt 8.5 - jeweils SCHLECHT und BESSER
 *
 * Das Kapitel zeigt die vier Paare als Ausschnitte. Diese Klasse ist ihre
 * Quelle: jede Codezeile dieser vier Buch-Snippets steht hier, und das
 * Snippet-Gate haelt das Kapitel dagegen. Gemessen gegen Shopware 6.6.10.6
 * (Dockware, Demo-Daten).
 *
 * Einbau: Namespace an Ihr Plugin anpassen (App\ laedt in einem Plugin nicht)
 * und die Klasse als Service mit dem Argument product.repository registrieren.
 *
 * Die SCHLECHT-Methoden sind absichtlich schlecht: Sie laden den ganzen
 * Katalog ohne Limit. Nicht in Produktion aufrufen - sie stehen hier, damit
 * das Paar im selben Shop gegeneinander laufen kann.
 *
 * Was gemessen ist (Kapitel 8):
 * - addFields() liefert PartialEntity: get('feld') geht, jeder Getter, den erst
 *   ProductEntity mitbringt (getProductNumber, getName, getCover), wirft
 *   "Error: Call to undefined method" - zur Laufzeit, nicht beim Deployment.
 *   getId() und getTranslation() stammen aus Entity und funktionieren. Bei
 *   Varianten ist get('name') null: ohne Vererbungs-Kontext erbt nichts.
 * - Fuenf addAssociation() ohne Limit erzeugen 5 Queries: die Hauptquery und
 *   je eine fuer prices, media, properties, categories (MySQL-General-Log).
 *   Mit setLimit() kommt eine ID-Query davor; hat keins der geladenen
 *   Produkte Eintraege in einer Tabelle, entfaellt deren Query.
 * - aggregate() hydriert keine Entity; search() mit setLimit(1) eine.
 * - searchIds()->getIds() liefert dieselben IDs wie search()->getIds(), aber
 *   als Liste; search()->getIds() ist nach ID geschluesselt.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace App\Service;

use Shopware\Core\Content\Product\ProductCollection;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric\CountAggregation;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\EntitySearchResult;

class DalExamples
{
    /**
     * @param EntityRepository<ProductCollection> $productRepository
     */
    public function __construct(
        private readonly EntityRepository $productRepository
    ) {
    }

    // ------------------------------------------------------------------
    // Criteria richtig nutzen
    // ------------------------------------------------------------------

    public function alleFelderLaden(Context $context): EntitySearchResult
    {
        // SCHLECHT: Laedt alle Felder und Relationen
        $criteria = new Criteria();
        $products = $this->productRepository->search($criteria, $context);

        return $products;
    }

    public function nurBenoetigteFelder(Context $context): EntitySearchResult
    {
        // BESSER: Nur benoetigte Daten laden
        $criteria = new Criteria();
        $criteria->setLimit(50);
        $criteria->addFields(['id', 'productNumber', 'name']);
        // Keine Associations laden, wenn nicht benoetigt!

        $products = $this->productRepository->search($criteria, $context);

        return $products;
    }

    /**
     * Wirft beim ersten Produkt: Error: Call to undefined method
     * ...\PartialEntity::getProductNumber(). Genau das zeigt das Kapitel.
     */
    public function typisierteGetterNachAddFields(EntitySearchResult $products): void
    {
        // ACHTUNG: ab jetzt KEINE typisierten Getter mehr
        foreach ($products as $product) {
            $product->get('productNumber');   // funktioniert
            $product->getProductNumber();     // Error: Call to undefined method
        }
    }

    // ------------------------------------------------------------------
    // Associations vermeiden
    // ------------------------------------------------------------------

    public function vieleAssociations(Context $context): EntitySearchResult
    {
        // SCHLECHT: jede Association kostet - aber nicht als JOIN
        $criteria = new Criteria();
        $criteria->addAssociation('categories');
        $criteria->addAssociation('manufacturer');
        $criteria->addAssociation('media');
        $criteria->addAssociation('prices');
        $criteria->addAssociation('properties');
        // -> gemessen: 5 Queries, nicht 5 JOINs

        return $this->productRepository->search($criteria, $context);
    }

    public function nurHauptbild(Context $context): EntitySearchResult
    {
        // BESSER: Nur laden was noetig ist
        $criteria = new Criteria();
        $criteria->addAssociation('cover'); // Nur das Hauptbild

        return $this->productRepository->search($criteria, $context);
    }

    /**
     * @param list<string> $productIds bereits bekannte IDs
     */
    public function gezieltMitIds(array $productIds, Context $context): EntitySearchResult
    {
        // ODER: Lazy Loading vermeiden mit gezielten Queries
        $criteria = new Criteria($productIds);
        $criteria->addAssociation('manufacturer');
        // -> Ein Query statt N Queries

        return $this->productRepository->search($criteria, $context);
    }

    // ------------------------------------------------------------------
    // Aggregationen effizient nutzen
    // ------------------------------------------------------------------

    public function zaehlenInPhp(Context $context): int
    {
        // SCHLECHT: Alle Produkte laden und in PHP zaehlen
        $criteria = new Criteria();
        $products = $this->productRepository->search($criteria, $context);
        $count = $products->count();

        return $count;
    }

    public function zaehlenInDatenbank(Context $context): int
    {
        // BESSER: COUNT direkt in der Datenbank, ganz ohne Entities
        $criteria = new Criteria();
        $criteria->addAggregation(
            new CountAggregation('product_count', 'id')
        );

        $aggregations = $this->productRepository->aggregate($criteria, $context);
        $count = $aggregations->get('product_count')->getCount();

        return $count;
    }

    // ------------------------------------------------------------------
    // IDs statt Entities verwenden
    // ------------------------------------------------------------------

    /**
     * @return array<string, string> nach ID geschluesselt
     */
    public function idsUeberEntities(Context $context): array
    {
        // SCHLECHT: Ganze Entities laden fuer ID-Liste
        $criteria = new Criteria();
        $products = $this->productRepository->search($criteria, $context);
        $ids = $products->getIds();

        return $ids;
    }

    /**
     * @return list<string>
     */
    public function idsDirekt(Context $context): array
    {
        // BESSER: searchIds() nutzt weniger Speicher
        $criteria = new Criteria();
        $ids = $this->productRepository->searchIds($criteria, $context)->getIds();

        return $ids;
    }
}
