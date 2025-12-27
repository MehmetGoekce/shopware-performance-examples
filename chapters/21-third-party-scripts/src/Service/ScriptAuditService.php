<?php

declare(strict_types=1);

namespace ShopwarePerformance\ThirdPartyScripts\Service;

use Psr\Log\LoggerInterface;
use Symfony\Component\HttpClient\HttpClient;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * ScriptAuditService - Analyse von Third-Party Scripts
 *
 * @description
 * Analysiert externe Scripts auf Performance-Impact, Sicherheit und Best Practices.
 * Erfasst Größe, Ladezeit, Blocking-Verhalten und Netzwerk-Requests.
 *
 * @example
 * $audit = $scriptAuditService->auditScript(
 *     url: 'https://www.googletagmanager.com/gtag/js?id=GA_MEASUREMENT_ID',
 *     context: 'product-page'
 * );
 *
 * if ($audit['impact_score'] > 75) {
 *     // Script hat hohen Performance-Impact
 * }
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ThirdPartyScripts
 */
class ScriptAuditService
{
    private const CACHE_TTL = 3600; // 1 Stunde
    private const MAX_ACCEPTABLE_SIZE = 102400; // 100 KB
    private const MAX_ACCEPTABLE_LOAD_TIME = 2000; // 2 Sekunden

    /**
     * @var array<string, array<string, mixed>> Cache für Audit-Ergebnisse
     */
    private array $auditCache = [];

    /**
     * @param HttpClientInterface $httpClient HTTP Client für Script-Downloads
     * @param LoggerInterface $logger Logger für Audit-Ergebnisse
     * @param string $cacheDir Cache-Verzeichnis
     */
    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly LoggerInterface $logger,
        private readonly string $cacheDir = '/tmp/script-audit'
    ) {
        if (!is_dir($this->cacheDir)) {
            mkdir($this->cacheDir, 0755, true);
        }
    }

    /**
     * Führt vollständiges Audit eines Scripts durch
     *
     * @param string $url Script-URL
     * @param string $context Kontext (z.B. 'homepage', 'checkout')
     * @param bool $useCache Cache nutzen
     * @return array<string, mixed> Audit-Ergebnis
     *
     * @throws \RuntimeException Bei Netzwerk-Fehlern
     */
    public function auditScript(string $url, string $context = 'unknown', bool $useCache = true): array
    {
        $cacheKey = md5($url . $context);

        // Cache prüfen
        if ($useCache && isset($this->auditCache[$cacheKey])) {
            $cached = $this->auditCache[$cacheKey];
            if ($cached['timestamp'] > time() - self::CACHE_TTL) {
                return $cached['data'];
            }
        }

        $this->logger->info('Starting script audit', [
            'url' => $url,
            'context' => $context,
        ]);

        // Audit durchführen
        $startTime = microtime(true);

        try {
            $scriptData = $this->fetchScript($url);
            $loadTime = (microtime(true) - $startTime) * 1000; // Millisekunden

            $audit = [
                'url' => $url,
                'context' => $context,
                'timestamp' => time(),
                'size' => [
                    'bytes' => $scriptData['size'],
                    'human' => $this->formatBytes($scriptData['size']),
                    'acceptable' => $scriptData['size'] <= self::MAX_ACCEPTABLE_SIZE,
                ],
                'load_time' => [
                    'ms' => round($loadTime, 2),
                    'acceptable' => $loadTime <= self::MAX_ACCEPTABLE_LOAD_TIME,
                ],
                'compression' => [
                    'enabled' => $scriptData['gzip_enabled'],
                    'ratio' => $scriptData['compression_ratio'] ?? null,
                ],
                'caching' => [
                    'cache_control' => $scriptData['cache_control'] ?? null,
                    'expires' => $scriptData['expires'] ?? null,
                    'etag' => $scriptData['etag'] ?? null,
                ],
                'security' => $this->analyzeSecurityHeaders($scriptData['headers']),
                'content_analysis' => $this->analyzeScriptContent($scriptData['content']),
                'performance_hints' => $this->generatePerformanceHints($scriptData, $loadTime),
                'impact_score' => 0, // Wird berechnet
                'risk_level' => 'unknown',
            ];

            // Impact Score berechnen (0-100, höher = schlechter)
            $audit['impact_score'] = $this->calculateImpactScore($audit);
            $audit['risk_level'] = $this->determineRiskLevel($audit['impact_score']);

            // Cache speichern
            $this->auditCache[$cacheKey] = [
                'timestamp' => time(),
                'data' => $audit,
            ];

            $this->logger->info('Script audit completed', [
                'url' => $url,
                'impact_score' => $audit['impact_score'],
                'risk_level' => $audit['risk_level'],
            ]);

            return $audit;

        } catch (\Exception $e) {
            $this->logger->error('Script audit failed', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException(
                "Failed to audit script: {$url}. Error: {$e->getMessage()}",
                0,
                $e
            );
        }
    }

    /**
     * Audiert mehrere Scripts gleichzeitig
     *
     * @param array<string> $urls Script-URLs
     * @param string $context Kontext
     * @return array<string, array<string, mixed>> URL => Audit-Ergebnis
     */
    public function auditMultiple(array $urls, string $context = 'unknown'): array
    {
        $results = [];

        foreach ($urls as $url) {
            try {
                $results[$url] = $this->auditScript($url, $context);
            } catch (\Exception $e) {
                $results[$url] = [
                    'error' => $e->getMessage(),
                    'impact_score' => 100, // Worst case
                    'risk_level' => 'critical',
                ];
            }
        }

        return $results;
    }

    /**
     * Generiert Audit-Report als Array
     *
     * @param array<string, array<string, mixed>> $audits Audit-Ergebnisse
     * @return array<string, mixed> Report
     */
    public function generateReport(array $audits): array
    {
        $totalSize = 0;
        $totalLoadTime = 0;
        $riskDistribution = [
            'low' => 0,
            'medium' => 0,
            'high' => 0,
            'critical' => 0,
        ];
        $recommendations = [];

        foreach ($audits as $url => $audit) {
            if (isset($audit['error'])) {
                continue;
            }

            $totalSize += $audit['size']['bytes'];
            $totalLoadTime += $audit['load_time']['ms'];
            $riskDistribution[$audit['risk_level']]++;

            // Empfehlungen sammeln
            if (!empty($audit['performance_hints'])) {
                foreach ($audit['performance_hints'] as $hint) {
                    $recommendations[] = [
                        'url' => $url,
                        'hint' => $hint,
                    ];
                }
            }
        }

        return [
            'summary' => [
                'total_scripts' => count($audits),
                'total_size' => [
                    'bytes' => $totalSize,
                    'human' => $this->formatBytes($totalSize),
                ],
                'total_load_time' => [
                    'ms' => round($totalLoadTime, 2),
                    'seconds' => round($totalLoadTime / 1000, 2),
                ],
                'average_impact_score' => $this->calculateAverageImpact($audits),
            ],
            'risk_distribution' => $riskDistribution,
            'recommendations' => $recommendations,
            'detailed_audits' => $audits,
        ];
    }

    /**
     * Lädt Script herunter und erfasst Metadaten
     *
     * @param string $url Script-URL
     * @return array<string, mixed> Script-Daten
     */
    private function fetchScript(string $url): array
    {
        $response = $this->httpClient->request('GET', $url, [
            'headers' => [
                'Accept-Encoding' => 'gzip, deflate, br',
                'User-Agent' => 'ShopwarePerformanceAudit/1.0',
            ],
        ]);

        $content = $response->getContent();
        $headers = $response->getHeaders();

        $size = strlen($content);
        $gzipEnabled = isset($headers['content-encoding']) &&
                       in_array('gzip', $headers['content-encoding'], true);

        $compressionRatio = null;
        if ($gzipEnabled && isset($headers['content-length'])) {
            $originalSize = (int) $headers['content-length'][0];
            if ($originalSize > 0) {
                $compressionRatio = round((1 - ($size / $originalSize)) * 100, 2);
            }
        }

        return [
            'url' => $url,
            'content' => $content,
            'size' => $size,
            'headers' => $headers,
            'gzip_enabled' => $gzipEnabled,
            'compression_ratio' => $compressionRatio,
            'cache_control' => $headers['cache-control'][0] ?? null,
            'expires' => $headers['expires'][0] ?? null,
            'etag' => $headers['etag'][0] ?? null,
        ];
    }

    /**
     * Analysiert Security-Header
     *
     * @param array<string, array<string>> $headers HTTP-Headers
     * @return array<string, mixed> Security-Analyse
     */
    private function analyzeSecurityHeaders(array $headers): array
    {
        return [
            'https_only' => isset($headers['strict-transport-security']),
            'cors_configured' => isset($headers['access-control-allow-origin']),
            'csp_present' => isset($headers['content-security-policy']),
            'x_frame_options' => $headers['x-frame-options'][0] ?? null,
            'referrer_policy' => $headers['referrer-policy'][0] ?? null,
            'issues' => $this->detectSecurityIssues($headers),
        ];
    }

    /**
     * Analysiert Script-Inhalt
     *
     * @param string $content Script-Content
     * @return array<string, mixed> Content-Analyse
     */
    private function analyzeScriptContent(string $content): array
    {
        return [
            'minified' => $this->isMinified($content),
            'contains_sourcemap' => str_contains($content, 'sourceMappingURL'),
            'contains_eval' => str_contains($content, 'eval('),
            'contains_document_write' => str_contains($content, 'document.write'),
            'external_requests' => $this->countExternalRequests($content),
            'cookie_access' => str_contains($content, 'document.cookie'),
            'local_storage_access' => str_contains($content, 'localStorage') ||
                                      str_contains($content, 'sessionStorage'),
        ];
    }

    /**
     * Generiert Performance-Optimierungs-Hinweise
     *
     * @param array<string, mixed> $scriptData Script-Daten
     * @param float $loadTime Ladezeit in ms
     * @return array<string> Hinweise
     */
    private function generatePerformanceHints(array $scriptData, float $loadTime): array
    {
        $hints = [];

        if (!$scriptData['gzip_enabled']) {
            $hints[] = 'Enable GZIP compression for this script';
        }

        if ($scriptData['size'] > self::MAX_ACCEPTABLE_SIZE) {
            $hints[] = sprintf(
                'Script size (%s) exceeds recommended limit (%s)',
                $this->formatBytes($scriptData['size']),
                $this->formatBytes(self::MAX_ACCEPTABLE_SIZE)
            );
        }

        if ($loadTime > self::MAX_ACCEPTABLE_LOAD_TIME) {
            $hints[] = sprintf(
                'Load time (%.2fms) exceeds recommended limit (%dms)',
                $loadTime,
                self::MAX_ACCEPTABLE_LOAD_TIME
            );
        }

        if (!isset($scriptData['cache_control']) || $scriptData['cache_control'] === 'no-cache') {
            $hints[] = 'Configure proper cache headers (Cache-Control, Expires)';
        }

        $content = $scriptData['content'];
        if (str_contains($content, 'document.write')) {
            $hints[] = 'Avoid document.write() - it blocks rendering';
        }

        if (str_contains($content, 'eval(')) {
            $hints[] = 'Avoid eval() - security risk and performance issue';
        }

        return $hints;
    }

    /**
     * Berechnet Impact Score (0-100)
     *
     * @param array<string, mixed> $audit Audit-Daten
     * @return int Score (höher = schlechter)
     */
    private function calculateImpactScore(array $audit): int
    {
        $score = 0;

        // Größe (0-30 Punkte)
        $sizePenalty = min(30, ($audit['size']['bytes'] / self::MAX_ACCEPTABLE_SIZE) * 30);
        $score += $sizePenalty;

        // Ladezeit (0-30 Punkte)
        $loadTimePenalty = min(30, ($audit['load_time']['ms'] / self::MAX_ACCEPTABLE_LOAD_TIME) * 30);
        $score += $loadTimePenalty;

        // Kompression (0-10 Punkte)
        if (!$audit['compression']['enabled']) {
            $score += 10;
        }

        // Caching (0-10 Punkte)
        if (!$audit['caching']['cache_control']) {
            $score += 10;
        }

        // Content-Analyse (0-20 Punkte)
        if ($audit['content_analysis']['contains_eval']) {
            $score += 5;
        }
        if ($audit['content_analysis']['contains_document_write']) {
            $score += 5;
        }
        if (!$audit['content_analysis']['minified']) {
            $score += 5;
        }
        if ($audit['content_analysis']['external_requests'] > 0) {
            $score += min(5, $audit['content_analysis']['external_requests']);
        }

        return min(100, (int) $score);
    }

    /**
     * Bestimmt Risk Level basierend auf Impact Score
     *
     * @param int $score Impact Score
     * @return string Risk Level (low, medium, high, critical)
     */
    private function determineRiskLevel(int $score): string
    {
        return match (true) {
            $score < 25 => 'low',
            $score < 50 => 'medium',
            $score < 75 => 'high',
            default => 'critical',
        };
    }

    /**
     * Prüft ob Script minified ist
     *
     * @param string $content Script-Inhalt
     * @return bool True wenn minified
     */
    private function isMinified(string $content): bool
    {
        // Heuristik: Durchschnittliche Zeilenlänge > 500 Zeichen
        $lines = explode("\n", $content);
        if (count($lines) === 0) {
            return false;
        }

        $avgLineLength = strlen($content) / count($lines);

        return $avgLineLength > 500;
    }

    /**
     * Zählt externe Requests im Script-Code
     *
     * @param string $content Script-Inhalt
     * @return int Anzahl erkannter Requests
     */
    private function countExternalRequests(string $content): int
    {
        $patterns = [
            '/fetch\s*\(/i',
            '/XMLHttpRequest/i',
            '/\.ajax\s*\(/i',
            '/new\s+Image\s*\(/i',
        ];

        $count = 0;
        foreach ($patterns as $pattern) {
            $count += preg_match_all($pattern, $content);
        }

        return $count;
    }

    /**
     * Erkennt Security-Issues in Headers
     *
     * @param array<string, array<string>> $headers HTTP-Headers
     * @return array<string> Liste von Issues
     */
    private function detectSecurityIssues(array $headers): array
    {
        $issues = [];

        if (!isset($headers['strict-transport-security'])) {
            $issues[] = 'Missing HSTS header';
        }

        if (isset($headers['access-control-allow-origin']) &&
            in_array('*', $headers['access-control-allow-origin'], true)) {
            $issues[] = 'CORS allows any origin (*)';
        }

        return $issues;
    }

    /**
     * Formatiert Bytes zu lesbarem Format
     *
     * @param int $bytes Bytes
     * @return string Formatiert (z.B. "52.3 KB")
     */
    private function formatBytes(int $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB'];
        $power = floor(log($bytes, 1024));
        $power = min($power, count($units) - 1);

        $value = $bytes / (1024 ** $power);

        return sprintf('%.1f %s', $value, $units[$power]);
    }

    /**
     * Berechnet durchschnittlichen Impact Score
     *
     * @param array<string, array<string, mixed>> $audits Audit-Ergebnisse
     * @return float Durchschnitt
     */
    private function calculateAverageImpact(array $audits): float
    {
        $scores = array_column($audits, 'impact_score');
        $validScores = array_filter($scores, fn($s) => is_numeric($s));

        if (empty($validScores)) {
            return 0.0;
        }

        return round(array_sum($validScores) / count($validScores), 2);
    }
}
