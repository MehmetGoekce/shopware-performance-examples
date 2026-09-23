<?php

declare(strict_types=1);

namespace PerformanceKultur;

/**
 * Performance Culture Score aus fuenf Komponenten, je 0-100 Punkte.
 *
 * Score = Code Review × 0.25 + Budget × 0.25 + Incidents × 0.20
 *       + Developer Satisfaction × 0.15 + Knowledge Sharing × 0.15
 *
 * Die Rohdaten liefert ein CultureDataSource, das Sie fuer Ihre Werkzeuge
 * schreiben. Das Error Budget kommt aus PerformanceBudgetService::calculate()
 * (RUM-Logs aus Kapitel 12), siehe scripts/error-budget.php.
 *
 * Komponenten ohne Daten zaehlen nicht mit: Der Score ist dann der gewichtete
 * Durchschnitt der bewerteten Komponenten, und "unrated" nennt die fehlenden.
 * Gewichte, Punktestufen und Zielwerte sind Vorgaben dieses Beispiels, keine
 * Branchenwerte. Passen Sie sie an Ihr Team an.
 */
final class CultureMetricsService
{
    public const WEIGHTS = [
        'code_review' => 0.25,
        'budget_compliance' => 0.25,
        'incident_response' => 0.20,
        'developer_satisfaction' => 0.15,
        'knowledge_sharing' => 0.15,
    ];

    /** Punkte je Stufe von PerformanceBudgetService::overall() */
    public const BUDGET_POINTS = [
        'green' => 100,
        'yellow' => 60,
        'orange' => 30,
        'red' => 0,
    ];

    /** Zielwerte je Quartal (90 Tage) fuer Knowledge Sharing */
    public const KNOWLEDGE_TARGETS = [
        'brown_bags' => 3,       // monatlich wie im Buch (knowledge_sharing.sync.brown_bag)
        'wiki_updates' => 12,    // etwa 1 pro Woche
        'slack_messages' => 100,
    ];

    /** Unter diesem Wert schlaegt der Service fuer die Komponente etwas vor */
    public const RECOMMENDATION_BELOW = 60;

    public function __construct(
        private readonly CultureDataSource $source
    ) {
    }

    /**
     * @param array<string, array{policy: string, remaining_percent: float|null}> $budget
     *        Ergebnis von PerformanceBudgetService::calculate()
     * @param float|null $previousScore Score der letzten Berechnung, fuer den Trend
     *
     * @return array{
     *     overall_score: float|null,
     *     components: array<string, array{score: float|null, metrics: array<string, mixed>, target: string}>,
     *     unrated: list<string>,
     *     trend: string,
     *     recommendations: list<string>
     * }
     */
    public function calculateCultureScore(array $budget, ?float $previousScore = null): array
    {
        $components = [
            'code_review' => $this->codeReview(),
            'budget_compliance' => $this->budgetCompliance($budget),
            'incident_response' => $this->incidentResponse(),
            'developer_satisfaction' => $this->developerSatisfaction(),
            'knowledge_sharing' => $this->knowledgeSharing(),
        ];

        $weighted = 0.0;
        $weightSum = 0.0;
        $unrated = [];
        foreach ($components as $key => $component) {
            if ($component['score'] === null) {
                $unrated[] = $key;
                continue;
            }
            $weighted += $component['score'] * self::WEIGHTS[$key];
            $weightSum += self::WEIGHTS[$key];
        }

        $overall = $weightSum > 0 ? round($weighted / $weightSum, 1) : null;

        return [
            'overall_score' => $overall,
            'components' => $components,
            'unrated' => $unrated,
            'trend' => self::trend($overall, $previousScore),
            'recommendations' => self::recommendations($components),
        ];
    }

    /**
     * Anteil der PRs mit Performance-Review, 100 % = 100 Punkte
     *
     * @return array{score: float|null, metrics: array<string, mixed>, target: string}
     */
    private function codeReview(): array
    {
        $counts = $this->source->pullRequestCounts(30);
        $target = 'Ziel: 80 %+ der PRs mit Performance-Review';

        if ($counts === null || $counts['total'] === 0) {
            return ['score' => null, 'metrics' => ['total_prs' => $counts['total'] ?? null], 'target' => $target];
        }

        $rate = min($counts['performance_reviewed'] / $counts['total'] * 100, 100.0);

        return [
            'score' => round($rate, 1),
            'metrics' => [
                'total_prs' => $counts['total'],
                'performance_reviewed' => $counts['performance_reviewed'],
                'review_rate_percent' => round($rate, 1),
            ],
            'target' => $target,
        ];
    }

    /**
     * Punkte aus der schlechtesten bewerteten Core-Web-Vital-Stufe
     *
     * @param array<string, array{policy: string, remaining_percent: float|null}> $budget
     *
     * @return array{score: float|null, metrics: array<string, mixed>, target: string}
     */
    private function budgetCompliance(array $budget): array
    {
        $overall = PerformanceBudgetService::overall($budget);
        $remaining = [];
        foreach ($budget as $metric => $row) {
            $remaining[$metric] = $row['remaining_percent'];
        }

        return [
            'score' => isset(self::BUDGET_POINTS[$overall]) ? (float) self::BUDGET_POINTS[$overall] : null,
            'metrics' => [
                'policy' => $overall,
                'remaining_percent' => $remaining,
                'unrated_metrics' => PerformanceBudgetService::unrated($budget),
            ],
            'target' => 'Ziel: jede Metrik ueber 50 % Budget uebrig (green)',
        ];
    }

    /**
     * MTTR der letzten 90 Tage plus Bonus fuer Postmortems
     *
     * @return array{score: float|null, metrics: array<string, mixed>, target: string}
     */
    private function incidentResponse(): array
    {
        $incidents = $this->source->performanceIncidents(90);
        $target = 'Ziel: MTTR unter 2 h, Postmortem zu jedem Incident';

        if ($incidents === null) {
            return ['score' => null, 'metrics' => [], 'target' => $target];
        }

        if ($incidents === []) {
            return ['score' => 100.0, 'metrics' => ['incident_count' => 0], 'target' => $target];
        }

        $count = \count($incidents);
        $mttr = array_sum(array_column($incidents, 'recovery_time_hours')) / $count;
        $withPostmortem = \count(array_filter($incidents, static fn (array $i): bool => $i['postmortem_completed']));
        $postmortemRate = $withPostmortem / $count * 100;

        $mttrPoints = match (true) {
            $mttr <= 2 => 100,
            $mttr <= 4 => 75,
            $mttr <= 8 => 50,
            default => 25,
        };
        $bonus = $postmortemRate >= 80 ? 10 : 0;

        return [
            'score' => (float) min($mttrPoints + $bonus, 100),
            'metrics' => [
                'incident_count' => $count,
                'mttr_hours' => round($mttr, 1),
                'postmortems_completed' => $withPostmortem,
                'postmortem_rate' => round($postmortemRate, 1),
            ],
            'target' => $target,
        ];
    }

    /**
     * Survey-Durchschnitt 1-5, linear auf 0-100
     *
     * @return array{score: float|null, metrics: array<string, mixed>, target: string}
     */
    private function developerSatisfaction(): array
    {
        $survey = $this->source->latestSurvey();
        $target = 'Ziel: Durchschnitt ueber 4.0 (von 5)';

        if ($survey === null) {
            return ['score' => null, 'metrics' => [], 'target' => $target];
        }

        $average = max(1.0, min(5.0, $survey['average_score']));

        return [
            'score' => round(($average - 1) / 4 * 100, 1),
            'metrics' => [
                'survey_date' => $survey['date'],
                'response_rate' => $survey['response_rate'],
                'average_score' => round($survey['average_score'], 2),
            ],
            'target' => $target,
        ];
    }

    /**
     * Brown Bags, Wiki-Updates und Slack-Nachrichten gegen die Zielwerte je Quartal
     *
     * @return array{score: float|null, metrics: array<string, mixed>, target: string}
     */
    private function knowledgeSharing(): array
    {
        $counts = $this->source->knowledgeSharingCounts(90);
        $target = 'Ziel je Quartal: 3 Brown Bags, 12 Wiki-Updates, 100 Nachrichten in #performance';

        if ($counts === null) {
            return ['score' => null, 'metrics' => [], 'target' => $target];
        }

        $points = 0.0;
        foreach (self::KNOWLEDGE_TARGETS as $key => $expected) {
            $points += min($counts[$key] / $expected * 100, 100.0);
        }

        return [
            'score' => round($points / \count(self::KNOWLEDGE_TARGETS), 1),
            'metrics' => $counts,
            'target' => $target,
        ];
    }

    /**
     * Mehr als 5 Punkte Abstand zur letzten Berechnung zaehlen als Trend
     */
    public static function trend(?float $current, ?float $previous): string
    {
        if ($current === null || $previous === null) {
            return 'unknown';
        }

        $diff = $current - $previous;

        return match (true) {
            $diff > 5 => 'improving',
            $diff < -5 => 'declining',
            default => 'stable',
        };
    }

    /**
     * @param array<string, array{score: float|null}> $components
     *
     * @return list<string>
     */
    private static function recommendations(array $components): array
    {
        $recommendations = [];

        foreach ($components as $key => $component) {
            if ($component['score'] === null) {
                $recommendations[] = 'Keine Daten fuer ' . $key . ': Datenquelle anbinden';
                continue;
            }
            if ($component['score'] < self::RECOMMENDATION_BELOW) {
                $recommendations[] = match ($key) {
                    'code_review' => 'Code-Review-Rate verbessern: Performance-Checkliste ins PR-Template',
                    'budget_compliance' => 'Error Budget knapp: Performance-Sprint planen',
                    'incident_response' => 'MTTR verbessern: Runbooks und Alerting pruefen',
                    'developer_satisfaction' => 'Developer Survey auswerten und Feedback adressieren',
                    'knowledge_sharing' => 'Mehr Brown Bags und Wiki-Dokumentation planen',
                    default => 'Bereich verbessern: ' . $key,
                };
            }
        }

        return $recommendations;
    }
}
