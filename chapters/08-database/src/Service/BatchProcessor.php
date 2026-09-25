<?php

declare(strict_types=1);

/**
 * Batch-Verarbeitung fuer grosse Datenmengen in Shopware 6
 *
 * Dieses Service demonstriert, wie man grosse Datenmengen effizient
 * verarbeitet, ohne den Speicher zu ueberlasten.
 *
 * Performance-Hinweise:
 * - Batch-Groesse von 500 ist ein guter Startwert
 * - gc_collect_cycles() zwischen Batches gibt Speicher frei
 * - searchIds() statt search() wenn nur IDs benoetigt werden
 *
 * Warum jede Schleife hier addSorting() setzt: die DAL erzeugt ohne
 * ausdrueckliche Sortierung kein ORDER BY, und LIMIT/OFFSET ohne ORDER BY gibt
 * in MySQL keine stabile Reihenfolge zurueck. Bei nebenlaeufigen Schreibzugriffen
 * verarbeitet eine solche Schleife Zeilen doppelt oder ueberspringt sie. Sortiert
 * wird nach id, weil der Wert eindeutig und unveraenderlich ist - eine Sortierung
 * nach name oder stock waere nicht eindeutig und damit auch nicht stabil.
 *
 * @package App\Service
 */

namespace App\Service;

use Shopware\Core\Content\Product\ProductEntity;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting\FieldSorting;

class BatchProcessor
{
    /**
     * Batch-Groesse: 500 ist ein guter Kompromiss zwischen
     * Speicherverbrauch und Datenbank-Roundtrips
     */
    private const BATCH_SIZE = 500;

    public function __construct(
        private readonly EntityRepository $productRepository
    ) {
    }

    /**
     * Verarbeitet alle aktiven Produkte in Batches.
     *
     * Der Callback bekommt eine vollstaendige ProductEntity. Bewusst ohne
     * Criteria::addFields(): sobald das gesetzt ist, hydriert die DAL
     * PartialEntity statt ProductEntity, und die Klasse kennt kein __call -
     * ein $product->getName() im Callback endet dann in
     * "Call to undefined method". Wer wirklich nur einzelne Skalarfelder
     * braucht, nimmt processAllProductFields() weiter unten.
     *
     * Verwendung:
     *   $processor->processAllActiveProducts($context, function(ProductEntity $product) {
     *       // Verarbeitung hier
     *   });
     *
     * @param Context $context Shopware-Kontext
     * @param callable(ProductEntity): void $callback Callback-Funktion pro Produkt
     * @return int Anzahl verarbeiteter Produkte
     */
    public function processAllActiveProducts(Context $context, callable $callback): int
    {
        $offset = 0;
        $processed = 0;

        do {
            $criteria = new Criteria();
            $criteria->setLimit(self::BATCH_SIZE);
            $criteria->setOffset($offset);
            $criteria->addFilter(new EqualsFilter('active', true));
            $criteria->addSorting(new FieldSorting('id', FieldSorting::ASCENDING));

            $products = $this->productRepository->search($criteria, $context);

            /** @var ProductEntity $product */
            foreach ($products as $product) {
                $callback($product);
                $processed++;
            }

            $offset += self::BATCH_SIZE;

            // Memory freigeben zwischen Batches
            gc_collect_cycles();

        } while ($products->count() === self::BATCH_SIZE);

        return $processed;
    }

    /**
     * Wie processAllActiveProducts(), laedt aber nur die angegebenen Felder.
     *
     * Spart Speicher, kostet dafuer die typisierten Getter: der Callback
     * bekommt eine PartialEntity und liest ueber get('feldname'). Assoziationen
     * stehen hier NICHT zur Verfuegung - mit addFields() liefert etwa
     * get('cover') zuverlaessig null, auch wenn addAssociation() gesetzt waere.
     *
     * @param array<string> $fields Felder, z.B. ['id', 'productNumber', 'stock']
     * @param Context $context Shopware-Kontext
     * @param callable(\Shopware\Core\Framework\DataAbstractionLayer\PartialEntity): void $callback
     * @return int Anzahl verarbeiteter Produkte
     */
    public function processAllProductFields(array $fields, Context $context, callable $callback): int
    {
        $offset = 0;
        $processed = 0;

        do {
            $criteria = new Criteria();
            $criteria->setLimit(self::BATCH_SIZE);
            $criteria->setOffset($offset);
            $criteria->addFilter(new EqualsFilter('active', true));
            $criteria->addSorting(new FieldSorting('id', FieldSorting::ASCENDING));
            $criteria->addFields($fields);

            $products = $this->productRepository->search($criteria, $context);

            /** @var \Shopware\Core\Framework\DataAbstractionLayer\PartialEntity $product */
            foreach ($products as $product) {
                $callback($product);
                $processed++;
            }

            $offset += self::BATCH_SIZE;
            gc_collect_cycles();

        } while ($products->count() === self::BATCH_SIZE);

        return $processed;
    }

    /**
     * Verarbeitet nur Produkt-IDs (noch speicherschonender).
     *
     * Nuetzlich wenn Sie nur IDs fuer weitere Operationen brauchen,
     * z.B. fuer Message Queue Jobs.
     *
     * @param Context $context Shopware-Kontext
     * @param callable(string): void $callback Callback mit Produkt-ID als Parameter
     * @return int Anzahl verarbeiteter IDs
     */
    public function processAllProductIds(Context $context, callable $callback): int
    {
        $offset = 0;
        $processed = 0;

        do {
            $criteria = new Criteria();
            $criteria->setLimit(self::BATCH_SIZE);
            $criteria->setOffset($offset);
            $criteria->addSorting(new FieldSorting('id', FieldSorting::ASCENDING));

            // searchIds() statt search() - viel weniger Speicher!
            $idResult = $this->productRepository->searchIds($criteria, $context);

            foreach ($idResult->getIds() as $id) {
                $callback($id);
                $processed++;
            }

            $offset += self::BATCH_SIZE;

            gc_collect_cycles();

        } while (count($idResult->getIds()) === self::BATCH_SIZE);

        return $processed;
    }

    /**
     * Batch-Update fuer viele Produkte.
     *
     * Sammelt Updates und schreibt sie in einem Batch statt einzeln.
     * Wichtig: Cache-Invalidierung erfolgt automatisch am Ende.
     *
     * @param array<array{id: string, data: array<string, mixed>}> $updates Array von Updates
     * @param Context $context Shopware-Kontext
     */
    public function batchUpdate(array $updates, Context $context): void
    {
        // Updates in Batches aufteilen
        $batches = array_chunk($updates, self::BATCH_SIZE);

        foreach ($batches as $batch) {
            $updateData = array_map(
                fn(array $update) => array_merge(['id' => $update['id']], $update['data']),
                $batch
            );

            $this->productRepository->update($updateData, $context);

            gc_collect_cycles();
        }
    }

    /**
     * Beispiel: Alle Produkte mit niedrigem Bestand finden.
     *
     * Demonstriert effiziente Aggregation statt alle Entities zu laden.
     *
     * Bei sehr grossen Katalogen wird OFFSET zunehmend teuer, weil MySQL die
     * uebersprungenen Zeilen trotzdem liest. Dann besser per Keyset blaettern:
     * statt setOffset() einen RangeFilter auf die zuletzt gesehene id setzen.
     *
     * @param int $threshold Bestandsschwelle
     * @param Context $context Shopware-Kontext
     * @return array<string> Produkt-IDs mit niedrigem Bestand
     */
    public function findLowStockProductIds(int $threshold, Context $context): array
    {
        $allLowStockIds = [];
        $offset = 0;

        do {
            $criteria = new Criteria();
            $criteria->setLimit(self::BATCH_SIZE);
            $criteria->setOffset($offset);
            $criteria->addSorting(new FieldSorting('id', FieldSorting::ASCENDING));
            $criteria->addFilter(new EqualsFilter('active', true));

            // Filter direkt in der Criteria - effizienter als PHP-Filter
            $criteria->addFilter(new RangeFilter('availableStock', [RangeFilter::LTE => $threshold]));

            $idResult = $this->productRepository->searchIds($criteria, $context);
            $allLowStockIds = array_merge($allLowStockIds, $idResult->getIds());

            $offset += self::BATCH_SIZE;

        } while (count($idResult->getIds()) === self::BATCH_SIZE);

        return $allLowStockIds;
    }
}
