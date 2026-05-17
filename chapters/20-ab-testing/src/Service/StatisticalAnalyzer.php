<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Service;

/**
 * StatisticalAnalyzer - Berechnet statistische Signifikanz für A/B Tests
 *
 * @description
 * Implementiert Welch's t-Test und Bayesian Analysis für Performance-Metriken.
 * Berücksichtigt ungleiche Varianzen und Sample Sizes.
 *
 * @example
 * $result = $analyzer->calculateSignificance(
 *     controlMetrics: [2100, 2050, 2200, 2150],
 *     variantMetrics: [1800, 1750, 1900, 1850],
 *     confidenceLevel: 0.95
 * );
 *
 * if ($result->isSignificant()) {
 *     echo "Winner: {$result->getWinner()}";
 * }
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ABTesting
 */
class StatisticalAnalyzer
{
    /**
     * Standard-Konfidenz-Level (95%)
     */
    private const DEFAULT_CONFIDENCE = 0.95;

    /**
     * Minimale Sample Size für valide Ergebnisse
     */
    private const MIN_SAMPLE_SIZE = 30;

    /**
     * Berechnet statistische Signifikanz zwischen zwei Varianten
     *
     * @param array<float> $controlMetrics Metriken der Control-Gruppe
     * @param array<float> $variantMetrics Metriken der Test-Variante
     * @param float $confidenceLevel Konfidenz-Level (0.90, 0.95, 0.99)
     * @return SignificanceResult Analyse-Resultat
     */
    public function calculateSignificance(
        array $controlMetrics,
        array $variantMetrics,
        float $confidenceLevel = self::DEFAULT_CONFIDENCE
    ): SignificanceResult {
        // Validierung
        $this->validateSampleSize($controlMetrics, $variantMetrics);

        // Statistische Werte berechnen
        $controlStats = $this->calculateStats($controlMetrics);
        $variantStats = $this->calculateStats($variantMetrics);

        // Welch's t-Test (für ungleiche Varianzen)
        $tStatistic = $this->calculateWelchT($controlStats, $variantStats);
        $degreesOfFreedom = $this->calculateWelchDF($controlStats, $variantStats);
        $pValue = $this->calculatePValue($tStatistic, $degreesOfFreedom);

        // Effektgröße (Cohen's d)
        $effectSize = $this->calculateCohenD($controlStats, $variantStats);

        // Verbesserung in Prozent
        $improvement = (($controlStats['mean'] - $variantStats['mean']) / $controlStats['mean']) * 100;

        // Konfidenz-Intervall
        $confidenceInterval = $this->calculateConfidenceInterval(
            $variantStats,
            $confidenceLevel
        );

        // Signifikanz prüfen
        $alpha = 1 - $confidenceLevel;
        $isSignificant = $pValue < $alpha;

        // Power Analysis
        $power = $this->calculateStatisticalPower(
            $controlStats,
            $variantStats,
            $alpha
        );

        return new SignificanceResult(
            controlMean: $controlStats['mean'],
            variantMean: $variantStats['mean'],
            improvement: $improvement,
            pValue: $pValue,
            isSignificant: $isSignificant,
            confidenceLevel: $confidenceLevel,
            effectSize: $effectSize,
            confidenceInterval: $confidenceInterval,
            statisticalPower: $power,
            sampleSizeControl: count($controlMetrics),
            sampleSizeVariant: count($variantMetrics)
        );
    }

    /**
     * Berechnet benötigte Sample Size für gewünschte Power
     *
     * @param float $expectedImprovement Erwartete Verbesserung (z.B. 0.15 für 15%)
     * @param float $baselineStdDev Baseline Standardabweichung
     * @param float $power Gewünschte Power (z.B. 0.80 für 80%)
     * @param float $alpha Signifikanz-Level (z.B. 0.05 für 95% Konfidenz)
     * @return int Benötigte Sample Size pro Variante
     */
    public function calculateRequiredSampleSize(
        float $expectedImprovement,
        float $baselineStdDev,
        float $power = 0.80,
        float $alpha = 0.05
    ): int {
        // Effektgröße basierend auf erwarteter Verbesserung
        $effectSize = $expectedImprovement;

        // Z-Werte für Power und Alpha
        $zAlpha = $this->getZValue(1 - $alpha / 2);  // Two-tailed
        $zBeta = $this->getZValue($power);

        // Sample Size Formel (vereinfacht)
        $n = (2 * pow($zAlpha + $zBeta, 2) * pow($baselineStdDev, 2)) / pow($effectSize, 2);

        return (int) ceil($n);
    }

    /**
     * Bayesian A/B Test Analyse
     *
     * @param array<float> $controlMetrics Control-Metriken
     * @param array<float> $variantMetrics Varianten-Metriken
     * @return BayesianResult Bayesian Analyse-Resultat
     */
    public function bayesianAnalysis(
        array $controlMetrics,
        array $variantMetrics
    ): BayesianResult {
        $controlStats = $this->calculateStats($controlMetrics);
        $variantStats = $this->calculateStats($variantMetrics);

        // Monte Carlo Simulation (10000 Samples)
        $simulations = 10000;
        $variantWins = 0;

        for ($i = 0; $i < $simulations; $i++) {
            $controlSample = $this->sampleFromNormal(
                $controlStats['mean'],
                $controlStats['stddev']
            );

            $variantSample = $this->sampleFromNormal(
                $variantStats['mean'],
                $variantStats['stddev']
            );

            if ($variantSample < $controlSample) { // Niedrigere Werte = besser (LCP, FID)
                $variantWins++;
            }
        }

        $probabilityToBeBest = $variantWins / $simulations;
        $expectedLoss = $this->calculateExpectedLoss($controlStats, $variantStats);

        return new BayesianResult(
            probabilityToBeBest: $probabilityToBeBest,
            expectedLoss: $expectedLoss,
            credibleInterval: $this->calculateCredibleInterval($variantStats),
            controlMean: $controlStats['mean'],
            variantMean: $variantStats['mean']
        );
    }

    /**
     * Multi-Variant Test (mehr als 2 Varianten)
     *
     * @param array<string, array<float>> $variants Array von Varianten mit Metriken
     * @param float $confidenceLevel Konfidenz-Level
     * @return MultiVariantResult Analyse-Resultat
     */
    public function multiVariantAnalysis(
        array $variants,
        float $confidenceLevel = self::DEFAULT_CONFIDENCE
    ): MultiVariantResult {
        if (count($variants) < 2) {
            throw new \InvalidArgumentException('At least 2 variants required');
        }

        $results = [];
        $variantNames = array_keys($variants);
        $controlName = $variantNames[0];
        $controlMetrics = $variants[$controlName];

        // Paarweise Vergleiche mit Bonferroni-Korrektur
        $comparisons = count($variants) - 1;
        $adjustedAlpha = (1 - $confidenceLevel) / $comparisons; // Bonferroni
        $adjustedConfidence = 1 - $adjustedAlpha;

        foreach ($variants as $variantName => $variantMetrics) {
            if ($variantName === $controlName) {
                continue;
            }

            $result = $this->calculateSignificance(
                $controlMetrics,
                $variantMetrics,
                $adjustedConfidence
            );

            $results[$variantName] = $result;
        }

        // Besten Gewinner finden
        $winner = $this->findWinner($results, $controlName);

        return new MultiVariantResult(
            comparisons: $results,
            winner: $winner,
            controlName: $controlName
        );
    }

    /**
     * Berechnet deskriptive Statistiken
     *
     * @param array<float> $data Datenpunkte
     * @return array<string, float> Statistiken
     */
    private function calculateStats(array $data): array
    {
        $n = count($data);
        $mean = array_sum($data) / $n;

        // Varianz und Standardabweichung
        $variance = 0;
        foreach ($data as $value) {
            $variance += pow($value - $mean, 2);
        }
        $variance /= ($n - 1); // Sample variance
        $stddev = sqrt($variance);

        // Standard Error
        $stderr = $stddev / sqrt($n);

        return [
            'mean' => $mean,
            'variance' => $variance,
            'stddev' => $stddev,
            'stderr' => $stderr,
            'n' => $n,
        ];
    }

    /**
     * Berechnet Welch's t-Statistik
     *
     * @param array<string, float> $stats1 Statistiken Gruppe 1
     * @param array<string, float> $stats2 Statistiken Gruppe 2
     * @return float t-Wert
     */
    private function calculateWelchT(array $stats1, array $stats2): float
    {
        $numerator = $stats1['mean'] - $stats2['mean'];
        $denominator = sqrt(
            ($stats1['variance'] / $stats1['n']) +
            ($stats2['variance'] / $stats2['n'])
        );

        return $numerator / $denominator;
    }

    /**
     * Berechnet Welch-Satterthwaite Freiheitsgrade
     *
     * @param array<string, float> $stats1 Statistiken Gruppe 1
     * @param array<string, float> $stats2 Statistiken Gruppe 2
     * @return float Freiheitsgrade
     */
    private function calculateWelchDF(array $stats1, array $stats2): float
    {
        $s1_n1 = $stats1['variance'] / $stats1['n'];
        $s2_n2 = $stats2['variance'] / $stats2['n'];

        $numerator = pow($s1_n1 + $s2_n2, 2);
        $denominator = (pow($s1_n1, 2) / ($stats1['n'] - 1)) +
                       (pow($s2_n2, 2) / ($stats2['n'] - 1));

        return $numerator / $denominator;
    }

    /**
     * Berechnet p-Value aus t-Statistik (approximiert)
     *
     * @param float $t t-Wert
     * @param float $df Freiheitsgrade
     * @return float p-Value
     */
    private function calculatePValue(float $t, float $df): float
    {
        // Vereinfachte Approximation via Normalverteilung für große df
        if ($df > 30) {
            return 2 * (1 - $this->normalCDF(abs($t)));
        }

        // Für kleine df: Lookup Table (approximiert)
        return $this->tDistributionPValue(abs($t), $df);
    }

    /**
     * Normal CDF (Cumulative Distribution Function)
     *
     * @param float $x x-Wert
     * @return float Wahrscheinlichkeit
     */
    private function normalCDF(float $x): float
    {
        // Abramowitz & Stegun approximation
        $t = 1 / (1 + 0.2316419 * abs($x));
        $d = 0.3989423 * exp(-$x * $x / 2);
        $probability = $d * $t * (0.3193815 + $t * (-0.3565638 + $t * (1.781478 + $t * (-1.821256 + $t * 1.330274))));

        return $x > 0 ? 1 - $probability : $probability;
    }

    /**
     * t-Distribution p-Value (approximiert)
     *
     * @param float $t t-Wert
     * @param float $df Freiheitsgrade
     * @return float p-Value
     */
    private function tDistributionPValue(float $t, float $df): float
    {
        // Sehr vereinfachte Lookup Table
        // In Production: Verwende scipy oder R für präzise Werte
        // String-Keys: PHP würde Float-Array-Keys zu int trunkieren
        // (1.645/1.960/2.576/3.291 → 1/1/2/3), siehe getZValue()
        $lookup = [
            '1.645' => 0.10,
            '1.960' => 0.05,
            '2.576' => 0.01,
            '3.291' => 0.001,
        ];

        foreach ($lookup as $critical => $p) {
            if ($t < (float) $critical) {
                return $p;
            }
        }

        return 0.0001; // Highly significant
    }

    /**
     * Berechnet Cohen's d (Effektgröße)
     *
     * @param array<string, float> $stats1 Statistiken Gruppe 1
     * @param array<string, float> $stats2 Statistiken Gruppe 2
     * @return float Cohen's d
     */
    private function calculateCohenD(array $stats1, array $stats2): float
    {
        $pooledStdDev = sqrt(
            (($stats1['n'] - 1) * $stats1['variance'] +
             ($stats2['n'] - 1) * $stats2['variance']) /
            ($stats1['n'] + $stats2['n'] - 2)
        );

        return ($stats1['mean'] - $stats2['mean']) / $pooledStdDev;
    }

    /**
     * Berechnet Konfidenz-Intervall
     *
     * @param array<string, float> $stats Statistiken
     * @param float $confidenceLevel Konfidenz-Level
     * @return array{lower: float, upper: float} Intervall
     */
    private function calculateConfidenceInterval(array $stats, float $confidenceLevel): array
    {
        $z = $this->getZValue($confidenceLevel + (1 - $confidenceLevel) / 2);
        $margin = $z * $stats['stderr'];

        return [
            'lower' => $stats['mean'] - $margin,
            'upper' => $stats['mean'] + $margin,
        ];
    }

    /**
     * Gibt Z-Wert für Konfidenz-Level zurück
     *
     * @param float $probability Wahrscheinlichkeit
     * @return float Z-Wert
     */
    private function getZValue(float $probability): float
    {
        // String keys to avoid PHP float-to-int array key truncation
        $lookup = [
            '0.8' => 0.842,
            '0.9' => 1.282,
            '0.95' => 1.645,
            '0.975' => 1.960,
            '0.99' => 2.326,
            '0.995' => 2.576,
        ];

        $key = (string) round($probability, 3);
        return $lookup[$key] ?? 1.96; // Default: 95%
    }

    /**
     * Berechnet Statistical Power
     *
     * @param array<string, float> $controlStats Control Statistiken
     * @param array<string, float> $variantStats Varianten Statistiken
     * @param float $alpha Signifikanz-Level
     * @return float Power (0-1)
     */
    private function calculateStatisticalPower(
        array $controlStats,
        array $variantStats,
        float $alpha
    ): float {
        $effectSize = $this->calculateCohenD($controlStats, $variantStats);
        $n = min($controlStats['n'], $variantStats['n']);

        // Vereinfachte Power-Berechnung
        $delta = abs($effectSize) * sqrt($n / 2);
        $zAlpha = $this->getZValue(1 - $alpha / 2);

        $power = 1 - $this->normalCDF($zAlpha - $delta);

        return max(0, min(1, $power)); // Clamp zu [0, 1]
    }

    /**
     * Samplet aus Normalverteilung (Box-Muller Transform)
     *
     * @param float $mean Mittelwert
     * @param float $stddev Standardabweichung
     * @return float Sample
     */
    private function sampleFromNormal(float $mean, float $stddev): float
    {
        $u1 = mt_rand() / mt_getrandmax();
        $u2 = mt_rand() / mt_getrandmax();

        $z = sqrt(-2 * log($u1)) * cos(2 * M_PI * $u2);

        return $mean + $z * $stddev;
    }

    /**
     * Berechnet Expected Loss (Bayesian)
     *
     * @param array<string, float> $controlStats Control Statistiken
     * @param array<string, float> $variantStats Varianten Statistiken
     * @return float Expected Loss
     */
    private function calculateExpectedLoss(array $controlStats, array $variantStats): float
    {
        // Vereinfachte Berechnung: Differenz der Means
        return max(0, $variantStats['mean'] - $controlStats['mean']);
    }

    /**
     * Berechnet Credible Interval (Bayesian)
     *
     * @param array<string, float> $stats Statistiken
     * @return array{lower: float, upper: float} Credible Interval
     */
    private function calculateCredibleInterval(array $stats): array
    {
        // 95% Credible Interval (approximiert via Normal)
        return $this->calculateConfidenceInterval($stats, 0.95);
    }

    /**
     * Findet besten Gewinner aus Multi-Variant Test
     *
     * @param array<string, SignificanceResult> $results Vergleichs-Resultate
     * @param string $controlName Name der Control-Gruppe
     * @return string Name des Gewinners
     */
    private function findWinner(array $results, string $controlName): string
    {
        $bestVariant = $controlName;
        $bestImprovement = 0;

        foreach ($results as $variantName => $result) {
            if ($result->isSignificant() && $result->getImprovement() > $bestImprovement) {
                $bestImprovement = $result->getImprovement();
                $bestVariant = $variantName;
            }
        }

        return $bestVariant;
    }

    /**
     * Validiert Sample Size
     *
     * @param array<float> $control Control-Metriken
     * @param array<float> $variant Varianten-Metriken
     * @return void
     * @throws \InvalidArgumentException Bei zu kleiner Sample Size
     */
    private function validateSampleSize(array $control, array $variant): void
    {
        if (count($control) < self::MIN_SAMPLE_SIZE || count($variant) < self::MIN_SAMPLE_SIZE) {
            throw new \InvalidArgumentException(
                "Sample size too small. Minimum: " . self::MIN_SAMPLE_SIZE
            );
        }
    }
}

/**
 * SignificanceResult - Resultat der Signifikanz-Analyse
 */
class SignificanceResult
{
    public function __construct(
        private readonly float $controlMean,
        private readonly float $variantMean,
        private readonly float $improvement,
        private readonly float $pValue,
        private readonly bool $isSignificant,
        private readonly float $confidenceLevel,
        private readonly float $effectSize,
        private readonly array $confidenceInterval,
        private readonly float $statisticalPower,
        private readonly int $sampleSizeControl,
        private readonly int $sampleSizeVariant
    ) {
    }

    public function isSignificant(): bool
    {
        return $this->isSignificant;
    }

    public function getWinner(): string
    {
        if (!$this->isSignificant) {
            return 'inconclusive';
        }

        return $this->variantMean < $this->controlMean ? 'variant' : 'control';
    }

    public function getImprovement(): float
    {
        return $this->improvement;
    }

    public function getPValue(): float
    {
        return $this->pValue;
    }

    public function getControlMean(): float
    {
        return $this->controlMean;
    }

    public function getVariantMean(): float
    {
        return $this->variantMean;
    }

    public function getConfidenceInterval(): array
    {
        return $this->confidenceInterval;
    }

    public function getStatisticalPower(): float
    {
        return $this->statisticalPower;
    }

    public function toArray(): array
    {
        return [
            'control_mean' => $this->controlMean,
            'variant_mean' => $this->variantMean,
            'improvement_percent' => round($this->improvement, 2),
            'p_value' => $this->pValue,
            'is_significant' => $this->isSignificant,
            'confidence_level' => $this->confidenceLevel,
            'effect_size' => $this->effectSize,
            'confidence_interval' => $this->confidenceInterval,
            'statistical_power' => $this->statisticalPower,
            'sample_size_control' => $this->sampleSizeControl,
            'sample_size_variant' => $this->sampleSizeVariant,
            'winner' => $this->getWinner(),
        ];
    }
}

/**
 * BayesianResult - Resultat der Bayesian Analyse
 */
class BayesianResult
{
    public function __construct(
        private readonly float $probabilityToBeBest,
        private readonly float $expectedLoss,
        private readonly array $credibleInterval,
        private readonly float $controlMean,
        private readonly float $variantMean
    ) {
    }

    public function getProbabilityToBeBest(): float
    {
        return $this->probabilityToBeBest;
    }

    public function shouldDeploy(float $threshold = 0.95): bool
    {
        return $this->probabilityToBeBest >= $threshold;
    }

    public function toArray(): array
    {
        return [
            'probability_to_be_best' => round($this->probabilityToBeBest, 4),
            'expected_loss' => round($this->expectedLoss, 2),
            'credible_interval' => $this->credibleInterval,
            'control_mean' => $this->controlMean,
            'variant_mean' => $this->variantMean,
            'recommendation' => $this->shouldDeploy() ? 'deploy' : 'continue_testing',
        ];
    }
}

/**
 * MultiVariantResult - Resultat eines Multi-Variant Tests
 */
class MultiVariantResult
{
    public function __construct(
        private readonly array $comparisons,
        private readonly string $winner,
        private readonly string $controlName
    ) {
    }

    public function getWinner(): string
    {
        return $this->winner;
    }

    public function getComparisons(): array
    {
        return $this->comparisons;
    }

    public function toArray(): array
    {
        $comparisonsArray = [];
        foreach ($this->comparisons as $variant => $result) {
            $comparisonsArray[$variant] = $result->toArray();
        }

        return [
            'winner' => $this->winner,
            'control' => $this->controlName,
            'comparisons' => $comparisonsArray,
        ];
    }
}
