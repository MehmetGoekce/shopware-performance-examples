<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../Stubs/ShopwareStubs.php';
require_once __DIR__ . '/../../src/Service/QueryOptimizer.php';

use PerformanceExamples\Service\QueryOptimizer;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\EntitySearchResult;

/**
 * Unit Tests for QueryOptimizer
 *
 * Tests the query optimization patterns from Chapter 8.
 * Verifies that the "good" methods apply proper limits and field selection.
 */
class QueryOptimizerTest extends TestCase
{
    /**
     * Test getProductsGood applies a limit to the criteria.
     */
    public function testGetProductsGoodAppliesLimit(): void
    {
        $capturedCriteria = null;

        $searchResult = $this->createMock(EntitySearchResult::class);
        $searchResult->method('getElements')->willReturn([]);

        $productRepo = $this->createMock(EntityRepository::class);
        $productRepo->method('search')
            ->willReturnCallback(function (Criteria $criteria) use (&$capturedCriteria, $searchResult) {
                $capturedCriteria = $criteria;
                return $searchResult;
            });

        $orderRepo = $this->createMock(EntityRepository::class);

        $optimizer = new QueryOptimizer($productRepo, $orderRepo);
        $optimizer->getProductsGood(Context::createDefaultContext(), 50);

        $this->assertNotNull($capturedCriteria);
        $this->assertSame(50, $capturedCriteria->getLimit());
    }

    /**
     * Test getProductsBad does NOT set a limit (demonstrating the anti-pattern).
     */
    public function testGetProductsBadHasNoLimit(): void
    {
        $capturedCriteria = null;

        $searchResult = $this->createMock(EntitySearchResult::class);
        $searchResult->method('getElements')->willReturn([]);

        $productRepo = $this->createMock(EntityRepository::class);
        $productRepo->method('search')
            ->willReturnCallback(function (Criteria $criteria) use (&$capturedCriteria, $searchResult) {
                $capturedCriteria = $criteria;
                return $searchResult;
            });

        $orderRepo = $this->createMock(EntityRepository::class);

        $optimizer = new QueryOptimizer($productRepo, $orderRepo);
        $optimizer->getProductsBad(Context::createDefaultContext());

        $this->assertNotNull($capturedCriteria);
        $this->assertNull($capturedCriteria->getLimit());
    }

    /**
     * Test searchProducts with all optional filters provided.
     */
    public function testSearchProductsWithAllFilters(): void
    {
        $searchResult = $this->createMock(EntitySearchResult::class);
        $searchResult->method('getElements')->willReturn([]);

        $productRepo = $this->createMock(EntityRepository::class);
        $productRepo->expects($this->once())->method('search')->willReturn($searchResult);

        $orderRepo = $this->createMock(EntityRepository::class);

        $optimizer = new QueryOptimizer($productRepo, $orderRepo);
        $result = $optimizer->searchProducts(
            Context::createDefaultContext(),
            categoryId: 'cat-123',
            minPrice: 10.0,
            maxPrice: 100.0,
            limit: 25
        );

        $this->assertIsArray($result);
    }

    /**
     * Test searchProducts with no optional filters.
     */
    public function testSearchProductsMinimalFilters(): void
    {
        $searchResult = $this->createMock(EntitySearchResult::class);
        $searchResult->method('getElements')->willReturn([]);

        $productRepo = $this->createMock(EntityRepository::class);
        $productRepo->expects($this->once())->method('search')->willReturn($searchResult);

        $orderRepo = $this->createMock(EntityRepository::class);

        $optimizer = new QueryOptimizer($productRepo, $orderRepo);
        $result = $optimizer->searchProducts(Context::createDefaultContext());

        $this->assertIsArray($result);
    }

    /**
     * Test countOrdersGood uses aggregation (limit=0).
     */
    public function testCountOrdersGoodUsesAggregation(): void
    {
        $capturedCriteria = null;

        $searchResult = $this->createMock(EntitySearchResult::class);
        $searchResult->method('getAggregations')->willReturn(
            new \Shopware\Core\Framework\DataAbstractionLayer\Search\AggregationResult\AggregationResultCollection()
        );

        $productRepo = $this->createMock(EntityRepository::class);
        $orderRepo = $this->createMock(EntityRepository::class);
        $orderRepo->method('search')
            ->willReturnCallback(function (Criteria $criteria) use (&$capturedCriteria, $searchResult) {
                $capturedCriteria = $criteria;
                return $searchResult;
            });

        $optimizer = new QueryOptimizer($productRepo, $orderRepo);
        $count = $optimizer->countOrdersGood(Context::createDefaultContext(), 'customer-1');

        $this->assertSame(0, $count);
        $this->assertNotNull($capturedCriteria);
        $this->assertSame(0, $capturedCriteria->getLimit());
    }
}
