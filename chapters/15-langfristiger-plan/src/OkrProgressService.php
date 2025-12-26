<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;

/**
 * OKR Progress Tracking Service
 *
 * Trackt Fortschritt von Performance-OKRs über Quartale.
 * Integriert mit RUM-Daten für automatisches Key Result Tracking.
 */
class OkrProgressService
{
    // Scoring Ranges
    private const SCORE_RANGES = [
        'exceptional' => ['min' => 0.9, 'max' => 1.0, 'color' => 'blue'],
        'strong' => ['min' => 0.7, 'max' => 0.9, 'color' => 'green'],
        'on_track' => ['min' => 0.5, 'max' => 0.7, 'color' => 'yellow'],
        'at_risk' => ['min' => 0.3, 'max' => 0.5, 'color' => 'orange'],
        'off_track' => ['min' => 0.0, 'max' => 0.3, 'color' => 'red'],
    ];

    public function __construct(
        private readonly OkrRepository $repository,
        private readonly RumDataRepository $rumRepository,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Erstellt neues OKR Set für ein Quartal
     */
    public function createQuarterOkrs(string $quarter, array $objectives): array
    {
        $okrSet = [
            'id' => $this->generateId(),
            'quarter' => $quarter,
            'created_at' => (new \DateTimeImmutable())->format('c'),
            'status' => 'active',
            'objectives' => [],
        ];

        foreach ($objectives as $objective) {
            $okrSet['objectives'][] = $this->createObjective($objective);
        }

        $this->repository->save($okrSet);

        $this->logger->info('OKR set created', [
            'quarter' => $quarter,
            'objectives_count' => count($objectives),
        ]);

        return $okrSet;
    }

    /**
     * Erstellt einzelnes Objective mit Key Results
     */
    private function createObjective(array $data): array
    {
        return [
            'id' => $this->generateId('OBJ'),
            'title' => $data['title'],
            'description' => $data['description'] ?? '',
            'owner' => $data['owner'] ?? 'Unassigned',
            'key_results' => array_map(fn($kr) => [
                'id' => $this->generateId('KR'),
                'description' => $kr['description'],
                'metric' => $kr['metric'],
                'baseline' => $kr['baseline'],
                'target' => $kr['target'],
                'current' => $kr['baseline'],  // Startet bei Baseline
                'score' => 0.0,
                'weight' => $kr['weight'] ?? 1.0,
                'auto_track' => $kr['auto_track'] ?? false,
                'data_source' => $kr['data_source'] ?? null,
            ], $data['key_results']),
            'score' => 0.0,
            'status' => 'not_started',
            'updates' => [],
        ];
    }

    /**
     * Aktualisiert Key Result mit neuem Wert
     */
    public function updateKeyResult(
        string $okrSetId,
        string $krId,
        float $currentValue,
        string $note = ''
    ): array {
        $okrSet = $this->repository->findById($okrSetId);

        foreach ($okrSet['objectives'] as &$objective) {
            foreach ($objective['key_results'] as &$kr) {
                if ($kr['id'] === $krId) {
                    $kr['current'] = $currentValue;
                    $kr['score'] = $this->calculateKrScore($kr);

                    // Update Log
                    $objective['updates'][] = [
                        'kr_id' => $krId,
                        'value' => $currentValue,
                        'score' => $kr['score'],
                        'note' => $note,
                        'timestamp' => (new \DateTimeImmutable())->format('c'),
                    ];

                    break 2;
                }
            }
        }

        // Objective-Scores neu berechnen
        $okrSet = $this->recalculateScores($okrSet);
        $this->repository->save($okrSet);

        return $okrSet;
    }

    /**
     * Berechnet Score für einzelnes Key Result
     */
    private function calculateKrScore(array $kr): float
    {
        $baseline = $kr['baseline'];
        $target = $kr['target'];
        $current = $kr['current'];

        // Unterscheiden ob höher oder niedriger besser ist
        $higherIsBetter = $target > $baseline;

        if ($higherIsBetter) {
            // z.B. Conversion Rate: Baseline 2.5%, Target 3.5%, Current 3.0%
            $progress = ($current - $baseline) / ($target - $baseline);
        } else {
            // z.B. LCP: Baseline 3000ms, Target 2500ms, Current 2700ms
            $progress = ($baseline - $current) / ($baseline - $target);
        }

        return min(max($progress, 0.0), 1.0);
    }

    /**
     * Berechnet alle Scores neu
     */
    private function recalculateScores(array $okrSet): array
    {
        foreach ($okrSet['objectives'] as &$objective) {
            $totalWeight = array_sum(array_column($objective['key_results'], 'weight'));
            $weightedScore = 0;

            foreach ($objective['key_results'] as $kr) {
                $weightedScore += $kr['score'] * $kr['weight'];
            }

            $objective['score'] = $totalWeight > 0
                ? round($weightedScore / $totalWeight, 2)
                : 0;

            $objective['status'] = $this->determineStatus($objective['score']);
        }

        return $okrSet;
    }

    /**
     * Bestimmt Status basierend auf Score
     */
    private function determineStatus(float $score): string
    {
        foreach (self::SCORE_RANGES as $status => $range) {
            if ($score >= $range['min'] && $score < $range['max']) {
                return $status;
            }
        }
        return 'exceptional'; // 1.0
    }

    /**
     * Automatisches Tracking aus RUM-Daten
     */
    public function autoTrackFromRum(string $okrSetId): array
    {
        $okrSet = $this->repository->findById($okrSetId);
        $updated = [];

        foreach ($okrSet['objectives'] as &$objective) {
            foreach ($objective['key_results'] as &$kr) {
                if ($kr['auto_track'] && $kr['data_source']) {
                    $value = $this->fetchFromRum($kr['data_source']);

                    if ($value !== null) {
                        $kr['current'] = $value;
                        $kr['score'] = $this->calculateKrScore($kr);
                        $updated[] = $kr['id'];
                    }
                }
            }
        }

        if (!empty($updated)) {
            $okrSet = $this->recalculateScores($okrSet);
            $this->repository->save($okrSet);

            $this->logger->info('Auto-tracked KRs from RUM', [
                'okr_set' => $okrSetId,
                'updated_count' => count($updated),
            ]);
        }

        return ['updated' => $updated];
    }

    /**
     * Holt Wert aus RUM-Daten
     */
    private function fetchFromRum(string $dataSource): ?float
    {
        // Format: "metric:lcp_p75" oder "good_rate:homepage"
        [$type, $identifier] = explode(':', $dataSource, 2);

        return match ($type) {
            'metric' => $this->rumRepository->getCurrentMetric($identifier),
            'good_rate' => $this->rumRepository->getPageGoodRate($identifier),
            'conversion' => $this->rumRepository->getConversionRate(),
            default => null,
        };
    }

    /**
     * Gibt Quartals-Progress zurück
     */
    public function getQuarterProgress(string $quarter): array
    {
        $okrSet = $this->repository->findByQuarter($quarter);

        if (!$okrSet) {
            return ['error' => 'OKR set not found for quarter'];
        }

        $overallScore = 0;
        $objectiveCount = count($okrSet['objectives']);

        foreach ($okrSet['objectives'] as $obj) {
            $overallScore += $obj['score'];
        }

        $avgScore = $objectiveCount > 0 ? $overallScore / $objectiveCount : 0;

        return [
            'quarter' => $quarter,
            'overall_score' => round($avgScore, 2),
            'status' => $this->determineStatus($avgScore),
            'objectives_summary' => array_map(fn($obj) => [
                'title' => $obj['title'],
                'score' => $obj['score'],
                'status' => $obj['status'],
                'key_results_count' => count($obj['key_results']),
            ], $okrSet['objectives']),
            'days_remaining' => $this->calculateDaysRemaining($quarter),
            'velocity_needed' => $this->calculateVelocityNeeded($okrSet),
        ];
    }

    /**
     * Berechnet verbleibende Tage im Quartal
     */
    private function calculateDaysRemaining(string $quarter): int
    {
        [$q, $year] = sscanf($quarter, 'Q%d-%d');

        $endMonth = $q * 3;
        $endDate = new \DateTimeImmutable("$year-$endMonth-01");
        $endDate = $endDate->modify('last day of this month');

        $now = new \DateTimeImmutable();
        $diff = $now->diff($endDate);

        return max($diff->days, 0);
    }

    /**
     * Berechnet benötigte Velocity zum Erreichen der Ziele
     */
    private function calculateVelocityNeeded(array $okrSet): array
    {
        $daysRemaining = $this->calculateDaysRemaining($okrSet['quarter']);
        $velocities = [];

        foreach ($okrSet['objectives'] as $obj) {
            $remainingProgress = 0.7 - $obj['score'];  // 70% = Erfolg

            if ($remainingProgress > 0 && $daysRemaining > 0) {
                $dailyNeeded = $remainingProgress / $daysRemaining;
                $velocities[] = [
                    'objective' => $obj['title'],
                    'current_score' => $obj['score'],
                    'needed_for_success' => 0.7,
                    'daily_progress_needed' => round($dailyNeeded * 100, 2) . '%',
                    'achievable' => $dailyNeeded < 0.02,  // < 2%/Tag ist machbar
                ];
            }
        }

        return $velocities;
    }

    /**
     * Generiert Weekly Check-In Report
     */
    public function generateWeeklyCheckin(string $quarter): array
    {
        $progress = $this->getQuarterProgress($quarter);
        $okrSet = $this->repository->findByQuarter($quarter);

        $blockers = [];
        $wins = [];

        foreach ($okrSet['objectives'] as $obj) {
            foreach ($obj['key_results'] as $kr) {
                if ($kr['score'] < 0.3) {
                    $blockers[] = [
                        'kr' => $kr['description'],
                        'current' => $kr['current'],
                        'target' => $kr['target'],
                    ];
                }
                if ($kr['score'] >= 0.8) {
                    $wins[] = $kr['description'];
                }
            }
        }

        return [
            'week' => (new \DateTimeImmutable())->format('W'),
            'quarter' => $quarter,
            'overall_score' => $progress['overall_score'],
            'status' => $progress['status'],
            'days_remaining' => $progress['days_remaining'],
            'blockers' => $blockers,
            'wins' => $wins,
            'focus_for_next_week' => $this->suggestFocus($blockers),
        ];
    }

    /**
     * Schlägt Fokus für nächste Woche vor
     */
    private function suggestFocus(array $blockers): array
    {
        if (empty($blockers)) {
            return ['Continue current momentum'];
        }

        return array_slice(array_map(fn($b) => $b['kr'], $blockers), 0, 3);
    }

    /**
     * Schliesst Quartal ab und archiviert
     */
    public function closeQuarter(string $quarter, array $reflections = []): array
    {
        $okrSet = $this->repository->findByQuarter($quarter);
        $progress = $this->getQuarterProgress($quarter);

        $okrSet['status'] = 'closed';
        $okrSet['closed_at'] = (new \DateTimeImmutable())->format('c');
        $okrSet['final_score'] = $progress['overall_score'];
        $okrSet['reflections'] = $reflections;

        $this->repository->save($okrSet);

        $this->logger->info('Quarter closed', [
            'quarter' => $quarter,
            'final_score' => $progress['overall_score'],
        ]);

        return [
            'quarter' => $quarter,
            'final_score' => $progress['overall_score'],
            'objectives_achieved' => count(array_filter(
                $okrSet['objectives'],
                fn($o) => $o['score'] >= 0.7
            )),
            'total_objectives' => count($okrSet['objectives']),
        ];
    }

    private function generateId(string $prefix = 'OKR'): string
    {
        return $prefix . '-' . strtoupper(bin2hex(random_bytes(4)));
    }
}
