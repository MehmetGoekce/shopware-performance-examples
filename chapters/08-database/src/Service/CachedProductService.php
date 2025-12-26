<?php

declare(strict_types=1);

/**
 * Beispiel: Query-Caching fuer teure Datenbank-Abfragen
 *
 * Shopware cached DAL-Queries automatisch, aber manchmal braucht man
 * explizites Caching fuer:
 * - Aggregierte Daten (z.B. "Top 10 Produkte")
 * - Berechnete Werte
 * - API-Responses die selten aendern
 *
 * WICHTIG: Cache Arrays, keine Entity-Objekte! Entities sind zu gross
 * und enthalten Referenzen die nicht serialisiert werden koennen.
 *
 * @package App\Service
 */

namespace App\Service;

use Psr\Cache\CacheItemPoolInterface;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting\FieldSorting;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;

class CachedProductService
{
    private const CACHE_TTL = 3600; // 1 Stunde

    public function __construct(
        private readonly EntityRepository $productRepository,
        private readonly CacheItemPoolInterface $cache,
        private readonly CacheInvalidator $cacheInvalidator
    ) {
    }

    /**
     * Holt die Top-Produkte mit Caching.
     *
     * Teure Query wird nur ausgefuehrt wenn Cache abgelaufen.
     * Cache-Key ist pro Sprache unterschiedlich.
     *
     * @param Context $context Shopware-Kontext
     * @param int $limit Anzahl Produkte
     * @return array<array{id: string, name: string, price: float|null}>
     */
    public function getTopProducts(Context $context, int $limit = 10): array
    {
        // Cache-Key pro Sprache und Sales Channel
        $cacheKey = sprintf(
            'top_products_%s_%s_%d',
            $context->getLanguageId(),
            $context->getSalesChannelId() ?? 'default',
            $limit
        );

        $cacheItem = $this->cache->getItem($cacheKey);

        if ($cacheItem->isHit()) {
            return $cacheItem->get();
        }

        // Teure Query ausfuehren
        $criteria = new Criteria();
        $criteria->setLimit($limit);
        $criteria->addFilter(new EqualsFilter('active', true));
        $criteria->addSorting(new FieldSorting('sales', FieldSorting::DESCENDING));

        // Nur Hauptbild laden, keine weiteren Relationen
        $criteria->addAssociation('cover.media');

        // Nur benoetigte Felder
        $criteria->addFields(['id', 'name', 'productNumber']);

        $products = $this->productRepository->search($criteria, $context);

        // Als Array cachen - NICHT als Entity-Objekte!
        $data = [];
        foreach ($products as $product) {
            $data[] = [
                'id' => $product->getId(),
                'name' => $product->getName(),
                'productNumber' => $product->getProductNumber(),
                'coverUrl' => $product->getCover()?->getMedia()?->getUrl(),
            ];
        }

        // Cache mit Tags fuer gezielte Invalidierung
        $cacheItem->set($data);
        $cacheItem->expiresAfter(self::CACHE_TTL);
        $cacheItem->tag(['product', 'top-products', 'product-listing']);

        $this->cache->save($cacheItem);

        return $data;
    }

    /**
     * Holt Kategorie-Statistiken mit Caching.
     *
     * Berechnet Produktanzahl pro Kategorie - teuer ohne Cache!
     *
     * @param string $categoryId Kategorie-ID
     * @param Context $context Shopware-Kontext
     * @return array{productCount: int, avgPrice: float, inStock: int}
     */
    public function getCategoryStats(string $categoryId, Context $context): array
    {
        $cacheKey = sprintf('category_stats_%s_%s', $categoryId, $context->getLanguageId());
        $cacheItem = $this->cache->getItem($cacheKey);

        if ($cacheItem->isHit()) {
            return $cacheItem->get();
        }

        // Aggregationen direkt in der Datenbank - effizienter als PHP!
        $criteria = new Criteria();
        $criteria->addFilter(new EqualsFilter('categories.id', $categoryId));
        $criteria->addFilter(new EqualsFilter('active', true));

        // Aggregation statt alle Produkte laden
        $criteria->addAggregation(
            new \Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric\CountAggregation(
                'product_count',
                'id'
            )
        );
        $criteria->addAggregation(
            new \Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric\AvgAggregation(
                'avg_price',
                'price'
            )
        );

        // Keine Entities laden - nur Aggregationen!
        $criteria->setLimit(1);

        $result = $this->productRepository->search($criteria, $context);

        $stats = [
            'productCount' => $result->getAggregations()->get('product_count')?->getCount() ?? 0,
            'avgPrice' => $result->getAggregations()->get('avg_price')?->getAvg() ?? 0.0,
        ];

        // In-Stock Count separat (komplexerer Filter)
        $inStockCriteria = new Criteria();
        $inStockCriteria->addFilter(new EqualsFilter('categories.id', $categoryId));
        $inStockCriteria->addFilter(new EqualsFilter('active', true));
        $inStockCriteria->addFilter(
            new \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter(
                'availableStock',
                [\Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter::GT => 0]
            )
        );

        $stats['inStock'] = $this->productRepository->searchIds($inStockCriteria, $context)->getTotal();

        // Cache mit Kategorie-Tag
        $cacheItem->set($stats);
        $cacheItem->expiresAfter(self::CACHE_TTL);
        $cacheItem->tag(['product', 'category-' . $categoryId, 'category-stats']);

        $this->cache->save($cacheItem);

        return $stats;
    }

    /**
     * Invalidiert den Cache wenn Produkte geaendert werden.
     *
     * Rufen Sie diese Methode auf wenn Sie Produkte programmatisch aendern.
     *
     * @param array<string> $productIds Geaenderte Produkt-IDs
     */
    public function invalidateProductCache(array $productIds): void
    {
        // Allgemeine Produkt-Tags invalidieren
        $tags = ['top-products', 'category-stats'];

        // Spezifische Produkt-Tags
        foreach ($productIds as $id) {
            $tags[] = 'product-' . $id;
        }

        $this->cacheInvalidator->invalidate($tags);
    }
}
