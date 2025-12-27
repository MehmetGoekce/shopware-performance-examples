<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Cache\CacheItemPoolInterface;
use Shopware\Core\System\SalesChannel\SalesChannelContext;

/**
 * Fallstudie 3: B2B Industriebedarf - Preis-Caching
 * Kapitel 23: Reale Fallstudien aus 26 Jahren
 *
 * Redis-Cache für komplexe Preisberechnungen.
 * B2B-Shops haben oft kundenspezifische Preise mit
 * Staffelungen, Rabatten und Währungsumrechnung.
 *
 * Ergebnis: Preisberechnung von 340ms auf 12ms
 */
class PriceCalculationCache
{
    private const CACHE_TTL = 3600; // 1 Stunde
    private const CACHE_PREFIX = 'price_calc_';

    public function __construct(
        private readonly CacheItemPoolInterface $cache,
        private readonly PriceCalculationService $priceService
    ) {
    }

    /**
     * Kundenspezifischen Preis mit Caching abrufen
     */
    public function getCustomerPrice(
        string $productId,
        string $customerId,
        SalesChannelContext $context,
        ?callable $fallback = null
    ): CalculatedPrice {
        $cacheKey = $this->buildCacheKey($productId, $customerId, $context);
        $cacheItem = $this->cache->getItem($cacheKey);

        if ($cacheItem->isHit()) {
            return $cacheItem->get();
        }

        // Cache-Miss: Preis berechnen
        $price = $fallback !== null
            ? $fallback()
            : $this->priceService->calculate($productId, $customerId, $context);

        // In Cache speichern
        $cacheItem->set($price);
        $cacheItem->expiresAfter(self::CACHE_TTL);
        $this->cache->save($cacheItem);

        return $price;
    }

    /**
     * Staffelpreise mit Caching
     */
    public function getTierPrices(
        string $productId,
        string $customerId,
        array $quantities,
        SalesChannelContext $context
    ): array {
        $prices = [];

        foreach ($quantities as $quantity) {
            $cacheKey = $this->buildTierCacheKey($productId, $customerId, $quantity, $context);
            $cacheItem = $this->cache->getItem($cacheKey);

            if ($cacheItem->isHit()) {
                $prices[$quantity] = $cacheItem->get();
                continue;
            }

            // Berechnen und cachen
            $price = $this->priceService->calculateTierPrice(
                $productId,
                $customerId,
                $quantity,
                $context
            );

            $cacheItem->set($price);
            $cacheItem->expiresAfter(self::CACHE_TTL);
            $this->cache->save($cacheItem);

            $prices[$quantity] = $price;
        }

        return $prices;
    }

    /**
     * Cache für Kunde invalidieren (bei Vertragsänderung)
     */
    public function invalidateCustomerCache(string $customerId): void
    {
        // Redis SCAN für Pattern-basierte Invalidierung
        $pattern = self::CACHE_PREFIX . '*_' . $customerId . '_*';

        if ($this->cache instanceof \Symfony\Component\Cache\Adapter\RedisAdapter) {
            $this->cache->clear($pattern);
        }
    }

    /**
     * Cache für Produkt invalidieren (bei Preisänderung)
     */
    public function invalidateProductCache(string $productId): void
    {
        $pattern = self::CACHE_PREFIX . $productId . '_*';

        if ($this->cache instanceof \Symfony\Component\Cache\Adapter\RedisAdapter) {
            $this->cache->clear($pattern);
        }
    }

    /**
     * Cache-Key aufbauen
     *
     * Format: price_calc_{productId}_{customerId}_{salesChannelId}_{currencyId}
     */
    private function buildCacheKey(
        string $productId,
        string $customerId,
        SalesChannelContext $context
    ): string {
        return sprintf(
            '%s%s_%s_%s_%s',
            self::CACHE_PREFIX,
            $productId,
            $customerId,
            $context->getSalesChannelId(),
            $context->getCurrency()->getId()
        );
    }

    /**
     * Cache-Key für Staffelpreise
     */
    private function buildTierCacheKey(
        string $productId,
        string $customerId,
        int $quantity,
        SalesChannelContext $context
    ): string {
        return sprintf(
            '%s%s_%s_%s_%s_qty%d',
            self::CACHE_PREFIX,
            $productId,
            $customerId,
            $context->getSalesChannelId(),
            $context->getCurrency()->getId(),
            $quantity
        );
    }
}

/**
 * Value Object für berechneten Preis
 */
class CalculatedPrice
{
    public function __construct(
        public readonly float $unitPrice,
        public readonly float $totalPrice,
        public readonly float $netPrice,
        public readonly float $taxRate,
        public readonly string $currencyCode
    ) {
    }
}
