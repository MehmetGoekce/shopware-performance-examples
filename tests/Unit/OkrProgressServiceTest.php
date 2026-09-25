<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use App\Service\OkrProgressService;
use App\Service\OkrRepository;
use App\Service\RumDataRepository;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;

require_once __DIR__ . '/fixtures/ch15-OkrRepository.php';
require_once __DIR__ . '/fixtures/ch15-RumDataRepository.php';
require_once __DIR__ . '/../../chapters/15-langfristiger-plan/src/OkrProgressService.php';

/**
 * Kapitel 15: Gesamtstufe eines OKR-Quartals am angezeigten Wert (MEM-331).
 *
 * getQuarterProgress() gibt overall_score auf zwei Stellen gerundet aus. Die
 * Stufe muss aus derselben Zahl kommen, sonst steht "0.70 on_track" neben
 * "0.70 strong". Dieselbe Fixture prueft tests/Shell/long-term-plan-scripts.bats
 * gegen scripts/quarterly-review.sh.
 */
class OkrProgressServiceTest extends TestCase
{
    /**
     * @param list<array{objective: string, key_results: list<array{title: string, score: float|int, weight?: float|int}>}> $okrs
     * @return array{overall_score: float, status: string}
     */
    private static function progress(array $okrs): array
    {
        $okrSet = [
            'id' => 'OKR-TEST',
            'quarter' => 'Q1-2026',
            'objectives' => array_map(static fn (array $o): array => [
                'title' => $o['objective'],
                'key_results' => array_map(static fn (array $kr): array => [
                    'description' => $kr['title'],
                    'score' => (float) $kr['score'],
                    'weight' => (float) ($kr['weight'] ?? 1.0),
                ], $o['key_results']),
                'score' => 0.0,
            ], $okrs),
        ];

        $repository = new class implements OkrRepository {
            public ?array $okrSet = null;

            public function findById(string $id): array
            {
                return $this->okrSet ?? [];
            }

            public function findByQuarter(string $quarter): ?array
            {
                return $this->okrSet;
            }

            public function save(array $okrSet): void
            {
                $this->okrSet = $okrSet;
            }
        };

        $rum = new class implements RumDataRepository {
            public function getCurrentMetric(string $metric): ?float
            {
                return null;
            }

            public function getPageGoodRate(string $page): ?float
            {
                return null;
            }

            public function getConversionRate(): ?float
            {
                return null;
            }
        };

        $service = new OkrProgressService($repository, $rum, new NullLogger());

        // Objective-Scores so, wie der Service sie nach jedem Update ablegt
        $recalculate = new \ReflectionMethod($service, 'recalculateScores');
        $repository->save($recalculate->invoke($service, $okrSet));

        $progress = $service->getQuarterProgress('Q1-2026');

        return ['overall_score' => $progress['overall_score'], 'status' => $progress['status']];
    }

    private static function statusOf(float $score): string
    {
        return match (true) {
            $score >= 0.9 => 'exceptional',
            $score >= 0.7 => 'strong',
            $score >= 0.5 => 'on_track',
            $score >= 0.3 => 'at_risk',
            default => 'off_track',
        };
    }

    /**
     * @return iterable<string, array{list<array{objective: string, key_results: list<array{title: string, score: float|int, weight?: float|int}>}>, array{overall_score: float|int, status: string}}>
     */
    public static function equivalenceCases(): iterable
    {
        /** @var list<array{name: string, okrs: list<array{objective: string, key_results: list<array{title: string, score: float|int, weight?: float|int}>}>, expected: array{overall_score: float|int, status: string}}> $cases */
        $cases = json_decode(
            (string) file_get_contents(__DIR__ . '/fixtures/ch15-okr-equivalence.json'),
            true,
            512,
            JSON_THROW_ON_ERROR
        );

        foreach ($cases as $case) {
            yield $case['name'] => [$case['okrs'], $case['expected']];
        }
    }

    /**
     * @param list<array{objective: string, key_results: list<array{title: string, score: float|int, weight?: float|int}>}> $okrs
     * @param array{overall_score: float|int, status: string} $expected
     */
    #[\PHPUnit\Framework\Attributes\DataProvider('equivalenceCases')]
    public function testSameResultAsQuarterlyReviewScript(array $okrs, array $expected): void
    {
        $progress = self::progress($okrs);

        self::assertSame((float) $expected['overall_score'], $progress['overall_score']);
        self::assertSame($expected['status'], $progress['status']);
    }

    public function testStatusAlwaysMatchesTheDisplayedScore(): void
    {
        mt_srand(331);
        for ($run = 0; $run < 400; $run++) {
            $okrs = [];
            for ($o = 0, $n = mt_rand(1, 4); $o < $n; $o++) {
                $okrs[] = ['objective' => "O$o", 'key_results' => [
                    ['title' => 'k', 'score' => mt_rand(0, 100) / 100],
                ]];
            }

            $progress = self::progress($okrs);

            self::assertSame(
                self::statusOf($progress['overall_score']),
                $progress['status'],
                sprintf('Lauf %d: %s', $run, json_encode($okrs))
            );
        }
    }
}
