<?php

declare(strict_types=1);

namespace PerformanceExamples\Service;

use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Psr\Log\LoggerInterface;

/**
 * Proaktiver Cache-Warmer für kritische Seiten
 *
 * Kapitel 6-8: HTTP-Cache & Application Cache
 *
 * Verwendung:
 *   bin/console performance:cache:warm
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
class CacheWarmer
{
    public function __construct(
        private readonly EntityRepository $productRepository,
        private readonly EntityRepository $categoryRepository,
        private readonly CacheInvalidator $cacheInvalidator,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Wärmt den Cache für die wichtigsten Produktseiten vor
     *
     * Performance-Tipp: Nur die Top-Produkte vorwärmen,
     * nicht das gesamte Sortiment.
     */
    public function warmProductCache(Context $context, int $limit = 100): int
    {
        $criteria = new Criteria();
        $criteria->setLimit($limit);
        // Nur aktive Produkte
        $criteria->addFilter(new \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter('active', true));
        // Nach Verkäufen sortieren (Top-Seller zuerst)
        $criteria->addSorting(new \Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting\FieldSorting('sales', 'DESC'));

        $products = $this->productRepository->search($criteria, $context);

        $warmed = 0;
        foreach ($products->getIds() as $productId) {
            // Triggert den Cache-Aufbau durch Invalidierung
            $this->cacheInvalidator->invalidate([
                'product-detail-route-' . $productId,
            ]);
            $warmed++;
        }

        $this->logger->info('Cache warmed for {count} products', ['count' => $warmed]);

        return $warmed;
    }

    /**
     * Wärmt den Cache für Kategorieseiten vor
     */
    public function warmCategoryCache(Context $context): int
    {
        $criteria = new Criteria();
        $criteria->addFilter(new \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter('active', true));

        $categories = $this->categoryRepository->search($criteria, $context);

        $warmed = 0;
        foreach ($categories->getIds() as $categoryId) {
            $this->cacheInvalidator->invalidate([
                'product-listing-route-' . $categoryId,
            ]);
            $warmed++;
        }

        $this->logger->info('Cache warmed for {count} categories', ['count' => $warmed]);

        return $warmed;
    }
}
