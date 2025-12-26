#!/usr/bin/env php
<?php
/**
 * Cache-Warming-Script fuer Shopware 6
 * Waermt kritische URLs nach Deployment oder Cache-Clear auf.
 *
 * Verwendung:
 *   php cache-warmup.php https://ihr-shop.ch
 *   php cache-warmup.php https://ihr-shop.ch --concurrency=4
 *
 * Voraussetzungen:
 *   - PHP 8.1+ mit cURL Extension
 *   - Sitemap unter /sitemap.xml erreichbar
 */

declare(strict_types=1);

// Konfiguration
$defaultConcurrency = 4;
$timeout = 30;

// Argumente parsen
$baseUrl = $argv[1] ?? null;
$concurrency = $defaultConcurrency;

foreach ($argv as $arg) {
    if (str_starts_with($arg, '--concurrency=')) {
        $concurrency = (int) substr($arg, 14);
    }
}

if (!$baseUrl) {
    echo "Verwendung: php cache-warmup.php <base-url> [--concurrency=N]\n";
    echo "Beispiel:   php cache-warmup.php https://ihr-shop.ch --concurrency=4\n";
    exit(1);
}

$baseUrl = rtrim($baseUrl, '/');
echo "Cache-Warming fuer: $baseUrl\n";
echo "Concurrency: $concurrency\n\n";

// Kritische URLs (immer aufwaermen)
$criticalUrls = [
    '/',
    '/navigation',
    '/account/login',
    '/checkout/cart',
];

// Sitemap URLs laden
$sitemapUrls = [];
$sitemapUrl = "$baseUrl/sitemap.xml";

echo "Lade Sitemap: $sitemapUrl\n";

$sitemapContent = @file_get_contents($sitemapUrl);
if ($sitemapContent) {
    libxml_use_internal_errors(true);
    $sitemap = simplexml_load_string($sitemapContent);

    if ($sitemap) {
        // Direkte URLs in Sitemap
        foreach ($sitemap->url ?? [] as $url) {
            $sitemapUrls[] = (string) $url->loc;
        }

        // Sitemap-Index (mehrere Sitemaps)
        foreach ($sitemap->sitemap ?? [] as $childSitemap) {
            $childUrl = (string) $childSitemap->loc;
            echo "  -> Lade Sub-Sitemap: $childUrl\n";
            $childContent = @file_get_contents($childUrl);
            if ($childContent) {
                $childXml = simplexml_load_string($childContent);
                foreach ($childXml->url ?? [] as $url) {
                    $sitemapUrls[] = (string) $url->loc;
                }
            }
        }
    }
    echo "Gefunden: " . count($sitemapUrls) . " URLs in Sitemap\n";
} else {
    echo "Warnung: Sitemap nicht erreichbar\n";
}

// Alle URLs kombinieren
$allUrls = [];
foreach ($criticalUrls as $path) {
    $allUrls[] = $baseUrl . $path;
}
$allUrls = array_merge($allUrls, $sitemapUrls);
$allUrls = array_unique($allUrls);

echo "Total zu waermen: " . count($allUrls) . " URLs\n\n";

// Multi-cURL Setup
$multiHandle = curl_multi_init();
$handles = [];
$results = ['success' => 0, 'failed' => 0];

/**
 * Fuegt URLs zur Multi-Handle-Queue hinzu
 */
function addToQueue(array &$urls, CurlMultiHandle $multiHandle, array &$handles, int $concurrency, int $timeout): void
{
    while (count($handles) < $concurrency && count($urls) > 0) {
        $url = array_shift($urls);
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_USERAGENT => 'Shopware-Cache-Warmer/1.0',
            CURLOPT_HTTPHEADER => [
                'Accept: text/html,application/xhtml+xml',
                'Accept-Encoding: gzip, deflate',
            ],
        ]);
        curl_multi_add_handle($multiHandle, $ch);
        $handles[(int)$ch] = ['handle' => $ch, 'url' => $url];
    }
}

// Initial fuellen
addToQueue($allUrls, $multiHandle, $handles, $concurrency, $timeout);

// Verarbeiten
$processed = 0;
$total = count($handles) + count($allUrls);

do {
    curl_multi_exec($multiHandle, $running);

    // Fertige Handles pruefen
    while ($info = curl_multi_info_read($multiHandle)) {
        $ch = $info['handle'];
        $id = (int)$ch;
        $data = $handles[$id];

        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $time = round(curl_getinfo($ch, CURLINFO_TOTAL_TIME) * 1000);

        $processed++;
        $status = ($httpCode >= 200 && $httpCode < 400) ? 'OK' : 'FAIL';

        if ($status === 'OK') {
            $results['success']++;
        } else {
            $results['failed']++;
        }

        printf(
            "[%d/%d] %s %d %dms %s\n",
            $processed,
            $total,
            $status,
            $httpCode,
            $time,
            $data['url']
        );

        // Aufraemen
        curl_multi_remove_handle($multiHandle, $ch);
        curl_close($ch);
        unset($handles[$id]);

        // Naechste URL hinzufuegen
        addToQueue($allUrls, $multiHandle, $handles, $concurrency, $timeout);
    }

    if ($running > 0) {
        curl_multi_select($multiHandle, 0.1);
    }

} while ($running > 0 || count($handles) > 0);

curl_multi_close($multiHandle);

// Zusammenfassung
echo "\n";
echo "=== Cache-Warming abgeschlossen ===\n";
echo "Erfolgreich: {$results['success']}\n";
echo "Fehlgeschlagen: {$results['failed']}\n";
echo "Total: $processed URLs\n";

exit($results['failed'] > 0 ? 1 : 0);
