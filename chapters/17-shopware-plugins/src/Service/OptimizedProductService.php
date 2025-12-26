<?php

declare(strict_types=1);

namespace App\Service;

use Shopware\Core\Content\Product\ProductCollection;
use Shopware\Core\Content\Product\ProductEntity;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\MultiFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting\FieldSorting;

/**
 * Optimized Product Service
 *
 * Demonstrates DAL best practices for performance-critical operations.
 *
 * Key Principles:
 * 1. Load only necessary fields and associations
 * 2. Filter as early as possible
 * 3. Limit results appropriately
 * 4. Use association criteria for nested data
 */
class OptimizedProductService
{
    public function __construct(
        private readonly EntityRepository $productRepository
    ) {}

    /**
     * Get products for listing with minimal data
     *
     * Performance considerations:
     * - Only loads cover image (not all media)
     * - Limits price association to first entry
     * - Filters by category at database level
     *
     * @param string $categoryId Category to filter by
     * @param Context $context Shopware context
     * @param int $limit Maximum results
     * @param int $offset Pagination offset
     */
    public function getProductsForListing(
        string $categoryId,
        Context $context,
        int $limit = 24,
        int $offset = 0
    ): ProductCollection {
        $criteria = new Criteria();

        // Pagination
        $criteria->setLimit($limit);
        $criteria->setOffset($offset);

        // Filter early - reduces data at SQL level
        $criteria->addFilter(
            new EqualsFilter('categories.id', $categoryId)
        );
        $criteria->addFilter(
            new EqualsFilter('active', true)
        );

        // Only main products (no variants in listing)
        $criteria->addFilter(
            new EqualsFilter('parentId', null)
        );

        // Sorting
        $criteria->addSorting(
            new FieldSorting('createdAt', FieldSorting::DESCENDING)
        );

        // MINIMAL associations - only what's rendered!
        // Cover image for product box
        $criteria->addAssociation('cover.media');

        // Manufacturer name (if displayed)
        $criteria->addAssociation('manufacturer');

        // First price only - not all price rules
        $priceCriteria = new Criteria();
        $priceCriteria->setLimit(1);
        $criteria->getAssociation('prices')->addCriteria($priceCriteria);

        // Total count for pagination (optional, only if needed)
        // $criteria->setTotalCountMode(Criteria::TOTAL_COUNT_MODE_EXACT);

        return $this->productRepository
            ->search($criteria, $context)
            ->getEntities();
    }

    /**
     * Get single product with full details
     *
     * Only load full associations for detail page,
     * not for listings or internal processes.
     */
    public function getProductDetail(
        string $productId,
        Context $context
    ): ?ProductEntity {
        $criteria = new Criteria([$productId]);

        // Full associations for detail page
        $criteria->addAssociation('cover.media');
        $criteria->addAssociation('media.media');  // All product images
        $criteria->addAssociation('manufacturer.media');
        $criteria->addAssociation('options.group');  // Variant options
        $criteria->addAssociation('properties.group');

        // Prices with rules
        $criteria->addAssociation('prices');

        // Reviews (limited)
        $reviewCriteria = new Criteria();
        $reviewCriteria->setLimit(10);
        $reviewCriteria->addSorting(
            new FieldSorting('createdAt', FieldSorting::DESCENDING)
        );
        $criteria->getAssociation('productReviews')
            ->addCriteria($reviewCriteria);

        // Cross-selling (if configured)
        $criteria->addAssociation('crossSellings');

        return $this->productRepository
            ->search($criteria, $context)
            ->first();
    }

    /**
     * Get product IDs only - no hydration overhead
     *
     * Use this for internal processes where you only need IDs.
     * Much faster than loading full entities.
     */
    public function getActiveProductIds(
        Context $context,
        int $limit = 1000
    ): array {
        $criteria = new Criteria();
        $criteria->setLimit($limit);

        $criteria->addFilter(
            new EqualsFilter('active', true)
        );
        $criteria->addFilter(
            new EqualsFilter('parentId', null)
        );

        // Return IDs only - no entity hydration!
        return $this->productRepository
            ->searchIds($criteria, $context)
            ->getIds();
    }

    /**
     * Search products with aggregations
     *
     * Demonstrates efficient aggregation usage.
     */
    public function searchWithFilters(
        string $term,
        array $filters,
        Context $context,
        int $limit = 24
    ): array {
        $criteria = new Criteria();
        $criteria->setLimit($limit);
        $criteria->setTerm($term);

        // Apply filters
        $filterConditions = [];

        if (isset($filters['minPrice'])) {
            $filterConditions[] = new RangeFilter(
                'cheapestPrice',
                [RangeFilter::GTE => $filters['minPrice']]
            );
        }

        if (isset($filters['maxPrice'])) {
            $filterConditions[] = new RangeFilter(
                'cheapestPrice',
                [RangeFilter::LTE => $filters['maxPrice']]
            );
        }

        if (isset($filters['manufacturerId'])) {
            $filterConditions[] = new EqualsFilter(
                'manufacturerId',
                $filters['manufacturerId']
            );
        }

        if (!empty($filterConditions)) {
            $criteria->addFilter(
                new MultiFilter(MultiFilter::CONNECTION_AND, $filterConditions)
            );
        }

        // Minimal associations for search results
        $criteria->addAssociation('cover.media');

        $result = $this->productRepository->search($criteria, $context);

        return [
            'products' => $result->getEntities(),
            'total' => $result->getTotal(),
        ];
    }
}
