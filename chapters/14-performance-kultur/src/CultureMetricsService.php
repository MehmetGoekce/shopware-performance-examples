<?php

declare(strict_types=1);

namespace App\Service;

/**
 * Performance Culture Metrics Service
 *
 * Sammelt und berechnet Metriken zur Performance-Kultur im Team.
 * Hilft Champions und Leads, den Kulturstatus zu tracken.
 */
class CultureMetricsService
{
    public function __construct(
        private readonly GitHubApiService $gitHub,
        private readonly IncidentTrackerService $incidentTracker,
        private readonly SurveyService $surveyService,
        private readonly PerformanceBudgetService $budgetService
    ) {}

    /**
     * Berechnet den Performance Culture Score
     *
     * @return array{
     *     overall_score: float,
     *     components: array,
     *     trend: string,
     *     recommendations: array
     * }
     */
    public function calculateCultureScore(): array
    {
        $components = [
            'code_review' => $this->getCodeReviewMetrics(),
            'budget_compliance' => $this->getBudgetComplianceScore(),
            'incident_response' => $this->getIncidentResponseScore(),
            'developer_satisfaction' => $this->getDeveloperSatisfactionScore(),
            'knowledge_sharing' => $this->getKnowledgeSharingScore(),
        ];

        // Gewichteter Durchschnitt
        $weights = [
            'code_review' => 0.25,
            'budget_compliance' => 0.25,
            'incident_response' => 0.20,
            'developer_satisfaction' => 0.15,
            'knowledge_sharing' => 0.15,
        ];

        $overallScore = 0;
        foreach ($components as $key => $component) {
            $overallScore += $component['score'] * $weights[$key];
        }

        return [
            'overall_score' => round($overallScore, 1),
            'components' => $components,
            'trend' => $this->calculateTrend($overallScore),
            'recommendations' => $this->generateRecommendations($components),
            'calculated_at' => (new \DateTimeImmutable())->format('c'),
        ];
    }

    /**
     * Code Review Metriken
     */
    private function getCodeReviewMetrics(): array
    {
        $days = 30;

        // PRs mit Performance-Review Label/Kommentar
        $totalPRs = $this->gitHub->getPRCount($days);
        $perfReviewedPRs = $this->gitHub->getPRsWithLabel('performance-reviewed', $days);
        $perfCommentPRs = $this->gitHub->getPRsWithPerformanceComments($days);

        $reviewedCount = max($perfReviewedPRs, $perfCommentPRs);
        $reviewRate = $totalPRs > 0 ? ($reviewedCount / $totalPRs) * 100 : 0;

        // Score: 100% reviewed = 100 Punkte
        $score = min($reviewRate, 100);

        return [
            'score' => round($score, 1),
            'metrics' => [
                'total_prs' => $totalPRs,
                'performance_reviewed' => $reviewedCount,
                'review_rate_percent' => round($reviewRate, 1),
            ],
            'target' => 'Ziel: 80%+ PRs mit Performance-Review',
        ];
    }

    /**
     * Budget Compliance Score
     */
    private function getBudgetComplianceScore(): array
    {
        $budget = $this->budgetService->calculateRemainingBudget();

        // Score basiert auf verbleibendem Budget
        $score = match ($budget['policy']) {
            'green' => 100,
            'yellow' => 60,
            'orange' => 30,
            'red' => 0,
            default => 50,
        };

        return [
            'score' => $score,
            'metrics' => [
                'remaining_budget' => $budget['remaining_percent'],
                'policy' => $budget['policy'],
                'violations' => $budget['violations'],
            ],
            'target' => 'Ziel: Budget > 50%',
        ];
    }

    /**
     * Incident Response Score
     */
    private function getIncidentResponseScore(): array
    {
        $incidents = $this->incidentTracker->getPerformanceIncidents(days: 90);

        if (empty($incidents)) {
            return [
                'score' => 100,
                'metrics' => [
                    'incident_count' => 0,
                    'mttr_hours' => 0,
                    'postmortems_completed' => 0,
                ],
                'target' => 'Keine Incidents in den letzten 90 Tagen',
            ];
        }

        // MTTR (Mean Time to Recovery)
        $totalRecoveryHours = array_sum(array_column($incidents, 'recovery_time_hours'));
        $mttr = $totalRecoveryHours / count($incidents);

        // Postmortem Completion Rate
        $withPostmortem = count(array_filter($incidents, fn($i) => $i['postmortem_completed']));
        $postmortemRate = ($withPostmortem / count($incidents)) * 100;

        // Score: MTTR < 2h = 100, < 4h = 75, < 8h = 50, sonst 25
        // Plus Bonus für Postmortems
        $mttrScore = match (true) {
            $mttr <= 2 => 100,
            $mttr <= 4 => 75,
            $mttr <= 8 => 50,
            default => 25,
        };

        $postmortemBonus = $postmortemRate >= 80 ? 10 : 0;
        $score = min($mttrScore + $postmortemBonus, 100);

        return [
            'score' => round($score, 1),
            'metrics' => [
                'incident_count' => count($incidents),
                'mttr_hours' => round($mttr, 1),
                'postmortems_completed' => $withPostmortem,
                'postmortem_rate' => round($postmortemRate, 1),
            ],
            'target' => 'Ziel: MTTR < 2h, 100% Postmortems',
        ];
    }

    /**
     * Developer Satisfaction Score (aus Survey)
     */
    private function getDeveloperSatisfactionScore(): array
    {
        $latestSurvey = $this->surveyService->getLatestPerformanceSurvey();

        if ($latestSurvey === null) {
            return [
                'score' => 50,  // Neutral wenn keine Daten
                'metrics' => [
                    'message' => 'Kein Survey-Daten verfügbar',
                    'recommendation' => 'Quarterly Developer Survey durchführen',
                ],
                'target' => 'Nächster Survey planen',
            ];
        }

        // Survey-Score auf 0-100 normalisieren (angenommen 1-5 Skala)
        $avgScore = $latestSurvey['average_score'];
        $normalizedScore = (($avgScore - 1) / 4) * 100;

        return [
            'score' => round($normalizedScore, 1),
            'metrics' => [
                'survey_date' => $latestSurvey['date'],
                'response_rate' => $latestSurvey['response_rate'],
                'average_score' => round($avgScore, 2),
                'key_feedback' => $latestSurvey['top_concerns'] ?? [],
            ],
            'target' => 'Ziel: Durchschnitt > 4.0 (von 5)',
        ];
    }

    /**
     * Knowledge Sharing Score
     */
    private function getKnowledgeSharingScore(): array
    {
        $days = 90;

        // Metriken sammeln
        $brownBags = $this->getEventCount('brown_bag', $days);
        $wikiUpdates = $this->getWikiUpdateCount($days);
        $slackActivity = $this->getSlackChannelActivity($days);

        // Erwartete Werte pro Quartal
        $expectedBrownBags = 6;  // ~2 pro Monat
        $expectedWikiUpdates = 12;  // ~1 pro Woche
        $expectedSlackMessages = 100;

        // Score berechnen
        $brownBagScore = min(($brownBags / $expectedBrownBags) * 100, 100);
        $wikiScore = min(($wikiUpdates / $expectedWikiUpdates) * 100, 100);
        $slackScore = min(($slackActivity / $expectedSlackMessages) * 100, 100);

        $score = ($brownBagScore + $wikiScore + $slackScore) / 3;

        return [
            'score' => round($score, 1),
            'metrics' => [
                'brown_bags' => $brownBags,
                'wiki_updates' => $wikiUpdates,
                'slack_messages' => $slackActivity,
            ],
            'target' => 'Ziel: Aktives Knowledge Sharing',
        ];
    }

    /**
     * Trend berechnen
     */
    private function calculateTrend(float $currentScore): string
    {
        // Vorherigen Score laden (vereinfacht - in Realität aus DB)
        $previousScore = $this->getPreviousScore();

        if ($previousScore === null) {
            return 'unknown';
        }

        $diff = $currentScore - $previousScore;

        return match (true) {
            $diff > 5 => 'improving',
            $diff < -5 => 'declining',
            default => 'stable',
        };
    }

    /**
     * Empfehlungen generieren
     */
    private function generateRecommendations(array $components): array
    {
        $recommendations = [];

        foreach ($components as $key => $component) {
            if ($component['score'] < 60) {
                $recommendations[] = match ($key) {
                    'code_review' => 'Code Review Rate verbessern: Performance-Checklist in PR-Template integrieren',
                    'budget_compliance' => 'Error Budget kritisch: Performance-Sprint planen',
                    'incident_response' => 'MTTR verbessern: Runbooks und Alerting überprüfen',
                    'developer_satisfaction' => 'Developer Survey durchführen und Feedback adressieren',
                    'knowledge_sharing' => 'Mehr Brown Bags und Wiki-Dokumentation planen',
                    default => 'Bereich verbessern: ' . $key,
                };
            }
        }

        if (empty($recommendations)) {
            $recommendations[] = 'Kultur ist gesund. Weiter so!';
        }

        return $recommendations;
    }

    // Hilfsmethoden (Stubs - in Realität implementieren)

    private function getEventCount(string $type, int $days): int
    {
        // Aus Kalender/Event-System laden
        return 0;
    }

    private function getWikiUpdateCount(int $days): int
    {
        // Aus Confluence/Notion API
        return 0;
    }

    private function getSlackChannelActivity(int $days): int
    {
        // Aus Slack API
        return 0;
    }

    private function getPreviousScore(): ?float
    {
        // Aus Datenbank laden
        return null;
    }
}
