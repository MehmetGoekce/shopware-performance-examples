<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Unit Tests for Performance Metrics Calculations
 *
 * Tests the metric calculations and thresholds used throughout the book.
 */
class PerformanceMetricsTest extends TestCase
{
    /**
     * Core Web Vitals thresholds (Google 2024).
     */
    private const CWV_THRESHOLDS = [
        'LCP' => ['good' => 2500, 'poor' => 4000],      // ms
        'INP' => ['good' => 200, 'poor' => 500],        // ms
        'CLS' => ['good' => 0.1, 'poor' => 0.25],       // score
    ];

    /**
     * Test LCP classification.
     */
    public function testLcpClassification(): void
    {
        $this->assertSame('good', $this->classifyLcp(1500));
        $this->assertSame('good', $this->classifyLcp(2500));
        $this->assertSame('needs-improvement', $this->classifyLcp(3000));
        $this->assertSame('poor', $this->classifyLcp(4500));
    }

    /**
     * Test INP classification.
     */
    public function testInpClassification(): void
    {
        $this->assertSame('good', $this->classifyInp(100));
        $this->assertSame('good', $this->classifyInp(200));
        $this->assertSame('needs-improvement', $this->classifyInp(350));
        $this->assertSame('poor', $this->classifyInp(600));
    }

    /**
     * Test CLS classification.
     */
    public function testClsClassification(): void
    {
        $this->assertSame('good', $this->classifyCls(0.05));
        $this->assertSame('good', $this->classifyCls(0.1));
        $this->assertSame('needs-improvement', $this->classifyCls(0.15));
        $this->assertSame('poor', $this->classifyCls(0.3));
    }

    /**
     * Test TTFB calculation.
     */
    public function testTtfbCalculation(): void
    {
        $requestStart = 1000.0;
        $responseStart = 1250.5;

        $ttfb = $responseStart - $requestStart;

        $this->assertSame(250.5, $ttfb);
        $this->assertLessThan(500, $ttfb); // Good TTFB
    }

    /**
     * Test performance score calculation (0-100).
     */
    public function testPerformanceScore(): void
    {
        // Weighted scoring similar to Lighthouse
        $weights = [
            'FCP' => 0.10,
            'SI' => 0.10,
            'LCP' => 0.25,
            'TBT' => 0.30,
            'CLS' => 0.25,
        ];

        // All metrics at perfect scores
        $metricScores = [
            'FCP' => 100,
            'SI' => 100,
            'LCP' => 100,
            'TBT' => 100,
            'CLS' => 100,
        ];

        $totalScore = 0;
        foreach ($weights as $metric => $weight) {
            $totalScore += $metricScores[$metric] * $weight;
        }

        $this->assertSame(100.0, $totalScore);

        // Mixed scores
        $metricScores2 = [
            'FCP' => 90,
            'SI' => 85,
            'LCP' => 70,
            'TBT' => 80,
            'CLS' => 95,
        ];

        $totalScore2 = 0;
        foreach ($weights as $metric => $weight) {
            $totalScore2 += $metricScores2[$metric] * $weight;
        }

        $this->assertEqualsWithDelta(82.75, $totalScore2, 0.01);
    }

    /**
     * Test cache hit ratio calculation.
     */
    public function testCacheHitRatio(): void
    {
        $hits = 950;
        $misses = 50;
        $total = $hits + $misses;

        $hitRatio = ($hits / $total) * 100;

        $this->assertSame(95.0, $hitRatio);
        $this->assertGreaterThan(90, $hitRatio); // Good cache performance
    }

    /**
     * Test compression ratio calculation.
     */
    public function testCompressionRatio(): void
    {
        $originalSize = 100000; // 100 KB
        $compressedSize = 25000; // 25 KB

        $ratio = (1 - ($compressedSize / $originalSize)) * 100;

        $this->assertSame(75.0, $ratio);
        $this->assertGreaterThan(70, $ratio); // Good compression
    }

    /**
     * Test query time threshold.
     */
    public function testQueryTimeThreshold(): void
    {
        $slowQueryThreshold = 1000; // 1 second in ms

        $queryTimes = [50, 120, 300, 1500, 2000, 80];

        $slowQueries = array_filter($queryTimes, fn($time) => $time > $slowQueryThreshold);

        $this->assertCount(2, $slowQueries);
        $this->assertContains(1500, $slowQueries);
        $this->assertContains(2000, $slowQueries);
    }

    /**
     * Test throughput calculation (requests per second).
     */
    public function testThroughputCalculation(): void
    {
        $totalRequests = 10000;
        $durationSeconds = 60;

        $rps = $totalRequests / $durationSeconds;

        $this->assertEqualsWithDelta(166.67, $rps, 0.01);
    }

    /**
     * Test percentile calculation.
     */
    public function testPercentileCalculation(): void
    {
        $responseTimes = [100, 120, 130, 150, 200, 250, 300, 400, 500, 1000];
        sort($responseTimes);

        // P50 (median)
        $p50Index = (int) ceil(0.50 * count($responseTimes)) - 1;
        $p50 = $responseTimes[$p50Index];

        // P95
        $p95Index = (int) ceil(0.95 * count($responseTimes)) - 1;
        $p95 = $responseTimes[$p95Index];

        // P99
        $p99Index = (int) ceil(0.99 * count($responseTimes)) - 1;
        $p99 = $responseTimes[$p99Index];

        $this->assertSame(200, $p50);
        $this->assertSame(1000, $p95);
        $this->assertSame(1000, $p99);
    }

    /**
     * Helper: Classify LCP value.
     */
    private function classifyLcp(int $value): string
    {
        if ($value <= self::CWV_THRESHOLDS['LCP']['good']) {
            return 'good';
        }
        if ($value <= self::CWV_THRESHOLDS['LCP']['poor']) {
            return 'needs-improvement';
        }
        return 'poor';
    }

    /**
     * Helper: Classify INP value.
     */
    private function classifyInp(int $value): string
    {
        if ($value <= self::CWV_THRESHOLDS['INP']['good']) {
            return 'good';
        }
        if ($value <= self::CWV_THRESHOLDS['INP']['poor']) {
            return 'needs-improvement';
        }
        return 'poor';
    }

    /**
     * Helper: Classify CLS value.
     */
    private function classifyCls(float $value): string
    {
        if ($value <= self::CWV_THRESHOLDS['CLS']['good']) {
            return 'good';
        }
        if ($value <= self::CWV_THRESHOLDS['CLS']['poor']) {
            return 'needs-improvement';
        }
        return 'poor';
    }
}
