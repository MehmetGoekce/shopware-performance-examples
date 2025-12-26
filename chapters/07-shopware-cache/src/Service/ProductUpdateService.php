<?php

declare(strict_types=1);

/**
 * Beispiel: Programmatische Cache-Invalidierung in Shopware 6
 *
 * Dieses Service demonstriert, wie man den Cache gezielt invalidiert,
 * wenn Produkte programmtisch aktualisiert werden (z.B. durch Import).
 *
 * @package App\Service
 */

namespace App\Service;

use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;

class ProductUpdateService
{
    public function __construct(
        private readonly EntityRepository $productRepository,
        private readonly CacheInvalidator $cacheInvalidator
    ) {
    }

    /**
     * Aktualisiert ein Produkt und invalidiert den zugehoerigen Cache.
     *
     * Wichtig: Shopware invalidiert bei normalen Repository-Updates automatisch.
     * Diese manuelle Invalidierung ist nur noetig bei:
     * - Direkten Datenbank-Updates (SQL)
     * - Externen System-Updates
     * - Batch-Importen mit verzoegerter Cache-Invalidierung
     *
     * @param string $productId Die Produkt-ID
     * @param array<string, mixed> $data Die zu aktualisierenden Daten
     * @param Context $context Der Shopware-Context
     */
    public function updateProduct(string $productId, array $data, Context $context): void
    {
        // Produkt aktualisieren
        $this->productRepository->update([
            array_merge(['id' => $productId], $data)
        ], $context);

        // Cache gezielt invalidieren
        // Nur noetig wenn automatische Invalidierung nicht greift
        $this->invalidateProductCache($productId);
    }

    /**
     * Aktualisiert mehrere Produkte mit optimierter Cache-Invalidierung.
     *
     * Bei Massenimporten: Erst alle Produkte aktualisieren,
     * dann Cache einmal invalidieren (nicht pro Produkt).
     *
     * @param array<array<string, mixed>> $products Array von Produktdaten mit 'id'
     * @param Context $context Der Shopware-Context
     */
    public function bulkUpdateProducts(array $products, Context $context): void
    {
        // Alle Produkt-IDs sammeln
        $productIds = array_column($products, 'id');

        // Batch-Update (ohne automatische Cache-Invalidierung pro Item)
        $this->productRepository->update($products, $context);

        // Einmalige Cache-Invalidierung fuer alle betroffenen Produkte
        $this->invalidateBulkProductCache($productIds);
    }

    /**
     * Invalidiert den Cache fuer ein einzelnes Produkt.
     *
     * Tags die invalidiert werden:
     * - product-{id}: Produktdetailseite
     * - product-listing: Kategorie-Listings (optional, siehe Kommentar)
     */
    private function invalidateProductCache(string $productId): void
    {
        $tags = [
            'product-' . $productId,
        ];

        // Optional: Listings nur invalidieren wenn sich Sortier-relevante
        // Felder geaendert haben (Preis, Name, Verfuegbarkeit)
        // $tags[] = 'product-listing';

        $this->cacheInvalidator->invalidate($tags);
    }

    /**
     * Invalidiert den Cache fuer mehrere Produkte effizient.
     *
     * Bei vielen Produkten (>100) kann es sinnvoller sein,
     * nur 'product-listing' zu invalidieren statt einzelne Tags.
     *
     * @param array<string> $productIds Liste der Produkt-IDs
     */
    private function invalidateBulkProductCache(array $productIds): void
    {
        // Bei vielen Produkten: Nur Listing-Cache invalidieren
        if (count($productIds) > 100) {
            $this->cacheInvalidator->invalidate([
                'product-listing',
                'navigation',  // Falls Kategoriezaehler betroffen
            ]);
            return;
        }

        // Bei wenigen Produkten: Gezielte Invalidierung
        $tags = array_map(
            static fn(string $id): string => 'product-' . $id,
            $productIds
        );

        $this->cacheInvalidator->invalidate($tags);
    }

    /**
     * Prueft ob ein Produkt im Cache ist.
     *
     * Nuetzlich fuer Debugging und Monitoring.
     *
     * @param string $productId Die Produkt-ID
     * @param Context $context Der Shopware-Context
     * @return bool True wenn gecacht, false wenn Cache-Miss
     */
    public function isProductCached(string $productId, Context $context): bool
    {
        // Simplified: Repository-Cache pruefen via Criteria
        $criteria = new Criteria([$productId]);

        // Erster Aufruf: Potentiell Cache-Miss
        $start = microtime(true);
        $this->productRepository->search($criteria, $context);
        $firstCall = microtime(true) - $start;

        // Zweiter Aufruf: Sollte Cache-Hit sein
        $start = microtime(true);
        $this->productRepository->search($criteria, $context);
        $secondCall = microtime(true) - $start;

        // Wenn zweiter Aufruf deutlich schneller, war erster ein Cache-Miss
        return $secondCall < ($firstCall * 0.5);
    }
}
