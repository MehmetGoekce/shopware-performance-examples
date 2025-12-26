<?php

declare(strict_types=1);

namespace PerformanceExamples\Subscriber;

use Shopware\Core\Framework\Routing\KernelListenerPriorities;
use Shopware\Core\PlatformRequest;
use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * HTTP-Cache-Header Subscriber für optimierte Caching-Strategie
 *
 * Kapitel 1: Der Performance-Imperativ (Case Study)
 *
 * Setzt aggressive Cache-Header für verschiedene Seitentypen.
 * Verwendet stale-while-revalidate für bessere User Experience.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
class HttpCacheSubscriber implements EventSubscriberInterface
{
    /**
     * Cache-TTL Konfiguration nach Seitentyp (in Sekunden)
     */
    private const CACHE_CONFIG = [
        // Produktseiten: 5 Minuten Cache, 24h stale-while-revalidate
        'product' => [
            'max_age' => 300,
            'stale_while_revalidate' => 86400,
            'surrogate_max_age' => 3600,
        ],
        // Kategorieseiten: 10 Minuten Cache
        'category' => [
            'max_age' => 600,
            'stale_while_revalidate' => 86400,
            'surrogate_max_age' => 3600,
        ],
        // Startseite: 2 Minuten Cache (häufigere Updates)
        'home' => [
            'max_age' => 120,
            'stale_while_revalidate' => 3600,
            'surrogate_max_age' => 1800,
        ],
        // CMS-Seiten: 1 Stunde Cache
        'cms' => [
            'max_age' => 3600,
            'stale_while_revalidate' => 86400,
            'surrogate_max_age' => 7200,
        ],
        // Default: 5 Minuten
        'default' => [
            'max_age' => 300,
            'stale_while_revalidate' => 3600,
            'surrogate_max_age' => 1800,
        ],
    ];

    /**
     * Seiten die NICHT gecacht werden dürfen
     */
    private const NO_CACHE_ROUTES = [
        'frontend.checkout.cart.page',
        'frontend.checkout.confirm.page',
        'frontend.checkout.finish.page',
        'frontend.account.login.page',
        'frontend.account.order.page',
        'frontend.account.profile.page',
    ];

    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::RESPONSE => [
                ['onResponse', KernelListenerPriorities::KERNEL_CONTROLLER_EVENT_SCOPE_VALIDATE],
            ],
        ];
    }

    public function onResponse(ResponseEvent $event): void
    {
        $request = $event->getRequest();
        $response = $event->getResponse();

        // Nur Storefront-Requests
        if (!$request->attributes->has(PlatformRequest::ATTRIBUTE_SALES_CHANNEL_ID)) {
            return;
        }

        // Keine Cache-Header für eingeloggte Benutzer
        if ($request->attributes->get('_customer')) {
            $this->setNoCache($response);
            return;
        }

        // Keine Cache-Header für bestimmte Routes
        $route = $request->attributes->get('_route', '');
        if (in_array($route, self::NO_CACHE_ROUTES, true)) {
            $this->setNoCache($response);
            return;
        }

        // Nur erfolgreiche GET-Requests cachen
        if ($request->getMethod() !== 'GET' || $response->getStatusCode() !== 200) {
            return;
        }

        // Cache-Konfiguration basierend auf Route ermitteln
        $config = $this->getCacheConfig($route);

        // Cache-Header setzen
        $this->setCacheHeaders($response, $config);
    }

    private function getCacheConfig(string $route): array
    {
        return match (true) {
            str_contains($route, 'product') => self::CACHE_CONFIG['product'],
            str_contains($route, 'category') || str_contains($route, 'listing') => self::CACHE_CONFIG['category'],
            $route === 'frontend.home.page' => self::CACHE_CONFIG['home'],
            str_contains($route, 'cms') => self::CACHE_CONFIG['cms'],
            default => self::CACHE_CONFIG['default'],
        };
    }

    private function setCacheHeaders($response, array $config): void
    {
        // Standard Cache-Control Header
        $cacheControl = sprintf(
            'public, max-age=%d, stale-while-revalidate=%d',
            $config['max_age'],
            $config['stale_while_revalidate']
        );

        $response->headers->set('Cache-Control', $cacheControl);

        // Surrogate-Control für CDN/Varnish
        $response->headers->set(
            'Surrogate-Control',
            sprintf('max-age=%d', $config['surrogate_max_age'])
        );

        // Vary-Header für korrektes Caching
        $response->headers->set('Vary', 'Accept-Encoding, Cookie');
    }

    private function setNoCache($response): void
    {
        $response->headers->set('Cache-Control', 'no-store, no-cache, must-revalidate, private');
        $response->headers->remove('Surrogate-Control');
    }
}
