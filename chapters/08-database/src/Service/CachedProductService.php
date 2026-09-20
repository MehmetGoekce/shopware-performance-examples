<?php

declare(strict_types=1);

/**
 * Beispiel: Caching fuer teure Datenbank-Abfragen
 *
 * Shopware 6.6 cached KEINE DAL-Queries pro Criteria. Die gecachte
 * Entity-Repository-Schicht wurde mit 6.5 entfernt; gecacht wird auf Ebene der
 * Store-API-Routen (Cached*Route-Dekoratoren) und im HTTP-Cache. Wer ein
 * Ergebnis zwischenspeichern will, das keiner Store-API-Route entspricht, muss
 * das selbst tun - dafuer ist diese Klasse das Beispiel:
 * - Aggregierte Daten (z.B. "Top 10 Produkte")
 * - Berechnete Werte
 * - API-Responses die selten aendern
 *
 * WICHTIG: Cache Arrays, keine Entity-Objekte! Entities sind zu gross
 * und enthalten Referenzen die nicht serialisiert werden koennen.
 *
 * Der Cache-Pool ist als TagAwareCacheInterface typisiert, nicht als
 * CacheItemPoolInterface: tag() gibt es nur auf Symfonys CacheItem, und
 * CacheItemPoolInterface::getItem() verspricht nur ein Psr\Cache\CacheItemInterface.
 * Mit dem falschen Typehint schlaegt die statische Analyse an, und zur Laufzeit
 * haengt es daran, welcher Service tatsaechlich injiziert wurde.
 *
 * @package App\Service
 */

namespace App\Service;

use Shopware\Core\Content\Product\ProductEntity;
use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric\AvgAggregation;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric\CountAggregation;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting\FieldSorting;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Symfony\Component\Cache\CacheItem;
use Symfony\Contracts\Cache\TagAwareCacheInterface;
use Psr\Cache\CacheItemPoolInterface;

class CachedProductService
{
    private const CACHE_TTL = 3600; // 1 Stunde

    public function __construct(
        private readonly EntityRepository $productRepository,
        private readonly CacheItemPoolInterface&TagAwareCacheInterface $cache,
        private readonly CacheInvalidator $cacheInvalidator
    ) {
    }

    /**
     * Holt die Top-Produkte mit Caching.
     *
     * Teure Query wird nur ausgefuehrt wenn Cache abgelaufen.
     * Cache-Key ist pro Sprache und Sales Channel unterschiedlich.
     *
     * Erwartet einen SalesChannelContext, nicht den allgemeinen Context:
     * getSalesChannelId() gibt es nur dort. Auf
     * Shopware\Core\Framework\Context aufgerufen ist es ein Fatal Error.
     *
     * @param SalesChannelContext $context Storefront-Kontext
     * @param int $limit Anzahl Produkte
     * @return array<array{id: string, name: string|null, productNumber: string|null, coverUrl: string|null}>
     */
    public function getTopProducts(SalesChannelContext $context, int $limit = 10): array
    {
        $cacheKey = sprintf(
            'top_products_%s_%s_%d',
            $context->getContext()->getLanguageId(),
            $context->getSalesChannelId(),
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

        // Hier steht bewusst KEIN $criteria->addFields([...]).
        // addFields() hat zwei Folgen, die zu dieser Methode nicht passen:
        // 1. Die DAL hydriert dann PartialEntity statt ProductEntity. Die Klasse
        //    kennt nur __get() und get(), aber kein __call - jeder getName()-
        //    Aufruf endet in "Call to undefined method".
        // 2. Geladene Associations fallen weg: mit addFields() liefert
        //    $product->get('cover') zuverlaessig null, das Hauptbild waere also
        //    gar nicht da.
        // Wer wirklich nur Skalarfelder braucht, nimmt addFields() UND liest
        // ausschliesslich ueber get('feldname') - dann aber ohne Associations.

        $products = $this->productRepository->search($criteria, $context->getContext());

        // Als Array cachen - NICHT als Entity-Objekte!
        $data = [];
        /** @var ProductEntity $product */
        foreach ($products as $product) {
            $data[] = [
                'id' => $product->getId(),
                'name' => $product->getTranslation('name'),
                'productNumber' => $product->getProductNumber(),
                'coverUrl' => $product->getCover()?->getMedia()?->getUrl(),
            ];
        }

        $cacheItem->set($data);
        $cacheItem->expiresAfter(self::CACHE_TTL);
        if ($cacheItem instanceof CacheItem) {
            $cacheItem->tag(['product', 'top-products', 'product-listing']);
        }

        $this->cache->save($cacheItem);

        return $data;
    }

    /**
     * Holt Kategorie-Statistiken mit Caching.
     *
     * Berechnet Produktanzahl und Durchschnittspreis pro Kategorie.
     *
     * Verwendet aggregate() statt search(): aggregate() hydriert ueberhaupt
     * keine Entities. Ein setLimit(1) mit search() laedt dagegen EINE Entity -
     * "keine Entities laden" waere dafuer die falsche Beschreibung.
     *
     * @param string $categoryId Kategorie-ID
     * @param SalesChannelContext $context Storefront-Kontext
     * @return array{productCount: int, avgPrice: float, inStock: int}
     */
    public function getCategoryStats(string $categoryId, SalesChannelContext $context): array
    {
        $cacheKey = sprintf(
            'category_stats_%s_%s',
            $categoryId,
            $context->getContext()->getLanguageId()
        );
        $cacheItem = $this->cache->getItem($cacheKey);

        if ($cacheItem->isHit()) {
            return $cacheItem->get();
        }

        $criteria = new Criteria();
        $criteria->addFilter(new EqualsFilter('categories.id', $categoryId));
        $criteria->addFilter(new EqualsFilter('active', true));
        $criteria->addAggregation(new CountAggregation('product_count', 'id'));
        $criteria->addAggregation(new AvgAggregation('avg_price', 'price'));

        $aggregations = $this->productRepository->aggregate($criteria, $context->getContext());

        $stats = [
            'productCount' => $aggregations->get('product_count')?->getCount() ?? 0,
            'avgPrice' => $aggregations->get('avg_price')?->getAvg() ?? 0.0,
        ];

        // In-Stock Count separat (komplexerer Filter). searchIds() laedt
        // ebenfalls keine Entities, nur IDs.
        $inStockCriteria = new Criteria();
        $inStockCriteria->addFilter(new EqualsFilter('categories.id', $categoryId));
        $inStockCriteria->addFilter(new EqualsFilter('active', true));
        $inStockCriteria->addFilter(new RangeFilter('availableStock', [RangeFilter::GT => 0]));

        $stats['inStock'] = $this->productRepository
            ->searchIds($inStockCriteria, $context->getContext())
            ->getTotal();

        $cacheItem->set($stats);
        $cacheItem->expiresAfter(self::CACHE_TTL);
        if ($cacheItem instanceof CacheItem) {
            $cacheItem->tag(['product', 'category-' . $categoryId, 'category-stats']);
        }

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
