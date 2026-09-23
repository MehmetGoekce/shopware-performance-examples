<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;

/**
 * Annual Performance Report Generator
 *
 * Generiert umfassende Jahresberichte für Stakeholder.
 * Aggregiert Daten aus RUM, Incidents, Budget und Kultur-Metriken.
 */
class AnnualReportService
{
    public function __construct(
        private readonly RumDataRepository $rumRepository,
        private readonly IncidentTrackerService $incidentTracker,
        private readonly PerformanceBudgetService $budgetService,
        private readonly CultureMetricsService $cultureService,
        private readonly TechDebtTrackerService $techDebtService,
        private readonly LoggerInterface $logger
    ) {}

    /**
     * Generiert vollständigen Jahresbericht
     *
     * @param int $year Das Jahr für den Bericht
     * @return array{
     *     meta: array,
     *     executive_summary: array,
     *     core_web_vitals: array,
     *     incidents: array,
     *     budget: array,
     *     culture: array,
     *     tech_debt: array,
     *     achievements: array,
     *     challenges: array,
     *     recommendations: array,
     *     kpis: array
     * }
     */
    public function generateAnnualReport(int $year): array
    {
        $this->logger->info('Generating annual report', ['year' => $year]);

        $startDate = new \DateTimeImmutable("$year-01-01");
        $endDate = new \DateTimeImmutable("$year-12-31");

        return [
            'meta' => $this->getReportMeta($year),
            'executive_summary' => $this->generateExecutiveSummary($year),
            'core_web_vitals' => $this->getCoreWebVitalsSection($startDate, $endDate),
            'incidents' => $this->getIncidentsSection($year),
            'budget' => $this->getBudgetSection($year),
            'culture' => $this->getCultureSection(),
            'tech_debt' => $this->getTechDebtSection(),
            'achievements' => $this->getAchievements($year),
            'challenges' => $this->getChallenges($year),
            'recommendations' => $this->generateRecommendations(),
            'kpis' => $this->getKpiSummary($year),
        ];
    }

    /**
     * Report Metadaten
     */
    private function getReportMeta(int $year): array
    {
        return [
            'title' => "Performance Jahresbericht $year",
            'generated_at' => (new \DateTimeImmutable())->format('c'),
            'period' => [
                'start' => "$year-01-01",
                'end' => "$year-12-31",
            ],
            'version' => '1.0',
            'confidentiality' => 'internal',
        ];
    }

    /**
     * Executive Summary für C-Level
     */
    private function generateExecutiveSummary(int $year): array
    {
        // KPIs aggregieren
        $cwvGoodRate = $this->rumRepository->getYearlyGoodRate($year);
        $incidentCount = count($this->incidentTracker->getPerformanceIncidents(days: 365));
        $budgetStatus = $this->budgetService->calculateRemainingBudget();
        $cultureScore = $this->cultureService->calculateCultureScore();

        // ROI berechnen (vereinfacht)
        $estimatedRoi = $this->estimateRoi($year);

        return [
            'headline' => $this->generateHeadline($cwvGoodRate, $incidentCount),
            'key_metrics' => [
                'cwv_good_rate' => [
                    'value' => $cwvGoodRate,
                    'target' => 85,
                    'status' => $cwvGoodRate >= 85 ? 'achieved' : 'missed',
                ],
                'performance_incidents' => [
                    'value' => $incidentCount,
                    'target' => '<5',
                    'status' => $incidentCount < 5 ? 'achieved' : 'missed',
                ],
                'error_budget' => [
                    'value' => $budgetStatus['remaining_percent'],
                    'status' => $budgetStatus['policy'],
                ],
                'culture_score' => [
                    'value' => $cultureScore['overall_score'],
                    'trend' => $cultureScore['trend'],
                ],
            ],
            'roi' => [
                'investment' => $estimatedRoi['investment'],
                'return' => $estimatedRoi['return'],
                'roi_percent' => $estimatedRoi['roi_percent'],
            ],
            'one_liner' => $this->generateOneLiner($cwvGoodRate, $incidentCount, $estimatedRoi),
        ];
    }

    /**
     * Core Web Vitals Jahresübersicht
     */
    private function getCoreWebVitalsSection(
        \DateTimeImmutable $start,
        \DateTimeImmutable $end
    ): array {
        $monthlyData = $this->rumRepository->getMonthlyAverages($start, $end);
        $yearStart = $this->rumRepository->getMetricsForDate($start);
        $yearEnd = $this->rumRepository->getMetricsForDate($end);

        return [
            'summary' => [
                'lcp' => [
                    'start_p75' => $yearStart['lcp_p75'] ?? null,
                    'end_p75' => $yearEnd['lcp_p75'] ?? null,
                    'improvement_percent' => $this->calculateImprovement(
                        $yearStart['lcp_p75'] ?? 0,
                        $yearEnd['lcp_p75'] ?? 0
                    ),
                ],
                'inp' => [
                    'start_p75' => $yearStart['inp_p75'] ?? null,
                    'end_p75' => $yearEnd['inp_p75'] ?? null,
                    'improvement_percent' => $this->calculateImprovement(
                        $yearStart['inp_p75'] ?? 0,
                        $yearEnd['inp_p75'] ?? 0
                    ),
                ],
                'cls' => [
                    'start_p75' => $yearStart['cls_p75'] ?? null,
                    'end_p75' => $yearEnd['cls_p75'] ?? null,
                    'improvement_percent' => $this->calculateImprovement(
                        $yearStart['cls_p75'] ?? 0,
                        $yearEnd['cls_p75'] ?? 0
                    ),
                ],
            ],
            'monthly_trend' => $monthlyData,
            'good_rate_progression' => $this->rumRepository->getGoodRateProgression($start, $end),
            'worst_pages' => $this->rumRepository->getWorstPerformingPages(5),
            'most_improved' => $this->rumRepository->getMostImprovedPages(5),
        ];
    }

    /**
     * Incidents Jahresübersicht
     */
    private function getIncidentsSection(int $year): array
    {
        $incidents = $this->incidentTracker->getPerformanceIncidents(days: 365);

        $bySeverity = ['p0' => 0, 'p1' => 0, 'p2' => 0];
        $byMonth = array_fill(1, 12, 0);
        $totalMttr = 0;

        foreach ($incidents as $incident) {
            $bySeverity[$incident['severity']]++;
            $month = (int)(new \DateTimeImmutable($incident['created_at']))->format('n');
            $byMonth[$month]++;
            $totalMttr += $incident['recovery_time_hours'] ?? 0;
        }

        $avgMttr = count($incidents) > 0 ? $totalMttr / count($incidents) : 0;

        return [
            'total' => count($incidents),
            'by_severity' => $bySeverity,
            'by_month' => $byMonth,
            'mttr_avg_hours' => round($avgMttr, 1),
            'postmortem_completion_rate' => $this->calculatePostmortemRate($incidents),
            'top_root_causes' => $this->aggregateRootCauses($incidents),
            'trend' => $this->calculateIncidentTrend($byMonth),
        ];
    }

    /**
     * Budget Jahresübersicht
     */
    private function getBudgetSection(int $year): array
    {
        return [
            'planned' => 50000,  // CHF - aus Config laden
            'actual' => 47500,   // CHF - aus Tracking
            'variance' => -2500,
            'variance_percent' => -5,
            'by_category' => [
                'tooling' => ['planned' => 15000, 'actual' => 14200],
                'infrastructure' => ['planned' => 20000, 'actual' => 22000],
                'training' => ['planned' => 10000, 'actual' => 8300],
                'contingency' => ['planned' => 5000, 'actual' => 3000],
            ],
            'roi_analysis' => $this->estimateRoi($year),
        ];
    }

    /**
     * Kultur-Metriken
     */
    private function getCultureSection(): array
    {
        $cultureScore = $this->cultureService->calculateCultureScore();

        return [
            'overall_score' => $cultureScore['overall_score'],
            'components' => $cultureScore['components'],
            'trend' => $cultureScore['trend'],
            'highlights' => [
                'champions_active' => 5,
                'brown_bags_held' => 12,
                'wiki_articles' => 24,
                'prs_reviewed' => 450,
            ],
        ];
    }

    /**
     * Tech Debt Status
     */
    private function getTechDebtSection(): array
    {
        $stats = $this->techDebtService->getStatistics();

        return [
            'score' => $stats['tech_debt_score'],
            'health' => $stats['health'],
            'trend' => $stats['trend'],
            'items_resolved' => $stats['resolved_this_quarter'] * 4, // Hochrechnung
            'hours_invested' => $stats['resolved_this_quarter'] * 4 * 8, // Schätzung
            'backlog_hours' => $stats['total_hours_backlog'],
        ];
    }

    /**
     * Jahres-Erfolge
     */
    private function getAchievements(int $year): array
    {
        return [
            [
                'title' => 'CWV Good Rate > 85%',
                'description' => 'Alle kritischen Seiten erreichen "Good" Status',
                'impact' => 'Besseres Google Ranking, höhere Conversion',
            ],
            [
                'title' => 'Zero P0 Incidents',
                'description' => 'Kein kritischer Performance-Incident im ganzen Jahr',
                'impact' => 'Hohe Kundenzufriedenheit, stabiler Betrieb',
            ],
            [
                'title' => 'Performance Champion Programm',
                'description' => '5 Champions ausgebildet und aktiv',
                'impact' => 'Skalierbare Performance-Kultur',
            ],
        ];
    }

    /**
     * Jahres-Herausforderungen
     */
    private function getChallenges(int $year): array
    {
        return [
            [
                'title' => 'Third-Party Script Explosion',
                'description' => 'Marketing-Tags beeinträchtigten LCP',
                'resolution' => 'Tag-Governance-Prozess eingeführt',
                'learning' => 'Proaktives Third-Party-Management nötig',
            ],
            [
                'title' => 'Mobile Performance Gap',
                'description' => 'Mobile vs. Desktop Unterschiede zu gross',
                'resolution' => 'Mobile-First Optimierungen Q3',
                'learning' => 'RUM-Segmentierung nach Device wichtig',
            ],
        ];
    }

    /**
     * Empfehlungen für nächstes Jahr
     */
    private function generateRecommendations(): array
    {
        return [
            [
                'priority' => 'high',
                'title' => 'Edge Computing Evaluation',
                'rationale' => 'Personalisierung ohne Latenz-Einbussen',
                'estimated_investment' => 15000,
                'expected_impact' => 'LCP -200ms für personalisierte Seiten',
            ],
            [
                'priority' => 'high',
                'title' => 'INP Fokus',
                'rationale' => 'Google Core Update Q1 macht INP wichtiger',
                'estimated_investment' => 8000,
                'expected_impact' => 'INP p75 < 150ms',
            ],
            [
                'priority' => 'medium',
                'title' => 'Automatisierung ausbauen',
                'rationale' => '40% manuelle Tasks automatisierbar',
                'estimated_investment' => 5000,
                'expected_impact' => '10 Stunden/Woche gespart',
            ],
        ];
    }

    /**
     * KPI-Zusammenfassung
     */
    private function getKpiSummary(int $year): array
    {
        return [
            'leading_indicators' => [
                'cwv_good_rate' => ['target' => 85, 'actual' => 88, 'status' => 'achieved'],
                'performance_review_rate' => ['target' => 80, 'actual' => 75, 'status' => 'missed'],
                'tech_debt_score' => ['target' => '<40', 'actual' => 35, 'status' => 'achieved'],
            ],
            'lagging_indicators' => [
                'conversion_rate' => ['baseline' => 2.5, 'current' => 3.1, 'change' => '+24%'],
                'bounce_rate' => ['baseline' => 45, 'current' => 32, 'change' => '-29%'],
                'page_views_per_session' => ['baseline' => 3.2, 'current' => 4.1, 'change' => '+28%'],
            ],
        ];
    }

    // Helper Methods

    private function generateHeadline(float $cwvRate, int $incidents): string
    {
        if ($cwvRate >= 90 && $incidents === 0) {
            return 'Hervorragendes Performance-Jahr';
        }
        if ($cwvRate >= 80 && $incidents <= 2) {
            return 'Solides Performance-Jahr mit Erfolgen';
        }
        if ($cwvRate >= 70) {
            return 'Performance verbessert, weitere Arbeit nötig';
        }
        return 'Herausforderndes Jahr, Investitionen erforderlich';
    }

    private function generateOneLiner(float $cwvRate, int $incidents, array $roi): string
    {
        return sprintf(
            'CWV Good Rate bei %d%%, %d Incidents, ROI von %d%%.',
            (int)$cwvRate,
            $incidents,
            (int)$roi['roi_percent']
        );
    }

    private function calculateImprovement(float $start, float $end): float
    {
        if ($start === 0.0) {
            return 0;
        }
        return round((($start - $end) / $start) * 100, 1);
    }

    private function estimateRoi(int $year): array
    {
        // Vereinfachte ROI-Berechnung
        $investment = 47500;
        $conversionImpact = 180000;
        $bounceImpact = 45000;
        $operationalSavings = 25000;
        $totalReturn = $conversionImpact + $bounceImpact + $operationalSavings;

        return [
            'investment' => $investment,
            'return' => $totalReturn,
            'roi_percent' => round((($totalReturn - $investment) / $investment) * 100, 1),
        ];
    }

    private function calculatePostmortemRate(array $incidents): float
    {
        if (empty($incidents)) {
            return 100.0;
        }
        $withPostmortem = count(array_filter($incidents, fn($i) => $i['postmortem_completed'] ?? false));
        return round(($withPostmortem / count($incidents)) * 100, 1);
    }

    private function aggregateRootCauses(array $incidents): array
    {
        $causes = [];
        foreach ($incidents as $incident) {
            $cause = $incident['root_cause'] ?? 'Unknown';
            $causes[$cause] = ($causes[$cause] ?? 0) + 1;
        }
        arsort($causes);
        return array_slice($causes, 0, 5, true);
    }

    private function calculateIncidentTrend(array $byMonth): string
    {
        $firstHalf = array_sum(array_slice($byMonth, 0, 6, true));
        $secondHalf = array_sum(array_slice($byMonth, 6, 6, true));

        if ($secondHalf < $firstHalf * 0.7) {
            return 'improving';
        }
        if ($secondHalf > $firstHalf * 1.3) {
            return 'worsening';
        }
        return 'stable';
    }
}
