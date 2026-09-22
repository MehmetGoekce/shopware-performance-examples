<?php

declare(strict_types=1);

namespace RumMonitoring\Controller;

use Psr\Log\LoggerInterface;
use RumMonitoring\Rum\RumPayload;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Nimmt die Beacons aus rum.js entgegen: POST /api/rum, eine Metrik pro Aufruf.
 *
 * Ohne _routeScope antwortet Shopware mit 412 "Invalid route scope", der
 * Beacon ist verloren. Der Scope "api" mit auth_required=false ist derselbe
 * Weg wie bei /api/_info/health-check: keine Anmeldung, kein Verkaufskanal,
 * keine Session. Eine Storefront-Route (/rum) ginge auch, legt aber fuer jeden
 * Beacon ohne Cookie eine neue Session an.
 */
#[Route(defaults: ['_routeScope' => ['api'], 'auth_required' => false])]
class RumController
{
    public function __construct(private readonly LoggerInterface $rumLogger)
    {
    }

    #[Route(path: '/api/rum', name: 'api.rum.collect', methods: ['POST'])]
    public function collect(Request $request): Response
    {
        // Browser schicken bei sendBeacon Sec-Fetch-Site: same-origin (Chromium, Firefox,
        // WebKit gemessen). Ein Beacon von einer fremden Website wird abgelehnt; Skripte
        // ohne den Header (curl) haelt das nicht auf - dafuer braucht es ein Rate-Limit.
        $site = $request->headers->get('Sec-Fetch-Site');
        if ($site !== null && $site !== 'same-origin') {
            return new Response('', Response::HTTP_FORBIDDEN);
        }

        $record = RumPayload::fromJson(
            $request->getContent(),
            $request->headers->get('CF-IPCountry')
        );

        if ($record === null) {
            return new Response('', Response::HTTP_BAD_REQUEST);
        }

        $this->rumLogger->info('rum', $record);

        return new Response('', Response::HTTP_NO_CONTENT);
    }
}
