<?php

declare(strict_types=1);

namespace App\MessageQueue;

use Doctrine\DBAL\Connection;
use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

/**
 * Async Product Handler
 *
 * Handles ProductImportMessage asynchronously.
 *
 * Best Practices:
 * 1. Batch processing for memory efficiency
 * 2. Progress logging for monitoring
 * 3. Graceful error handling
 * 4. Memory cleanup between batches
 * 5. DBAL for performance-critical operations
 */
#[AsMessageHandler]
class AsyncProductHandler
{
    public function __construct(
        private readonly Connection $connection,
        private readonly LoggerInterface $logger
    ) {}

    public function __invoke(ProductImportMessage $message): void
    {
        $productIds = $message->getProductIds();
        $source = $message->getImportSource();
        $batchSize = $message->getBatchSize();

        $this->logger->info('Starting async product processing', [
            'count' => count($productIds),
            'source' => $source,
            'batchSize' => $batchSize,
        ]);

        $startTime = microtime(true);
        $processed = 0;
        $failed = 0;

        // Process in batches for memory efficiency
        $batches = array_chunk($productIds, $batchSize);

        foreach ($batches as $batchIndex => $batch) {
            try {
                $this->processBatch($batch, $message);
                $processed += count($batch);

                $this->logger->debug('Batch {index} processed', [
                    'index' => $batchIndex + 1,
                    'total' => count($batches),
                    'processed' => $processed,
                ]);
            } catch (\Throwable $e) {
                $failed += count($batch);

                $this->logger->error('Batch {index} failed: {message}', [
                    'index' => $batchIndex + 1,
                    'message' => $e->getMessage(),
                    'batch' => $batch,
                ]);

                // Continue with next batch instead of failing completely
                // For critical operations, you might want to throw instead
            }

            // Free memory after each batch
            gc_collect_cycles();
        }

        $duration = microtime(true) - $startTime;

        $this->logger->info('Async product processing completed', [
            'source' => $source,
            'processed' => $processed,
            'failed' => $failed,
            'duration' => round($duration, 2),
            'perSecond' => round($processed / max($duration, 0.001), 1),
        ]);
    }

    /**
     * Process a batch of product IDs
     */
    private function processBatch(array $productIds, ProductImportMessage $message): void
    {
        if (empty($productIds)) {
            return;
        }

        // Convert to binary for SQL
        $binaryIds = array_map(
            fn($id) => hex2bin(str_replace('-', '', $id)),
            $productIds
        );

        $placeholders = implode(',', array_fill(0, count($binaryIds), '?'));

        $this->connection->transactional(function () use ($binaryIds, $placeholders, $message) {
            // ============================================
            // Example: Update import metadata
            // ============================================
            $this->connection->executeStatement(
                "UPDATE product
                 SET custom_fields = JSON_SET(
                     COALESCE(custom_fields, '{}'),
                     '$.import_source',
                     ?,
                     '$.import_timestamp',
                     ?
                 )
                 WHERE id IN ($placeholders)",
                array_merge(
                    [$message->getImportSource(), date('c')],
                    $binaryIds
                )
            );

            // ============================================
            // Example: Mark as needing review (for imports)
            // ============================================
            if ($message->getImportSource() === 'erp') {
                $this->connection->executeStatement(
                    "UPDATE product
                     SET custom_fields = JSON_SET(
                         COALESCE(custom_fields, '{}'),
                         '$.needs_review',
                         true
                     )
                     WHERE id IN ($placeholders)
                       AND JSON_EXTRACT(custom_fields, '$.auto_import') = true",
                    $binaryIds
                );
            }

            // ============================================
            // Example: Update stock from external source
            // ============================================
            // This would typically include fetching data from the import source
            // and updating stock values

            // ============================================
            // Example: Calculate derived fields
            // ============================================
            $this->connection->executeStatement(
                "UPDATE product p
                 SET custom_fields = JSON_SET(
                     COALESCE(custom_fields, '{}'),
                     '$.has_stock',
                     CASE WHEN stock > 0 THEN true ELSE false END
                 )
                 WHERE id IN ($placeholders)",
                $binaryIds
            );
        });
    }
}
