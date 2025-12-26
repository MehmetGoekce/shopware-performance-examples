<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;

/**
 * Technical Debt Tracker für Performance-relevante Tech Debt
 *
 * Trackt, priorisiert und reportet Performance-bezogene Technical Debt.
 * Implementiert die "25% Regel" (Shopify-Ansatz).
 *
 * @see https://shopify.engineering/technical-debt-25-percent-rule
 */
class TechDebtTrackerService
{
    // Priorisierungs-Faktoren
    private const PRIORITY_WEIGHTS = [
        'business_impact' => 0.35,    // Impact auf Business-Metriken
        'effort' => 0.25,             // Aufwand (invertiert)
        'frequency' => 0.20,          // Wie oft betrifft es User
        'growth_risk' => 0.20,        // Wird schlimmer wenn ignoriert?
    ];

    // Empfohlene Kapazität für Tech Debt (25% Rule)
    private const RECOMMENDED_CAPACITY_PERCENT = 25;

    public function __construct(
        private readonly TechDebtRepository $repository,
        private readonly JiraApiService $jira,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Fügt neues Tech Debt Item hinzu
     *
     * @param array{
     *     title: string,
     *     description: string,
     *     category: string,
     *     affected_pages: array,
     *     estimated_hours: int,
     *     business_impact_score: int,
     *     frequency_score: int,
     *     growth_risk_score: int,
     *     created_by: string
     * } $item
     */
    public function addTechDebtItem(array $item): array
    {
        // Validierung
        $this->validateItem($item);

        // Priority Score berechnen
        $priorityScore = $this->calculatePriorityScore($item);

        $techDebtItem = [
            'id' => $this->generateId(),
            'title' => $item['title'],
            'description' => $item['description'],
            'category' => $item['category'],
            'affected_pages' => $item['affected_pages'],
            'estimated_hours' => $item['estimated_hours'],
            'scores' => [
                'business_impact' => $item['business_impact_score'],
                'effort' => $this->invertEffortScore($item['estimated_hours']),
                'frequency' => $item['frequency_score'],
                'growth_risk' => $item['growth_risk_score'],
            ],
            'priority_score' => $priorityScore,
            'status' => 'backlog',
            'created_at' => (new \DateTimeImmutable())->format('c'),
            'created_by' => $item['created_by'],
            'resolved_at' => null,
        ];

        $this->repository->save($techDebtItem);

        $this->logger->info('Tech debt item added', [
            'id' => $techDebtItem['id'],
            'title' => $techDebtItem['title'],
            'priority_score' => $priorityScore,
        ]);

        return $techDebtItem;
    }

    /**
     * Berechnet Priority Score basierend auf gewichteten Faktoren
     */
    private function calculatePriorityScore(array $item): float
    {
        $effortScore = $this->invertEffortScore($item['estimated_hours']);

        $weightedScore =
            ($item['business_impact_score'] * self::PRIORITY_WEIGHTS['business_impact']) +
            ($effortScore * self::PRIORITY_WEIGHTS['effort']) +
            ($item['frequency_score'] * self::PRIORITY_WEIGHTS['frequency']) +
            ($item['growth_risk_score'] * self::PRIORITY_WEIGHTS['growth_risk']);

        return round($weightedScore, 2);
    }

    /**
     * Invertiert Effort Score (weniger Aufwand = höhere Priorität)
     * 1-8h = 100, 8-24h = 75, 24-80h = 50, >80h = 25
     */
    private function invertEffortScore(int $hours): int
    {
        return match (true) {
            $hours <= 8 => 100,
            $hours <= 24 => 75,
            $hours <= 80 => 50,
            default => 25,
        };
    }

    /**
     * Gibt priorisierte Tech Debt Liste zurück
     */
    public function getPrioritizedBacklog(int $limit = 20): array
    {
        $items = $this->repository->findByStatus('backlog');

        usort($items, fn($a, $b) => $b['priority_score'] <=> $a['priority_score']);

        return array_slice($items, 0, $limit);
    }

    /**
     * Gibt Empfehlung für Sprint-Planung
     * Basierend auf 25% Kapazitäts-Regel
     */
    public function getSprintRecommendation(int $sprintCapacityHours): array
    {
        $techDebtBudget = (int)($sprintCapacityHours * (self::RECOMMENDED_CAPACITY_PERCENT / 100));

        $prioritizedItems = $this->getPrioritizedBacklog(50);
        $recommendedItems = [];
        $totalHours = 0;

        foreach ($prioritizedItems as $item) {
            if ($totalHours + $item['estimated_hours'] <= $techDebtBudget) {
                $recommendedItems[] = $item;
                $totalHours += $item['estimated_hours'];
            }
        }

        return [
            'sprint_capacity' => $sprintCapacityHours,
            'tech_debt_budget' => $techDebtBudget,
            'recommended_items' => $recommendedItems,
            'total_hours' => $totalHours,
            'remaining_budget' => $techDebtBudget - $totalHours,
            'items_count' => count($recommendedItems),
        ];
    }

    /**
     * Gibt Tech Debt Statistiken zurück
     */
    public function getStatistics(): array
    {
        $allItems = $this->repository->findAll();

        $byStatus = [
            'backlog' => 0,
            'in_progress' => 0,
            'resolved' => 0,
        ];

        $byCategory = [];
        $totalHoursBacklog = 0;
        $resolvedThisQuarter = 0;

        $quarterStart = new \DateTimeImmutable('first day of -2 months');

        foreach ($allItems as $item) {
            $byStatus[$item['status']]++;

            if (!isset($byCategory[$item['category']])) {
                $byCategory[$item['category']] = 0;
            }
            $byCategory[$item['category']]++;

            if ($item['status'] === 'backlog') {
                $totalHoursBacklog += $item['estimated_hours'];
            }

            if ($item['status'] === 'resolved' && $item['resolved_at']) {
                $resolvedAt = new \DateTimeImmutable($item['resolved_at']);
                if ($resolvedAt >= $quarterStart) {
                    $resolvedThisQuarter++;
                }
            }
        }

        // Tech Debt Score (0-100, niedriger = besser)
        $techDebtScore = $this->calculateTechDebtScore($allItems);

        return [
            'total_items' => count($allItems),
            'by_status' => $byStatus,
            'by_category' => $byCategory,
            'total_hours_backlog' => $totalHoursBacklog,
            'resolved_this_quarter' => $resolvedThisQuarter,
            'tech_debt_score' => $techDebtScore,
            'trend' => $this->calculateTrend(),
            'health' => $this->determineHealth($techDebtScore),
        ];
    }

    /**
     * Berechnet Tech Debt Score
     * Berücksichtigt Menge, Alter und Kritikalität
     */
    private function calculateTechDebtScore(array $items): int
    {
        if (empty($items)) {
            return 0;
        }

        $backlogItems = array_filter($items, fn($i) => $i['status'] === 'backlog');

        if (empty($backlogItems)) {
            return 0;
        }

        // Faktoren
        $countFactor = min(count($backlogItems) / 20, 1) * 40;  // Max 40 Punkte

        // Durchschnittliche Priorität der Backlog-Items
        $avgPriority = array_sum(array_column($backlogItems, 'priority_score')) / count($backlogItems);
        $priorityFactor = ($avgPriority / 100) * 30;  // Max 30 Punkte

        // Ältestes Item (Tage seit Erstellung)
        $oldestDate = min(array_column($backlogItems, 'created_at'));
        $daysSinceOldest = (new \DateTimeImmutable())->diff(new \DateTimeImmutable($oldestDate))->days;
        $ageFactor = min($daysSinceOldest / 180, 1) * 30;  // Max 30 Punkte für 6+ Monate

        return (int)round($countFactor + $priorityFactor + $ageFactor);
    }

    /**
     * Bestimmt Gesundheitsstatus basierend auf Score
     */
    private function determineHealth(int $score): string
    {
        return match (true) {
            $score <= 25 => 'healthy',
            $score <= 50 => 'manageable',
            $score <= 75 => 'concerning',
            default => 'critical',
        };
    }

    /**
     * Berechnet Trend im Vergleich zum Vorquartal
     */
    private function calculateTrend(): string
    {
        // Vereinfacht - in Realität historische Daten vergleichen
        $currentScore = $this->calculateTechDebtScore($this->repository->findAll());
        $previousScore = $this->repository->getPreviousQuarterScore();

        if ($previousScore === null) {
            return 'unknown';
        }

        $diff = $currentScore - $previousScore;

        return match (true) {
            $diff < -5 => 'improving',
            $diff > 5 => 'worsening',
            default => 'stable',
        };
    }

    /**
     * Generiert Report für Stakeholder
     */
    public function generateReport(): array
    {
        $stats = $this->getStatistics();
        $topItems = $this->getPrioritizedBacklog(5);

        return [
            'generated_at' => (new \DateTimeImmutable())->format('c'),
            'summary' => [
                'health' => $stats['health'],
                'score' => $stats['tech_debt_score'],
                'trend' => $stats['trend'],
                'total_backlog_hours' => $stats['total_hours_backlog'],
            ],
            'top_priority_items' => array_map(fn($item) => [
                'title' => $item['title'],
                'category' => $item['category'],
                'priority_score' => $item['priority_score'],
                'estimated_hours' => $item['estimated_hours'],
            ], $topItems),
            'by_category' => $stats['by_category'],
            'recommendations' => $this->generateRecommendations($stats),
        ];
    }

    /**
     * Generiert Empfehlungen basierend auf aktuellem Status
     */
    private function generateRecommendations(array $stats): array
    {
        $recommendations = [];

        if ($stats['health'] === 'critical') {
            $recommendations[] = [
                'priority' => 'high',
                'action' => 'Performance-Sprint planen',
                'description' => 'Tech Debt Score kritisch. Dedizierter Sprint empfohlen.',
            ];
        }

        if ($stats['total_hours_backlog'] > 160) {
            $recommendations[] = [
                'priority' => 'medium',
                'action' => '25% Regel implementieren',
                'description' => 'Über 4 Wochen Backlog. Feste Tech-Debt-Zeit einplanen.',
            ];
        }

        if ($stats['trend'] === 'worsening') {
            $recommendations[] = [
                'priority' => 'high',
                'action' => 'Root Cause Analysis',
                'description' => 'Tech Debt wächst. Ursachen identifizieren.',
            ];
        }

        if (empty($recommendations)) {
            $recommendations[] = [
                'priority' => 'low',
                'action' => 'Weiter so',
                'description' => 'Tech Debt unter Kontrolle. Routine beibehalten.',
            ];
        }

        return $recommendations;
    }

    /**
     * Sync mit Jira (optional)
     */
    public function syncWithJira(): array
    {
        $items = $this->getPrioritizedBacklog(10);
        $synced = [];

        foreach ($items as $item) {
            if (empty($item['jira_key'])) {
                $jiraIssue = $this->jira->createIssue([
                    'project' => 'PERF',
                    'summary' => '[Tech Debt] ' . $item['title'],
                    'description' => $item['description'],
                    'labels' => ['tech-debt', 'performance'],
                    'customfield_priority_score' => $item['priority_score'],
                ]);

                $this->repository->updateJiraKey($item['id'], $jiraIssue['key']);
                $synced[] = $jiraIssue['key'];
            }
        }

        return ['synced_count' => count($synced), 'keys' => $synced];
    }

    private function validateItem(array $item): void
    {
        $required = ['title', 'description', 'category', 'estimated_hours'];
        foreach ($required as $field) {
            if (empty($item[$field])) {
                throw new \InvalidArgumentException("Field '$field' is required");
            }
        }

        $validCategories = ['frontend', 'backend', 'database', 'infrastructure', 'third-party'];
        if (!in_array($item['category'], $validCategories, true)) {
            throw new \InvalidArgumentException("Invalid category: {$item['category']}");
        }
    }

    private function generateId(): string
    {
        return 'TD-' . strtoupper(bin2hex(random_bytes(4)));
    }
}
