<?php

declare(strict_types=1);

namespace ShopwarePerformance\ThirdPartyScripts\Service;

use Psr\Log\LoggerInterface;
use Symfony\Component\Cache\Adapter\FilesystemAdapter;
use Symfony\Contracts\Cache\ItemInterface;

/**
 * TagManagerService - Google Tag Manager Optimierung
 *
 * @description
 * Optimiert GTM-Container für Performance: Lazy Loading, Event-Delegation,
 * Trigger-Optimierung, Data Layer Management.
 *
 * @example
 * // GTM mit Performance-Optimierung laden
 * $tagManagerService->injectOptimized(
 *     containerId: 'GTM-XXXXXXX',
 *     strategy: 'lazy',
 *     delay: 3000
 * );
 *
 * // Data Layer Event pushen
 * $tagManagerService->pushEvent('purchase', [
 *     'transaction_id' => '12345',
 *     'value' => 99.99,
 *     'currency' => 'EUR',
 * ]);
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ThirdPartyScripts
 */
class TagManagerService
{
    private const GTM_BASE_URL = 'https://www.googletagmanager.com/gtm.js';
    private const DEFAULT_DELAY = 3000; // 3 Sekunden
    private const CACHE_TTL = 86400; // 24 Stunden

    /**
     * @var array<array<string, mixed>> Data Layer Queue
     */
    private array $dataLayerQueue = [];

    /**
     * @param LoggerInterface $logger Logger
     * @param FilesystemAdapter $cache Cache Adapter
     * @param bool $debugMode Debug-Modus aktivieren
     */
    public function __construct(
        private readonly LoggerInterface $logger,
        private readonly FilesystemAdapter $cache,
        private readonly bool $debugMode = false
    ) {
    }

    /**
     * Generiert optimierten GTM-Snippet Code
     *
     * @param string $containerId GTM Container-ID (z.B. 'GTM-XXXXXXX')
     * @param string $strategy Loading-Strategie ('immediate', 'lazy', 'interaction')
     * @param int|null $delay Verzögerung in ms (nur für 'lazy')
     * @param array<string> $triggers Event-Trigger für 'interaction' Strategie
     * @return string HTML/JavaScript Code
     */
    public function generateOptimizedSnippet(
        string $containerId,
        string $strategy = 'lazy',
        ?int $delay = null,
        array $triggers = ['scroll', 'mousemove', 'touchstart']
    ): string {
        $this->validateContainerId($containerId);

        return match ($strategy) {
            'immediate' => $this->generateImmediateSnippet($containerId),
            'lazy' => $this->generateLazySnippet($containerId, $delay ?? self::DEFAULT_DELAY),
            'interaction' => $this->generateInteractionSnippet($containerId, $triggers),
            default => throw new \InvalidArgumentException("Invalid strategy: {$strategy}"),
        };
    }

    /**
     * Pusht Event in Data Layer
     *
     * @param string $event Event-Name
     * @param array<string, mixed> $data Event-Daten
     * @param bool $immediate Sofort senden (true) oder queuen (false)
     * @return void
     */
    public function pushEvent(string $event, array $data = [], bool $immediate = false): void
    {
        $eventData = array_merge(['event' => $event], $data);

        if ($immediate) {
            $this->dataLayerQueue[] = $eventData;
        } else {
            // In Session/Storage queuen für späteren Push
            $this->queueEvent($eventData);
        }

        if ($this->debugMode) {
            $this->logger->debug('GTM Event pushed', [
                'event' => $event,
                'data' => $data,
                'immediate' => $immediate,
            ]);
        }
    }

    /**
     * Generiert Data Layer Initialization Code
     *
     * @param array<array<string, mixed>> $initialData Initial Data Layer Daten
     * @return string JavaScript Code
     */
    public function generateDataLayerInit(array $initialData = []): string
    {
        $dataLayerJson = json_encode($initialData, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);

        return <<<JS
        <script>
        window.dataLayer = window.dataLayer || [];
        if ({$dataLayerJson}.length > 0) {
            window.dataLayer.push(...{$dataLayerJson});
        }
        </script>
        JS;
    }

    /**
     * Generiert Performance-optimierte Trigger-Konfiguration
     *
     * @param array<string, array<string, mixed>> $triggers Trigger-Definitionen
     * @return array<string, array<string, mixed>> Optimierte Trigger
     */
    public function optimizeTriggers(array $triggers): array
    {
        $optimized = [];

        foreach ($triggers as $name => $config) {
            $optimizedConfig = $config;

            // Debounce für Scroll/Resize Events
            if (in_array($config['type'] ?? '', ['scroll', 'resize', 'mousemove'], true)) {
                $optimizedConfig['debounce'] = $config['debounce'] ?? 250; // ms
            }

            // Passive Event Listeners
            if (in_array($config['type'] ?? '', ['scroll', 'touchstart', 'wheel'], true)) {
                $optimizedConfig['passive'] = true;
            }

            // Lazy Evaluation
            if (($config['fire_on'] ?? 'load') === 'interaction') {
                $optimizedConfig['defer'] = true;
            }

            $optimized[$name] = $optimizedConfig;
        }

        return $optimized;
    }

    /**
     * Analysiert GTM-Container Performance
     *
     * @param string $containerId Container-ID
     * @return array<string, mixed> Performance-Analyse
     */
    public function analyzeContainerPerformance(string $containerId): array
    {
        $cacheKey = "gtm_analysis_{$containerId}";

        return $this->cache->get($cacheKey, function (ItemInterface $item) use ($containerId) {
            $item->expiresAfter(self::CACHE_TTL);

            // Container-URL
            $containerUrl = $this->buildContainerUrl($containerId);

            // Script-Größe ermitteln
            $scriptSize = $this->fetchContainerSize($containerUrl);

            // Tags zählen (Schätzung basierend auf Größe)
            $estimatedTags = $this->estimateTagCount($scriptSize);

            return [
                'container_id' => $containerId,
                'container_url' => $containerUrl,
                'size' => [
                    'bytes' => $scriptSize,
                    'human' => $this->formatBytes($scriptSize),
                ],
                'estimated_tags' => $estimatedTags,
                'performance_score' => $this->calculatePerformanceScore($scriptSize, $estimatedTags),
                'recommendations' => $this->generateRecommendations($scriptSize, $estimatedTags),
                'analyzed_at' => time(),
            ];
        });
    }

    /**
     * Generiert Server-Side Tagging Konfiguration
     *
     * @param string $serverContainerUrl Server Container URL
     * @param string $containerId Client Container-ID
     * @return array<string, mixed> Server-Side Config
     */
    public function generateServerSideConfig(string $serverContainerUrl, string $containerId): array
    {
        return [
            'server_container_url' => $serverContainerUrl,
            'client_container_id' => $containerId,
            'transport_url' => rtrim($serverContainerUrl, '/') . '/g/collect',
            'snippet' => $this->generateServerSideSnippet($serverContainerUrl, $containerId),
            'benefits' => [
                'reduced_client_load' => true,
                'better_caching' => true,
                'improved_accuracy' => true,
                'gdpr_friendly' => true,
            ],
        ];
    }

    /**
     * Generiert Immediate-Loading Snippet
     *
     * @param string $containerId Container-ID
     * @return string HTML/JS Code
     */
    private function generateImmediateSnippet(string $containerId): string
    {
        $containerUrl = $this->buildContainerUrl($containerId);

        return <<<HTML
        <!-- Google Tag Manager -->
        <script>(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
        new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
        j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
        '{$containerUrl}&gtm_auth=&gtm_preview=&gtm_cookies_win=x';
        f.parentNode.insertBefore(j,f);
        })(window,document,'script','dataLayer','{$containerId}');</script>
        <!-- End Google Tag Manager -->
        HTML;
    }

    /**
     * Generiert Lazy-Loading Snippet (verzögert)
     *
     * @param string $containerId Container-ID
     * @param int $delay Verzögerung in ms
     * @return string HTML/JS Code
     */
    private function generateLazySnippet(string $containerId, int $delay): string
    {
        $containerUrl = $this->buildContainerUrl($containerId);

        return <<<HTML
        <!-- Google Tag Manager (Lazy Loaded) -->
        <script>
        window.dataLayer = window.dataLayer || [];
        window.dataLayer.push({'gtm.start': new Date().getTime(), event: 'gtm.js'});

        // Lazy load GTM after {$delay}ms or user interaction
        (function() {
            let loaded = false;

            function loadGTM() {
                if (loaded) return;
                loaded = true;

                const script = document.createElement('script');
                script.async = true;
                script.src = '{$containerUrl}&gtm_auth=&gtm_preview=&gtm_cookies_win=x';
                document.head.appendChild(script);

                if (window.console && window.console.log) {
                    console.log('GTM loaded lazily');
                }
            }

            // Load after delay
            setTimeout(loadGTM, {$delay});

            // Or load on first user interaction (whichever comes first)
            ['scroll', 'mousemove', 'touchstart', 'click'].forEach(function(event) {
                window.addEventListener(event, loadGTM, { once: true, passive: true });
            });
        })();
        </script>
        <!-- End Google Tag Manager (Lazy) -->
        HTML;
    }

    /**
     * Generiert Interaction-Based Loading Snippet
     *
     * @param string $containerId Container-ID
     * @param array<string> $triggers Event-Trigger
     * @return string HTML/JS Code
     */
    private function generateInteractionSnippet(string $containerId, array $triggers): string
    {
        $containerUrl = $this->buildContainerUrl($containerId);
        $triggersList = json_encode($triggers, JSON_THROW_ON_ERROR);

        return <<<HTML
        <!-- Google Tag Manager (Interaction-Based) -->
        <script>
        window.dataLayer = window.dataLayer || [];

        (function() {
            let loaded = false;
            const triggers = {$triggersList};

            function loadGTM() {
                if (loaded) return;
                loaded = true;

                window.dataLayer.push({'gtm.start': new Date().getTime(), event: 'gtm.js'});

                const script = document.createElement('script');
                script.async = true;
                script.src = '{$containerUrl}&gtm_auth=&gtm_preview=&gtm_cookies_win=x';
                document.head.appendChild(script);

                // Remove event listeners after loading
                triggers.forEach(function(trigger) {
                    window.removeEventListener(trigger, loadGTM);
                });
            }

            // Load on any specified interaction
            triggers.forEach(function(trigger) {
                window.addEventListener(trigger, loadGTM, { once: true, passive: true });
            });
        })();
        </script>
        <!-- End Google Tag Manager (Interaction) -->
        HTML;
    }

    /**
     * Generiert Server-Side Tagging Snippet
     *
     * @param string $serverUrl Server Container URL
     * @param string $containerId Container-ID
     * @return string HTML/JS Code
     */
    private function generateServerSideSnippet(string $serverUrl, string $containerId): string
    {
        $transportUrl = rtrim($serverUrl, '/') . '/g/collect';

        return <<<HTML
        <!-- Google Tag Manager (Server-Side) -->
        <script>
        window.dataLayer = window.dataLayer || [];
        window.dataLayer.push({'gtm.start': new Date().getTime(), event: 'gtm.js'});

        (function(w,d,s,l,i){
            var f=d.getElementsByTagName(s)[0],
            j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';
            j.async=true;
            j.src='{$serverUrl}/gtm.js?id='+i+dl;
            f.parentNode.insertBefore(j,f);
        })(window,document,'script','dataLayer','{$containerId}');

        // Override transport URL for server-side processing
        window.gtag_enable_tcf_support = true;
        </script>
        <!-- End Google Tag Manager (Server-Side) -->
        HTML;
    }

    /**
     * Baut Container-URL
     *
     * @param string $containerId Container-ID
     * @return string Vollständige URL
     */
    private function buildContainerUrl(string $containerId): string
    {
        return self::GTM_BASE_URL . '?id=' . urlencode($containerId);
    }

    /**
     * Lädt Container und gibt Größe zurück
     *
     * @param string $url Container-URL
     * @return int Größe in Bytes
     */
    private function fetchContainerSize(string $url): int
    {
        try {
            $context = stream_context_create([
                'http' => [
                    'method' => 'GET',
                    'header' => 'User-Agent: ShopwarePerformance/1.0',
                ],
            ]);

            $content = @file_get_contents($url, false, $context);

            return $content ? strlen($content) : 0;

        } catch (\Exception $e) {
            $this->logger->warning('Failed to fetch GTM container', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }
    }

    /**
     * Schätzt Anzahl Tags basierend auf Container-Größe
     *
     * @param int $sizeBytes Container-Größe in Bytes
     * @return int Geschätzte Anzahl Tags
     */
    private function estimateTagCount(int $sizeBytes): int
    {
        // Heuristik: ~5-10 KB pro Tag
        return (int) ceil($sizeBytes / 7500);
    }

    /**
     * Berechnet Performance Score (0-100, höher = besser)
     *
     * @param int $size Container-Größe
     * @param int $tagCount Anzahl Tags
     * @return int Score
     */
    private function calculatePerformanceScore(int $size, int $tagCount): int
    {
        $score = 100;

        // Größen-Penalty (> 100 KB)
        if ($size > 102400) {
            $score -= min(30, ($size - 102400) / 10240);
        }

        // Tag-Count Penalty (> 20 Tags)
        if ($tagCount > 20) {
            $score -= min(20, ($tagCount - 20) * 2);
        }

        return max(0, (int) $score);
    }

    /**
     * Generiert Optimierungsempfehlungen
     *
     * @param int $size Container-Größe
     * @param int $tagCount Anzahl Tags
     * @return array<string> Empfehlungen
     */
    private function generateRecommendations(int $size, int $tagCount): array
    {
        $recommendations = [];

        if ($size > 102400) {
            $recommendations[] = 'Container exceeds 100 KB - consider removing unused tags';
        }

        if ($tagCount > 30) {
            $recommendations[] = "Too many tags ({$tagCount}) - audit and consolidate where possible";
        }

        if ($tagCount > 10) {
            $recommendations[] = 'Consider using lazy loading strategy for non-critical tags';
        }

        $recommendations[] = 'Use server-side tagging for better performance and privacy';
        $recommendations[] = 'Implement trigger optimization with debouncing';

        return $recommendations;
    }

    /**
     * Queued Event für späteren Push
     *
     * @param array<string, mixed> $eventData Event-Daten
     * @return void
     */
    private function queueEvent(array $eventData): void
    {
        // In Realität würde dies in Session/Storage gespeichert
        // Hier vereinfacht als Property
        $this->dataLayerQueue[] = $eventData;
    }

    /**
     * Validiert Container-ID Format
     *
     * @param string $containerId Container-ID
     * @return void
     * @throws \InvalidArgumentException Bei ungültiger ID
     */
    private function validateContainerId(string $containerId): void
    {
        if (!preg_match('/^GTM-[A-Z0-9]+$/i', $containerId)) {
            throw new \InvalidArgumentException(
                "Invalid GTM Container ID: {$containerId}. Expected format: GTM-XXXXXXX"
            );
        }
    }

    /**
     * Formatiert Bytes zu lesbarem Format
     *
     * @param int $bytes Bytes
     * @return string Formatiert
     */
    private function formatBytes(int $bytes): string
    {
        $units = ['B', 'KB', 'MB'];
        $power = floor(log($bytes, 1024));
        $power = min($power, count($units) - 1);

        return sprintf('%.1f %s', $bytes / (1024 ** $power), $units[$power]);
    }
}
