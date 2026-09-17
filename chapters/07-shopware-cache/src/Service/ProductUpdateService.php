<?php

declare(strict_types=1);

/**
 * Cache-Invalidierung bei Produkt-Updates
 * Kapitel 7: Shopwares Application Cache meistern
 *
 * Zwei Wege, Produkte zu ändern:
 *
 * 1. Über das Repository (Admin, API, Import über den DAL):
 *    Shopware invalidiert selbst, synchron im schreibenden Request.
 *    Eigene Tags sind nicht nötig.
 *
 * 2. Direkt per SQL (z. B. schneller Bestandsabgleich aus dem ERP):
 *    Shopware bekommt davon nichts mit. Gecachte Seiten und Store-API-Antworten
 *    zeigen den alten Stand, bis ihre Lebensdauer abläuft. Deshalb hier die
 *    Tags selbst invalidieren - dieselben, die Shopware 6.6 bei einer
 *    Produktänderung verwendet (CacheInvalidationSubscriber):
 *      product-<id>                        Seiten/Routen, die das Produkt enthalten
 *      product-detail-route-<id|parentId>  Produktdetail (Varianten: auch Parent)
 *      product-review-route-<id>           Bewertungen
 *      product-listing-route-<categoryId>  Listings aller zugeordneten Kategorien
 *      product-stream-<streamId>           Listings/Cross-Selling aus Dynamischen Produktgruppen
 *      product-search-route, product-suggest-route
 *    Tags wie "product-listing", "price" oder "stock" gibt es nicht.
 *
 * CacheInvalidator leert cache.object und cache.http und schickt die Tags an
 * einen konfigurierten Reverse Proxy (Varnish, Kapitel 6).
 * Mit shopware.cache.invalidation.delay > 0 werden die Tags nur gesammelt;
 * $force = true invalidiert trotzdem sofort.
 *
 * Gilt für Shopware 6.6. Mit 6.7 entfallen die Cached*Route-Klassen, dieser
 * Code läuft dort nicht mehr. Shopware 6.7 invalidiert Produkte über das Event
 * Shopware\Core\Content\Product\Events\InvalidateProductCache
 * (CacheInvalidationSubscriber::invalidateProduct). In 6.6 deckt dieses Event
 * ohne Feature-Flag CACHE_REWORK nur Listings, Detailseite und Streams ab.
 *
 * Installation (in einem eigenen Plugin, Namespace "YourPlugin" anpassen):
 *   1. Kopieren nach src/Service/ProductUpdateService.php
 *   2. Service registrieren: src/Resources/config/services.xml aus diesem Ordner
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\Service;

use Doctrine\DBAL\ArrayParameterType;
use Doctrine\DBAL\Connection;
use Shopware\Core\Content\Product\SalesChannel\Detail\CachedProductDetailRoute;
use Shopware\Core\Content\Product\SalesChannel\Listing\CachedProductListingRoute;
use Shopware\Core\Content\Product\SalesChannel\Review\CachedProductReviewRoute;
use Shopware\Core\Defaults;
use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\Cache\EntityCacheKeyGenerator;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\Uuid\Uuid;

class ProductUpdateService
{
    public function __construct(
        private readonly EntityRepository $productRepository,
        private readonly Connection $connection,
        private readonly CacheInvalidator $cacheInvalidator
    ) {
    }

    /**
     * Weg 1: Bestand über das Repository ändern.
     * Shopware invalidiert die passenden Tags selbst.
     */
    public function updateStock(string $productId, int $stock, Context $context): void
    {
        $this->productRepository->update([
            ['id' => $productId, 'stock' => $stock],
        ], $context);
    }

    /**
     * Weg 2: Bestand direkt per SQL ändern und danach selbst invalidieren.
     *
     * @param array<int|string, int> $stockByProductId Produkt-ID (hex) => neuer Bestand
     *        (int|string: PHP macht rein numerische Keys zu int)
     */
    public function updateStockViaSql(array $stockByProductId): void
    {
        foreach ($stockByProductId as $productId => $stock) {
            $this->connection->executeStatement(
                'UPDATE product SET stock = :stock, available_stock = :stock
                 WHERE id = :id AND version_id = :version',
                [
                    'stock' => $stock,
                    'id' => Uuid::fromHexToBytes((string) $productId),
                    'version' => Uuid::fromHexToBytes(Defaults::LIVE_VERSION),
                ]
            );
        }

        // Einmal für alle Produkte invalidieren, nicht pro Zeile
        $this->invalidateProducts(array_map('strval', array_keys($stockByProductId)));
    }

    /**
     * @param list<string> $productIds Produkt-IDs (hex)
     */
    public function invalidateProducts(array $productIds, bool $force = false): void
    {
        if ($productIds === []) {
            return;
        }

        $ids = Uuid::fromHexToBytesList($productIds);
        $version = Uuid::fromHexToBytes(Defaults::LIVE_VERSION);

        /** @var list<string> $parentIds */
        $parentIds = $this->connection->fetchFirstColumn(
            'SELECT DISTINCT LOWER(HEX(parent_id)) FROM product
             WHERE id IN (:ids) AND parent_id IS NOT NULL AND version_id = :version',
            ['ids' => $ids, 'version' => $version],
            ['ids' => ArrayParameterType::BINARY]
        );

        /** @var list<string> $categoryIds */
        $categoryIds = $this->connection->fetchFirstColumn(
            'SELECT DISTINCT LOWER(HEX(category_id)) FROM product_category_tree
             WHERE product_id IN (:ids) AND product_version_id = :version AND category_version_id = :version',
            ['ids' => $ids, 'version' => $version],
            ['ids' => ArrayParameterType::BINARY]
        );

        /** @var list<string> $streamIds */
        $streamIds = $this->connection->fetchFirstColumn(
            'SELECT DISTINCT LOWER(HEX(product_stream_id)) FROM product_stream_mapping
             WHERE product_id IN (:ids) AND product_version_id = :version',
            ['ids' => $ids, 'version' => $version],
            ['ids' => ArrayParameterType::BINARY]
        );

        $tags = [
            ...array_map(EntityCacheKeyGenerator::buildProductTag(...), $productIds),
            ...array_map(CachedProductDetailRoute::buildName(...), [...$parentIds, ...$productIds]),
            ...array_map(CachedProductReviewRoute::buildName(...), $productIds),
            ...array_map(CachedProductListingRoute::buildName(...), $categoryIds),
            ...array_map(EntityCacheKeyGenerator::buildStreamTag(...), $streamIds),
            'product-search-route',
            'product-suggest-route',
        ];

        $this->cacheInvalidator->invalidate($tags, $force);
    }
}
