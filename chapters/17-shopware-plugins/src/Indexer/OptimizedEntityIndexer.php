<?php

declare(strict_types=1);

namespace App\Indexer;

use Doctrine\DBAL\Connection;
use Psr\Log\LoggerInterface;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenContainerEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Indexing\EntityIndexer;
use Shopware\Core\Framework\DataAbstractionLayer\Indexing\EntityIndexingMessage;
use Shopware\Core\Framework\Plugin\Exception\DecorationPatternException;

/**
 * Optimized Entity Indexer
 *
 * Demonstrates best practices for custom entity indexers:
 *
 * 1. DBAL over DAL: Use Connection directly to avoid event loops
 *    and get better performance
 *
 * 2. Batch Processing: Process in reasonable chunks to manage memory
 *
 * 3. Async Support: Use forceQueue for heavy operations
 *
 * 4. Filter Early: Only index what's necessary
 *
 * Common Indexer Issues:
 * - ProductIndexer with 5k+ variants runs out of memory
 * - cheapest_price field grows to 1MB+ with many variants
 * - DAL usage triggers events = infinite loops
 */
class OptimizedEntityIndexer extends EntityIndexer
{
    /**
     * Batch size for iteration
     * Keep this reasonable to avoid memory issues
     */
    private const BATCH_SIZE = 50;

    /**
     * Batch size for processing
     * Can be smaller if processing is heavy
     */
    private const PROCESS_BATCH_SIZE = 10;

    public function __construct(
        private readonly Connection $connection,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Unique indexer name
     * Used for selective indexing (dal:refresh:index --skip=...)
     */
    public function getName(): string
    {
        return 'custom.optimized.indexer';
    }

    /**
     * Iterate through all entities that need indexing
     *
     * Called by dal:refresh:index command
     * Returns batches of IDs to process
     */
    public function iterate(?array $offset): ?EntityIndexingMessage
    {
        $sql = <<<SQL
            SELECT LOWER(HEX(id)) as id
            FROM product
            WHERE parent_id IS NULL
              AND (:lastId IS NULL OR id > UNHEX(:lastId))
            ORDER BY id
            LIMIT :limit
        SQL;

        $ids = $this->connection->fetchFirstColumn($sql, [
            'lastId' => $offset['lastId'] ?? null,
            'limit' => self::BATCH_SIZE,
        ]);

        if (empty($ids)) {
            return null;
        }

        $this->logger->debug('Indexer iteration: {count} products', [
            'count' => count($ids),
            'lastId' => $offset['lastId'] ?? 'start',
        ]);

        // Return message with offset for next iteration
        return new EntityIndexingMessage(
            $ids,
            ['lastId' => end($ids)]
        );
    }

    /**
     * React to entity write events
     *
     * Called automatically when entities are written.
     * Returns message to process affected entities.
     */
    public function update(EntityWrittenContainerEvent $event): ?EntityIndexingMessage
    {
        $productEvent = $event->getEventByEntityName('product');

        if ($productEvent === null) {
            return null;
        }

        $ids = [];

        foreach ($productEvent->getWriteResults() as $result) {
            $payload = $result->getPayload();

            // Skip variants - we index parent products only
            if ($payload !== null && isset($payload['parentId'])) {
                continue;
            }

            // Skip delete operations
            if ($result->getOperation() === 'delete') {
                continue;
            }

            $ids[] = $result->getPrimaryKey();
        }

        if (empty($ids)) {
            return null;
        }

        $this->logger->info('Indexer update triggered for {count} products', [
            'count' => count($ids),
        ]);

        // Third parameter = forceQueue (true = async processing)
        // Use true for heavy operations to not block the request
        return new EntityIndexingMessage($ids, null, true);
    }

    /**
     * Process the indexing message
     *
     * IMPORTANT: Use Connection directly, NOT DAL!
     * DAL would trigger EntityWrittenEvent = infinite loop
     */
    public function handle(EntityIndexingMessage $message): void
    {
        $ids = $message->getData();

        if (empty($ids)) {
            return;
        }

        $this->logger->info('Processing {count} products in indexer', [
            'count' => count($ids),
        ]);

        $startTime = microtime(true);

        // Process in smaller batches within the message
        $batches = array_chunk($ids, self::PROCESS_BATCH_SIZE);

        $this->connection->transactional(function () use ($batches) {
            foreach ($batches as $batchIndex => $batch) {
                $this->indexBatch($batch);

                // Free memory after each batch
                gc_collect_cycles();
            }
        });

        $duration = microtime(true) - $startTime;

        $this->logger->info('Indexer completed in {duration}s', [
            'duration' => round($duration, 3),
            'count' => count($ids),
            'perSecond' => round(count($ids) / $duration, 1),
        ]);
    }

    /**
     * Index a batch of products
     *
     * Example: Calculate and store aggregated values
     */
    private function indexBatch(array $ids): void
    {
        if (empty($ids)) {
            return;
        }

        // Convert to binary IDs for SQL
        $binaryIds = array_map(
            fn($id) => hex2bin(str_replace('-', '', $id)),
            $ids
        );

        $placeholders = implode(',', array_fill(0, count($binaryIds), '?'));

        // ============================================
        // Example 1: Count variants per product
        // ============================================
        $this->connection->executeStatement(
            "UPDATE product p
             SET custom_fields = JSON_SET(
                 COALESCE(custom_fields, '{}'),
                 '$.variant_count',
                 (SELECT COUNT(*) FROM product v WHERE v.parent_id = p.id)
             )
             WHERE p.id IN ($placeholders)",
            $binaryIds
        );

        // ============================================
        // Example 2: Calculate total reviews
        // ============================================
        $this->connection->executeStatement(
            "UPDATE product p
             SET custom_fields = JSON_SET(
                 COALESCE(custom_fields, '{}'),
                 '$.review_count',
                 (SELECT COUNT(*) FROM product_review r WHERE r.product_id = p.id),
                 '$.avg_rating',
                 (SELECT AVG(points) FROM product_review r WHERE r.product_id = p.id)
             )
             WHERE p.id IN ($placeholders)",
            $binaryIds
        );

        // ============================================
        // Example 3: Update indexed timestamp
        // ============================================
        $this->connection->executeStatement(
            "UPDATE product
             SET custom_fields = JSON_SET(
                 COALESCE(custom_fields, '{}'),
                 '$.last_indexed_at',
                 ?
             )
             WHERE id IN ($placeholders)",
            array_merge([date('c')], $binaryIds)
        );
    }

    /**
     * Get total count for progress bar
     */
    public function getTotal(): int
    {
        return (int) $this->connection->fetchOne(
            'SELECT COUNT(*) FROM product WHERE parent_id IS NULL'
        );
    }

    /**
     * Required by EntityIndexer but we don't support decoration
     */
    public function getDecorated(): EntityIndexer
    {
        throw new DecorationPatternException(self::class);
    }
}
