<?php

declare(strict_types=1);

/**
 * Purgt HTML-Seiten am CDN, wenn Produkte oder Kategorien geschrieben werden
 * Kapitel 11: CDN-Integration
 *
 * Bewusst NICHT enthalten: Purge von Mediendateien. Shopware schreibt den
 * Upload-Timestamp in den Medienpfad (media/<hash>/<cacheBuster>/datei.jpg) und
 * haengt zusaetzlich ?ts=<uploadedAt> an. Eine ersetzte Datei bekommt damit eine
 * neue URL - die alte zu purgen bringt nichts. Zu invalidieren sind die
 * HTML-Seiten, die die alte URL referenzieren, und die traegt Shopware bereits
 * als Tag (product-<id>) an der Antwort.
 *
 * Die Tags stammen aus CdnCacheTagSubscriber, der Shopwares xkey-Tags als
 * Cache-Tag-Header ausliefert. Ohne diesen Header purgt Cloudflare ins Leere.
 *
 * Produktiv gehoert der Purge hinter Symfony Messenger: product.written feuert
 * bei jeder Bestandsaenderung, also auch bei jeder Bestellung, und ein
 * synchroner HTTP-Call haengt dann im Request-Pfad. Das Beispiel bleibt
 * synchron, damit der Ablauf sichtbar bleibt.
 *
 * @see https://developers.cloudflare.com/cache/how-to/purge-cache/
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\EventSubscriber;

use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use YourPlugin\Service\CloudflarePurgeService;

class CdnPurgeSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly CloudflarePurgeService $purgeService
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            'product.written' => 'onProductWritten',
            'category.written' => 'onCategoryWritten',
        ];
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        $this->purgeService->purgeByTags(
            array_map(static fn (string $id): string => 'product-' . $id, $event->getIds())
        );
    }

    /**
     * Die Tag-Namen stehen im Core, nicht im Handbuch, und keiner davon heisst
     * schlicht "category-<id>":
     *
     *   CachedCategoryRoute::buildName()        -> category-route-<id>
     *   ProductListingRoute::buildName()        -> product-listing-<id>
     *   CachedProductListingRoute::buildName()  -> product-listing-route-<id>
     *
     * Wer "category-<id>" purgt, purgt ins Leere - der Tag existiert nicht.
     * "navigation" dagegen schon, den traegt jede Seite mit Hauptnavigation.
     *
     * Die Produkte *innerhalb* einer Listing-Seite sind nicht einzeln getaggt
     * ("List-type routes are not tagged with all entities returned in the
     * response ... These routes instead rely on their TTL") - ein neues Produkt
     * in einer Kategorie erscheint also erst nach Ablauf der TTL.
     *
     * @see https://developer.shopware.com/docs/concepts/framework/http_cache.html
     */
    public function onCategoryWritten(EntityWrittenEvent $event): void
    {
        $tags = ['navigation'];

        foreach ($event->getIds() as $id) {
            $tags[] = 'category-route-' . $id;
            $tags[] = 'product-listing-' . $id;
            $tags[] = 'product-listing-route-' . $id;
        }

        $this->purgeService->purgeByTags($tags);
    }
}
