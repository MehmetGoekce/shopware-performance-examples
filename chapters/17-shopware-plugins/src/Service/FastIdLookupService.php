<?php

declare(strict_types=1);

namespace App\Service;

use Doctrine\DBAL\ArrayParameterType;
use Doctrine\DBAL\Connection;
use Psr\Log\LoggerInterface;

/**
 * Fast ID Lookup Service
 *
 * Uses DBAL (plain SQL) instead of DAL for performance-critical operations.
 *
 * When to use DBAL over DAL:
 * - Internal processes (not API responses)
 * - Simple ID lookups
 * - Batch updates without event triggering
 * - Indexer operations
 * - Performance-critical paths
 *
 * DBAL advantages:
 * - 10-100x faster for simple operations
 * - No entity hydration overhead
 * - No event dispatching
 * - Direct SQL control
 */
class FastIdLookupService
{
    public function __construct(
        private readonly Connection $connection,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Get active product IDs using DBAL
     *
     * Much faster than DAL for simple ID lookups.
     */
    public function getActiveProductIds(int $limit = 1000, ?string $afterId = null): array
    {
        $sql = <<<SQL
            SELECT LOWER(HEX(id)) as id
            FROM product
            WHERE active = 1
              AND parent_id IS NULL
              AND (:afterId IS NULL OR id > UNHEX(:afterId))
            ORDER BY id
            LIMIT :limit
        SQL;

        return $this->connection->fetchFirstColumn($sql, [
            'afterId' => $afterId,
            'limit' => $limit,
        ]);
    }

    /**
     * Get product IDs by category
     */
    public function getProductIdsByCategory(string $categoryId, int $limit = 1000): array
    {
        $sql = <<<SQL
            SELECT LOWER(HEX(p.id)) as id
            FROM product p
            INNER JOIN product_category pc ON pc.product_id = p.id
            WHERE pc.category_id = UNHEX(:categoryId)
              AND p.active = 1
              AND p.parent_id IS NULL
            LIMIT :limit
        SQL;

        return $this->connection->fetchFirstColumn($sql, [
            'categoryId' => str_replace('-', '', $categoryId),
            'limit' => $limit,
        ]);
    }

    /**
     * Batch update stock without triggering events
     *
     * IMPORTANT: This bypasses the DAL and does NOT:
     * - Trigger EntityWrittenEvent
     * - Invalidate caches automatically
     * - Run indexers
     *
     * Use only when you handle these manually or don't need them.
     *
     * @param array<string, int> $stockUpdates [productId => newStock]
     */
    public function updateStockBatch(array $stockUpdates): int
    {
        if (empty($stockUpdates)) {
            return 0;
        }

        $this->logger->info('Batch updating stock for {count} products', [
            'count' => count($stockUpdates),
        ]);

        $updated = 0;

        $this->connection->beginTransaction();

        try {
            $stmt = $this->connection->prepare(
                'UPDATE product SET stock = :stock, updated_at = NOW() WHERE id = UNHEX(:id)'
            );

            foreach ($stockUpdates as $productId => $stock) {
                $stmt->executeStatement([
                    'id' => str_replace('-', '', $productId),
                    'stock' => $stock,
                ]);
                $updated++;
            }

            $this->connection->commit();

            $this->logger->info('Successfully updated {count} products', [
                'count' => $updated,
            ]);

            return $updated;
        } catch (\Throwable $e) {
            $this->connection->rollBack();

            $this->logger->error('Batch stock update failed: {message}', [
                'message' => $e->getMessage(),
            ]);

            throw $e;
        }
    }

    /**
     * Bulk insert with ON DUPLICATE KEY UPDATE
     *
     * Efficient for import scenarios.
     *
     * @param array<array{id: string, stock: int, ean?: string}> $products
     */
    public function upsertProducts(array $products): int
    {
        if (empty($products)) {
            return 0;
        }

        // Build batch insert
        $values = [];
        $params = [];
        $i = 0;

        foreach ($products as $product) {
            $values[] = "(UNHEX(:id{$i}), :stock{$i}, :ean{$i}, NOW(), NOW())";
            $params["id{$i}"] = str_replace('-', '', $product['id']);
            $params["stock{$i}"] = $product['stock'];
            $params["ean{$i}"] = $product['ean'] ?? null;
            $i++;
        }

        $sql = sprintf(
            'INSERT INTO product_stock_import (product_id, stock, ean, created_at, updated_at)
             VALUES %s
             ON DUPLICATE KEY UPDATE
                stock = VALUES(stock),
                ean = VALUES(ean),
                updated_at = NOW()',
            implode(', ', $values)
        );

        return $this->connection->executeStatement($sql, $params);
    }

    /**
     * Get variant count for products
     *
     * Demonstrates efficient aggregation with DBAL.
     */
    public function getVariantCounts(array $productIds): array
    {
        if (empty($productIds)) {
            return [];
        }

        $sql = <<<SQL
            SELECT
                LOWER(HEX(parent_id)) as parent_id,
                COUNT(*) as variant_count
            FROM product
            WHERE parent_id IN (:ids)
            GROUP BY parent_id
        SQL;

        $result = $this->connection->fetchAllAssociative($sql, [
            'ids' => array_map(
                fn($id) => hex2bin(str_replace('-', '', $id)),
                $productIds
            ),
        ], [
            'ids' => ArrayParameterType::STRING,
        ]);

        $counts = [];
        foreach ($result as $row) {
            $counts[$row['parent_id']] = (int) $row['variant_count'];
        }

        return $counts;
    }

    /**
     * Find products with low stock
     */
    public function findLowStockProducts(int $threshold = 10): array
    {
        $sql = <<<SQL
            SELECT
                LOWER(HEX(id)) as id,
                product_number,
                stock,
                available_stock
            FROM product
            WHERE parent_id IS NULL
              AND active = 1
              AND stock <= :threshold
            ORDER BY stock ASC
            LIMIT 100
        SQL;

        return $this->connection->fetchAllAssociative($sql, [
            'threshold' => $threshold,
        ]);
    }

    /**
     * Get cheapest prices directly (bypassing DAL calculation)
     *
     * Useful for batch exports or reports.
     */
    public function getCheapestPrices(array $productIds, string $currencyId): array
    {
        if (empty($productIds)) {
            return [];
        }

        $sql = <<<SQL
            SELECT
                LOWER(HEX(pp.product_id)) as product_id,
                MIN(JSON_UNQUOTE(JSON_EXTRACT(pp.price, CONCAT('$.c', :currencyId, '.gross')))) as price
            FROM product_price pp
            WHERE pp.product_id IN (:ids)
            GROUP BY pp.product_id
        SQL;

        $result = $this->connection->fetchAllAssociative($sql, [
            'currencyId' => str_replace('-', '', $currencyId),
            'ids' => array_map(
                fn($id) => hex2bin(str_replace('-', '', $id)),
                $productIds
            ),
        ], [
            'ids' => ArrayParameterType::STRING,
        ]);

        $prices = [];
        foreach ($result as $row) {
            $prices[$row['product_id']] = (float) $row['price'];
        }

        return $prices;
    }
}
