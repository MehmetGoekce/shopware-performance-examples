<?php

declare(strict_types=1);

namespace App\Subscriber;

use Doctrine\DBAL\Connection;
use Psr\Log\LoggerInterface;
use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Defaults;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Performance-Aware Event Subscriber
 *
 * Demonstrates best practices for event subscribers:
 *
 * 1. Loop Protection: Prevents infinite loops when subscriber
 *    modifies the same entity type it's listening to.
 *
 * 2. Version Filtering: Only processes live version, not drafts.
 *
 * 3. DBAL Usage: Uses Connection directly to avoid triggering
 *    additional events (which would happen with DAL).
 *
 * 4. Selective Processing: Only reacts to specific field changes.
 *
 * 5. Batch Processing: Groups operations for efficiency.
 */
class PerformanceAwareSubscriber implements EventSubscriberInterface
{
    /**
     * Loop protection flag
     * Prevents re-entry during our own writes
     */
    private bool $isProcessing = false;

    public function __construct(
        private readonly Connection $connection,
        private readonly LoggerInterface $logger
    ) {}

    public static function getSubscribedEvents(): array
    {
        return [
            // Priority 100 = runs before most other subscribers
            ProductEvents::PRODUCT_WRITTEN_EVENT => ['onProductWritten', 100],
        ];
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        // ============================================
        // Guard 1: Loop Protection
        // ============================================
        if ($this->isProcessing) {
            return;
        }

        // ============================================
        // Guard 2: Only Live Version
        // ============================================
        // Versioned entities (products, orders) dispatch events
        // for both live and draft versions. We only want live.
        if ($event->getContext()->getVersionId() !== Defaults::LIVE_VERSION) {
            return;
        }

        // ============================================
        // Guard 3: Filter Relevant Changes Only
        // ============================================
        $productIdsToProcess = [];

        foreach ($event->getWriteResults() as $result) {
            // Skip if no payload (delete operations)
            $payload = $result->getPayload();
            if ($payload === null) {
                continue;
            }

            // Only react to specific field changes
            // This prevents unnecessary processing
            $relevantFields = ['name', 'description', 'price', 'stock'];
            $hasRelevantChange = false;

            foreach ($relevantFields as $field) {
                if (array_key_exists($field, $payload)) {
                    $hasRelevantChange = true;
                    break;
                }
            }

            if ($hasRelevantChange) {
                $productIdsToProcess[] = $result->getPrimaryKey();
            }
        }

        // Nothing to process
        if (empty($productIdsToProcess)) {
            return;
        }

        // ============================================
        // Processing with Loop Protection
        // ============================================
        $this->isProcessing = true;

        try {
            $this->processProducts($productIdsToProcess);
        } catch (\Throwable $e) {
            $this->logger->error('Failed to process products: {message}', [
                'message' => $e->getMessage(),
                'productIds' => $productIdsToProcess,
            ]);
        } finally {
            // ALWAYS reset the flag, even on error
            $this->isProcessing = false;
        }
    }

    /**
     * Process products using DBAL
     *
     * IMPORTANT: We use Connection directly, NOT the DAL!
     *
     * Using DAL here would:
     * - Trigger PRODUCT_WRITTEN_EVENT again
     * - Create potential for infinite loops
     * - Add unnecessary overhead
     *
     * @param array<string> $productIds
     */
    private function processProducts(array $productIds): void
    {
        if (empty($productIds)) {
            return;
        }

        $this->logger->info('Processing {count} products', [
            'count' => count($productIds),
        ]);

        // Convert IDs to binary for SQL
        $binaryIds = array_map(
            fn($id) => hex2bin(str_replace('-', '', $id)),
            $productIds
        );

        $placeholders = implode(',', array_fill(0, count($binaryIds), '?'));

        // Example: Update a custom field to track processing
        $sql = <<<SQL
            UPDATE product
            SET custom_fields = JSON_SET(
                COALESCE(custom_fields, '{}'),
                '$.last_processed_at',
                :timestamp
            )
            WHERE id IN ($placeholders)
        SQL;

        $this->connection->executeStatement(
            $sql,
            array_merge([date('c')], $binaryIds)
        );

        $this->logger->info('Successfully processed {count} products', [
            'count' => count($productIds),
        ]);
    }
}
