<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../Stubs/ShopwareStubs.php';
require_once __DIR__ . '/../../src/Service/CacheWarmer.php';

use PerformanceExamples\Service\CacheWarmer;
use Shopware\Core\Framework\Context;

/**
 * Unit Tests for CacheWarmer
 *
 * Tests the cache warming logic from Chapters 6-8.
 * Uses mocks for Shopware repositories and CacheInvalidator.
 */
class CacheWarmerTest extends TestCase
{
    /**
     * Test warmProductCache with mocked repository returning product IDs.
     */
    public function testWarmProductCacheReturnsWarmedCount(): void
    {
        $productIds = ['prod-1', 'prod-2', 'prod-3'];

        // Mock EntityRepository
        $searchResult = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\Search\EntitySearchResult::class);
        $searchResult->method('getIds')->willReturn($productIds);

        $productRepo = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\EntityRepository::class);
        $productRepo->method('search')->willReturn($searchResult);

        $categoryRepo = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\EntityRepository::class);

        // Mock CacheInvalidator
        $cacheInvalidator = $this->createMock(\Shopware\Core\Framework\Adapter\Cache\CacheInvalidator::class);
        $cacheInvalidator->expects($this->exactly(3))
            ->method('invalidate');

        // Mock Logger
        $logger = $this->createMock(\Psr\Log\LoggerInterface::class);
        $logger->expects($this->once())->method('info');

        $warmer = new CacheWarmer($productRepo, $categoryRepo, $cacheInvalidator, $logger);
        $count = $warmer->warmProductCache(Context::createDefaultContext(), 100);

        $this->assertSame(3, $count);
    }

    /**
     * Test warmProductCache with empty result.
     */
    public function testWarmProductCacheEmptyResult(): void
    {
        $searchResult = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\Search\EntitySearchResult::class);
        $searchResult->method('getIds')->willReturn([]);

        $productRepo = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\EntityRepository::class);
        $productRepo->method('search')->willReturn($searchResult);

        $categoryRepo = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\EntityRepository::class);

        $cacheInvalidator = $this->createMock(\Shopware\Core\Framework\Adapter\Cache\CacheInvalidator::class);
        $cacheInvalidator->expects($this->never())->method('invalidate');

        $logger = $this->createMock(\Psr\Log\LoggerInterface::class);

        $warmer = new CacheWarmer($productRepo, $categoryRepo, $cacheInvalidator, $logger);
        $count = $warmer->warmProductCache(Context::createDefaultContext());

        $this->assertSame(0, $count);
    }

    /**
     * Test warmCategoryCache with mocked repository returning category IDs.
     */
    public function testWarmCategoryCacheReturnsWarmedCount(): void
    {
        $categoryIds = ['cat-1', 'cat-2'];

        $searchResult = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\Search\EntitySearchResult::class);
        $searchResult->method('getIds')->willReturn($categoryIds);

        $productRepo = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\EntityRepository::class);

        $categoryRepo = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\EntityRepository::class);
        $categoryRepo->method('search')->willReturn($searchResult);

        $cacheInvalidator = $this->createMock(\Shopware\Core\Framework\Adapter\Cache\CacheInvalidator::class);
        $cacheInvalidator->expects($this->exactly(2))->method('invalidate');

        $logger = $this->createMock(\Psr\Log\LoggerInterface::class);

        $warmer = new CacheWarmer($productRepo, $categoryRepo, $cacheInvalidator, $logger);
        $count = $warmer->warmCategoryCache(Context::createDefaultContext());

        $this->assertSame(2, $count);
    }
}
