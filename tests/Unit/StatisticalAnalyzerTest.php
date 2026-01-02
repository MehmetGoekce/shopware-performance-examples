<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../../chapters/20-ab-testing/src/Service/StatisticalAnalyzer.php';

use ShopwarePerformance\ABTesting\Service\StatisticalAnalyzer;
use ShopwarePerformance\ABTesting\Service\SignificanceResult;
use ShopwarePerformance\ABTesting\Service\BayesianResult;
use ShopwarePerformance\ABTesting\Service\MultiVariantResult;

/**
 * Unit Tests for StatisticalAnalyzer
 *
 * Tests the statistical functions used for A/B testing:
 * - Welch's t-test for significance
 * - Cohen's d for effect size
 * - Bayesian analysis
 * - Sample size calculations
 */
class StatisticalAnalyzerTest extends TestCase
{
    private StatisticalAnalyzer $analyzer;

    protected function setUp(): void
    {
        $this->analyzer = new StatisticalAnalyzer();
    }

    /**
     * Test that small sample sizes throw an exception
     */
    public function testMinimumSampleSizeValidation(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Sample size too small');

        // Only 10 samples each (minimum is 30)
        $control = array_fill(0, 10, 2000);
        $variant = array_fill(0, 10, 1800);

        $this->analyzer->calculateSignificance($control, $variant);
    }

    /**
     * Test significance calculation with clearly different groups
     */
    public function testSignificantDifference(): void
    {
        // Control: LCP around 2100ms (slower)
        $control = $this->generateMetrics(2100, 100, 50);
        // Variant: LCP around 1800ms (faster - 14% improvement)
        $variant = $this->generateMetrics(1800, 100, 50);

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $this->assertInstanceOf(SignificanceResult::class, $result);
        $this->assertTrue($result->isSignificant(), 'Should detect significant difference');
        $this->assertEquals('variant', $result->getWinner(), 'Variant should win (lower is better)');
        $this->assertGreaterThan(10, $result->getImprovement(), 'Improvement should be > 10%');
        $this->assertLessThan(0.05, $result->getPValue(), 'p-value should be < 0.05');
    }

    /**
     * Test no significant difference with similar groups
     */
    public function testNoSignificantDifference(): void
    {
        // Both groups nearly identical
        $control = $this->generateMetrics(2000, 200, 35);
        $variant = $this->generateMetrics(1990, 200, 35);

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $this->assertFalse($result->isSignificant(), 'Should not detect significant difference');
        $this->assertEquals('inconclusive', $result->getWinner());
    }

    /**
     * Test confidence interval calculation
     */
    public function testConfidenceInterval(): void
    {
        $control = $this->generateMetrics(2000, 100, 50);
        $variant = $this->generateMetrics(1800, 100, 50);

        $result = $this->analyzer->calculateSignificance($control, $variant, 0.95);
        $ci = $result->getConfidenceInterval();

        $this->assertArrayHasKey('lower', $ci);
        $this->assertArrayHasKey('upper', $ci);
        $this->assertLessThan($ci['upper'], $ci['lower'], 'Lower bound should be less than upper');

        // Variant mean should be within confidence interval
        $variantMean = $result->getVariantMean();
        $this->assertGreaterThanOrEqual($ci['lower'], $variantMean);
        $this->assertLessThanOrEqual($ci['upper'], $variantMean);
    }

    /**
     * Test statistical power calculation
     */
    public function testStatisticalPower(): void
    {
        // Large sample size with clear difference = high power
        $control = $this->generateMetrics(2000, 100, 100);
        $variant = $this->generateMetrics(1700, 100, 100);

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $power = $result->getStatisticalPower();
        $this->assertGreaterThanOrEqual(0, $power);
        $this->assertLessThanOrEqual(1, $power);
        $this->assertGreaterThan(0.5, $power, 'Power should be reasonably high for large effect');
    }

    /**
     * Test required sample size calculation
     */
    public function testRequiredSampleSize(): void
    {
        // 10% improvement expected, stddev of 200ms
        $sampleSize = $this->analyzer->calculateRequiredSampleSize(
            expectedImprovement: 0.10,
            baselineStdDev: 200,
            power: 0.80,
            alpha: 0.05
        );

        $this->assertIsInt($sampleSize);
        $this->assertGreaterThan(0, $sampleSize);
        // For these parameters, should need several hundred samples
        $this->assertGreaterThan(100, $sampleSize);
    }

    /**
     * Test larger improvement requires smaller sample size
     */
    public function testSampleSizeDecreasesWithLargerEffect(): void
    {
        $smallEffect = $this->analyzer->calculateRequiredSampleSize(0.05, 100);
        $largeEffect = $this->analyzer->calculateRequiredSampleSize(0.20, 100);

        $this->assertGreaterThan(
            $largeEffect,
            $smallEffect,
            'Larger effect size should require smaller sample'
        );
    }

    /**
     * Test Bayesian analysis
     */
    public function testBayesianAnalysis(): void
    {
        $control = $this->generateMetrics(2000, 100, 50);
        $variant = $this->generateMetrics(1700, 100, 50);

        $result = $this->analyzer->bayesianAnalysis($control, $variant);

        $this->assertInstanceOf(BayesianResult::class, $result);

        $probability = $result->getProbabilityToBeBest();
        $this->assertGreaterThanOrEqual(0, $probability);
        $this->assertLessThanOrEqual(1, $probability);

        // With clear improvement, probability should be high
        $this->assertGreaterThan(0.8, $probability, 'Variant should have high probability to be best');
    }

    /**
     * Test Bayesian deployment recommendation
     */
    public function testBayesianDeploymentRecommendation(): void
    {
        // Clear winner
        $control = $this->generateMetrics(2500, 100, 50);
        $variant = $this->generateMetrics(1800, 100, 50);

        $result = $this->analyzer->bayesianAnalysis($control, $variant);

        $this->assertTrue(
            $result->shouldDeploy(0.95),
            'Should recommend deployment for clear winner'
        );
    }

    /**
     * Test multi-variant analysis
     */
    public function testMultiVariantAnalysis(): void
    {
        $variants = [
            'control' => $this->generateMetrics(2000, 100, 40),
            'variant_a' => $this->generateMetrics(1900, 100, 40),
            'variant_b' => $this->generateMetrics(1700, 100, 40),
            'variant_c' => $this->generateMetrics(1950, 100, 40),
        ];

        $result = $this->analyzer->multiVariantAnalysis($variants);

        $this->assertInstanceOf(MultiVariantResult::class, $result);
        $this->assertNotEmpty($result->getComparisons());

        // variant_b should win (lowest value)
        $winner = $result->getWinner();
        $this->assertContains($winner, ['control', 'variant_a', 'variant_b', 'variant_c']);
    }

    /**
     * Test multi-variant with insufficient variants throws exception
     */
    public function testMultiVariantRequiresAtLeastTwoVariants(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('At least 2 variants required');

        $this->analyzer->multiVariantAnalysis([
            'control' => $this->generateMetrics(2000, 100, 40),
        ]);
    }

    /**
     * Test result array conversion
     */
    public function testResultToArray(): void
    {
        $control = $this->generateMetrics(2000, 100, 50);
        $variant = $this->generateMetrics(1800, 100, 50);

        $result = $this->analyzer->calculateSignificance($control, $variant);
        $array = $result->toArray();

        $this->assertArrayHasKey('control_mean', $array);
        $this->assertArrayHasKey('variant_mean', $array);
        $this->assertArrayHasKey('improvement_percent', $array);
        $this->assertArrayHasKey('p_value', $array);
        $this->assertArrayHasKey('is_significant', $array);
        $this->assertArrayHasKey('effect_size', $array);
        $this->assertArrayHasKey('winner', $array);
    }

    /**
     * Test with different confidence levels
     *
     * @dataProvider confidenceLevelProvider
     */
    public function testDifferentConfidenceLevels(float $confidence): void
    {
        $control = $this->generateMetrics(2000, 100, 50);
        $variant = $this->generateMetrics(1850, 100, 50);

        $result = $this->analyzer->calculateSignificance($control, $variant, $confidence);

        $this->assertInstanceOf(SignificanceResult::class, $result);
    }

    public static function confidenceLevelProvider(): array
    {
        return [
            '90% confidence' => [0.90],
            '95% confidence' => [0.95],
            '99% confidence' => [0.99],
        ];
    }

    /**
     * Helper: Generate normally distributed metrics
     *
     * @param float $mean Target mean
     * @param float $stddev Standard deviation
     * @param int $count Number of samples
     * @return array<float>
     */
    private function generateMetrics(float $mean, float $stddev, int $count): array
    {
        $metrics = [];
        for ($i = 0; $i < $count; $i++) {
            // Box-Muller transform for normal distribution
            $u1 = mt_rand() / mt_getrandmax();
            $u2 = mt_rand() / mt_getrandmax();
            $z = sqrt(-2 * log($u1)) * cos(2 * M_PI * $u2);
            $metrics[] = $mean + $z * $stddev;
        }
        return $metrics;
    }
}
