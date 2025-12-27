<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Tests;

use PHPUnit\Framework\TestCase;
use ShopwarePerformance\ABTesting\Service\StatisticalAnalyzer;

/**
 * StatisticalAnalyzerTest - Unit Tests für StatisticalAnalyzer
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */
class StatisticalAnalyzerTest extends TestCase
{
    private StatisticalAnalyzer $analyzer;

    protected function setUp(): void
    {
        $this->analyzer = new StatisticalAnalyzer();
    }

    public function testCalculateSignificanceWithClearDifference(): void
    {
        // Control: Mean ~2100ms
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];

        // Variant: Mean ~1800ms (signifikant besser)
        $variant = [1800, 1750, 1900, 1850, 1780, 1820, 1890, 1770, 1840, 1810];

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $this->assertTrue($result->isSignificant());
        $this->assertSame('variant', $result->getWinner());
        $this->assertGreaterThan(10, $result->getImprovement());
        $this->assertLessThan(0.05, $result->getPValue());
    }

    public function testCalculateSignificanceWithNoSignificantDifference(): void
    {
        // Control & Variant haben ähnliche Werte
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [2090, 2060, 2180, 2130, 2100, 2110, 2170, 2080, 2150, 2120];

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $this->assertFalse($result->isSignificant());
        $this->assertSame('inconclusive', $result->getWinner());
    }

    public function testCalculateSignificanceWithVariantWorse(): void
    {
        // Variant ist schlechter als Control
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [2800, 2750, 2900, 2850, 2780, 2820, 2890, 2770, 2840, 2810];

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $this->assertTrue($result->isSignificant());
        $this->assertSame('control', $result->getWinner());
        $this->assertLessThan(-10, $result->getImprovement());
    }

    public function testThrowsExceptionForSmallSampleSize(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Sample size too small');

        $control = [2100, 2050, 2200];
        $variant = [1800, 1750, 1900];

        $this->analyzer->calculateSignificance($control, $variant);
    }

    public function testCalculateRequiredSampleSize(): void
    {
        // Erwartete 15% Verbesserung, Baseline StdDev = 200
        $sampleSize = $this->analyzer->calculateRequiredSampleSize(
            expectedImprovement: 0.15,
            baselineStdDev: 200,
            power: 0.80,
            alpha: 0.05
        );

        $this->assertGreaterThan(0, $sampleSize);
        $this->assertIsInt($sampleSize);

        // Für 15% Improvement mit Power 0.80 sollte Sample Size im realistischen Bereich sein
        $this->assertLessThan(10000, $sampleSize);
    }

    public function testBayesianAnalysis(): void
    {
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [1800, 1750, 1900, 1850, 1780, 1820, 1890, 1770, 1840, 1810];

        $result = $this->analyzer->bayesianAnalysis($control, $variant);

        $this->assertGreaterThan(0.90, $result->getProbabilityToBeBest());
        $this->assertTrue($result->shouldDeploy(0.90));

        $resultArray = $result->toArray();
        $this->assertArrayHasKey('probability_to_be_best', $resultArray);
        $this->assertArrayHasKey('expected_loss', $resultArray);
        $this->assertArrayHasKey('recommendation', $resultArray);
    }

    public function testMultiVariantAnalysis(): void
    {
        $variants = [
            'control' => [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110],
            'variant_a' => [1800, 1750, 1900, 1850, 1780, 1820, 1890, 1770, 1840, 1810],
            'variant_b' => [1900, 1850, 2000, 1950, 1880, 1920, 1990, 1870, 1940, 1910],
        ];

        $result = $this->analyzer->multiVariantAnalysis($variants);

        $this->assertSame('variant_a', $result->getWinner());

        $comparisons = $result->getComparisons();
        $this->assertArrayHasKey('variant_a', $comparisons);
        $this->assertArrayHasKey('variant_b', $comparisons);

        $resultArray = $result->toArray();
        $this->assertArrayHasKey('winner', $resultArray);
        $this->assertArrayHasKey('comparisons', $resultArray);
    }

    public function testSignificanceResultToArray(): void
    {
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [1800, 1750, 1900, 1850, 1780, 1820, 1890, 1770, 1840, 1810];

        $result = $this->analyzer->calculateSignificance($control, $variant);
        $array = $result->toArray();

        $this->assertArrayHasKey('control_mean', $array);
        $this->assertArrayHasKey('variant_mean', $array);
        $this->assertArrayHasKey('improvement_percent', $array);
        $this->assertArrayHasKey('p_value', $array);
        $this->assertArrayHasKey('is_significant', $array);
        $this->assertArrayHasKey('effect_size', $array);
        $this->assertArrayHasKey('statistical_power', $array);
        $this->assertArrayHasKey('winner', $array);
    }

    public function testConfidenceIntervalCalculation(): void
    {
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [1800, 1750, 1900, 1850, 1780, 1820, 1890, 1770, 1840, 1810];

        $result = $this->analyzer->calculateSignificance($control, $variant, 0.95);

        $ci = $result->getConfidenceInterval();

        $this->assertArrayHasKey('lower', $ci);
        $this->assertArrayHasKey('upper', $ci);

        // Variant Mean sollte innerhalb des Confidence Intervals liegen
        $variantMean = $result->getVariantMean();
        $this->assertGreaterThan($ci['lower'], $variantMean);
        $this->assertLessThan($ci['upper'], $variantMean);
    }

    public function testStatisticalPowerCalculation(): void
    {
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [1800, 1750, 1900, 1850, 1780, 1820, 1890, 1770, 1840, 1810];

        $result = $this->analyzer->calculateSignificance($control, $variant);

        $power = $result->getStatisticalPower();

        // Power sollte zwischen 0 und 1 sein
        $this->assertGreaterThanOrEqual(0, $power);
        $this->assertLessThanOrEqual(1, $power);

        // Mit klarem Unterschied sollte Power hoch sein
        $this->assertGreaterThan(0.5, $power);
    }

    public function testDifferentConfidenceLevels(): void
    {
        $control = [2100, 2050, 2200, 2150, 2080, 2120, 2190, 2070, 2140, 2110];
        $variant = [2000, 1950, 2100, 2050, 1980, 2020, 2090, 1970, 2040, 2010];

        // 90% Confidence
        $result90 = $this->analyzer->calculateSignificance($control, $variant, 0.90);

        // 99% Confidence
        $result99 = $this->analyzer->calculateSignificance($control, $variant, 0.99);

        // Bei gleichem Datensatz sollte 90% eher signifikant sein als 99%
        if ($result90->isSignificant()) {
            $this->assertLessThan($result99->getPValue(), $result90->getPValue());
        }
    }
}
