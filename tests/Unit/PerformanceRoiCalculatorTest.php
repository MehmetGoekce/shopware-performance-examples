<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../../src/Service/PerformanceRoiCalculator.php';

use PerformanceExamples\Service\PerformanceRoiCalculator;
use PerformanceExamples\Service\PerformanceRoiResult;

/**
 * Unit Tests for PerformanceRoiCalculator
 *
 * Tests the ROI calculation logic from Chapter 1.
 * Pure logic, no mocks needed.
 */
class PerformanceRoiCalculatorTest extends TestCase
{
    private PerformanceRoiCalculator $calculator;

    protected function setUp(): void
    {
        $this->calculator = new PerformanceRoiCalculator();
    }

    /**
     * Test revenue impact with typical B2B shop values (from the book).
     */
    public function testCalculateRevenueImpactTypicalShop(): void
    {
        $result = $this->calculator->calculateRevenueImpact(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 4.8,
            targetLoadTimeSeconds: 2.0,
            currentConversionRate: 0.022
        );

        $this->assertInstanceOf(PerformanceRoiResult::class, $result);
        $this->assertGreaterThan(0, $result->additionalRevenue);
        $this->assertGreaterThan($result->currentConversionRate, $result->newConversionRate);
    }

    /**
     * Test that no improvement yields zero additional revenue.
     */
    public function testNoImprovementYieldsZeroRevenue(): void
    {
        $result = $this->calculator->calculateRevenueImpact(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 2.0,
            targetLoadTimeSeconds: 2.0,
            currentConversionRate: 0.022
        );

        $this->assertSame(0.0, $result->additionalRevenue);
        $this->assertSame(0.022, $result->newConversionRate);
    }

    /**
     * Test that slower target (target >= current) yields zero additional revenue.
     */
    public function testSlowerTargetYieldsZeroRevenue(): void
    {
        $result = $this->calculator->calculateRevenueImpact(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 2.0,
            targetLoadTimeSeconds: 5.0,
            currentConversionRate: 0.022
        );

        $this->assertSame(0.0, $result->additionalRevenue);
    }

    /**
     * Test zero revenue input.
     */
    public function testZeroRevenueInput(): void
    {
        $result = $this->calculator->calculateRevenueImpact(
            currentRevenue: 0.0,
            currentLoadTimeSeconds: 4.8,
            targetLoadTimeSeconds: 2.0,
            currentConversionRate: 0.022
        );

        $this->assertSame(0.0, $result->additionalRevenue);
        $this->assertGreaterThan(0.022, $result->newConversionRate);
    }

    /**
     * Test full ROI calculation with investment cost.
     */
    public function testCalculateFullRoi(): void
    {
        $result = $this->calculator->calculateFullRoi(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 4.8,
            targetLoadTimeSeconds: 2.0,
            currentConversionRate: 0.022,
            investmentCost: 12_600
        );

        $this->assertGreaterThan(0, $result->roiPercent);
        $this->assertSame(12_600.0, $result->investmentCost);
        $this->assertGreaterThan(0, $result->additionalRevenue);
    }

    /**
     * Test full ROI with zero investment cost.
     */
    public function testFullRoiZeroInvestment(): void
    {
        $result = $this->calculator->calculateFullRoi(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 4.8,
            targetLoadTimeSeconds: 2.0,
            currentConversionRate: 0.022,
            investmentCost: 0.0
        );

        $this->assertSame(0.0, $result->roiPercent);
    }

    /**
     * Test lost revenue calculation.
     */
    public function testCalculateLostRevenue(): void
    {
        $lost = $this->calculator->calculateLostRevenue(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 4.8,
            baselineLoadTimeSeconds: 2.0
        );

        $this->assertGreaterThan(0, $lost);
        $this->assertLessThanOrEqual(8_000_000, $lost);
    }

    /**
     * Test lost revenue when load time is at or below baseline.
     */
    public function testNoLostRevenueAtBaseline(): void
    {
        $lost = $this->calculator->calculateLostRevenue(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 2.0,
            baselineLoadTimeSeconds: 2.0
        );

        $this->assertSame(0.0, $lost);

        $lostFaster = $this->calculator->calculateLostRevenue(
            currentRevenue: 8_000_000,
            currentLoadTimeSeconds: 1.5,
            baselineLoadTimeSeconds: 2.0
        );

        $this->assertSame(0.0, $lostFaster);
    }

    /**
     * Test that lost revenue is capped at 100% of revenue.
     */
    public function testLostRevenueCappedAt100Percent(): void
    {
        $lost = $this->calculator->calculateLostRevenue(
            currentRevenue: 1_000_000,
            currentLoadTimeSeconds: 100.0,
            baselineLoadTimeSeconds: 2.0
        );

        $this->assertSame(1_000_000.0, $lost);
    }

    /**
     * Test sample report generation.
     */
    public function testGenerateSampleReport(): void
    {
        $report = $this->calculator->generateSampleReport();

        $this->assertArrayHasKey('input', $report);
        $this->assertArrayHasKey('output', $report);
        $this->assertArrayHasKey('summary', $report);

        $this->assertSame(8_000_000.0, $report['input']['current_revenue']);
        $this->assertGreaterThan(0, $report['output']['additional_revenue']);
        $this->assertGreaterThan(0, $report['output']['roi_percent']);
        $this->assertIsString($report['summary']);
    }

    /**
     * Test conversion rate lift is proportional to load time improvement.
     */
    public function testConversionLiftProportionality(): void
    {
        $small = $this->calculator->calculateRevenueImpact(8_000_000, 3.0, 2.5, 0.022);
        $large = $this->calculator->calculateRevenueImpact(8_000_000, 5.0, 2.0, 0.022);

        $this->assertGreaterThan($small->additionalRevenue, $large->additionalRevenue);
    }
}
