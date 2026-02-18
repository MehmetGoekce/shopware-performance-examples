<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../Stubs/ShopwareStubs.php';
require_once __DIR__ . '/../../src/Subscriber/HttpCacheSubscriber.php';

use PerformanceExamples\Subscriber\HttpCacheSubscriber;

/**
 * Unit Tests for HttpCacheSubscriber
 *
 * Tests the HTTP cache header configuration from Chapter 1.
 * Verifies cache config constants, no-cache routes, and TTL logic.
 */
class HttpCacheSubscriberTest extends TestCase
{
    /**
     * Test that the subscriber registers for the response event.
     */
    public function testGetSubscribedEvents(): void
    {
        $events = HttpCacheSubscriber::getSubscribedEvents();

        $this->assertArrayHasKey('kernel.response', $events);
    }

    /**
     * Test cache config contains expected page types.
     */
    public function testCacheConfigContainsAllPageTypes(): void
    {
        $reflection = new \ReflectionClass(HttpCacheSubscriber::class);
        $cacheConfig = $reflection->getConstant('CACHE_CONFIG');

        $expectedTypes = ['product', 'category', 'home', 'cms', 'default'];

        foreach ($expectedTypes as $type) {
            $this->assertArrayHasKey($type, $cacheConfig, "Missing cache config for '$type'");
            $this->assertArrayHasKey('max_age', $cacheConfig[$type]);
            $this->assertArrayHasKey('stale_while_revalidate', $cacheConfig[$type]);
            $this->assertArrayHasKey('surrogate_max_age', $cacheConfig[$type]);
        }
    }

    /**
     * Test that product pages have shorter TTL than CMS pages.
     */
    public function testProductTtlShorterThanCms(): void
    {
        $reflection = new \ReflectionClass(HttpCacheSubscriber::class);
        $cacheConfig = $reflection->getConstant('CACHE_CONFIG');

        $this->assertLessThan(
            $cacheConfig['cms']['max_age'],
            $cacheConfig['product']['max_age'],
            'Product TTL should be shorter than CMS TTL'
        );
    }

    /**
     * Test that home page has shortest TTL of cacheable pages.
     */
    public function testHomepageHasShortestTtl(): void
    {
        $reflection = new \ReflectionClass(HttpCacheSubscriber::class);
        $cacheConfig = $reflection->getConstant('CACHE_CONFIG');

        $homeMaxAge = $cacheConfig['home']['max_age'];

        foreach (['product', 'category', 'cms'] as $type) {
            $this->assertLessThanOrEqual(
                $cacheConfig[$type]['max_age'],
                $homeMaxAge,
                "Home TTL should be <= $type TTL"
            );
        }
    }

    /**
     * Test no-cache routes include checkout and account pages.
     */
    public function testNoCacheRoutesContainSecurePages(): void
    {
        $reflection = new \ReflectionClass(HttpCacheSubscriber::class);
        $noCacheRoutes = $reflection->getConstant('NO_CACHE_ROUTES');

        $this->assertContains('frontend.checkout.cart.page', $noCacheRoutes);
        $this->assertContains('frontend.checkout.confirm.page', $noCacheRoutes);
        $this->assertContains('frontend.checkout.finish.page', $noCacheRoutes);
        $this->assertContains('frontend.account.login.page', $noCacheRoutes);
        $this->assertContains('frontend.account.order.page', $noCacheRoutes);
        $this->assertContains('frontend.account.profile.page', $noCacheRoutes);
    }

    /**
     * Test no-cache routes count.
     */
    public function testNoCacheRoutesCount(): void
    {
        $reflection = new \ReflectionClass(HttpCacheSubscriber::class);
        $noCacheRoutes = $reflection->getConstant('NO_CACHE_ROUTES');

        $this->assertCount(6, $noCacheRoutes);
    }

    /**
     * Test all TTL values are positive integers.
     */
    public function testAllTtlValuesArePositive(): void
    {
        $reflection = new \ReflectionClass(HttpCacheSubscriber::class);
        $cacheConfig = $reflection->getConstant('CACHE_CONFIG');

        foreach ($cacheConfig as $type => $config) {
            $this->assertGreaterThan(0, $config['max_age'], "$type max_age must be positive");
            $this->assertGreaterThan(0, $config['stale_while_revalidate'], "$type stale_while_revalidate must be positive");
            $this->assertGreaterThan(0, $config['surrogate_max_age'], "$type surrogate_max_age must be positive");
        }
    }

    /**
     * Test getCacheConfig returns correct config for product routes.
     */
    public function testGetCacheConfigForProductRoute(): void
    {
        $subscriber = new HttpCacheSubscriber();
        $reflection = new \ReflectionMethod($subscriber, 'getCacheConfig');
        $reflection->setAccessible(true);

        $reflectionClass = new \ReflectionClass(HttpCacheSubscriber::class);
        $cacheConfig = $reflectionClass->getConstant('CACHE_CONFIG');

        $result = $reflection->invoke($subscriber, 'frontend.detail.product.page');
        $this->assertSame($cacheConfig['product'], $result);

        $result = $reflection->invoke($subscriber, 'frontend.home.page');
        $this->assertSame($cacheConfig['home'], $result);

        $result = $reflection->invoke($subscriber, 'some.unknown.route');
        $this->assertSame($cacheConfig['default'], $result);
    }
}
