<?php

declare(strict_types=1);

namespace App\Subscriber;

use Shopware\Core\Framework\Adapter\Cache\CacheTagCollection;
use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\Request;

/**
 * Cache Tag Subscriber
 *
 * Adds custom cache tags to HTTP cache entries for fine-grained
 * cache invalidation.
 *
 * Shopware's HTTP cache uses a tag-based invalidation system:
 * - Every cached page is tagged with relevant entity IDs
 * - When an entity changes, all pages with that tag are invalidated
 * - Custom tags allow plugins to participate in this system
 *
 * Default Shopware tags include:
 * - product-{id}
 * - category-{id}
 * - cms-page-{id}
 * - navigation-{salesChannelId}
 *
 * This subscriber adds custom tags for:
 * - Route-specific caching
 * - Feature-flag-based invalidation
 * - Custom business logic
 */
class CacheTagSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly CacheTagCollection $cacheTagCollection
    ) {}

    public static function getSubscribedEvents(): array
    {
        return [
            StorefrontRenderEvent::class => ['addCacheTags', 0],
        ];
    }

    public function addCacheTags(StorefrontRenderEvent $event): void
    {
        $request = $event->getRequest();
        $route = $request->attributes->get('_route');

        // ============================================
        // Route-based tags
        // ============================================
        $this->addRouteBasedTags($route, $request);

        // ============================================
        // Page-specific tags
        // ============================================
        $this->addPageSpecificTags($event);
    }

    private function addRouteBasedTags(string $route, Request $request): void
    {
        switch ($route) {
            case 'frontend.detail.page':
                // Product detail page - add custom product tag
                $productId = $request->get('productId');
                if ($productId) {
                    $this->cacheTagCollection->add(
                        sprintf('custom-product-%s', $productId)
                    );

                    // Tag for price-sensitive invalidation
                    $this->cacheTagCollection->add(
                        sprintf('product-price-%s', $productId)
                    );
                }
                break;

            case 'frontend.navigation.page':
                // Category page - add category-specific tags
                $navigationId = $request->get('navigationId');
                if ($navigationId) {
                    $this->cacheTagCollection->add(
                        sprintf('custom-category-%s', $navigationId)
                    );
                }
                break;

            case 'frontend.home.page':
                // Homepage - special tag for homepage-specific content
                $this->cacheTagCollection->add('homepage');
                $this->cacheTagCollection->add('featured-products');
                break;

            case 'frontend.checkout.cart.page':
                // Cart page should NOT be cached aggressively
                // But we can add tags for partial caching
                $this->cacheTagCollection->add('cart-recommendations');
                break;
        }
    }

    private function addPageSpecificTags(StorefrontRenderEvent $event): void
    {
        $page = $event->getParameters()['page'] ?? null;

        if ($page === null) {
            return;
        }

        // ============================================
        // CMS Page tags
        // ============================================
        if (method_exists($page, 'getCmsPage')) {
            $cmsPage = $page->getCmsPage();
            if ($cmsPage !== null) {
                $this->cacheTagCollection->add(
                    sprintf('custom-cms-%s', $cmsPage->getId())
                );

                // Tag each CMS block for granular invalidation
                foreach ($cmsPage->getSections() as $section) {
                    foreach ($section->getBlocks() as $block) {
                        $this->cacheTagCollection->add(
                            sprintf('cms-block-%s', $block->getId())
                        );
                    }
                }
            }
        }

        // ============================================
        // Manufacturer tags (for brand pages)
        // ============================================
        if (method_exists($page, 'getProduct')) {
            $product = $page->getProduct();
            if ($product !== null && $product->getManufacturerId()) {
                $this->cacheTagCollection->add(
                    sprintf('manufacturer-%s', $product->getManufacturerId())
                );
            }
        }

        // ============================================
        // Time-based tags for scheduled content
        // ============================================
        // These allow invalidation based on time windows
        $this->cacheTagCollection->add(
            sprintf('day-%s', date('Y-m-d'))
        );

        // For hourly promotions
        if ($this->hasTimeBasedContent()) {
            $this->cacheTagCollection->add(
                sprintf('hour-%s', date('Y-m-d-H'))
            );
        }
    }

    private function hasTimeBasedContent(): bool
    {
        // Check if current page has time-sensitive content
        // This could be determined by CMS configuration
        return false;
    }
}
