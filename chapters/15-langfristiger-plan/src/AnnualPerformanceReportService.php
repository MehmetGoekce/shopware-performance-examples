<?php

declare(strict_types=1);

namespace App\Service;

/**
 * SKIZZE, nicht lauffaehig: Aufbau eines Jahresberichts wie in Kapitel 15
 * (Abschnitt "Jahres-Dashboard"), Zeile fuer Zeile wie im Buch.
 *
 * Die Hilfsmethoden (getCWVAtDate, getConversionRate, getOKRAchievement,
 * getIncidentSummary, ...) fehlen absichtlich, weil die Daten in Ihren Systemen
 * liegen. Die RUM-Logs aus Kapitel 12 reichen fuer ein Jahr nicht: Monolog
 * behaelt 30 Tagesdateien. Legen Sie deshalb jeden Monat die Ausgabe von
 * "bin/console rum:report --hours=672" und "php scripts/error-budget.php"
 * (Kapitel 14) ab und lesen Sie diese Monatswerte hier ein.
 *
 * Keine Zahl in dieser Datei ist ein Messwert, und der Bericht rechnet keinen
 * Umsatz- oder ROI-Effekt aus Studien hoch (siehe getConversionChange()).
 */
class AnnualPerformanceReportService
{
    public function generateAnnualReport(int $year): array
    {
        return [
            'summary' => $this->getSummary($year),
            'cwv_progress' => $this->getCWVProgress($year),
            'okr_achievement' => $this->getOKRAchievement($year),
            'incidents' => $this->getIncidentSummary($year),
            'investments' => $this->getInvestmentSummary($year),
            'recommendations' => $this->getRecommendations($year),
        ];
    }

    private function getSummary(int $year): array
    {
        $startOfYear = $this->getCWVAtDate("$year-01-01");
        $endOfYear = $this->getCWVAtDate("$year-12-31");

        return [
            'lcp_improvement' => [
                'start' => $startOfYear['lcp'],
                'end' => $endOfYear['lcp'],
                'change_percent' => $this->calculateChange(
                    $startOfYear['lcp'],
                    $endOfYear['lcp']
                ),
            ],
            'cls_improvement' => [
                'start' => $startOfYear['cls'],
                'end' => $endOfYear['cls'],
                'change_percent' => $this->calculateChange(
                    $startOfYear['cls'],
                    $endOfYear['cls']
                ),
            ],
            'conversion_change' => $this->getConversionChange($year),
        ];
    }

    private function getConversionChange(int $year): array
    {
        // Nicht aus Studien hochrechnen: Deloitte (2020) mass +8,4 %
        // Retail-Conversion für 0,1 s schnellere mobile Ladezeit, über
        // 37 Marken in vier Wochen. Das ist weder LCP noch linear
        // (1 s wären sonst +84 %). Zählen Sie Ihre eigene Analytics.
        $before = $this->getConversionRate("$year-01");
        $after = $this->getConversionRate("$year-12");

        return [
            'conversion_start_percent' => $before,
            'conversion_end_percent' => $after,
            'change_points' => round($after - $before, 2),
            // Veränderung, nicht Wirkung: Saison, Kampagnen und Sortiment
            // wirken mit. Den Anteil der Performance zeigt ein A/B-Test (Kapitel 20)
        ];
    }
}
