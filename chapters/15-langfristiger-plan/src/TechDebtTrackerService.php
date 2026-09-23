<?php

declare(strict_types=1);

namespace App\Service;

/**
 * Trackt Performance-bezogene technische Schulden
 *
 * Skala wie in Kapitel 15: Der Score ist die Summe der Severity-Punkte aller
 * offenen Items (critical 100, high 40, medium 10, low 2), ohne Obergrenze.
 * Richtwert: < 200 gesund, 200-499 Aufmerksamkeit, ab 500 kritisch.
 * Punkte und Grenzen sind Vorgaben dieses Kapitels, keine Branchenwerte.
 *
 * Die Items liefert ein TechDebtRepository, das Sie an Ihren Tracker anbinden
 * (Jira, GitHub Issues, eine Tabelle). Siehe tests/Unit/TechDebtTrackerServiceTest.php.
 */
class TechDebtTrackerService
{
    // Punkte-System für Priorisierung
    private const SEVERITY_POINTS = [
        'critical' => 100,
        'high' => 40,
        'medium' => 10,
        'low' => 2,
    ];

    private const EFFORT_POINTS = [
        'trivial' => 1,    // < 2 Stunden
        'small' => 2,      // < 1 Tag
        'medium' => 5,     // 1-5 Tage
        'large' => 13,     // 1-2 Wochen
        'xlarge' => 21,    // > 2 Wochen
    ];

    public function __construct(
        private readonly TechDebtRepository $repository
    ) {
    }

    /**
     * @param array{severity: string, effort: string} $item
     */
    public function calculatePriority(array $item): float
    {
        $severity = self::SEVERITY_POINTS[$item['severity']] ?? 10;
        $effort = self::EFFORT_POINTS[$item['effort']] ?? 5;

        // WSJF-ähnliche Priorisierung: Wert / Aufwand. Critical-Items
        // (SLA < 1 Sprint) vor dieser Rangliste einplanen
        return $severity / $effort;
    }

    /**
     * @return array{total_score: int, status: string, by_category: array<string, int>, item_count: int, top_priorities: list<array<string, mixed>>}
     */
    public function getTechDebtScore(): array
    {
        $items = $this->repository->findAllPerformanceDebt();

        $totalPoints = 0;
        $byCategory = [];

        foreach ($items as $item) {
            $points = self::SEVERITY_POINTS[$item['severity']] ?? 10;
            $totalPoints += $points;

            $category = $item['category'] ?? 'other';
            $byCategory[$category] = ($byCategory[$category] ?? 0) + $points;
        }

        // Score: Je höher, desto mehr Schulden
        // Richtwert: < 200 = gesund, 200-499 = Aufmerksamkeit, ab 500 = kritisch
        return [
            'total_score' => $totalPoints,
            'status' => $this->getStatus($totalPoints),
            'by_category' => $byCategory,
            'item_count' => count($items),
            'top_priorities' => $this->getTopPriorities($items, 5),
        ];
    }

    private function getStatus(int $score): string
    {
        return match (true) {
            $score < 200 => 'healthy',
            $score < 500 => 'attention',
            default => 'critical',
        };
    }

    /**
     * @param list<array<string, mixed>> $items
     *
     * @return list<array<string, mixed>>
     */
    private function getTopPriorities(array $items, int $limit): array
    {
        usort($items, fn($a, $b) =>
            $this->calculatePriority($b) <=> $this->calculatePriority($a)
        );

        return array_slice($items, 0, $limit);
    }
}
