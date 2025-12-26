<?php

declare(strict_types=1);

namespace App\MessageQueue;

use Shopware\Core\Framework\MessageQueue\AsyncMessageInterface;

/**
 * Product Import Message
 *
 * Async message for processing product imports in the background.
 *
 * Implementing AsyncMessageInterface ensures the message is:
 * - Processed asynchronously via the message queue
 * - Not blocking the original request
 * - Retryable on failure
 *
 * Use cases:
 * - ERP imports
 * - Bulk updates
 * - Heavy calculations
 * - External API sync
 */
class ProductImportMessage implements AsyncMessageInterface
{
    /**
     * @param array<string> $productIds Product IDs to process
     * @param string $importSource Source identifier (erp, csv, api, etc.)
     * @param array<string, mixed> $options Optional processing options
     */
    public function __construct(
        private readonly array $productIds,
        private readonly string $importSource,
        private readonly array $options = []
    ) {}

    /**
     * Get product IDs to process
     *
     * @return array<string>
     */
    public function getProductIds(): array
    {
        return $this->productIds;
    }

    /**
     * Get import source identifier
     */
    public function getImportSource(): string
    {
        return $this->importSource;
    }

    /**
     * Get processing options
     *
     * @return array<string, mixed>
     */
    public function getOptions(): array
    {
        return $this->options;
    }

    /**
     * Check if indexing should be skipped
     */
    public function shouldSkipIndexing(): bool
    {
        return $this->options['skipIndexing'] ?? false;
    }

    /**
     * Check if cache invalidation should be delayed
     */
    public function shouldDelayCacheInvalidation(): bool
    {
        return $this->options['delayCacheInvalidation'] ?? true;
    }

    /**
     * Get batch size for processing
     */
    public function getBatchSize(): int
    {
        return $this->options['batchSize'] ?? 100;
    }
}
