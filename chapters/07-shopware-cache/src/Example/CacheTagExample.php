<?php

declare(strict_types=1);

/**
 * Cache-Tags nach dem Symfony-Prinzip, das auch Shopware nutzt
 * Kapitel 7: Shopwares Application Cache meistern
 *
 * Tags werden am Cache-Eintrag gesetzt ($item->tag()), nicht als drittes
 * Argument von get() - das ist $beta (Early Expiration).
 * get() erneuert einen Eintrag mit einer gewissen Wahrscheinlichkeit schon vor
 * Ablauf (Probabilistic Early Expiration, $beta = 1.0).
 * Die zusätzliche Sperre von Symfony (LockRegistry, rund 20 Dateisperren, auf die
 * die Keys per crc32 verteilt werden) greift nur bei undekorierten Symfony-Pools.
 * Shopwares cache.object ist in 6.6 von CacheDecorator gewrappt, der den
 * Contracts-CacheTrait ohne LockRegistry nutzt - dort sperrt niemand.
 *
 * Getestet mit RedisTagAwareAdapter (Shopware 6.6.10.6, Redis 7.4).
 *
 * @see https://symfony.com/doc/current/cache.html
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\Example;

use Symfony\Contracts\Cache\ItemInterface;
use Symfony\Contracts\Cache\TagAwareCacheInterface;

class CacheTagExample
{
    public function __construct(
        private readonly TagAwareCacheInterface $cache
    ) {
    }

    /**
     * @return array<string, string>
     */
    public function loadProduct(string $id): array
    {
        return $this->cache->get('product_' . $id, function (ItemInterface $item) use ($id) {
            $item->expiresAfter(3600);
            $item->tag(['product-' . $id, 'category-XYZ']);

            return $this->loadFromDatabase($id);
        });
    }

    public function onProductChanged(string $id): void
    {
        // Alle Einträge mit diesem Tag verwerfen
        $this->cache->invalidateTags(['product-' . $id]);
    }

    /**
     * @return array<string, string>
     */
    private function loadFromDatabase(string $id): array
    {
        return ['id' => $id];
    }
}
