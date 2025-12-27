<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Unit Tests for Cache Key Generation Patterns
 *
 * Tests common cache key patterns used throughout the book examples.
 */
class CacheKeyGeneratorTest extends TestCase
{
    /**
     * Test product cache key generation.
     */
    public function testProductCacheKey(): void
    {
        $productId = 'abc123def456';
        $salesChannelId = 'sc_default';

        $cacheKey = sprintf('product_%s_%s', $productId, $salesChannelId);

        $this->assertSame('product_abc123def456_sc_default', $cacheKey);
    }

    /**
     * Test category tree cache key.
     */
    public function testCategoryTreeCacheKey(): void
    {
        $salesChannelId = 'sc_default';
        $depth = 3;

        $cacheKey = sprintf('category_tree_%s_depth_%d', $salesChannelId, $depth);

        $this->assertSame('category_tree_sc_default_depth_3', $cacheKey);
    }

    /**
     * Test cache key with hash for complex criteria.
     */
    public function testCriteriaHashCacheKey(): void
    {
        $criteria = [
            'page' => 1,
            'limit' => 24,
            'sort' => 'name-asc',
            'filter' => ['manufacturer' => 'abc'],
        ];

        $hash = md5(json_encode($criteria));
        $cacheKey = sprintf('search_results_%s', $hash);

        $this->assertStringStartsWith('search_results_', $cacheKey);
        $this->assertSame(32 + strlen('search_results_'), strlen($cacheKey));
    }

    /**
     * Test that same criteria produces same hash.
     */
    public function testCriteriaHashConsistency(): void
    {
        $criteria1 = ['page' => 1, 'limit' => 24];
        $criteria2 = ['page' => 1, 'limit' => 24];
        $criteria3 = ['page' => 2, 'limit' => 24];

        $hash1 = md5(json_encode($criteria1));
        $hash2 = md5(json_encode($criteria2));
        $hash3 = md5(json_encode($criteria3));

        $this->assertSame($hash1, $hash2);
        $this->assertNotSame($hash1, $hash3);
    }

    /**
     * Test cache TTL configuration.
     */
    public function testCacheTtlConfiguration(): void
    {
        $ttlConfig = [
            'product' => 3600,      // 1 hour
            'category' => 7200,     // 2 hours
            'navigation' => 86400,  // 24 hours
            'search' => 300,        // 5 minutes
        ];

        $this->assertSame(3600, $ttlConfig['product']);
        $this->assertSame(7200, $ttlConfig['category']);
        $this->assertSame(86400, $ttlConfig['navigation']);
        $this->assertSame(300, $ttlConfig['search']);
    }

    /**
     * Test cache tag generation for invalidation.
     */
    public function testCacheTagGeneration(): void
    {
        $productId = 'prod123';
        $categoryIds = ['cat1', 'cat2', 'cat3'];

        $tags = ['product-' . $productId];
        foreach ($categoryIds as $catId) {
            $tags[] = 'category-' . $catId;
        }

        $this->assertCount(4, $tags);
        $this->assertContains('product-prod123', $tags);
        $this->assertContains('category-cat1', $tags);
        $this->assertContains('category-cat2', $tags);
        $this->assertContains('category-cat3', $tags);
    }

    /**
     * Test HTTP cache key with request parameters.
     */
    public function testHttpCacheKey(): void
    {
        $uri = '/category/clothing';
        $queryParams = ['page' => '2', 'sort' => 'price-asc'];

        ksort($queryParams); // Ensure consistent ordering
        $queryString = http_build_query($queryParams);
        $cacheKey = md5($uri . '?' . $queryString);

        $this->assertSame(32, strlen($cacheKey));

        // Same params in different order should produce same key
        $queryParams2 = ['sort' => 'price-asc', 'page' => '2'];
        ksort($queryParams2);
        $queryString2 = http_build_query($queryParams2);
        $cacheKey2 = md5($uri . '?' . $queryString2);

        $this->assertSame($cacheKey, $cacheKey2);
    }

    /**
     * Test ignored URL parameters for caching.
     */
    public function testIgnoredUrlParameters(): void
    {
        $ignoredParams = ['gclid', 'utm_source', 'utm_medium', 'utm_campaign', 'fbclid'];

        $queryParams = [
            'page' => '1',
            'gclid' => 'abc123',
            'utm_source' => 'google',
            'sort' => 'name',
        ];

        // Filter out ignored params
        $filteredParams = array_diff_key($queryParams, array_flip($ignoredParams));

        $this->assertArrayHasKey('page', $filteredParams);
        $this->assertArrayHasKey('sort', $filteredParams);
        $this->assertArrayNotHasKey('gclid', $filteredParams);
        $this->assertArrayNotHasKey('utm_source', $filteredParams);
    }
}
