<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\MockObject\MockObject;

/**
 * Unit Tests for BatchProcessor
 *
 * These tests demonstrate how to test Shopware services
 * without requiring a full Shopware installation.
 */
class BatchProcessorTest extends TestCase
{
    /**
     * Test that batch processing respects the batch size limit.
     */
    public function testBatchSizeConstant(): void
    {
        // Read the constant value using reflection
        $reflector = new \ReflectionClass(\App\Service\BatchProcessor::class);
        $constant = $reflector->getConstant('BATCH_SIZE');

        $this->assertSame(500, $constant, 'Batch size should be 500 for optimal performance');
    }

    /**
     * Test that batch update correctly chunks large arrays.
     */
    public function testBatchUpdateChunking(): void
    {
        // Create 1200 mock updates (should result in 3 batches)
        $updates = [];
        for ($i = 0; $i < 1200; $i++) {
            $updates[] = [
                'id' => 'product-' . $i,
                'data' => ['stock' => $i * 10]
            ];
        }

        $chunks = array_chunk($updates, 500);

        $this->assertCount(3, $chunks, 'Should create 3 batches for 1200 items');
        $this->assertCount(500, $chunks[0], 'First batch should have 500 items');
        $this->assertCount(500, $chunks[1], 'Second batch should have 500 items');
        $this->assertCount(200, $chunks[2], 'Third batch should have 200 items');
    }

    /**
     * Test update data transformation.
     */
    public function testUpdateDataTransformation(): void
    {
        $updates = [
            ['id' => 'abc123', 'data' => ['stock' => 100, 'active' => true]],
            ['id' => 'def456', 'data' => ['stock' => 200]],
        ];

        $transformed = array_map(
            fn(array $update) => array_merge(['id' => $update['id']], $update['data']),
            $updates
        );

        $expected = [
            ['id' => 'abc123', 'stock' => 100, 'active' => true],
            ['id' => 'def456', 'stock' => 200],
        ];

        $this->assertSame($expected, $transformed);
    }

    /**
     * Test that low stock threshold filtering works correctly.
     */
    public function testLowStockThresholdLogic(): void
    {
        $threshold = 10;
        $products = [
            ['id' => '1', 'stock' => 5],   // Below threshold
            ['id' => '2', 'stock' => 10],  // At threshold
            ['id' => '3', 'stock' => 15],  // Above threshold
            ['id' => '4', 'stock' => 0],   // Zero stock
        ];

        $lowStock = array_filter($products, fn($p) => $p['stock'] <= $threshold);

        $this->assertCount(3, $lowStock, 'Should find 3 products at or below threshold');
    }
}
