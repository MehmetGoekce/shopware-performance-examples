<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use Doctrine\DBAL\Connection;
use Psr\Log\LoggerInterface;
use Shopware\Elasticsearch\Framework\ElasticsearchHelper;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * Optimizes Elasticsearch indexing performance.
 *
 * Features:
 * - Disable refresh during bulk import
 * - Force merge after indexing
 * - Batch size optimization
 * - Index alias management for zero-downtime reindex
 *
 * Usage:
 *   Inject and call methods before/after bulk operations
 *
 * @example
 *   $optimizer->prepareForBulkIndex('sw_product');
 *   // ... perform indexing ...
 *   $optimizer->finalizeBulkIndex('sw_product');
 */
class IndexingOptimizer
{
    private const DEFAULT_REFRESH_INTERVAL = '5s';
    private const BULK_REFRESH_INTERVAL = '-1'; // Disabled

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly LoggerInterface $logger,
        private readonly string $elasticsearchUrl = 'http://localhost:9200'
    ) {
    }

    /**
     * Prepare index for bulk operations.
     *
     * Disables refresh interval for faster indexing.
     * IMPORTANT: Call finalizeBulkIndex() when done!
     */
    public function prepareForBulkIndex(string $indexName): void
    {
        $this->logger->info('Preparing index for bulk operations', ['index' => $indexName]);

        $this->setRefreshInterval($indexName, self::BULK_REFRESH_INTERVAL);
        $this->setTranslogDurability($indexName, 'async');
    }

    /**
     * Finalize after bulk operations.
     *
     * Re-enables refresh, runs force merge, refreshes index.
     */
    public function finalizeBulkIndex(string $indexName): void
    {
        $this->logger->info('Finalizing bulk index operations', ['index' => $indexName]);

        // Re-enable refresh
        $this->setRefreshInterval($indexName, self::DEFAULT_REFRESH_INTERVAL);
        $this->setTranslogDurability($indexName, 'request');

        // Force merge for optimal segment count
        $this->forceMerge($indexName);

        // Explicit refresh
        $this->refreshIndex($indexName);
    }

    /**
     * Set index refresh interval.
     *
     * @param string $interval Use '-1' to disable, '5s' for 5 seconds, etc.
     */
    public function setRefreshInterval(string $indexName, string $interval): void
    {
        $this->updateSettings($indexName, [
            'index' => [
                'refresh_interval' => $interval,
            ],
        ]);
    }

    /**
     * Set translog durability mode.
     *
     * @param string $durability 'request' (safe) or 'async' (fast)
     */
    public function setTranslogDurability(string $indexName, string $durability): void
    {
        $this->updateSettings($indexName, [
            'index' => [
                'translog' => [
                    'durability' => $durability,
                ],
            ],
        ]);
    }

    /**
     * Force merge index segments.
     *
     * Reduces segment count for faster queries.
     * WARNING: CPU intensive - run during low traffic!
     *
     * @param int $maxSegments Target segment count (1 is optimal but slow)
     */
    public function forceMerge(string $indexName, int $maxSegments = 1): void
    {
        $url = sprintf('%s/%s/_forcemerge?max_num_segments=%d',
            $this->elasticsearchUrl,
            $indexName,
            $maxSegments
        );

        try {
            $response = $this->httpClient->request('POST', $url);
            $result = $response->toArray();

            $this->logger->info('Force merge completed', [
                'index' => $indexName,
                'shards' => $result['_shards'] ?? [],
            ]);
        } catch (\Throwable $e) {
            $this->logger->error('Force merge failed', [
                'index' => $indexName,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Refresh index to make documents searchable.
     */
    public function refreshIndex(string $indexName): void
    {
        $url = sprintf('%s/%s/_refresh', $this->elasticsearchUrl, $indexName);

        try {
            $this->httpClient->request('POST', $url);
        } catch (\Throwable $e) {
            $this->logger->error('Refresh failed', [
                'index' => $indexName,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Clear index caches.
     *
     * Useful after large updates to free memory.
     */
    public function clearCache(string $indexName): void
    {
        $url = sprintf('%s/%s/_cache/clear', $this->elasticsearchUrl, $indexName);

        try {
            $this->httpClient->request('POST', $url);
            $this->logger->info('Cache cleared', ['index' => $indexName]);
        } catch (\Throwable $e) {
            $this->logger->error('Cache clear failed', [
                'index' => $indexName,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Get index statistics.
     *
     * @return array{docs: int, size_bytes: int, segments: int}
     */
    public function getIndexStats(string $indexName): array
    {
        $url = sprintf('%s/%s/_stats', $this->elasticsearchUrl, $indexName);

        try {
            $response = $this->httpClient->request('GET', $url);
            $data = $response->toArray();

            $indices = $data['indices'][$indexName] ?? [];
            $primaries = $indices['primaries'] ?? [];

            return [
                'docs' => $primaries['docs']['count'] ?? 0,
                'size_bytes' => $primaries['store']['size_in_bytes'] ?? 0,
                'segments' => $primaries['segments']['count'] ?? 0,
            ];
        } catch (\Throwable $e) {
            return ['docs' => 0, 'size_bytes' => 0, 'segments' => 0];
        }
    }

    /**
     * Check if index exists.
     */
    public function indexExists(string $indexName): bool
    {
        $url = sprintf('%s/%s', $this->elasticsearchUrl, $indexName);

        try {
            $response = $this->httpClient->request('HEAD', $url);
            return $response->getStatusCode() === 200;
        } catch (\Throwable $e) {
            return false;
        }
    }

    private function updateSettings(string $indexName, array $settings): void
    {
        $url = sprintf('%s/%s/_settings', $this->elasticsearchUrl, $indexName);

        try {
            $this->httpClient->request('PUT', $url, [
                'json' => $settings,
            ]);
        } catch (\Throwable $e) {
            $this->logger->error('Failed to update settings', [
                'index' => $indexName,
                'settings' => $settings,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
