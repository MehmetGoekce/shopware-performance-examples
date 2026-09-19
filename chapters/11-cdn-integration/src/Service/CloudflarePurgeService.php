<?php

declare(strict_types=1);

/**
 * Cache-Purge gegen die Cloudflare-API v4
 * Kapitel 11: CDN-Integration
 *
 * Plan-Verfuegbarkeit (Stand 2026-09, Cloudflare-Doku): URL, Hostname, Tag,
 * Prefix und Purge Everything sind auf ALLEN Plans verfuegbar - seit April 2025.
 * Frueher verbreitete Angaben wie "Tags nur Enterprise" oder "Prefix ab Business"
 * sind veraltet. Unterschiedlich sind nur die Rate-Limits:
 * Free 5/min, Pro 5/s, Business 10/s, Enterprise 50/s.
 *
 * Harte Grenze pro Request: 100 Operationen (Single-File-Purge: Enterprise 500).
 * Deshalb zerlegt dieser Service jede Liste in 100er-Bloecke.
 *
 * Wildcards gibt es beim Single-File-Purge nicht - woertlich: "Wildcards are not
 * supported on single file purge, and you must use purge by hostname, prefix, or
 * implement cache tags as an alternative solution". URLs muessen vollqualifiziert
 * sein (mit Schema und Host).
 *
 * Alle Methoden geben bool zurueck und werfen nie. Das ist Absicht: der Aufrufer
 * haengt an einem DAL-Write-Event (product.written feuert bei jeder Bestellung).
 * Wuerde eine Cloudflare-Stoerung hier eine TransportException durchreichen,
 * scheiterte der Write - aus einem CDN-Ausfall wuerde ein Shop-Ausfall.
 *
 * @see https://developers.cloudflare.com/cache/how-to/purge-cache/
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\Service;

use Psr\Log\LoggerInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class CloudflarePurgeService
{
    private const API_BASE = 'https://api.cloudflare.com/client/v4';

    /**
     * "Max operations per request: 100" - gilt fuer tags, prefixes, hosts und
     * (ausser Enterprise) auch fuer files.
     */
    private const MAX_ITEMS_PER_REQUEST = 100;

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly LoggerInterface $logger,
        private readonly string $zoneId,
        private readonly string $apiToken
    ) {
    }

    /**
     * Einzelne URLs invalidieren. Vollqualifiziert, keine Wildcards.
     *
     * @param string[] $urls
     */
    public function purgeByUrls(array $urls): bool
    {
        return $this->dispatchChunked('files', $urls);
    }

    /**
     * Per Cache-Tag invalidieren.
     *
     * Voraussetzung: die Antwort traegt einen Cache-Tag-Header. Shopware setzt
     * ihn nicht von sich aus - dafuer sorgt CdnCacheTagSubscriber.
     *
     * @param string[] $tags
     */
    public function purgeByTags(array $tags): bool
    {
        return $this->dispatchChunked('tags', $tags);
    }

    /**
     * Per URL-Prefix invalidieren, z.B. "shop.example.com/theme/".
     *
     * @param string[] $prefixes
     */
    public function purgeByPrefixes(array $prefixes): bool
    {
        return $this->dispatchChunked('prefixes', $prefixes);
    }

    /**
     * Per Hostname invalidieren.
     *
     * @param string[] $hostnames
     */
    public function purgeByHostnames(array $hostnames): bool
    {
        return $this->dispatchChunked('hosts', $hostnames);
    }

    /**
     * Kompletter Zone-Purge.
     *
     * Danach laufen alle Anfragen wieder auf den Origin - bei viel Traffic ist
     * das ein Lastspitzen-Risiko. Nur fuer Deploy-Hooks oder bewusste Resets.
     */
    public function purgeEverything(): bool
    {
        return $this->dispatch(['purge_everything' => true]);
    }

    /**
     * Zerlegt die Liste in 100er-Bloecke und schickt sie nacheinander.
     *
     * @param string[] $items
     */
    private function dispatchChunked(string $key, array $items): bool
    {
        $items = array_values(array_unique(array_filter($items)));

        if ($items === []) {
            return true;
        }

        $ok = true;

        foreach (array_chunk($items, self::MAX_ITEMS_PER_REQUEST) as $chunk) {
            $ok = $this->dispatch([$key => $chunk]) && $ok;
        }

        return $ok;
    }

    /**
     * @param array<string,mixed> $payload
     */
    private function dispatch(array $payload): bool
    {
        // Symfony HttpClient arbeitet lazy: erst getStatusCode()/toArray()
        // loest den Request wirklich aus und wirft bei DNS-, Verbindungs- oder
        // TLS-Fehlern eine TransportException. Ohne dieses catch flaeche der
        // Fehler bis in den DAL-Write hoch.
        try {
            $response = $this->httpClient->request(
                'POST',
                sprintf('%s/zones/%s/purge_cache', self::API_BASE, $this->zoneId),
                [
                    'headers' => [
                        'Authorization' => 'Bearer ' . $this->apiToken,
                        'Content-Type' => 'application/json',
                    ],
                    'json' => $payload,
                ]
            );

            // Cloudflare antwortet auch bei fachlichen Fehlern mit 200 und
            // "success": false - der Status allein reicht als Erfolgskriterium nicht.
            if ($response->getStatusCode() !== 200) {
                $this->logger->error('Cloudflare-Purge fehlgeschlagen', [
                    'status' => $response->getStatusCode(),
                    'payload' => array_keys($payload),
                ]);

                return false;
            }

            $body = $response->toArray(false);

            if (($body['success'] ?? false) !== true) {
                $this->logger->error('Cloudflare-Purge abgelehnt', [
                    'errors' => $body['errors'] ?? [],
                    'payload' => array_keys($payload),
                ]);

                return false;
            }

            return true;
        } catch (\Throwable $e) {
            $this->logger->error('Cloudflare-Purge nicht zustellbar', [
                'error' => $e->getMessage(),
                'payload' => array_keys($payload),
            ]);

            return false;
        }
    }
}
