<?php

declare(strict_types=1);

namespace App\Middleware;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Setzt Cache-Control + Surrogate-Control + Cache-Tag Header pro Route.
 *
 * Begleitcode zu Kap 11, Subsection "Edge Caching von HTML".
 * Lauscht auf kernel.response und mapped Routen auf Cache-Strategien.
 *
 * Skeleton — Production-Hardening offen:
 *  - @TODO Route-Tag-Mapping in Config-File externalisieren
 *  - @TODO Differenzierte TTLs pro Sales-Channel
 *  - @TODO Cache-Tag-Output mit Storefront-Subscriber konsolidieren
 *    (vermeidet doppeltes Setzen)
 */
final class CacheHeaderMiddleware implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::RESPONSE => ['onKernelResponse', -8],
        ];
    }

    public function onKernelResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request  = $event->getRequest();
        $response = $event->getResponse();
        $path     = $request->getPathInfo();
        $tags     = [];

        if (str_starts_with($path, '/detail/')) {
            $response->headers->set('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=3600');
            $response->headers->set('Surrogate-Control', 'max-age=300');

            if ($productId = $request->attributes->get('productId')) {
                $tags[] = 'product-' . $productId;
            }
        } elseif (str_starts_with($path, '/navigation/') || str_starts_with($path, '/category/')) {
            $response->headers->set('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=3600');
            $response->headers->set('Surrogate-Control', 'max-age=600');

            if ($categoryId = $request->attributes->get('categoryId')) {
                $tags[] = 'category-' . $categoryId;
            }
        }

        if ($tags !== []) {
            // Cloudflare-Konvention: komma-separiert.
            $response->headers->set('Cache-Tag', implode(',', $tags));
            // Fastly-Konvention: space-separiert. Beide parallel = Dual-Vendor.
            $response->headers->set('Surrogate-Key', implode(' ', $tags));
        }
    }
}
