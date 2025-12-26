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
 * @package App\Service
 */

namespace App\Service;

use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Content\Product\ProductEntity;

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
     * Verwendung:
     *   $processor->processAllActiveProducts($context, function($product) {
     *       // Verarbeitung hier
     *   });
     *
     * @param Context $context Shopware-Kontext
     * @param callable $callback Callback-Funktion pro Produkt
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

            // Nur benoetigte Felder laden - spart Speicher!
            $criteria->addFields(['id', 'productNumber', 'name', 'stock']);

            $products = $this->productRepository->search($criteria, $context);

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
     * Verarbeitet nur Produkt-IDs (noch speicherschonender).
     *
     * Nuetzlich wenn Sie nur IDs fuer weitere Operationen brauchen,
     * z.B. fuer Message Queue Jobs.
     *
     * @param Context $context Shopware-Kontext
     * @param callable $callback Callback mit Produkt-ID als Parameter
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
            $criteria->addFilter(new EqualsFilter('active', true));

            // Filter direkt in der Criteria - effizienter als PHP-Filter
            $criteria->addFilter(
                new \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter(
                    'availableStock',
                    [
                        \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter::LTE => $threshold
                    ]
                )
            );

            $idResult = $this->productRepository->searchIds($criteria, $context);
            $allLowStockIds = array_merge($allLowStockIds, $idResult->getIds());

            $offset += self::BATCH_SIZE;

        } while (count($idResult->getIds()) === self::BATCH_SIZE);

        return $allLowStockIds;
    }
}
