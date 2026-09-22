<?php

declare(strict_types=1);

namespace AbTesting\Stats;

/**
 * Welch-t-Test, Stichprobengroesse und Sample-Ratio-Mismatch-Test fuer A/B-Tests.
 *
 * Referenzwerte in den Tests: SciPy 1.8, stats.ttest_ind(equal_var=False),
 * stats.chisquare.
 */
final class StatisticalAnalyzer
{
    /**
     * Vergleicht die Mittelwerte zweier Gruppen (Welch: ungleiche Varianzen erlaubt).
     *
     * @param list<float> $control Messwerte der Kontrollgruppe, z. B. LCP in ms
     * @param list<float> $variant Messwerte der Variante
     * @param float $confidence Konfidenzniveau, 0.95 = Signifikanzniveau 5 %
     */
    public function compare(array $control, array $variant, float $confidence = 0.95): SignificanceResult
    {
        if (\count($control) < 2 || \count($variant) < 2) {
            throw new \InvalidArgumentException('Je Gruppe mindestens 2 Messwerte');
        }
        if ($confidence <= 0 || $confidence >= 1) {
            throw new \InvalidArgumentException('confidence muss in (0, 1) liegen');
        }

        $c = $this->describe($control);
        $v = $this->describe($variant);

        // Quadrierte Standardfehler der beiden Mittelwerte
        $seC = $c['variance'] / $c['n'];
        $seV = $v['variance'] / $v['n'];
        $se = sqrt($seC + $seV);

        if ($se === 0.0) {
            throw new \InvalidArgumentException('Beide Gruppen ohne Streuung');
        }

        $difference = $v['mean'] - $c['mean'];
        $t = $difference / $se;

        // Welch-Satterthwaite-Freiheitsgrade
        $df = ($seC + $seV) ** 2 / ($seC ** 2 / ($c['n'] - 1) + $seV ** 2 / ($v['n'] - 1));

        $pValue = Distributions::studentTwoSidedP($t, $df);
        $margin = Distributions::studentQuantile(1 - (1 - $confidence) / 2, $df) * $se;

        return new SignificanceResult(
            controlN: $c['n'],
            variantN: $v['n'],
            controlMean: $c['mean'],
            variantMean: $v['mean'],
            difference: $difference,
            relativeChange: $difference / $c['mean'] * 100,
            tStatistic: $t,
            degreesOfFreedom: $df,
            pValue: $pValue,
            confidence: $confidence,
            ciLow: $difference - $margin,
            ciHigh: $difference + $margin,
        );
    }

    /**
     * Seitenaufrufe je Variante fuer einen zweiseitigen Test (Normal-Naeherung).
     *
     * @param float $minimumEffect kleinster Unterschied, der gefunden werden soll, in der Einheit der Metrik (z. B. 210 ms)
     * @param float $standardDeviation Standardabweichung der Metrik, gemessen an der Baseline
     */
    public function requiredSampleSize(
        float $minimumEffect,
        float $standardDeviation,
        float $alpha = 0.05,
        float $power = 0.80,
    ): int {
        if ($minimumEffect <= 0 || $standardDeviation <= 0) {
            throw new \InvalidArgumentException('minimumEffect und standardDeviation muessen > 0 sein');
        }

        $zAlpha = Distributions::normalQuantile(1 - $alpha / 2);
        $zBeta = Distributions::normalQuantile($power);

        return (int) ceil(2 * ($zAlpha + $zBeta) ** 2 * $standardDeviation ** 2 / $minimumEffect ** 2);
    }

    /**
     * Chi-Quadrat-Anpassungstest: Passt die Verteilung auf die Varianten zum
     * konfigurierten Split? Ein sehr kleiner p-Wert (ueblich: < 0.001) heisst,
     * dass die Zuweisung oder die Datenerfassung kaputt ist - dann ist auch der
     * Vergleich der Metriken nicht zu gebrauchen.
     *
     * @param array<string, int> $observed Variante => Anzahl
     * @param array<string, int> $weights Variante => Gewicht aus der Konfiguration
     */
    public function sampleRatioMismatchP(array $observed, array $weights): float
    {
        $total = array_sum($observed);
        $weightSum = array_sum($weights);

        if ($total === 0 || \count($weights) < 2) {
            throw new \InvalidArgumentException('Keine Beobachtungen oder weniger als zwei Varianten');
        }

        $chi2 = 0.0;
        foreach ($weights as $variant => $weight) {
            $expected = $total * $weight / $weightSum;
            $chi2 += (($observed[$variant] ?? 0) - $expected) ** 2 / $expected;
        }

        return Distributions::chiSquareSurvival($chi2, \count($weights) - 1);
    }

    /**
     * @param list<float> $values
     *
     * @return array{n: int, mean: float, variance: float}
     */
    private function describe(array $values): array
    {
        $n = \count($values);
        $mean = array_sum($values) / $n;

        $sum = 0.0;
        foreach ($values as $value) {
            $sum += ($value - $mean) ** 2;
        }

        // Stichprobenvarianz (n - 1), wie ttest_ind
        return ['n' => $n, 'mean' => $mean, 'variance' => $sum / ($n - 1)];
    }
}
