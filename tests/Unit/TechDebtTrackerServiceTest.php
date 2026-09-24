<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use App\Service\TechDebtRepository;
use App\Service\TechDebtTrackerService;
use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../../chapters/15-langfristiger-plan/src/TechDebtRepository.php';
require_once __DIR__ . '/../../chapters/15-langfristiger-plan/src/TechDebtTrackerService.php';

/**
 * Kapitel 15: Tech-Debt-Score als Summe der Severity-Punkte.
 */
class TechDebtTrackerServiceTest extends TestCase
{
    /**
     * @param list<array{title: string, severity: string, effort: string, category?: string}> $items
     */
    private static function tracker(array $items): TechDebtTrackerService
    {
        return new TechDebtTrackerService(new class ($items) implements TechDebtRepository {
            /**
             * @param list<array{title: string, severity: string, effort: string, category?: string}> $items
             */
            public function __construct(private readonly array $items)
            {
            }

            public function findAllPerformanceDebt(): array
            {
                return $this->items;
            }
        });
    }

    /**
     * @return array{title: string, severity: string, effort: string, category: string}
     */
    private static function item(string $title, string $severity, string $effort, string $category = 'frontend'): array
    {
        return ['title' => $title, 'severity' => $severity, 'effort' => $effort, 'category' => $category];
    }

    public function testScoreIsTheSumOfSeverityPointsWithoutUpperBound(): void
    {
        $items = array_fill(0, 6, self::item('crit', 'critical', 'large'));

        $score = self::tracker($items)->getTechDebtScore();

        self::assertSame(600, $score['total_score']);
        self::assertSame('critical', $score['status']);
        self::assertSame(6, $score['item_count']);
    }

    public function testStatusBoundaries(): void
    {
        $status = static function (int $criticals, int $lows): string {
            $items = array_merge(
                array_fill(0, $criticals, self::item('c', 'critical', 'small')),
                array_fill(0, $lows, self::item('l', 'low', 'small'))
            );

            return self::tracker($items)->getTechDebtScore()['status'];
        };

        self::assertSame('healthy', $status(1, 49));   // 198
        self::assertSame('attention', $status(2, 0));  // 200
        self::assertSame('attention', $status(4, 49)); // 498
        self::assertSame('critical', $status(5, 0));   // 500
    }

    public function testPointsAreGroupedByCategoryAndMissingCategoryIsOther(): void
    {
        $score = self::tracker([
            self::item('a', 'high', 'small', 'database'),
            self::item('b', 'medium', 'small', 'database'),
            ['title' => 'c', 'severity' => 'low', 'effort' => 'small'],
        ])->getTechDebtScore();

        self::assertSame(['database' => 50, 'other' => 2], $score['by_category']);
    }

    public function testUnknownSeverityAndEffortCountAsMedium(): void
    {
        $tracker = self::tracker([self::item('x', 'blocker', 'huge')]);

        self::assertSame(10, $tracker->getTechDebtScore()['total_score']);
        self::assertSame(2.0, $tracker->calculatePriority(['severity' => 'blocker', 'effort' => 'huge']));
    }

    public function testCheapHighItemOutranksExpensiveCriticalItem(): void
    {
        $score = self::tracker([
            self::item('critical, 2 Wochen', 'critical', 'xlarge'), // 100 / 21 = 4.8
            self::item('high, 1 Tag', 'high', 'small'),             // 40 / 2 = 20
            self::item('low, trivial', 'low', 'trivial'),           // 2 / 1 = 2
        ])->getTechDebtScore();

        self::assertSame(
            ['high, 1 Tag', 'critical, 2 Wochen', 'low, trivial'],
            array_column($score['top_priorities'], 'title')
        );
    }

    /**
     * Dieselbe Fixture prüft tests/Shell/long-term-plan-scripts.bats gegen
     * scripts/tech-debt-report.sh --json: Skript und Service rechnen gleich.
     *
     * @return iterable<string, array{list<array{title: string, severity: string, effort: string, category?: string}>, array{total_score: int, status: string, by_category: array<string, int>, item_count: int, top_titles: list<string>}}>
     */
    public static function equivalenceCases(): iterable
    {
        /** @var list<array{name: string, items: list<array{title: string, severity: string, effort: string, category?: string}>, expected: array{total_score: int, status: string, by_category: array<string, int>, item_count: int, top_titles: list<string>}}> $cases */
        $cases = json_decode(
            (string) file_get_contents(__DIR__ . '/fixtures/ch15-tech-debt-equivalence.json'),
            true,
            512,
            JSON_THROW_ON_ERROR
        );

        foreach ($cases as $case) {
            yield $case['name'] => [$case['items'], $case['expected']];
        }
    }

    /**
     * @param list<array{title: string, severity: string, effort: string, category?: string}> $items
     * @param array{total_score: int, status: string, by_category: array<string, int>, item_count: int, top_titles: list<string>} $expected
     */
    #[\PHPUnit\Framework\Attributes\DataProvider('equivalenceCases')]
    public function testSameResultAsTechDebtReportScript(array $items, array $expected): void
    {
        $score = self::tracker($items)->getTechDebtScore();

        self::assertSame($expected['total_score'], $score['total_score']);
        self::assertSame($expected['status'], $score['status']);
        self::assertSame($expected['by_category'], $score['by_category']);
        self::assertSame($expected['item_count'], $score['item_count']);
        self::assertSame($expected['top_titles'], array_column($score['top_priorities'], 'title'));
    }

    public function testTopPrioritiesAreCappedAtFive(): void
    {
        $score = self::tracker(array_fill(0, 7, self::item('m', 'medium', 'medium')))->getTechDebtScore();

        self::assertCount(5, $score['top_priorities']);
        self::assertSame(70, $score['total_score']);
    }
}
