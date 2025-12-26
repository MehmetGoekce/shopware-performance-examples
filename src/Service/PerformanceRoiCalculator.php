<?php

declare(strict_types=1);

namespace PerformanceExamples\Service;

/**
 * Performance ROI Calculator
 *
 * Kapitel 1: Der Performance-Imperativ (Modellrechnung)
 *
 * Berechnet den Return on Investment für Performance-Optimierungen
 * basierend auf der Deloitte/Google "Milliseconds Make Millions" Studie.
 *
 * Studienergebnisse (2020):
 * - 0.1s Ladezeit-Verbesserung = +8.4% Conversion (Retail)
 * - 0.1s Ladezeit-Verbesserung = +9.2% Warenkorbwert (Retail)
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 * @see https://web.dev/case-studies/milliseconds-make-millions
 */
class PerformanceRoiCalculator
{
    /**
     * Conversion-Steigerung pro 0.1s Ladezeit-Verbesserung
     * Quelle: Deloitte/Google 2020
     */
    private const CONVERSION_LIFT_PER_100MS = 0.084; // 8.4%

    /**
     * Conversion-Verlust pro Sekunde Verzögerung
     * Konservative Schätzung basierend auf Industriedaten
     */
    private const CONVERSION_LOSS_PER_SECOND = 0.07; // 7%

    /**
     * Berechnet die erwartete Umsatzsteigerung durch Performance-Optimierung
     */
    public function calculateRevenueImpact(
        float $currentRevenue,
        float $currentLoadTimeSeconds,
        float $targetLoadTimeSeconds,
        float $currentConversionRate
    ): PerformanceRoiResult {
        // Verbesserung in Sekunden
        $improvementSeconds = $currentLoadTimeSeconds - $targetLoadTimeSeconds;

        if ($improvementSeconds <= 0) {
            return new PerformanceRoiResult(
                currentConversionRate: $currentConversionRate,
                newConversionRate: $currentConversionRate,
                additionalRevenue: 0.0,
                roiPercent: 0.0
            );
        }

        // Conversion-Steigerung berechnen
        // Formel: (Verbesserung in 100ms-Schritten) × 8.4%
        $improvement100ms = $improvementSeconds * 10;
        $conversionLift = $improvement100ms * self::CONVERSION_LIFT_PER_100MS;

        // Neue Conversion Rate
        $newConversionRate = $currentConversionRate * (1 + $conversionLift);

        // Zusätzlicher Umsatz
        $additionalRevenue = $currentRevenue * $conversionLift;

        return new PerformanceRoiResult(
            currentConversionRate: $currentConversionRate,
            newConversionRate: $newConversionRate,
            additionalRevenue: $additionalRevenue,
            roiPercent: 0.0 // Wird separat berechnet mit Investitionskosten
        );
    }

    /**
     * Berechnet den vollständigen ROI inklusive Investitionskosten
     */
    public function calculateFullRoi(
        float $currentRevenue,
        float $currentLoadTimeSeconds,
        float $targetLoadTimeSeconds,
        float $currentConversionRate,
        float $investmentCost
    ): PerformanceRoiResult {
        $result = $this->calculateRevenueImpact(
            $currentRevenue,
            $currentLoadTimeSeconds,
            $targetLoadTimeSeconds,
            $currentConversionRate
        );

        // ROI berechnen: (Gewinn - Investition) / Investition × 100
        $roiPercent = $investmentCost > 0
            ? (($result->additionalRevenue - $investmentCost) / $investmentCost) * 100
            : 0.0;

        return new PerformanceRoiResult(
            currentConversionRate: $result->currentConversionRate,
            newConversionRate: $result->newConversionRate,
            additionalRevenue: $result->additionalRevenue,
            roiPercent: $roiPercent,
            investmentCost: $investmentCost
        );
    }

    /**
     * Berechnet den geschätzten Umsatzverlust durch langsame Ladezeiten
     */
    public function calculateLostRevenue(
        float $currentRevenue,
        float $currentLoadTimeSeconds,
        float $baselineLoadTimeSeconds = 2.0
    ): float {
        if ($currentLoadTimeSeconds <= $baselineLoadTimeSeconds) {
            return 0.0;
        }

        $excessSeconds = $currentLoadTimeSeconds - $baselineLoadTimeSeconds;
        $conversionLoss = $excessSeconds * self::CONVERSION_LOSS_PER_SECOND;

        // Maximaler Verlust: 100%
        $conversionLoss = min($conversionLoss, 1.0);

        return $currentRevenue * $conversionLoss;
    }

    /**
     * Generiert einen Beispiel-Report für einen typischen B2B-Shop
     * (wie im Buch Kapitel 1 beschrieben)
     */
    public function generateSampleReport(): array
    {
        // Typischer Schweizer B2B-Shop (aus dem Buch)
        $currentRevenue = 8_000_000.0; // CHF 8 Mio.
        $currentLoadTime = 4.8; // Sekunden
        $targetLoadTime = 2.0; // Sekunden
        $currentConversionRate = 0.022; // 2.2%

        // Typische Investitionskosten
        $investmentCost = 12_600.0; // CHF
        // - Entwicklerzeit: 60h × CHF 150 = CHF 9.000
        // - Server-Optimierung: CHF 200/Monat × 12 = CHF 2.400
        // - Tools & Monitoring: CHF 100/Monat × 12 = CHF 1.200

        $result = $this->calculateFullRoi(
            $currentRevenue,
            $currentLoadTime,
            $targetLoadTime,
            $currentConversionRate,
            $investmentCost
        );

        return [
            'input' => [
                'current_revenue' => $currentRevenue,
                'current_load_time_seconds' => $currentLoadTime,
                'target_load_time_seconds' => $targetLoadTime,
                'current_conversion_rate' => $currentConversionRate,
                'investment_cost' => $investmentCost,
            ],
            'output' => [
                'new_conversion_rate' => round($result->newConversionRate, 4),
                'conversion_rate_lift_percent' => round(
                    ($result->newConversionRate / $currentConversionRate - 1) * 100,
                    1
                ),
                'additional_revenue' => round($result->additionalRevenue, 2),
                'roi_percent' => round($result->roiPercent, 0),
            ],
            'summary' => sprintf(
                'Bei einer Investition von CHF %s ergibt sich ein zusätzlicher ' .
                'Jahresumsatz von CHF %s (ROI: %s%%).',
                number_format($investmentCost, 0, ',', '.'),
                number_format($result->additionalRevenue, 0, ',', '.'),
                number_format($result->roiPercent, 0, ',', '.')
            ),
        ];
    }
}

/**
 * Value Object für ROI-Berechnungsergebnisse
 */
readonly class PerformanceRoiResult
{
    public function __construct(
        public float $currentConversionRate,
        public float $newConversionRate,
        public float $additionalRevenue,
        public float $roiPercent,
        public float $investmentCost = 0.0
    ) {}
}
