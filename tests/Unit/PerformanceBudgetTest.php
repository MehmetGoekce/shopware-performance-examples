<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PerformanceKultur\PerformanceBudgetService;
use PHPUnit\Framework\TestCase;
use RumMonitoring\Rum\RumStatistics;

require_once __DIR__ . '/../../chapters/12-real-user-monitoring/RumMonitoring/src/Rum/RumStatistics.php';
require_once __DIR__ . '/../../chapters/14-performance-kultur/src/PerformanceBudgetService.php';

/**
 * Kapitel 14: Error Budget aus den RUM-Logs von Kapitel 12.
 */
class PerformanceBudgetTest extends TestCase
{
    /**
     * @return list<array<string, mixed>>
     */
    private static function records(string $metric, int $good, int $over, float $threshold): array
    {
        $records = [];
        for ($i = 0; $i < $good; $i++) {
            $records[] = ['metric' => $metric, 'id' => "v5-$i-1", 'value' => $threshold];
        }
        for ($i = 0; $i < $over; $i++) {
            $records[] = ['metric' => $metric, 'id' => "v5-o$i-1", 'value' => $threshold + 1];
        }

        return $records;
    }

    public function testExactly25PercentOverUsesTheWholeBudgetAndP75IsStillGood(): void
    {
        $budget = PerformanceBudgetService::calculate(self::records('LCP', 75, 25, 2500));

        self::assertSame(100, $budget['LCP']['samples']);
        self::assertSame(25, $budget['LCP']['over']);
        self::assertSame(100.0, $budget['LCP']['used_percent']);
        self::assertSame(0.0, $budget['LCP']['remaining_percent']);
        self::assertSame('orange', $budget['LCP']['policy']);
    }

    public function testOneMorePageViewOverTheThresholdBreaksTheSlo(): void
    {
        $budget = PerformanceBudgetService::calculate(self::records('LCP', 74, 26, 2500));

        self::assertSame(104.0, $budget['LCP']['used_percent']);
        self::assertSame('red', $budget['LCP']['policy']);
    }

    public function testValueOnTheThresholdIsGood(): void
    {
        $budget = PerformanceBudgetService::calculate(self::records('CLS', 100, 0, 0.1));

        self::assertSame(0, $budget['CLS']['over']);
        self::assertSame('green', $budget['CLS']['policy']);
    }

    /**
     * Budget uebrig >= 0 genau dann, wenn das p75 nach RumStatistics (Kapitel 12) "gut" ist
     */
    public function testBudgetAgreesWithTheP75OfChapter12(): void
    {
        mt_srand(314);
        foreach (['LCP', 'INP', 'CLS'] as $metric) {
            $threshold = RumStatistics::THRESHOLDS[$metric][0];
            for ($run = 0; $run < 300; $run++) {
                $n = mt_rand(100, 400);
                $shareOver = mt_rand(15, 35) / 100;
                $values = [];
                $records = [];
                for ($i = 0; $i < $n; $i++) {
                    $value = mt_rand() / mt_getrandmax() < $shareOver ? $threshold * 1.5 : $threshold * mt_rand(50, 100) / 100;
                    $values[] = $value;
                    $records[] = ['metric' => $metric, 'id' => "v5-$run-$i", 'value' => $value];
                }
                sort($values);

                $budget = PerformanceBudgetService::calculate($records)[$metric];
                $p75Good = RumStatistics::percentile($values, 75) <= $threshold;

                self::assertSame($p75Good, $budget['remaining_percent'] >= 0, "$metric Lauf $run: n=$n, ueber=" . $budget['over']);
            }
        }
    }

    public function testRepeatedReportsOfOnePageViewCountOnceWithTheLastValue(): void
    {
        $records = self::records('INP', 99, 0, 200);
        // Ein Seitenaufruf meldet INP dreimal (bei jedem Wechsel in den Hintergrund)
        $records[] = ['metric' => 'INP', 'id' => 'v5-x-1', 'value' => 900];
        $records[] = ['metric' => 'INP', 'id' => 'v5-x-1', 'value' => 900];
        $records[] = ['metric' => 'INP', 'id' => 'v5-x-1', 'value' => 150];

        $budget = PerformanceBudgetService::calculate($records);

        self::assertSame(100, $budget['INP']['samples']);
        self::assertSame(0, $budget['INP']['over']);
    }

    public function testRecordsWithoutIdCountSeparately(): void
    {
        $records = array_fill(0, 100, ['metric' => 'LCP', 'value' => 3000]);

        $budget = PerformanceBudgetService::calculate($records);

        self::assertSame(100, $budget['LCP']['samples']);
        self::assertSame(100, $budget['LCP']['over']);
    }

    public function testBelowMinSamplesThereIsNoRating(): void
    {
        $budget = PerformanceBudgetService::calculate(self::records('LCP', 0, 99, 2500));

        self::assertSame(99, $budget['LCP']['samples']);
        self::assertSame(99, $budget['LCP']['over']);
        self::assertNull($budget['LCP']['used_percent']);
        self::assertSame('no-data', $budget['LCP']['policy']);
        self::assertSame('red', PerformanceBudgetService::calculate(self::records('LCP', 0, 99, 2500), 99)['LCP']['policy']);
    }

    public function testOtherMetricsAndBrokenValuesAreIgnored(): void
    {
        $records = self::records('LCP', 100, 0, 2500);
        $records[] = ['metric' => 'TTFB', 'id' => 'v5-t-1', 'value' => 9000];
        $records[] = ['metric' => 'LCP', 'id' => 'v5-k-1', 'value' => 'kaputt'];

        $budget = PerformanceBudgetService::calculate($records);

        self::assertSame(['LCP', 'INP', 'CLS'], array_keys($budget));
        self::assertSame(100, $budget['LCP']['samples']);
    }

    /**
     * @return iterable<string, array{float, string}>
     */
    public static function policyProvider(): iterable
    {
        yield '100' => [100.0, 'green'];
        yield '50.1' => [50.1, 'green'];
        yield '50' => [50.0, 'yellow'];
        yield '20' => [20.0, 'yellow'];
        yield '19.9' => [19.9, 'orange'];
        yield '0' => [0.0, 'orange'];
        yield '-0.1' => [-0.1, 'red'];
    }

    #[\PHPUnit\Framework\Attributes\DataProvider('policyProvider')]
    public function testPolicyLevels(float $remaining, string $policy): void
    {
        self::assertSame($policy, PerformanceBudgetService::policy($remaining));
    }

    public function testOverallIsTheWorstMetricWithData(): void
    {
        $noData = ['policy' => 'no-data'];

        self::assertSame('red', PerformanceBudgetService::overall(['LCP' => ['policy' => 'green'], 'INP' => ['policy' => 'red'], 'CLS' => ['policy' => 'orange']]));
        self::assertSame('yellow', PerformanceBudgetService::overall(['LCP' => ['policy' => 'yellow'], 'INP' => $noData, 'CLS' => ['policy' => 'green']]));
        self::assertSame('no-data', PerformanceBudgetService::overall(['LCP' => $noData, 'INP' => $noData, 'CLS' => $noData]));
    }
}
