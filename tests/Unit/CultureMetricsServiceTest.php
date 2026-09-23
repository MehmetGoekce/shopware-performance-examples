<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PerformanceKultur\CultureDataSource;
use PerformanceKultur\CultureMetricsService;
use PerformanceKultur\PerformanceBudgetService;
use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../../chapters/12-real-user-monitoring/RumMonitoring/src/Rum/RumStatistics.php';
require_once __DIR__ . '/../../chapters/14-performance-kultur/src/PerformanceBudgetService.php';
require_once __DIR__ . '/../../chapters/14-performance-kultur/src/CultureDataSource.php';
require_once __DIR__ . '/../../chapters/14-performance-kultur/src/CultureMetricsService.php';

/**
 * Kapitel 14: Performance Culture Score.
 */
class CultureMetricsServiceTest extends TestCase
{
    /**
     * @param array{total: int, performance_reviewed: int}|null $prs
     * @param list<array{recovery_time_hours: float, postmortem_completed: bool}>|null $incidents
     * @param array{date: string, average_score: float, response_rate: float}|null $survey
     * @param array{brown_bags: int, wiki_updates: int, slack_messages: int}|null $knowledge
     */
    private static function source(?array $prs, ?array $incidents, ?array $survey, ?array $knowledge): CultureDataSource
    {
        return new class ($prs, $incidents, $survey, $knowledge) implements CultureDataSource {
            /**
             * @param array{total: int, performance_reviewed: int}|null $prs
             * @param list<array{recovery_time_hours: float, postmortem_completed: bool}>|null $incidents
             * @param array{date: string, average_score: float, response_rate: float}|null $survey
             * @param array{brown_bags: int, wiki_updates: int, slack_messages: int}|null $knowledge
             */
            public function __construct(
                private readonly ?array $prs,
                private readonly ?array $incidents,
                private readonly ?array $survey,
                private readonly ?array $knowledge
            ) {
            }

            public function pullRequestCounts(int $days): ?array
            {
                return $this->prs;
            }

            public function performanceIncidents(int $days): ?array
            {
                return $this->incidents;
            }

            public function latestSurvey(): ?array
            {
                return $this->survey;
            }

            public function knowledgeSharingCounts(int $days): ?array
            {
                return $this->knowledge;
            }
        };
    }

    /**
     * Echte Ausgabe von PerformanceBudgetService::calculate(): $over von 100 LCP-Werten ueber 2500 ms
     *
     * @return array<string, array{samples: int, over: int, used_percent: float|null, remaining_percent: float|null, policy: string}>
     */
    private static function budget(int $over): array
    {
        $records = [];
        for ($i = 0; $i < 100; $i++) {
            $records[] = ['metric' => 'LCP', 'id' => "v5-$i", 'value' => $i < $over ? 2501 : 2500];
        }

        return PerformanceBudgetService::calculate($records);
    }

    public function testWeightsAddUpToOne(): void
    {
        self::assertEqualsWithDelta(1.0, array_sum(CultureMetricsService::WEIGHTS), 1e-9);
    }

    public function testAllComponentsRatedGiveTheWeightedSum(): void
    {
        $service = new CultureMetricsService(self::source(
            ['total' => 10, 'performance_reviewed' => 8],                        // 80
            [['recovery_time_hours' => 3.0, 'postmortem_completed' => true]],    // 75 + 10 = 85
            ['date' => '2026-09-01', 'average_score' => 4.0, 'response_rate' => 0.9], // 75
            ['brown_bags' => 3, 'wiki_updates' => 12, 'slack_messages' => 100]   // (50+100+100)/3
        ));

        // 10 von 100 ueber der Schwelle: 40 % verbraucht, 60 % uebrig -> green -> 100
        $result = $service->calculateCultureScore(self::budget(10));

        $expected = 80 * 0.25 + 100 * 0.25 + 85 * 0.20 + 75 * 0.15 + 83.3 * 0.15;
        self::assertSame(round($expected, 1), $result['overall_score']);
        self::assertSame([], $result['unrated']);
        self::assertSame('green', $result['components']['budget_compliance']['metrics']['policy']);
    }

    public function testComponentsWithoutDataAreLeftOutNotScoredAsNeutral(): void
    {
        $service = new CultureMetricsService(self::source(
            ['total' => 10, 'performance_reviewed' => 5],
            null,
            null,
            null
        ));

        // 30 von 100 ueber der Schwelle: SLO verletzt -> red -> 0 Punkte
        $result = $service->calculateCultureScore(self::budget(30));

        self::assertSame(round((50 * 0.25 + 0 * 0.25) / 0.5, 1), $result['overall_score']);
        self::assertSame(['incident_response', 'developer_satisfaction', 'knowledge_sharing'], $result['unrated']);
        self::assertContains('Keine Daten fuer incident_response: Datenquelle anbinden', $result['recommendations']);
    }

    public function testNothingRatedGivesNoScore(): void
    {
        $service = new CultureMetricsService(self::source(null, null, null, null));

        $result = $service->calculateCultureScore(PerformanceBudgetService::calculate([]));

        self::assertNull($result['overall_score']);
        self::assertCount(5, $result['unrated']);
        self::assertSame('unknown', $result['trend']);
    }

    public function testNoIncidentsIsFullScoreButNoTrackerIsUnrated(): void
    {
        $none = new CultureMetricsService(self::source(null, [], null, null));
        $noTracker = new CultureMetricsService(self::source(null, null, null, null));

        self::assertSame(100.0, $none->calculateCultureScore([])['components']['incident_response']['score']);
        self::assertNull($noTracker->calculateCultureScore([])['components']['incident_response']['score']);
    }

    public function testBudgetStepsMapToPoints(): void
    {
        $service = new CultureMetricsService(self::source(null, null, null, null));

        // 10 -> 60 % uebrig green, 15 -> 40 % yellow, 25 -> 0 % orange, 26 -> red
        $points = [];
        foreach ([10 => 'green', 15 => 'yellow', 25 => 'orange', 26 => 'red'] as $over => $policy) {
            $component = $service->calculateCultureScore(self::budget($over))['components']['budget_compliance'];
            self::assertSame($policy, $component['metrics']['policy']);
            $points[] = $component['score'];
        }

        self::assertSame([100.0, 60.0, 30.0, 0.0], $points);
    }

    public function testSurveyScaleOneToFiveMapsToZeroToHundred(): void
    {
        foreach ([1.0 => 0.0, 3.0 => 50.0, 5.0 => 100.0] as $average => $score) {
            $service = new CultureMetricsService(self::source(
                null,
                null,
                ['date' => '2026-09-01', 'average_score' => $average, 'response_rate' => 1.0],
                null
            ));

            self::assertSame($score, $service->calculateCultureScore([])['components']['developer_satisfaction']['score']);
        }
    }

    public function testTrendNeedsMoreThanFivePoints(): void
    {
        self::assertSame('stable', CultureMetricsService::trend(55.0, 50.0));
        self::assertSame('improving', CultureMetricsService::trend(55.1, 50.0));
        self::assertSame('stable', CultureMetricsService::trend(45.0, 50.0));
        self::assertSame('declining', CultureMetricsService::trend(44.9, 50.0));
        self::assertSame('unknown', CultureMetricsService::trend(50.0, null));
    }

    public function testMttrStepsAndPostmortemBonus(): void
    {
        $score = static function (float $hours, bool $postmortem): ?float {
            $service = new CultureMetricsService(self::source(
                null,
                [['recovery_time_hours' => $hours, 'postmortem_completed' => $postmortem]],
                null,
                null
            ));

            return $service->calculateCultureScore([])['components']['incident_response']['score'];
        };

        self::assertSame(100.0, $score(2.0, true));
        self::assertSame(75.0, $score(2.1, false));
        self::assertSame(60.0, $score(8.0, true));
        self::assertSame(25.0, $score(8.1, false));
    }
}
