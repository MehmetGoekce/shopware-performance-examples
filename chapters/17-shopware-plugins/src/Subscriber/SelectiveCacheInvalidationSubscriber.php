<?php

declare(strict_types=1);

namespace App\Subscriber;

use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Defaults;
use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Selective Cache Invalidation Subscriber
 *
 * Demonstrates controlled cache invalidation to avoid
 * mass-purges that can cause performance spikes.
 *
 * Problems with aggressive invalidation:
 * - ERP imports can invalidate thousands of cache entries
 * - Admin changes during peak traffic cause latency spikes
 * - Database locks from invalidation queue
 *
 * Solutions:
 * - Only invalidate what actually changed
 * - Use delayed invalidation (Shopware 6.7+ default)
 * - Batch invalidations
 * - Skip non-visible field changes
 */
class SelectiveCacheInvalidationSubscriber implements EventSubscriberInterface
{
    /**
     * Fields that affect visible page content
     */
    private const VISIBLE_FIELDS = [
        'name',
        'description',
        'price',
        'cover',
        'active',
        'manufacturer',
        'customFields',
    ];

    /**
     * Fields that only affect backend/internal operations
     * Changes to these should NOT invalidate cache
     */
    private const INTERNAL_FIELDS = [
        'stock',           // Stock shown via ESI/AJAX
        'sales',           // Internal metrics
        'autoIncrement',   // Technical field
        'versionId',       // Version control
    ];

    public function __construct(
        private readonly CacheInvalidator $cacheInvalidator
    ) {}

    public static function getSubscribedEvents(): array
    {
        // Lower priority = runs AFTER default Shopware invalidation
        // This allows us to add custom tags without interfering
        return [
            ProductEvents::PRODUCT_WRITTEN_EVENT => ['onProductWritten', -100],
        ];
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        // Only live version
        if ($event->getContext()->getVersionId() !== Defaults::LIVE_VERSION) {
            return;
        }

        $tagsToInvalidate = [];

        foreach ($event->getWriteResults() as $result) {
            $payload = $result->getPayload();

            if ($payload === null) {
                continue;
            }

            $productId = $result->getPrimaryKey();

            // ============================================
            // Determine what type of change occurred
            // ============================================

            $hasVisibleChange = $this->hasVisibleChange($payload);
            $hasPriceChange = isset($payload['price']);
            $hasStockChange = isset($payload['stock']);

            // ============================================
            // Price-specific invalidation
            // ============================================
            if ($hasPriceChange) {
                // Only invalidate price-related cache, not full product
                $tagsToInvalidate[] = sprintf('product-price-%s', $productId);

                // Listing pages that show this product
                $tagsToInvalidate[] = sprintf('product-listing-%s', $productId);
            }

            // ============================================
            // Stock changes - often no invalidation needed
            // ============================================
            if ($hasStockChange && !$hasVisibleChange) {
                // Stock is typically loaded via ESI or AJAX
                // No need to invalidate the full page cache
                continue;
            }

            // ============================================
            // Visible content changes
            // ============================================
            if ($hasVisibleChange) {
                // Full product invalidation
                $tagsToInvalidate[] = sprintf('custom-product-%s', $productId);

                // Related pages
                $tagsToInvalidate[] = sprintf('product-detail-%s', $productId);
            }
        }

        // ============================================
        // Batch invalidation
        // ============================================
        if (!empty($tagsToInvalidate)) {
            // Remove duplicates
            $tagsToInvalidate = array_unique($tagsToInvalidate);

            // Single batch call instead of individual invalidations
            $this->cacheInvalidator->invalidate($tagsToInvalidate);
        }
    }

    /**
     * Check if the payload contains changes to visible fields
     */
    private function hasVisibleChange(array $payload): bool
    {
        foreach (self::VISIBLE_FIELDS as $field) {
            if (array_key_exists($field, $payload)) {
                return true;
            }
        }

        return false;
    }
}
