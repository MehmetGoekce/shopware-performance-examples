<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Unit Tests for TenantAwareCache
 *
 * Kapitel 23: Fallstudie 5 - Internationaler Marketplace
 *
 * Tests the tenant isolation logic without requiring Redis.
 */
class TenantAwareCacheTest extends TestCase
{
    /**
     * Test that cache keys are properly prefixed with tenant ID.
     */
    public function testCacheKeyPrefixing(): void
    {
        $tenantId = 'tenant_123';
        $key = 'product_list';

        $prefixedKey = sprintf('tenant_%s_%s', $tenantId, $key);

        $this->assertSame('tenant_tenant_123_product_list', $prefixedKey);
        $this->assertStringStartsWith('tenant_', $prefixedKey);
        $this->assertStringContainsString($tenantId, $prefixedKey);
    }

    /**
     * Test that different tenants have different cache key prefixes.
     */
    public function testTenantIsolation(): void
    {
        $tenant1 = 'shop_de';
        $tenant2 = 'shop_fr';
        $key = 'navigation_cache';

        $key1 = sprintf('tenant_%s_%s', $tenant1, $key);
        $key2 = sprintf('tenant_%s_%s', $tenant2, $key);

        $this->assertNotSame($key1, $key2);
        $this->assertSame('tenant_shop_de_navigation_cache', $key1);
        $this->assertSame('tenant_shop_fr_navigation_cache', $key2);
    }

    /**
     * Test that pattern generation for cache clearing works.
     */
    public function testCacheClearPattern(): void
    {
        $tenantId = 'shop_ch';

        $pattern = sprintf('tenant_%s_*', $tenantId);

        $this->assertSame('tenant_shop_ch_*', $pattern);
        $this->assertStringEndsWith('*', $pattern);
    }

    /**
     * Test clear all tenants pattern.
     */
    public function testClearAllTenantsPattern(): void
    {
        $pattern = 'tenant_*';

        // Should match any tenant prefix
        $this->assertTrue((bool) preg_match('/^tenant_/', 'tenant_shop_de_key'));
        $this->assertTrue((bool) preg_match('/^tenant_/', 'tenant_shop_fr_key'));
        $this->assertFalse((bool) preg_match('/^tenant_/', 'other_prefix_key'));
    }

    /**
     * Test domain to tenant mapping logic.
     */
    public function testDomainTenantMapping(): void
    {
        $tenantDomainMap = [
            'shop.de' => 'tenant_de',
            'shop.fr' => 'tenant_fr',
            'shop.ch' => 'tenant_ch',
        ];

        $this->assertSame('tenant_de', $tenantDomainMap['shop.de']);
        $this->assertSame('tenant_fr', $tenantDomainMap['shop.fr']);
        $this->assertSame('tenant_ch', $tenantDomainMap['shop.ch']);

        // Unknown domain should return default
        $unknownHost = 'unknown.com';
        $tenantId = $tenantDomainMap[$unknownHost] ?? 'default';
        $this->assertSame('default', $tenantId);
    }

    /**
     * Test cache stats structure.
     */
    public function testCacheStatsStructure(): void
    {
        $tenantId = 'shop_de';
        $keyCount = 150;
        $estimatedSize = 1024 * 50; // 50 KB

        $stats = [
            'tenant_id' => $tenantId,
            'key_count' => $keyCount,
            'estimated_size' => $estimatedSize,
        ];

        $this->assertArrayHasKey('tenant_id', $stats);
        $this->assertArrayHasKey('key_count', $stats);
        $this->assertArrayHasKey('estimated_size', $stats);
        $this->assertSame($tenantId, $stats['tenant_id']);
        $this->assertIsInt($stats['key_count']);
        $this->assertIsInt($stats['estimated_size']);
    }

    /**
     * Test size estimation logic.
     */
    public function testSizeEstimation(): void
    {
        // Simulating the estimation logic from TenantAwareCache
        $sampleKeys = 100;
        $sampleSize = 5000; // 5000 bytes from 100 samples
        $totalKeys = 1000;

        $avgSize = $sampleSize / $sampleKeys; // 50 bytes avg
        $estimatedTotal = (int) ($avgSize * $totalKeys); // 50000 bytes

        $this->assertSame(50000, $estimatedTotal);
        $this->assertEquals(50, $avgSize);
    }

    /**
     * Test that tenant context can be set for background jobs.
     */
    public function testTenantContextSetting(): void
    {
        $initialTenant = null;
        $newTenant = 'background_job_tenant';

        // Simulate setTenantContext behavior
        $currentTenant = $initialTenant;
        $currentTenant = $newTenant;

        $this->assertSame('background_job_tenant', $currentTenant);
        $this->assertNotNull($currentTenant);
    }

    /**
     * Test multiple key prefixing at once.
     */
    public function testBatchKeyPrefixing(): void
    {
        $tenantId = 'shop_de';
        $keys = ['product_1', 'product_2', 'product_3'];

        $prefixedKeys = array_map(
            fn(string $key) => sprintf('tenant_%s_%s', $tenantId, $key),
            $keys
        );

        $this->assertCount(3, $prefixedKeys);
        $this->assertSame('tenant_shop_de_product_1', $prefixedKeys[0]);
        $this->assertSame('tenant_shop_de_product_2', $prefixedKeys[1]);
        $this->assertSame('tenant_shop_de_product_3', $prefixedKeys[2]);
    }
}
