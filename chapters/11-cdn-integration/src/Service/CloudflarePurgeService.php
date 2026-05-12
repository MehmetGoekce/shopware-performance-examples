<?php

declare(strict_types=1);

namespace App\Service;

use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * Cloudflare-Cache-Purge-Service.
 *
 * Begleitcode zu Kap 11, Subsection "Cache-Invalidierung".
 * Nutzt Cloudflare API v4 (POST /zones/{zone_id}/purge_cache).
 *
 * Skeleton — Production-Hardening offen:
 *  - @TODO Rate-Limit-Schutz (Free 5/min, Pro 5/s, Business 10/s, Enterprise 50/s)
 *  - @TODO Retry mit exponentiellem Backoff
 *  - @TODO Async-Queue (Symfony Messenger) bei hoher Purge-Frequenz
 *  - @TODO Logger statt return-bool (Audit-Trail)
 *
 * Quelle: https://developers.cloudflare.com/cache/how-to/purge-cache/
 */
final class CloudflarePurgeService
{
    private const API_BASE = 'https://api.cloudflare.com/client/v4';

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly string $zoneId,
        private readonly string $apiToken,
    ) {
    }

    /**
     * Einzelne URLs invalidieren.
     *
     * @param string[] $urls Vollqualifizierte URLs (mit https://)
     */
    public function purgeByUrls(array $urls): bool
    {
        return $this->dispatch(['files' => array_values($urls)]);
    }

    /**
     * Per Cache-Tag invalidieren — seit 2026 auf ALLEN Cloudflare-Plans verfuegbar.
     *
     * Voraussetzung: Origin muss "Cache-Tag: tag-1,tag-2"-Header senden
     * (z.B. via CacheHeaderMiddleware oder einem CacheTagSubscriber).
     *
     * @param string[] $tags
     */
    public function purgeByTags(array $tags): bool
    {
        return $this->dispatch(['tags' => array_values($tags)]);
    }

    /**
     * Per Hostname invalidieren — Business+ Plans.
     *
     * @param string[] $hostnames
     */
    public function purgeByHostnames(array $hostnames): bool
    {
        return $this->dispatch(['hosts' => array_values($hostnames)]);
    }

    /**
     * Kompletten Zone-Cache loeschen.
     *
     * VORSICHT: Cache-Stampede-Risiko bei traffic-starken Stores.
     * Nur fuer Deploy-Hooks oder explizit gewollte Reset-Vorgaenge.
     */
    public function purgeEverything(): bool
    {
        return $this->dispatch(['purge_everything' => true]);
    }

    /**
     * Interner Request-Dispatch.
     *
     * @param array<string,mixed> $payload
     */
    private function dispatch(array $payload): bool
    {
        $response = $this->httpClient->request(
            'POST',
            sprintf('%s/zones/%s/purge_cache', self::API_BASE, $this->zoneId),
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $this->apiToken,
                    'Content-Type'  => 'application/json',
                ],
                'json' => $payload,
            ],
        );

        return $response->getStatusCode() === 200;
    }
}
