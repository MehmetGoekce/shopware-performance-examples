<?php

declare(strict_types=1);

namespace App\Cache;

use Psr\Cache\CacheItemPoolInterface;
use Psr\Cache\CacheItemInterface;
use Symfony\Component\Cache\Adapter\RedisAdapter;

/**
 * Fallstudie 5: Internationaler Marketplace - Tenant-Aware Cache
 * Kapitel 23: Reale Fallstudien aus 26 Jahren
 *
 * Multi-Tenant Redis-Cache mit Tenant-Isolation.
 * Verhindert Cache-Kollisionen zwischen Mandanten und
 * ermöglicht tenant-spezifische Cache-Invalidierung.
 *
 * Ergebnis: 340% Traffic-Steigerung ohne Performance-Einbußen
 */
class TenantAwareCache implements CacheItemPoolInterface
{
    private ?string $currentTenantId = null;

    public function __construct(
        private readonly RedisAdapter $redis,
        private readonly TenantResolver $tenantResolver
    ) {
    }

    /**
     * Cache-Key mit Tenant-Prefix
     */
    private function prefixKey(string $key): string
    {
        $tenantId = $this->getCurrentTenantId();
        return sprintf('tenant_%s_%s', $tenantId, $key);
    }

    /**
     * Aktuellen Tenant ermitteln
     */
    private function getCurrentTenantId(): string
    {
        if ($this->currentTenantId === null) {
            $this->currentTenantId = $this->tenantResolver->resolve();
        }
        return $this->currentTenantId;
    }

    /**
     * Tenant-Context setzen (für Background-Jobs)
     */
    public function setTenantContext(string $tenantId): void
    {
        $this->currentTenantId = $tenantId;
    }

    // CacheItemPoolInterface Implementation

    public function getItem(string $key): CacheItemInterface
    {
        return $this->redis->getItem($this->prefixKey($key));
    }

    public function getItems(array $keys = []): iterable
    {
        $prefixedKeys = array_map([$this, 'prefixKey'], $keys);
        return $this->redis->getItems($prefixedKeys);
    }

    public function hasItem(string $key): bool
    {
        return $this->redis->hasItem($this->prefixKey($key));
    }

    public function clear(): bool
    {
        // Nur Cache des aktuellen Tenants löschen
        $pattern = sprintf('tenant_%s_*', $this->getCurrentTenantId());
        return $this->clearByPattern($pattern);
    }

    public function deleteItem(string $key): bool
    {
        return $this->redis->deleteItem($this->prefixKey($key));
    }

    public function deleteItems(array $keys): bool
    {
        $prefixedKeys = array_map([$this, 'prefixKey'], $keys);
        return $this->redis->deleteItems($prefixedKeys);
    }

    public function save(CacheItemInterface $item): bool
    {
        return $this->redis->save($item);
    }

    public function saveDeferred(CacheItemInterface $item): bool
    {
        return $this->redis->saveDeferred($item);
    }

    public function commit(): bool
    {
        return $this->redis->commit();
    }

    // Erweiterte Multi-Tenant Funktionen

    /**
     * Cache eines spezifischen Tenants löschen (Admin-Funktion)
     */
    public function clearTenantCache(string $tenantId): bool
    {
        $pattern = sprintf('tenant_%s_*', $tenantId);
        return $this->clearByPattern($pattern);
    }

    /**
     * Cache aller Tenants löschen (nur für Deployments)
     */
    public function clearAllTenantsCache(): bool
    {
        return $this->clearByPattern('tenant_*');
    }

    /**
     * Cache-Statistiken pro Tenant
     */
    public function getTenantCacheStats(string $tenantId): array
    {
        $pattern = sprintf('tenant_%s_*', $tenantId);
        $keys = $this->scanKeys($pattern);

        return [
            'tenant_id' => $tenantId,
            'key_count' => count($keys),
            'estimated_size' => $this->estimateCacheSize($keys),
        ];
    }

    /**
     * Pattern-basierte Cache-Löschung via Redis SCAN
     */
    private function clearByPattern(string $pattern): bool
    {
        $keys = $this->scanKeys($pattern);

        if (empty($keys)) {
            return true;
        }

        return $this->redis->deleteItems($keys);
    }

    /**
     * Redis SCAN für Pattern-Matching
     */
    private function scanKeys(string $pattern): array
    {
        $redis = $this->getRedisConnection();
        $keys = [];
        $iterator = null;

        do {
            $result = $redis->scan($iterator, $pattern, 1000);
            if ($result !== false) {
                $keys = array_merge($keys, $result);
            }
        } while ($iterator !== 0);

        return $keys;
    }

    /**
     * Cache-Größe schätzen
     */
    private function estimateCacheSize(array $keys): int
    {
        $redis = $this->getRedisConnection();
        $size = 0;

        foreach (array_slice($keys, 0, 100) as $key) {
            $size += $redis->strlen($key);
        }

        // Hochrechnen auf alle Keys
        if (count($keys) > 100) {
            $avgSize = $size / 100;
            $size = (int) ($avgSize * count($keys));
        }

        return $size;
    }

    private function getRedisConnection(): \Redis
    {
        $reflection = new \ReflectionClass($this->redis);
        $property = $reflection->getProperty('redis');
        $property->setAccessible(true);
        return $property->getValue($this->redis);
    }
}

/**
 * Tenant-Resolver Interface
 */
interface TenantResolver
{
    public function resolve(): string;
}

/**
 * Domain-basierter Tenant-Resolver
 */
class DomainTenantResolver implements TenantResolver
{
    public function __construct(
        private readonly array $tenantDomainMap
    ) {
    }

    public function resolve(): string
    {
        $host = $_SERVER['HTTP_HOST'] ?? 'default';

        return $this->tenantDomainMap[$host] ?? 'default';
    }
}
