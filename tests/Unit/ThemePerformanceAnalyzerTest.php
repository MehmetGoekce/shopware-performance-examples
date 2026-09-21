<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../../chapters/16-shopware-themes/src/ThemePerformanceAnalyzer.php';

use App\Service\ThemePerformanceAnalyzer;
use Psr\Log\LoggerInterface;

/**
 * Unit tests for ThemePerformanceAnalyzer (Kapitel 16)
 *
 * Die Integrationstests bauen ein echtes public/theme/<prefix>/ in einem
 * temporären Verzeichnis nach — so, wie theme:compile es anlegt.
 * Private Methoden werden per Reflection getestet.
 */
class ThemePerformanceAnalyzerTest extends TestCase
{
    private ThemePerformanceAnalyzer $analyzer;
    /** @var \ReflectionClass<ThemePerformanceAnalyzer> */
    private \ReflectionClass $reflection;
    private string $projectDir;

    protected function setUp(): void
    {
        $this->projectDir = sys_get_temp_dir() . '/tpa-' . bin2hex(random_bytes(4));
        mkdir($this->projectDir . '/public/theme', 0777, true);

        $this->analyzer = new ThemePerformanceAnalyzer(
            $this->projectDir,
            $this->createMock(LoggerInterface::class)
        );

        $this->reflection = new \ReflectionClass($this->analyzer);
    }

    protected function tearDown(): void
    {
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($this->projectDir, \FilesystemIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($it as $file) {
            $file->isDir() ? rmdir($file->getPathname()) : unlink($file->getPathname());
        }
        rmdir($this->projectDir);
    }

    private function invokePrivate(string $methodName, array $args = []): mixed
    {
        $method = $this->reflection->getMethod($methodName);
        $method->setAccessible(true);
        return $method->invoke($this->analyzer, ...$args);
    }

    /**
     * Legt public/theme/<prefix>/ mit den gegebenen Dateien an (Pfad => Inhalt)
     *
     * @param array<string, string> $files
     */
    private function createThemeDir(string $prefix, array $files): string
    {
        $dir = $this->projectDir . '/public/theme/' . $prefix;
        foreach ($files as $path => $content) {
            @mkdir(\dirname($dir . '/' . $path), 0777, true);
            file_put_contents($dir . '/' . $path, $content);
        }
        return $dir;
    }

    // =================================================================
    // analyzeThemeDirectory() — gegen echte Dateien
    // =================================================================

    public function testAnalyzeSplitsEntriesFromChunks(): void
    {
        $dir = $this->createThemeDir('c7629e6bf9db1d9c6b66f6f545d51be2', [
            'css/all.css' => str_repeat('.a{color:red}', 100),
            'js/storefront/storefront.js' => str_repeat('x', 5000),
            'js/storefront/storefront.hammer.50cbec.js' => str_repeat('h', 2000),
            'js/performance-theme/performance-theme.js' => str_repeat('p', 300),
            'js/performance-theme/performance-theme.async-slider.plugin.6cd542.js' => str_repeat('s', 700),
        ]);

        $result = $this->analyzer->analyzeThemeDirectory($dir);

        $this->assertSame(2, $result['assets']['javascript']['fileCount'], 'zwei Einstiege');
        $this->assertSame(5300, $result['assets']['javascript']['totalSize']);
        $this->assertSame(2, $result['assets']['chunks']['fileCount'], 'zwei Chunks');
        $this->assertSame(2700, $result['assets']['chunks']['totalSize']);
        $this->assertSame(1, $result['assets']['css']['fileCount']);
        $this->assertSame(100, $result['score']);
        $this->assertSame([], $result['issues']);
    }

    public function testAnalyzeReportsLibraryChunksAsInfo(): void
    {
        $dir = $this->createThemeDir('abc', [
            'css/all.css' => 'a{}',
            'js/storefront/storefront.js' => 'x',
            'js/storefront/storefront.tiny-slider.41a54b.js' => str_repeat('t', 1000),
            'js/storefront/storefront.hammer.50cbec.js' => str_repeat('h', 500),
        ]);

        $result = $this->analyzer->analyzeThemeDirectory($dir);
        $libraries = array_column($result['libraryChunks'], 'library');

        $this->assertContains('tiny-slider', $libraries);
        $this->assertContains('hammer', $libraries);
        $this->assertSame([], $result['issues'], 'Chunks zählen nicht gegen das Budget');
    }

    public function testAnalyzeFlagsOversizedEntryJavaScript(): void
    {
        // Zufallsdaten komprimieren kaum: gzip bleibt über 200 KB
        $dir = $this->createThemeDir('big', [
            'css/all.css' => 'a{}',
            'js/storefront/storefront.js' => random_bytes(260 * 1024),
        ]);

        $result = $this->analyzer->analyzeThemeDirectory($dir);
        $types = array_column($result['issues'], 'type');

        $this->assertContains('js_size', $types);
        $this->assertSame(80, $result['score']);
        $this->assertSame('high', $result['recommendations'][0]['priority']);
    }

    public function testAnalyzeRejectsDirectoryWithoutCss(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->analyzer->analyzeThemeDirectory($this->projectDir . '/public/theme/missing');
    }

    public function testFindLatestThemeDirectoryPicksNewestAllCss(): void
    {
        $old = $this->createThemeDir('old', ['css/all.css' => 'a{}']);
        $new = $this->createThemeDir('new', ['css/all.css' => 'b{}']);
        touch($old . '/css/all.css', time() - 3600);
        // Ein Asset-Verzeichnis ohne css/all.css darf nicht gewählt werden
        $this->createThemeDir('assets-only', ['assets/logo.svg' => '<svg/>']);

        $this->assertSame($new, $this->analyzer->findLatestThemeDirectory());
    }

    public function testFindLatestThemeDirectoryReturnsNullWhenNothingCompiled(): void
    {
        $this->assertNull($this->analyzer->findLatestThemeDirectory());
    }

    // =================================================================
    // isChunk()
    // =================================================================

    public function testIsChunkRecognisesWebpackChunkHash(): void
    {
        $this->assertTrue($this->invokePrivate('isChunk', ['storefront.hammer.50cbec.js']));
        $this->assertTrue($this->invokePrivate('isChunk', ['storefront.index.92319.0b57b1.js']));
        $this->assertFalse($this->invokePrivate('isChunk', ['storefront.js']));
        $this->assertFalse($this->invokePrivate('isChunk', ['performance-theme.js']));
    }

    // =================================================================
    // formatBytes()
    // =================================================================

    public function testFormatBytesUnderKilobyte(): void
    {
        $this->assertEquals('512 B', $this->invokePrivate('formatBytes', [512]));
    }

    public function testFormatBytesKilobytes(): void
    {
        $this->assertEquals('2 KB', $this->invokePrivate('formatBytes', [2048]));
    }

    public function testFormatBytesKilobytesDecimal(): void
    {
        $this->assertEquals('1.5 KB', $this->invokePrivate('formatBytes', [1536]));
    }

    public function testFormatBytesMegabytes(): void
    {
        $this->assertEquals('1 MB', $this->invokePrivate('formatBytes', [1048576]));
    }

    // =================================================================
    // detectIssues()
    // =================================================================

    private function assets(int $jsGzip, int $cssGzip): array
    {
        return [
            'javascript' => ['gzipSize' => $jsGzip, 'totalSize' => $jsGzip * 3, 'files' => [], 'fileCount' => 1],
            'chunks' => ['gzipSize' => 0, 'totalSize' => 0, 'files' => [], 'fileCount' => 0],
            'css' => ['gzipSize' => $cssGzip, 'totalSize' => $cssGzip * 7, 'files' => [], 'fileCount' => 1],
            'total' => ['gzipSize' => $jsGzip + $cssGzip],
        ];
    }

    public function testDetectIssuesUsesGzipNotRawSize(): void
    {
        // Messwerte Dockware 6.6.10.6: Einstieg 75 KB gzip (230 KB roh), CSS 55 KB gzip (391 KB roh)
        $result = $this->invokePrivate('detectIssues', [$this->assets(75 * 1024, 55 * 1024)]);
        $this->assertSame([], $result);
    }

    public function testDetectIssuesJavaScriptTooLarge(): void
    {
        $result = $this->invokePrivate('detectIssues', [$this->assets(250 * 1024, 50 * 1024)]);
        $this->assertSame(['js_size'], array_column($result, 'type'));
        $this->assertSame('high', $result[0]['severity']);
    }

    public function testDetectIssuesCssTooLarge(): void
    {
        $result = $this->invokePrivate('detectIssues', [$this->assets(50 * 1024, 150 * 1024)]);
        $this->assertSame(['css_size'], array_column($result, 'type'));
        $this->assertSame('medium', $result[0]['severity']);
    }

    // =================================================================
    // calculateScore()
    // =================================================================

    public function testCalculateScoreSeverities(): void
    {
        $assets = ['total' => ['gzipSize' => 300 * 1024]];
        $this->assertEquals(100, $this->invokePrivate('calculateScore', [[], $assets]));
        $this->assertEquals(80, $this->invokePrivate('calculateScore', [[['severity' => 'high']], $assets]));
        $this->assertEquals(90, $this->invokePrivate('calculateScore', [[['severity' => 'medium']], $assets]));
        $this->assertEquals(95, $this->invokePrivate('calculateScore', [[['severity' => 'low']], $assets]));
    }

    public function testCalculateScoreOversizedDeductsAtMost30(): void
    {
        $assets = ['total' => ['gzipSize' => 750 * 1024]]; // 50 % über 500 KB
        $this->assertEquals(70, $this->invokePrivate('calculateScore', [[], $assets]));
    }

    public function testCalculateScoreMinimumIsZero(): void
    {
        $issues = array_fill(0, 10, ['severity' => 'high']);
        $assets = ['total' => ['gzipSize' => 2000 * 1024]];
        $this->assertEquals(0, $this->invokePrivate('calculateScore', [$issues, $assets]));
    }

    // =================================================================
    // overBudget()
    // =================================================================

    public function testOverBudgetIsZeroUnderThreshold(): void
    {
        $this->assertEquals('0 B', $this->invokePrivate('overBudget', [$this->assets(150 * 1024, 50 * 1024), 'js']));
    }

    public function testOverBudgetIsMeasuredDifference(): void
    {
        $this->assertEquals('50 KB', $this->invokePrivate('overBudget', [$this->assets(250 * 1024, 50 * 1024), 'js']));
        $this->assertEquals('20 KB', $this->invokePrivate('overBudget', [$this->assets(50 * 1024, 120 * 1024), 'css']));
    }

    // =================================================================
    // deduplicateRecommendations()
    // =================================================================

    public function testDeduplicateRemovesDuplicateTitlesAndSortsByPriority(): void
    {
        $recommendations = [
            ['priority' => 'low', 'title' => 'Low', 'actions' => []],
            ['priority' => 'high', 'title' => 'High', 'actions' => []],
            ['priority' => 'high', 'title' => 'High', 'actions' => []],
            ['priority' => 'medium', 'title' => 'Medium', 'actions' => []],
        ];

        $result = $this->invokePrivate('deduplicateRecommendations', [$recommendations]);

        $this->assertSame(['High', 'Medium', 'Low'], array_column($result, 'title'));
    }

    // =================================================================
    // formatReport()
    // =================================================================

    public function testFormatReportNamesThemeDirectoryAndGzip(): void
    {
        $dir = $this->createThemeDir('rep', [
            'css/all.css' => 'a{}',
            'js/storefront/storefront.js' => 'x',
        ]);

        $report = $this->analyzer->formatReport($this->analyzer->analyzeThemeDirectory($dir));

        $this->assertStringContainsString($dir, $report);
        $this->assertStringContainsString('Einstiegs-JS', $report);
        $this->assertStringNotContainsString('bundles/storefront', $report);
    }
}
