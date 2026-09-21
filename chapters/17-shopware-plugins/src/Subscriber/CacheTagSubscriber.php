<?php

declare(strict_types=1);

namespace App\Subscriber;

use App\Service\CustomTagInvalidator;
use Shopware\Core\Framework\Adapter\Cache\Event\AddCacheTagEvent;
use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Contracts\EventDispatcher\EventDispatcherInterface;

/**
 * Eigenes Cache-Tag für Daten, von denen Shopware nichts weiss.
 *
 * Beispiel: Die Detailseite zeigt einen Wert aus einer eigenen
 * Quelle (ERP-Lagerampel, externe Bewertung). Ändert sich der
 * Wert, invalidiert CustomTagInvalidator genau dieses Tag - und
 * damit nur die betroffenen Seiten.
 *
 * AddCacheTagEvent gibt es ab Shopware 6.6.6.0. Tags aus der früher
 * gezeigten CacheTagCollection erreichen den HTTP-Cache in 6.6 noch,
 * in 6.7.0.0 nicht mehr: Http\CacheStore liest dort nur den
 * CacheTagCollector (dieses Event) und den Header sw-cache-tags.
 *
 * @see Kapitel 17, "Eigene Cache-Tags hinzufügen"
 * @see Kapitel 6, "Eigenes Cache-Tag"
 */
class CacheTagSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly EventDispatcherInterface $dispatcher
    ) {}

    public static function getSubscribedEvents(): array
    {
        return [
            StorefrontRenderEvent::class => 'addCacheTags',
        ];
    }

    public function addCacheTags(StorefrontRenderEvent $event): void
    {
        $request = $event->getRequest();

        if ($request->attributes->get('_route') !== 'frontend.detail.page') {
            return;
        }

        $productId = $request->attributes->get('productId');
        if (!\is_string($productId)) {
            return;
        }

        $this->dispatcher->dispatch(new AddCacheTagEvent(CustomTagInvalidator::tag($productId)));
    }
}
