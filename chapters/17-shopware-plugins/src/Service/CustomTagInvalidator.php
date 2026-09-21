<?php

declare(strict_types=1);

namespace App\Service;

use Shopware\Core\Framework\Adapter\Cache\CacheInvalidator;

/**
 * Invalidiert das Tag, das CacheTagSubscriber vergibt.
 *
 * Setzer und Invalidierer müssen dasselbe Tag verwenden - deshalb
 * bauen beide Seiten es mit derselben Methode tag().
 *
 * Aufruf dort, wo sich die eigene Quelle ändert (ERP-Import,
 * Webhook, Cronjob). Für Änderungen über den DAL ist das nicht
 * nötig: Dann invalidiert Shopware die Produktseiten selbst.
 *
 * @see Kapitel 17, "Kontrollierte Cache-Invalidierung"
 */
class CustomTagInvalidator
{
    public function __construct(
        private readonly CacheInvalidator $cacheInvalidator
    ) {}

    public static function tag(string $productId): string
    {
        return 'custom-product-' . $productId;
    }

    /**
     * @param list<string> $productIds
     */
    public function invalidateProducts(array $productIds): void
    {
        // Ein Aufruf für alle Tags statt einer je Produkt
        $this->cacheInvalidator->invalidate(array_map(
            self::tag(...),
            $productIds
        ));
    }
}
