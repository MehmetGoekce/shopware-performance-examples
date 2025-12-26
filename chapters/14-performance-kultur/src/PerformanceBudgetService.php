<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;

/**
 * Performance Budget Tracker
 *
 * Berechnet und trackt das Performance Error Budget basierend auf RUM-Daten.
 * Integriert mit Kapitel 12 (RUM) und Kapitel 13 (CI).
 *
 * @see https://sre.google/workbook/error-budget-policy/
 */
class PerformanceBudgetService
{
    // SLO-Schwellenwerte (p75)
    private const SLO_LCP_P75 = 2500;  // ms
    private const SLO_CLS_P75 = 0.1;
    private const SLO_INP_P75 = 200;   // ms

    // Budget-Periode
    private const BUDGET_PERIOD_DAYS = 30;

    // Erlaubte Fehlerrate (0.1% = 99.9% SLO)
    private const ALLOWED_ERROR_RATE = 0.001;

    public function __construct(
        private readonly RumDataRepository $rumRepository,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Berechnet das verbleibende Error Budget
     *
     * @return array{
     *     remaining_percent: float,
     *     used_percent: float,
     *     policy: string,
     *     violations: array,
     *     total_samples: int,
     *     period_start: string,
     *     period_end: string,
     *     details: array
     * }
     */
    public function calculateRemainingBudget(): array
    {
        $startDate = new \DateTimeImmutable('-' . self::BUDGET_PERIOD_DAYS . ' days');
        $endDate = new \DateTimeImmutable();

        $metrics = $this->rumRepository->getMetricsSince($startDate);

        if ($metrics['total_samples'] === 0) {
            return $this->emptyBudgetResult($startDate, $endDate);
        }

        // Violations zählen
        $violations = [
            'lcp' => $this->countViolations($metrics['lcp'] ?? [], self::SLO_LCP_P75),
            'cls' => $this->countViolations($metrics['cls'] ?? [], self::SLO_CLS_P75),
            'inp' => $this->countViolations($metrics['inp'] ?? [], self::SLO_INP_P75),
        ];

        $totalViolations = array_sum($violations);
        $totalSamples = $metrics['total_samples'];

        // Actual Error Rate
        $actualErrorRate = $totalSamples > 0
            ? $totalViolations / $totalSamples
            : 0;

        // Budget Consumption: actual / allowed
        $budgetConsumption = self::ALLOWED_ERROR_RATE > 0
            ? min($actualErrorRate / self::ALLOWED_ERROR_RATE, 1)
            : 0;

        $usedPercent = $budgetConsumption * 100;
        $remainingPercent = max(100 - $usedPercent, 0);

        $policy = $this->determinePolicy($remainingPercent);

        $this->logBudgetStatus($remainingPercent, $policy, $violations);

        return [
            'remaining_percent' => round($remainingPercent, 1),
            'used_percent' => round($usedPercent, 1),
            'policy' => $policy,
            'violations' => $violations,
            'total_samples' => $totalSamples,
            'period_start' => $startDate->format('Y-m-d'),
            'period_end' => $endDate->format('Y-m-d'),
            'details' => [
                'actual_error_rate' => round($actualErrorRate * 100, 4),
                'allowed_error_rate' => self::ALLOWED_ERROR_RATE * 100,
                'slos' => [
                    'lcp_p75' => self::SLO_LCP_P75,
                    'cls_p75' => self::SLO_CLS_P75,
                    'inp_p75' => self::SLO_INP_P75,
                ],
            ],
        ];
    }

    /**
     * Bestimmt die Policy basierend auf verbleibendem Budget
     */
    private function determinePolicy(float $remaining): string
    {
        return match (true) {
            $remaining > 50 => 'green',      // Normal development
            $remaining > 20 => 'yellow',     // Cautious releases
            $remaining > 0 => 'orange',      // Performance focus
            default => 'red',                // Feature freeze
        };
    }

    /**
     * Gibt Policy-Beschreibung zurück
     */
    public function getPolicyDescription(string $policy): array
    {
        return match ($policy) {
            'green' => [
                'title' => 'Normal Development',
                'description' => 'Budget gesund. Normale Feature-Entwicklung möglich.',
                'actions' => [
                    'Normale Release-Kadenz',
                    'Experimente erlaubt',
                    'Standard Review-Prozess',
                ],
            ],
            'yellow' => [
                'title' => 'Vorsicht',
                'description' => 'Budget unter 50%. Erhöhte Aufmerksamkeit erforderlich.',
                'actions' => [
                    'Performance-Review für neue Features',
                    'Keine großen Refactorings',
                    'Täglicher Dashboard-Review',
                ],
            ],
            'orange' => [
                'title' => 'Performance-Fokus',
                'description' => 'Budget kritisch. Priorität auf Stabilität.',
                'actions' => [
                    '50% Kapazität für Performance',
                    'Nur kritische Features',
                    'Extended Reviews erforderlich',
                ],
            ],
            'red' => [
                'title' => 'Feature Freeze',
                'description' => 'Budget aufgebraucht. Nur Fixes erlaubt.',
                'actions' => [
                    'Keine neuen Features',
                    'Nur P0/Security Fixes',
                    'War Room Setup',
                ],
            ],
            default => [
                'title' => 'Unknown',
                'description' => 'Policy nicht definiert',
                'actions' => [],
            ],
        };
    }

    /**
     * Zählt Violations über Schwellenwert
     */
    private function countViolations(array $values, float $threshold): int
    {
        return count(array_filter($values, fn($v) => $v > $threshold));
    }

    /**
     * Leeres Budget-Ergebnis wenn keine Daten
     */
    private function emptyBudgetResult(
        \DateTimeImmutable $start,
        \DateTimeImmutable $end
    ): array {
        return [
            'remaining_percent' => 100.0,
            'used_percent' => 0.0,
            'policy' => 'green',
            'violations' => ['lcp' => 0, 'cls' => 0, 'inp' => 0],
            'total_samples' => 0,
            'period_start' => $start->format('Y-m-d'),
            'period_end' => $end->format('Y-m-d'),
            'details' => [
                'message' => 'No RUM data available',
            ],
        ];
    }

    /**
     * Loggt Budget-Status
     */
    private function logBudgetStatus(
        float $remaining,
        string $policy,
        array $violations
    ): void {
        $context = [
            'remaining_percent' => $remaining,
            'policy' => $policy,
            'violations' => $violations,
        ];

        if ($policy === 'red') {
            $this->logger->critical('Performance budget exhausted!', $context);
        } elseif ($policy === 'orange') {
            $this->logger->warning('Performance budget critical', $context);
        } elseif ($policy === 'yellow') {
            $this->logger->notice('Performance budget below 50%', $context);
        } else {
            $this->logger->info('Performance budget healthy', $context);
        }
    }

    /**
     * Gibt Trend im Vergleich zum Vormonat zurück
     */
    public function getBudgetTrend(): string
    {
        $current = $this->calculateRemainingBudget();

        // Vormonat berechnen (vereinfacht)
        $previousStart = new \DateTimeImmutable('-60 days');
        $previousEnd = new \DateTimeImmutable('-30 days');
        $previousMetrics = $this->rumRepository->getMetricsBetween($previousStart, $previousEnd);

        if ($previousMetrics['total_samples'] === 0) {
            return 'unknown';
        }

        $previousViolations = [
            'lcp' => $this->countViolations($previousMetrics['lcp'] ?? [], self::SLO_LCP_P75),
            'cls' => $this->countViolations($previousMetrics['cls'] ?? [], self::SLO_CLS_P75),
            'inp' => $this->countViolations($previousMetrics['inp'] ?? [], self::SLO_INP_P75),
        ];

        $previousRate = array_sum($previousViolations) / $previousMetrics['total_samples'];
        $currentRate = array_sum($current['violations']) / max($current['total_samples'], 1);

        $diff = $currentRate - $previousRate;

        return match (true) {
            $diff < -0.001 => 'improving',  // Weniger Violations
            $diff > 0.001 => 'declining',   // Mehr Violations
            default => 'stable',
        };
    }
}
