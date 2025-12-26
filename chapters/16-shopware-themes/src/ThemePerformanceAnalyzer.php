<?php

declare(strict_types=1);

namespace App\Service;

use Shopware\Core\System\SystemConfig\SystemConfigService;
use Shopware\Storefront\Theme\ThemeService;
use Psr\Log\LoggerInterface;

/**
 * Theme Performance Analyzer
 *
 * Analysiert Theme-Assets auf Performance-Probleme und gibt
 * Optimierungsempfehlungen.
 */
class ThemePerformanceAnalyzer
{
    // Schwellenwerte für Warnungen
    private const THRESHOLD_JS_SIZE = 300 * 1024;  // 300 KB
    private const THRESHOLD_CSS_SIZE = 150 * 1024; // 150 KB
    private const THRESHOLD_TOTAL_SIZE = 500 * 1024; // 500 KB

    // Bekannte "schwere" Bibliotheken
    private const HEAVY_LIBRARIES = [
        'jquery' => ['size' => 229000, 'alternative' => 'Vanilla JS (ab SW 6.5 entfernt)'],
        'flatpickr' => ['size' => 115000, 'alternative' => 'Native date input'],
        'tiny-slider' => ['size' => 100000, 'alternative' => 'CSS Scroll Snap'],
        'hammer' => ['size' => 72000, 'alternative' => 'Touch-Events direkt nutzen'],
    ];

    public function __construct(
        private readonly ThemeService $themeService,
        private readonly SystemConfigService $configService,
        private readonly string $projectDir,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Vollständige Theme-Analyse durchführen
     *
     * @param string $themeId
     * @return array{
     *     score: int,
     *     issues: array,
     *     recommendations: array,
     *     assets: array
     * }
     */
    public function analyzeTheme(string $themeId): array
    {
        $this->logger->info('Analyzing theme performance', ['themeId' => $themeId]);

        $assets = $this->collectAssets($themeId);
        $issues = $this->detectIssues($assets);
        $recommendations = $this->generateRecommendations($issues, $assets);
        $score = $this->calculateScore($issues, $assets);

        return [
            'themeId' => $themeId,
            'analyzedAt' => (new \DateTimeImmutable())->format('c'),
            'score' => $score,
            'issues' => $issues,
            'recommendations' => $recommendations,
            'assets' => $assets,
        ];
    }

    /**
     * Assets sammeln und analysieren
     */
    private function collectAssets(string $themeId): array
    {
        $bundlePath = $this->projectDir . '/public/bundles/storefront';

        $jsFiles = $this->scanDirectory($bundlePath . '/js', '*.js');
        $cssFiles = $this->scanDirectory($bundlePath . '/css', '*.css');

        return [
            'javascript' => [
                'files' => $jsFiles,
                'totalSize' => array_sum(array_column($jsFiles, 'size')),
                'fileCount' => count($jsFiles),
            ],
            'css' => [
                'files' => $cssFiles,
                'totalSize' => array_sum(array_column($cssFiles, 'size')),
                'fileCount' => count($cssFiles),
            ],
            'total' => [
                'size' => array_sum(array_column($jsFiles, 'size')) +
                          array_sum(array_column($cssFiles, 'size')),
            ],
        ];
    }

    /**
     * Verzeichnis scannen
     */
    private function scanDirectory(string $path, string $pattern): array
    {
        if (!is_dir($path)) {
            return [];
        }

        $files = [];
        $iterator = new \GlobIterator($path . '/' . $pattern);

        foreach ($iterator as $file) {
            $content = file_get_contents($file->getPathname());
            $libraries = $this->detectLibraries($content);

            $files[] = [
                'name' => $file->getFilename(),
                'path' => $file->getPathname(),
                'size' => $file->getSize(),
                'sizeFormatted' => $this->formatBytes($file->getSize()),
                'gzipSize' => strlen(gzencode($content, 9)),
                'libraries' => $libraries,
            ];
        }

        // Nach Grösse sortieren (grösste zuerst)
        usort($files, fn($a, $b) => $b['size'] <=> $a['size']);

        return $files;
    }

    /**
     * Bibliotheken im Code erkennen
     */
    private function detectLibraries(string $content): array
    {
        $detected = [];

        foreach (self::HEAVY_LIBRARIES as $lib => $info) {
            // Einfache Erkennung (kann verfeinert werden)
            if (stripos($content, $lib) !== false) {
                $detected[] = [
                    'name' => $lib,
                    'estimatedSize' => $info['size'],
                    'alternative' => $info['alternative'],
                ];
            }
        }

        return $detected;
    }

    /**
     * Probleme erkennen
     */
    private function detectIssues(array $assets): array
    {
        $issues = [];

        // JavaScript zu gross
        if ($assets['javascript']['totalSize'] > self::THRESHOLD_JS_SIZE) {
            $issues[] = [
                'severity' => 'high',
                'type' => 'js_size',
                'message' => sprintf(
                    'JavaScript Bundle zu gross: %s (Limit: %s)',
                    $this->formatBytes($assets['javascript']['totalSize']),
                    $this->formatBytes(self::THRESHOLD_JS_SIZE)
                ),
                'details' => [
                    'current' => $assets['javascript']['totalSize'],
                    'threshold' => self::THRESHOLD_JS_SIZE,
                ],
            ];
        }

        // CSS zu gross
        if ($assets['css']['totalSize'] > self::THRESHOLD_CSS_SIZE) {
            $issues[] = [
                'severity' => 'medium',
                'type' => 'css_size',
                'message' => sprintf(
                    'CSS Bundle zu gross: %s (Limit: %s)',
                    $this->formatBytes($assets['css']['totalSize']),
                    $this->formatBytes(self::THRESHOLD_CSS_SIZE)
                ),
            ];
        }

        // Schwere Bibliotheken
        foreach ($assets['javascript']['files'] as $file) {
            foreach ($file['libraries'] as $lib) {
                $issues[] = [
                    'severity' => 'medium',
                    'type' => 'heavy_library',
                    'message' => sprintf(
                        'Schwere Bibliothek gefunden: %s (~%s)',
                        $lib['name'],
                        $this->formatBytes($lib['estimatedSize'])
                    ),
                    'details' => [
                        'library' => $lib['name'],
                        'alternative' => $lib['alternative'],
                    ],
                ];
            }
        }

        // Zu viele separate Dateien (HTTP/2 hilft, aber trotzdem prüfen)
        if ($assets['javascript']['fileCount'] > 10) {
            $issues[] = [
                'severity' => 'low',
                'type' => 'too_many_files',
                'message' => sprintf(
                    '%d separate JS-Dateien. Erwäge Code-Splitting Optimierung.',
                    $assets['javascript']['fileCount']
                ),
            ];
        }

        return $issues;
    }

    /**
     * Empfehlungen generieren
     */
    private function generateRecommendations(array $issues, array $assets): array
    {
        $recommendations = [];

        foreach ($issues as $issue) {
            switch ($issue['type']) {
                case 'js_size':
                    $recommendations[] = [
                        'priority' => 'high',
                        'title' => 'JavaScript Bundle reduzieren',
                        'actions' => [
                            'Nicht benötigte Plugins mit PluginManager.deregister() entfernen',
                            'Selektive Bootstrap JS Imports verwenden',
                            'Async/Dynamic Imports für selten genutzte Features',
                            'Tree-Shaking aktivieren (Vite ab SW 6.7)',
                        ],
                        'expectedSavings' => $this->estimateSavings($assets, 'js'),
                    ];
                    break;

                case 'css_size':
                    $recommendations[] = [
                        'priority' => 'medium',
                        'title' => 'CSS Bundle optimieren',
                        'actions' => [
                            '@StorefrontBootstrap statt @Storefront verwenden',
                            'Bootstrap Komponenten selektiv importieren',
                            'PurgeCSS für ungenutztes CSS',
                            'Critical CSS für Above-the-Fold implementieren',
                        ],
                        'expectedSavings' => $this->estimateSavings($assets, 'css'),
                    ];
                    break;

                case 'heavy_library':
                    $recommendations[] = [
                        'priority' => 'medium',
                        'title' => sprintf('Alternative für %s prüfen', $issue['details']['library']),
                        'actions' => [
                            $issue['details']['alternative'],
                            'Lazy Loading implementieren wenn Bibliothek benötigt',
                        ],
                        'expectedSavings' => $this->formatBytes(
                            self::HEAVY_LIBRARIES[$issue['details']['library']]['size'] ?? 0
                        ),
                    ];
                    break;
            }
        }

        // Deduplizieren
        return $this->deduplicateRecommendations($recommendations);
    }

    /**
     * Performance-Score berechnen (0-100)
     */
    private function calculateScore(array $issues, array $assets): int
    {
        $score = 100;

        // Punktabzug für Issues
        foreach ($issues as $issue) {
            switch ($issue['severity']) {
                case 'high':
                    $score -= 20;
                    break;
                case 'medium':
                    $score -= 10;
                    break;
                case 'low':
                    $score -= 5;
                    break;
            }
        }

        // Punktabzug für Grösse
        if ($assets['total']['size'] > self::THRESHOLD_TOTAL_SIZE) {
            $overPercent = (($assets['total']['size'] - self::THRESHOLD_TOTAL_SIZE)
                           / self::THRESHOLD_TOTAL_SIZE) * 100;
            $score -= min($overPercent, 30);
        }

        return max(0, min(100, (int)$score));
    }

    /**
     * Geschätzte Einsparungen
     */
    private function estimateSavings(array $assets, string $type): string
    {
        $current = $assets[$type === 'js' ? 'javascript' : 'css']['totalSize'];
        $target = $type === 'js' ? self::THRESHOLD_JS_SIZE : self::THRESHOLD_CSS_SIZE;

        if ($current <= $target) {
            return '0 KB';
        }

        // Konservative Schätzung: 40% Reduktion möglich
        $savings = min($current - $target, $current * 0.4);

        return $this->formatBytes((int)$savings);
    }

    /**
     * Doppelte Empfehlungen entfernen
     */
    private function deduplicateRecommendations(array $recommendations): array
    {
        $seen = [];
        $unique = [];

        foreach ($recommendations as $rec) {
            $key = $rec['title'];
            if (!isset($seen[$key])) {
                $seen[$key] = true;
                $unique[] = $rec;
            }
        }

        // Nach Priorität sortieren
        usort($unique, function ($a, $b) {
            $priority = ['high' => 0, 'medium' => 1, 'low' => 2];
            return $priority[$a['priority']] <=> $priority[$b['priority']];
        });

        return $unique;
    }

    /**
     * Bytes formatieren
     */
    private function formatBytes(int $bytes): string
    {
        if ($bytes < 1024) {
            return $bytes . ' B';
        }

        if ($bytes < 1024 * 1024) {
            return round($bytes / 1024, 1) . ' KB';
        }

        return round($bytes / (1024 * 1024), 2) . ' MB';
    }

    /**
     * CLI-freundliche Ausgabe generieren
     */
    public function formatReport(array $analysis): string
    {
        $output = [];
        $output[] = str_repeat('=', 60);
        $output[] = '  Theme Performance Analysis';
        $output[] = str_repeat('=', 60);
        $output[] = '';
        $output[] = sprintf('Theme: %s', $analysis['themeId']);
        $output[] = sprintf('Score: %d/100', $analysis['score']);
        $output[] = sprintf('Analyzed: %s', $analysis['analyzedAt']);
        $output[] = '';

        // Assets
        $output[] = '--- Assets ---';
        $output[] = sprintf(
            'JavaScript: %s (%d files)',
            $this->formatBytes($analysis['assets']['javascript']['totalSize']),
            $analysis['assets']['javascript']['fileCount']
        );
        $output[] = sprintf(
            'CSS: %s (%d files)',
            $this->formatBytes($analysis['assets']['css']['totalSize']),
            $analysis['assets']['css']['fileCount']
        );
        $output[] = sprintf(
            'Total: %s',
            $this->formatBytes($analysis['assets']['total']['size'])
        );
        $output[] = '';

        // Issues
        if (!empty($analysis['issues'])) {
            $output[] = '--- Issues ---';
            foreach ($analysis['issues'] as $issue) {
                $output[] = sprintf('[%s] %s', strtoupper($issue['severity']), $issue['message']);
            }
            $output[] = '';
        }

        // Recommendations
        if (!empty($analysis['recommendations'])) {
            $output[] = '--- Recommendations ---';
            foreach ($analysis['recommendations'] as $rec) {
                $output[] = sprintf('[%s] %s', strtoupper($rec['priority']), $rec['title']);
                foreach ($rec['actions'] as $action) {
                    $output[] = sprintf('    - %s', $action);
                }
                $output[] = sprintf('    Expected savings: %s', $rec['expectedSavings']);
                $output[] = '';
            }
        }

        return implode("\n", $output);
    }
}
