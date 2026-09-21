<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;

/**
 * Theme Performance Analyzer
 *
 * Vermisst ein kompiliertes Theme unter public/theme/<prefix>/ — dort legt
 * theme:compile CSS und JavaScript ab, die die Storefront ausliefert:
 *
 *   css/all.css                            gesamtes Theme-CSS, jede Seite
 *   js/<technical-name>/<name>.js          Einstieg je Theme/Plugin, jede Seite
 *   js/<technical-name>/<name>.<hash6>.js  Chunk, lädt nur bei Bedarf
 *
 * Unter public/bundles/storefront/ liegt bis 6.7.10 kein Storefront-JavaScript;
 * ab 6.7.11 lädt jede Seite dort zusätzlich storefront/shopware/shopware.js
 * (Vite-Laufzeitmodul), das dieser Analyzer nicht mitzählt.
 * Gleiche Regeln wie scripts/analyze-bundle.sh.
 *
 * @see \Shopware\Storefront\Theme\ThemeCompiler::collectCompiledFiles()
 * @see \Shopware\Storefront\Theme\ThemeCompiler::copyScriptFilesToTheme()
 */
class ThemePerformanceAnalyzer
{
    // Grenzwerte gzip, dieselben Zahlen wie config/lighthouse-budget.json —
    // aber eine andere Messgrösse: Lighthouse zählt alles, was eine Seite
    // lädt (auch Chunks, Drittanbieter), dieser Analyzer nur Einstieg und
    // all.css. Ein grüner Analyzer sagt nichts über das Lighthouse-Budget.
    private const THRESHOLD_JS_SIZE = 200 * 1024;    // Einstiegs-JS
    private const THRESHOLD_CSS_SIZE = 100 * 1024;   // all.css
    private const THRESHOLD_TOTAL_SIZE = 500 * 1024; // beides zusammen

    // Bibliotheken, die die Storefront als eigenen Chunk ausliefert
    // (Dateiname storefront.<name>.<hash6>.js, gemessen in 6.6.10.6).
    // flatpickr ist hier nicht erkennbar: Es steckt samt Locales in
    // storefront.index.<hash6>.js (95 KB, gzip 27 KB); der Chunk des
    // DatePicker-Plugins (2,4 KB) importiert es nur.
    private const LIBRARY_CHUNKS = ['tiny-slider', 'hammer', 'three.module'];

    public function __construct(
        private readonly string $projectDir,
        private readonly LoggerInterface $logger
    ) {
    }

    /**
     * Neuestes kompiliertes Theme-Verzeichnis (public/theme/<prefix>)
     */
    public function findLatestThemeDirectory(): ?string
    {
        $candidates = glob($this->projectDir . '/public/theme/*/css/all.css') ?: [];
        usort($candidates, fn (string $a, string $b) => filemtime($b) <=> filemtime($a));

        return $candidates === [] ? null : \dirname($candidates[0], 2);
    }

    /**
     * Vollständige Analyse eines Theme-Verzeichnisses
     *
     * @return array{
     *     themeDir: string,
     *     analyzedAt: string,
     *     score: int,
     *     issues: array<int, array<string, mixed>>,
     *     recommendations: array<int, array<string, mixed>>,
     *     libraryChunks: array<int, array<string, mixed>>,
     *     assets: array<string, mixed>
     * }
     */
    public function analyzeThemeDirectory(string $themeDir): array
    {
        if (!is_file($themeDir . '/css/all.css')) {
            throw new \InvalidArgumentException(sprintf('Keine css/all.css in %s', $themeDir));
        }

        $this->logger->info('Analyzing theme performance', ['themeDir' => $themeDir]);

        $assets = $this->collectAssets($themeDir);
        $issues = $this->detectIssues($assets);

        return [
            'themeDir' => $themeDir,
            'analyzedAt' => (new \DateTimeImmutable())->format('c'),
            'score' => $this->calculateScore($issues, $assets),
            'issues' => $issues,
            'recommendations' => $this->generateRecommendations($issues, $assets),
            'libraryChunks' => $this->detectLibraryChunks($assets['chunks']['files']),
            'assets' => $assets,
        ];
    }

    /**
     * Assets sammeln: Einstiegs-JS, Chunks, CSS
     *
     * @return array<string, mixed>
     */
    private function collectAssets(string $themeDir): array
    {
        $entries = [];
        $chunks = [];

        foreach ($this->scanDirectory($themeDir . '/js', 'js') as $file) {
            if ($this->isChunk($file['name'])) {
                $chunks[] = $file;
            } else {
                $entries[] = $file;
            }
        }

        $cssFiles = $this->scanDirectory($themeDir . '/css', 'css');

        return [
            'javascript' => $this->summarize($entries),
            'chunks' => $this->summarize($chunks),
            'css' => $this->summarize($cssFiles),
            'total' => [
                'gzipSize' => array_sum(array_column($entries, 'gzipSize'))
                    + array_sum(array_column($cssFiles, 'gzipSize')),
            ],
        ];
    }

    /**
     * Webpack benennt Chunks im Production-Build [name].[chunkhash:6].js
     */
    private function isChunk(string $fileName): bool
    {
        return preg_match('/\.[0-9a-f]{6}\.js$/', $fileName) === 1;
    }

    /**
     * @param list<array<string, mixed>> $files
     *
     * @return array<string, mixed>
     */
    private function summarize(array $files): array
    {
        return [
            'files' => $files,
            'totalSize' => array_sum(array_column($files, 'size')),
            'gzipSize' => array_sum(array_column($files, 'gzipSize')),
            'fileCount' => \count($files),
        ];
    }

    /**
     * Verzeichnis rekursiv scannen (JS liegt in js/<technical-name>/)
     *
     * @return list<array<string, mixed>>
     */
    private function scanDirectory(string $path, string $extension): array
    {
        if (!is_dir($path)) {
            return [];
        }

        $files = [];
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($path, \FilesystemIterator::SKIP_DOTS)
        );

        foreach ($iterator as $file) {
            if (!$file->isFile() || $file->getExtension() !== $extension) {
                continue;
            }

            $content = (string) file_get_contents($file->getPathname());

            $files[] = [
                'name' => $file->getFilename(),
                'path' => $file->getPathname(),
                'size' => $file->getSize(),
                'sizeFormatted' => $this->formatBytes($file->getSize()),
                'gzipSize' => \strlen((string) gzencode($content, 9)),
            ];
        }

        // Nach Grösse sortieren (grösste zuerst)
        usort($files, fn ($a, $b) => $b['size'] <=> $a['size']);

        return $files;
    }

    /**
     * Bibliotheks-Chunks erkennen — Info, kein Problem: Sie laden nur
     * auf Seiten, deren Plugin sie braucht.
     *
     * @param list<array<string, mixed>> $chunks
     *
     * @return list<array<string, mixed>>
     */
    private function detectLibraryChunks(array $chunks): array
    {
        $detected = [];

        foreach ($chunks as $chunk) {
            foreach (self::LIBRARY_CHUNKS as $library) {
                if (str_contains($chunk['name'], '.' . $library . '.')) {
                    $detected[] = [
                        'library' => $library,
                        'file' => $chunk['name'],
                        'size' => $chunk['size'],
                        'gzipSize' => $chunk['gzipSize'],
                    ];
                }
            }
        }

        return $detected;
    }

    /**
     * Probleme erkennen: nur, was jede Seite lädt, zählt gegen das Budget
     *
     * @param array<string, mixed> $assets
     *
     * @return list<array<string, mixed>>
     */
    private function detectIssues(array $assets): array
    {
        $issues = [];

        if ($assets['javascript']['gzipSize'] > self::THRESHOLD_JS_SIZE) {
            $issues[] = [
                'severity' => 'high',
                'type' => 'js_size',
                'message' => sprintf(
                    'Einstiegs-JavaScript zu gross: %s gzip (Limit: %s)',
                    $this->formatBytes($assets['javascript']['gzipSize']),
                    $this->formatBytes(self::THRESHOLD_JS_SIZE)
                ),
                'details' => [
                    'current' => $assets['javascript']['gzipSize'],
                    'threshold' => self::THRESHOLD_JS_SIZE,
                ],
            ];
        }

        if ($assets['css']['gzipSize'] > self::THRESHOLD_CSS_SIZE) {
            $issues[] = [
                'severity' => 'medium',
                'type' => 'css_size',
                'message' => sprintf(
                    'all.css zu gross: %s gzip (Limit: %s)',
                    $this->formatBytes($assets['css']['gzipSize']),
                    $this->formatBytes(self::THRESHOLD_CSS_SIZE)
                ),
                'details' => [
                    'current' => $assets['css']['gzipSize'],
                    'threshold' => self::THRESHOLD_CSS_SIZE,
                ],
            ];
        }

        return $issues;
    }

    /**
     * Empfehlungen zu den gefundenen Problemen
     *
     * @param list<array<string, mixed>> $issues
     * @param array<string, mixed>       $assets
     *
     * @return list<array<string, mixed>>
     */
    private function generateRecommendations(array $issues, array $assets): array
    {
        $recommendations = [];

        foreach ($issues as $issue) {
            switch ($issue['type']) {
                case 'js_size':
                    $recommendations[] = [
                        'priority' => 'high',
                        'title' => 'Einstiegs-JavaScript reduzieren',
                        'actions' => [
                            'Jedes aktive Plugin mit JavaScript bringt eine eigene Einstiegsdatei: unnötige Plugins deaktivieren',
                            'Eigene Plugins mit PluginManager.register(name, () => import(...), selector) registrieren',
                            'Zusammensetzung prüfen: scripts/analyze-bundle.sh --stats',
                        ],
                        'overBudget' => $this->overBudget($assets, 'js'),
                    ];
                    break;

                case 'css_size':
                    $recommendations[] = [
                        'priority' => 'medium',
                        'title' => 'all.css verkleinern',
                        'actions' => [
                            '@StorefrontBootstrap statt @Storefront prüfen (lässt den Shopware-Skin weg)',
                            'Critical CSS inline, all.css asynchron laden',
                        ],
                        'overBudget' => $this->overBudget($assets, 'css'),
                    ];
                    break;
            }
        }

        return $this->deduplicateRecommendations($recommendations);
    }

    /**
     * Performance-Score (0-100): Abzüge je Problem und für das Gesamtbudget
     *
     * @param list<array<string, mixed>> $issues
     * @param array<string, mixed>       $assets
     */
    private function calculateScore(array $issues, array $assets): int
    {
        $score = 100;

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

        if ($assets['total']['gzipSize'] > self::THRESHOLD_TOTAL_SIZE) {
            $overPercent = (($assets['total']['gzipSize'] - self::THRESHOLD_TOTAL_SIZE)
                           / self::THRESHOLD_TOTAL_SIZE) * 100;
            $score -= min($overPercent, 30);
        }

        return max(0, min(100, (int) $score));
    }

    /**
     * Um wie viel das Budget überschritten ist (gzip) — gemessen, nicht geschätzt
     *
     * @param array<string, mixed> $assets
     */
    private function overBudget(array $assets, string $type): string
    {
        $current = $assets[$type === 'js' ? 'javascript' : 'css']['gzipSize'];
        $target = $type === 'js' ? self::THRESHOLD_JS_SIZE : self::THRESHOLD_CSS_SIZE;

        return $this->formatBytes(max(0, $current - $target));
    }

    /**
     * Doppelte Empfehlungen entfernen, nach Priorität sortieren
     *
     * @param list<array<string, mixed>> $recommendations
     *
     * @return list<array<string, mixed>>
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

        usort($unique, function ($a, $b) {
            $priority = ['high' => 0, 'medium' => 1, 'low' => 2];

            return $priority[$a['priority']] <=> $priority[$b['priority']];
        });

        return $unique;
    }

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
     * CLI-freundliche Ausgabe
     *
     * @param array<string, mixed> $analysis
     */
    public function formatReport(array $analysis): string
    {
        $assets = $analysis['assets'];
        $output = [];
        $output[] = str_repeat('=', 60);
        $output[] = '  Theme Performance Analysis';
        $output[] = str_repeat('=', 60);
        $output[] = '';
        $output[] = sprintf('Theme-Verzeichnis: %s', $analysis['themeDir']);
        $output[] = sprintf('Score: %d/100', $analysis['score']);
        $output[] = sprintf('Analyzed: %s', $analysis['analyzedAt']);
        $output[] = '';

        $output[] = '--- Jede Seite (gzip) ---';
        $output[] = sprintf(
            'Einstiegs-JS: %s (%d Dateien)',
            $this->formatBytes($assets['javascript']['gzipSize']),
            $assets['javascript']['fileCount']
        );
        $output[] = sprintf('CSS: %s', $this->formatBytes($assets['css']['gzipSize']));
        $output[] = sprintf(
            'Chunks bei Bedarf: %d Dateien, %s gzip',
            $assets['chunks']['fileCount'],
            $this->formatBytes($assets['chunks']['gzipSize'])
        );
        $output[] = '';

        if (!empty($analysis['libraryChunks'])) {
            $output[] = '--- Bibliotheken als Chunk (laden nur bei Bedarf) ---';
            foreach ($analysis['libraryChunks'] as $lib) {
                $output[] = sprintf('%s: %s gzip (%s)', $lib['library'], $this->formatBytes($lib['gzipSize']), $lib['file']);
            }
            $output[] = '';
        }

        if (!empty($analysis['issues'])) {
            $output[] = '--- Issues ---';
            foreach ($analysis['issues'] as $issue) {
                $output[] = sprintf('[%s] %s', strtoupper($issue['severity']), $issue['message']);
            }
            $output[] = '';
        }

        if (!empty($analysis['recommendations'])) {
            $output[] = '--- Recommendations ---';
            foreach ($analysis['recommendations'] as $rec) {
                $output[] = sprintf('[%s] %s', strtoupper($rec['priority']), $rec['title']);
                foreach ($rec['actions'] as $action) {
                    $output[] = sprintf('    - %s', $action);
                }
                $output[] = sprintf('    Über Budget: %s', $rec['overBudget']);
                $output[] = '';
            }
        }

        return implode("\n", $output);
    }
}
