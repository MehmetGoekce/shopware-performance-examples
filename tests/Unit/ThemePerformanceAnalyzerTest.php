<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

// Load Shopware stubs for mocking
require_once __DIR__ . '/../Stubs/ShopwareStubs.php';
require_once __DIR__ . '/../../chapters/16-shopware-themes/src/ThemePerformanceAnalyzer.php';

use App\Service\ThemePerformanceAnalyzer;
use Shopware\Core\System\SystemConfig\SystemConfigService;
use Shopware\Storefront\Theme\ThemeService;
use Psr\Log\LoggerInterface;

/**
 * Unit Tests for ThemePerformanceAnalyzer
 *
 * Tests the theme analysis logic using mocks for Shopware dependencies.
 * Uses reflection to test private methods.
 */
class ThemePerformanceAnalyzerTest extends TestCase
{
    private ThemePerformanceAnalyzer $analyzer;
    private \ReflectionClass $reflection;

    protected function setUp(): void
    {
        $themeService = $this->createMock(ThemeService::class);
        $configService = $this->createMock(SystemConfigService::class);
        $logger = $this->createMock(LoggerInterface::class);

        $this->analyzer = new ThemePerformanceAnalyzer(
            $themeService,
            $configService,
            '/tmp/test-project',
            $logger
        );

        $this->reflection = new \ReflectionClass($this->analyzer);
    }

    /**
     * Helper: Invoke private method
     */
    private function invokePrivate(string $methodName, array $args = []): mixed
    {
        $method = $this->reflection->getMethod($methodName);
        $method->setAccessible(true);
        return $method->invoke($this->analyzer, ...$args);
    }

    // =================================================================
    // formatBytes() Tests
    // =================================================================

    public function testFormatBytesUnderKilobyte(): void
    {
        $result = $this->invokePrivate('formatBytes', [512]);
        $this->assertEquals('512 B', $result);
    }

    public function testFormatBytesKilobytes(): void
    {
        $result = $this->invokePrivate('formatBytes', [2048]);
        $this->assertEquals('2 KB', $result);
    }

    public function testFormatBytesKilobytesDecimal(): void
    {
        $result = $this->invokePrivate('formatBytes', [1536]);
        $this->assertEquals('1.5 KB', $result);
    }

    public function testFormatBytesMegabytes(): void
    {
        $result = $this->invokePrivate('formatBytes', [1048576]); // 1 MB
        $this->assertEquals('1 MB', $result);
    }

    public function testFormatBytesLargeMegabytes(): void
    {
        $result = $this->invokePrivate('formatBytes', [5242880]); // 5 MB
        $this->assertEquals('5 MB', $result);
    }

    // =================================================================
    // detectLibraries() Tests
    // =================================================================

    public function testDetectLibrariesFindsJquery(): void
    {
        $content = 'function test() { return jQuery.ajax(...); }';
        $result = $this->invokePrivate('detectLibraries', [$content]);

        $this->assertCount(1, $result);
        $this->assertEquals('jquery', $result[0]['name']);
        $this->assertEquals(229000, $result[0]['estimatedSize']);
    }

    public function testDetectLibrariesFindsFlatpickr(): void
    {
        $content = 'import flatpickr from "flatpickr";';
        $result = $this->invokePrivate('detectLibraries', [$content]);

        $this->assertCount(1, $result);
        $this->assertEquals('flatpickr', $result[0]['name']);
    }

    public function testDetectLibrariesFindsMultiple(): void
    {
        $content = 'jQuery + flatpickr + tiny-slider + hammer';
        $result = $this->invokePrivate('detectLibraries', [$content]);

        $this->assertCount(4, $result);
        $names = array_column($result, 'name');
        $this->assertContains('jquery', $names);
        $this->assertContains('flatpickr', $names);
        $this->assertContains('tiny-slider', $names);
        $this->assertContains('hammer', $names);
    }

    public function testDetectLibrariesReturnsEmptyForCleanCode(): void
    {
        $content = 'const app = { init() { console.log("Hello"); }};';
        $result = $this->invokePrivate('detectLibraries', [$content]);

        $this->assertEmpty($result);
    }

    public function testDetectLibrariesCaseInsensitive(): void
    {
        $content = 'JQUERY and Flatpickr and TINY-SLIDER';
        $result = $this->invokePrivate('detectLibraries', [$content]);

        $this->assertCount(3, $result);
    }

    // =================================================================
    // detectIssues() Tests
    // =================================================================

    public function testDetectIssuesJavaScriptTooLarge(): void
    {
        $assets = [
            'javascript' => [
                'totalSize' => 400 * 1024, // 400 KB > 300 KB threshold
                'files' => [],
                'fileCount' => 2,
            ],
            'css' => [
                'totalSize' => 100 * 1024,
                'files' => [],
                'fileCount' => 1,
            ],
        ];

        $result = $this->invokePrivate('detectIssues', [$assets]);

        $this->assertNotEmpty($result);
        $jsIssue = array_filter($result, fn($i) => $i['type'] === 'js_size');
        $this->assertCount(1, $jsIssue);
        $this->assertEquals('high', array_values($jsIssue)[0]['severity']);
    }

    public function testDetectIssuesCSSTooLarge(): void
    {
        $assets = [
            'javascript' => [
                'totalSize' => 100 * 1024,
                'files' => [],
                'fileCount' => 2,
            ],
            'css' => [
                'totalSize' => 200 * 1024, // 200 KB > 150 KB threshold
                'files' => [],
                'fileCount' => 1,
            ],
        ];

        $result = $this->invokePrivate('detectIssues', [$assets]);

        $cssIssue = array_filter($result, fn($i) => $i['type'] === 'css_size');
        $this->assertCount(1, $cssIssue);
        $this->assertEquals('medium', array_values($cssIssue)[0]['severity']);
    }

    public function testDetectIssuesTooManyFiles(): void
    {
        $assets = [
            'javascript' => [
                'totalSize' => 100 * 1024,
                'files' => [],
                'fileCount' => 15, // > 10 threshold
            ],
            'css' => [
                'totalSize' => 50 * 1024,
                'files' => [],
                'fileCount' => 1,
            ],
        ];

        $result = $this->invokePrivate('detectIssues', [$assets]);

        $fileIssue = array_filter($result, fn($i) => $i['type'] === 'too_many_files');
        $this->assertCount(1, $fileIssue);
        $this->assertEquals('low', array_values($fileIssue)[0]['severity']);
    }

    public function testDetectIssuesHeavyLibrary(): void
    {
        $assets = [
            'javascript' => [
                'totalSize' => 100 * 1024,
                'files' => [
                    [
                        'name' => 'main.js',
                        'libraries' => [
                            ['name' => 'jquery', 'estimatedSize' => 229000, 'alternative' => 'Vanilla JS'],
                        ],
                    ],
                ],
                'fileCount' => 1,
            ],
            'css' => [
                'totalSize' => 50 * 1024,
                'files' => [],
                'fileCount' => 1,
            ],
        ];

        $result = $this->invokePrivate('detectIssues', [$assets]);

        $libIssue = array_filter($result, fn($i) => $i['type'] === 'heavy_library');
        $this->assertCount(1, $libIssue);
    }

    public function testDetectIssuesNoIssuesWhenOptimal(): void
    {
        $assets = [
            'javascript' => [
                'totalSize' => 150 * 1024, // Under threshold
                'files' => [],
                'fileCount' => 3,
            ],
            'css' => [
                'totalSize' => 80 * 1024, // Under threshold
                'files' => [],
                'fileCount' => 2,
            ],
        ];

        $result = $this->invokePrivate('detectIssues', [$assets]);

        $this->assertEmpty($result);
    }

    // =================================================================
    // calculateScore() Tests
    // =================================================================

    public function testCalculateScorePerfect(): void
    {
        $issues = [];
        $assets = [
            'total' => ['size' => 300 * 1024], // Under 500 KB threshold
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        $this->assertEquals(100, $result);
    }

    public function testCalculateScoreHighSeverityDeducts20(): void
    {
        $issues = [
            ['severity' => 'high', 'type' => 'js_size', 'message' => 'Test'],
        ];
        $assets = [
            'total' => ['size' => 300 * 1024],
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        $this->assertEquals(80, $result);
    }

    public function testCalculateScoreMediumSeverityDeducts10(): void
    {
        $issues = [
            ['severity' => 'medium', 'type' => 'css_size', 'message' => 'Test'],
        ];
        $assets = [
            'total' => ['size' => 300 * 1024],
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        $this->assertEquals(90, $result);
    }

    public function testCalculateScoreLowSeverityDeducts5(): void
    {
        $issues = [
            ['severity' => 'low', 'type' => 'too_many_files', 'message' => 'Test'],
        ];
        $assets = [
            'total' => ['size' => 300 * 1024],
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        $this->assertEquals(95, $result);
    }

    public function testCalculateScoreMultipleIssues(): void
    {
        $issues = [
            ['severity' => 'high', 'type' => 'js_size', 'message' => 'Test'],   // -20
            ['severity' => 'medium', 'type' => 'css_size', 'message' => 'Test'], // -10
            ['severity' => 'low', 'type' => 'too_many_files', 'message' => 'Test'], // -5
        ];
        $assets = [
            'total' => ['size' => 300 * 1024],
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        $this->assertEquals(65, $result); // 100 - 20 - 10 - 5
    }

    public function testCalculateScoreOversizedDeductsExtra(): void
    {
        $issues = [];
        $assets = [
            'total' => ['size' => 750 * 1024], // 50% over 500 KB threshold
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        // 50% over = 50 points deduction, capped at 30
        $this->assertEquals(70, $result); // 100 - 30
    }

    public function testCalculateScoreMinimumIsZero(): void
    {
        $issues = array_fill(0, 10, ['severity' => 'high', 'type' => 'test', 'message' => 'Test']);
        $assets = [
            'total' => ['size' => 2000 * 1024], // Massively over
        ];

        $result = $this->invokePrivate('calculateScore', [$issues, $assets]);

        $this->assertEquals(0, $result);
    }

    // =================================================================
    // deduplicateRecommendations() Tests
    // =================================================================

    public function testDeduplicateRemovesDuplicateTitles(): void
    {
        $recommendations = [
            ['priority' => 'high', 'title' => 'Reduce JS Bundle', 'actions' => []],
            ['priority' => 'high', 'title' => 'Reduce JS Bundle', 'actions' => []], // Duplicate
            ['priority' => 'medium', 'title' => 'Optimize CSS', 'actions' => []],
        ];

        $result = $this->invokePrivate('deduplicateRecommendations', [$recommendations]);

        $this->assertCount(2, $result);
    }

    public function testDeduplicateSortsByPriority(): void
    {
        $recommendations = [
            ['priority' => 'low', 'title' => 'Low Priority', 'actions' => []],
            ['priority' => 'high', 'title' => 'High Priority', 'actions' => []],
            ['priority' => 'medium', 'title' => 'Medium Priority', 'actions' => []],
        ];

        $result = $this->invokePrivate('deduplicateRecommendations', [$recommendations]);

        $this->assertEquals('High Priority', $result[0]['title']);
        $this->assertEquals('Medium Priority', $result[1]['title']);
        $this->assertEquals('Low Priority', $result[2]['title']);
    }

    // =================================================================
    // estimateSavings() Tests
    // =================================================================

    public function testEstimateSavingsUnderThreshold(): void
    {
        $assets = [
            'javascript' => ['totalSize' => 200 * 1024], // Under 300 KB
            'css' => ['totalSize' => 100 * 1024],
        ];

        $result = $this->invokePrivate('estimateSavings', [$assets, 'js']);

        $this->assertEquals('0 KB', $result);
    }

    public function testEstimateSavingsOverThreshold(): void
    {
        $assets = [
            'javascript' => ['totalSize' => 500 * 1024], // 200 KB over threshold
            'css' => ['totalSize' => 100 * 1024],
        ];

        $result = $this->invokePrivate('estimateSavings', [$assets, 'js']);

        // 40% of 500 KB = 200 KB, but diff is 200 KB, so min(200, 200) = 200 KB
        $this->assertStringContainsString('KB', $result);
    }

    // =================================================================
    // formatReport() Tests
    // =================================================================

    public function testFormatReportContainsAllSections(): void
    {
        $analysis = [
            'themeId' => 'test-theme',
            'analyzedAt' => '2024-01-15T10:00:00+00:00',
            'score' => 85,
            'issues' => [
                ['severity' => 'medium', 'type' => 'css_size', 'message' => 'CSS too large'],
            ],
            'recommendations' => [
                [
                    'priority' => 'medium',
                    'title' => 'Optimize CSS',
                    'actions' => ['Use PurgeCSS'],
                    'expectedSavings' => '50 KB',
                ],
            ],
            'assets' => [
                'javascript' => ['totalSize' => 250000, 'fileCount' => 3],
                'css' => ['totalSize' => 180000, 'fileCount' => 2],
                'total' => ['size' => 430000],
            ],
        ];

        $result = $this->analyzer->formatReport($analysis);

        $this->assertStringContainsString('Theme Performance Analysis', $result);
        $this->assertStringContainsString('test-theme', $result);
        $this->assertStringContainsString('Score: 85/100', $result);
        $this->assertStringContainsString('Assets', $result);
        $this->assertStringContainsString('Issues', $result);
        $this->assertStringContainsString('Recommendations', $result);
        $this->assertStringContainsString('CSS too large', $result);
        $this->assertStringContainsString('Optimize CSS', $result);
        $this->assertStringContainsString('Use PurgeCSS', $result);
    }

    public function testFormatReportNoIssues(): void
    {
        $analysis = [
            'themeId' => 'perfect-theme',
            'analyzedAt' => '2024-01-15T10:00:00+00:00',
            'score' => 100,
            'issues' => [],
            'recommendations' => [],
            'assets' => [
                'javascript' => ['totalSize' => 150000, 'fileCount' => 2],
                'css' => ['totalSize' => 80000, 'fileCount' => 1],
                'total' => ['size' => 230000],
            ],
        ];

        $result = $this->analyzer->formatReport($analysis);

        $this->assertStringContainsString('Score: 100/100', $result);
        // Issues section should not appear if empty
        $this->assertStringNotContainsString('[HIGH]', $result);
        $this->assertStringNotContainsString('[MEDIUM]', $result);
    }
}
