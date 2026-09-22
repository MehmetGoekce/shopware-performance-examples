<?php declare(strict_types=1);

namespace MobilePerformance\Controller;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Liefert den Service Worker unter /sw.js aus
 * Kapitel 19: Mobile Performance
 *
 * Ein Service Worker darf nur Seiten unterhalb seines eigenen Pfads
 * steuern. Aus /bundles/mobileperformance/ geladen, waere sein Scope
 * /bundles/mobileperformance/ – deshalb diese Route an der Wurzel.
 * no-cache: Der Browser fragt bei jedem Update-Check nach, ob sich die
 * Datei geaendert hat.
 */
#[Route(defaults: ['_routeScope' => ['storefront']])]
class ServiceWorkerController
{
    #[Route(path: '/sw.js', name: 'frontend.mobile_performance.service_worker', methods: ['GET'])]
    public function serviceWorker(): Response
    {
        $script = (string) file_get_contents(__DIR__ . '/../Resources/sw/sw.js');

        return new Response($script, Response::HTTP_OK, [
            'Content-Type' => 'application/javascript; charset=utf-8',
            'Cache-Control' => 'no-cache',
        ]);
    }
}
