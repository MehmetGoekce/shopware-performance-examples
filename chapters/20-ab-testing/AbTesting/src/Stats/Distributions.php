<?php

declare(strict_types=1);

namespace AbTesting\Stats;

/**
 * Verteilungsfunktionen fuer die Auswertung: t-Verteilung, Normalverteilung, Chi-Quadrat.
 *
 * Rechnet mit der regularisierten unvollstaendigen Beta- und Gammafunktion
 * (Kettenbrueche nach Lentz, Numerical Recipes Kap. 6.2/6.4). Damit stimmt der
 * p-Wert auch bei kleinen Freiheitsgraden - eine Normal-Naeherung ist dort zu
 * optimistisch, eine Tabelle mit vier Stufen falsch.
 * Referenzwerte in den Tests: SciPy 1.8 (stats.t, stats.norm, stats.chisquare).
 */
final class Distributions
{
    private const EPS = 1e-15;
    private const TINY = 1e-300;
    private const MAX_ITERATIONS = 500;

    /** Lanczos-Naeherung, g = 7, n = 9 */
    private const LANCZOS = [
        0.99999999999980993, 676.5203681218851, -1259.1392167224028,
        771.32342877765313, -176.61502916214059, 12.507343278686905,
        -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
    ];

    /**
     * Zweiseitiger p-Wert der t-Verteilung: P(|T| >= |t|) bei df Freiheitsgraden.
     */
    public static function studentTwoSidedP(float $t, float $df): float
    {
        if ($df <= 0) {
            throw new \InvalidArgumentException('df muss > 0 sein');
        }

        return self::incompleteBeta($df / ($df + $t * $t), $df / 2, 0.5);
    }

    /**
     * Quantil der t-Verteilung fuer p in (0.5, 1), per Bisektion auf der Verteilungsfunktion.
     */
    public static function studentQuantile(float $p, float $df): float
    {
        if ($p <= 0.5 || $p >= 1) {
            throw new \InvalidArgumentException('p muss in (0.5, 1) liegen');
        }

        // P(T <= x) = 1 - p2/2 fuer x > 0; gesucht ist x mit p2 = 2 (1 - p)
        $target = 2 * (1 - $p);
        $low = 0.0;
        $high = 1.0;
        while (self::studentTwoSidedP($high, $df) > $target) {
            $high *= 2;
        }

        for ($i = 0; $i < 200 && $high - $low > 1e-12; ++$i) {
            $mid = ($low + $high) / 2;
            if (self::studentTwoSidedP($mid, $df) > $target) {
                $low = $mid;
            } else {
                $high = $mid;
            }
        }

        return ($low + $high) / 2;
    }

    public static function normalCdf(float $x): float
    {
        $tail = 0.5 * self::upperGamma(0.5, $x * $x / 2);

        return $x >= 0 ? 1 - $tail : $tail;
    }

    /**
     * Quantil der Standardnormalverteilung (Acklam, danach ein Halley-Schritt).
     */
    public static function normalQuantile(float $p): float
    {
        if ($p <= 0 || $p >= 1) {
            throw new \InvalidArgumentException('p muss in (0, 1) liegen');
        }

        $a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00];
        $b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01];
        $c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00];
        $d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00];
        $low = 0.02425;

        if ($p < $low || $p > 1 - $low) {
            $q = sqrt(-2 * log($p < $low ? $p : 1 - $p));
            $x = ((((($c[0] * $q + $c[1]) * $q + $c[2]) * $q + $c[3]) * $q + $c[4]) * $q + $c[5])
                / (((($d[0] * $q + $d[1]) * $q + $d[2]) * $q + $d[3]) * $q + 1);
            $x = $p < $low ? $x : -$x;
        } else {
            $q = $p - 0.5;
            $r = $q * $q;
            $x = ((((($a[0] * $r + $a[1]) * $r + $a[2]) * $r + $a[3]) * $r + $a[4]) * $r + $a[5]) * $q
                / ((((($b[0] * $r + $b[1]) * $r + $b[2]) * $r + $b[3]) * $r + $b[4]) * $r + 1);
        }

        $e = self::normalCdf($x) - $p;
        $u = $e * sqrt(2 * M_PI) * exp($x * $x / 2);

        return $x - $u / (1 + $x * $u / 2);
    }

    /**
     * P(X >= x) fuer Chi-Quadrat mit df Freiheitsgraden.
     */
    public static function chiSquareSurvival(float $x, int $df): float
    {
        if ($df < 1) {
            throw new \InvalidArgumentException('df muss >= 1 sein');
        }

        return $x <= 0 ? 1.0 : self::upperGamma($df / 2, $x / 2);
    }

    public static function logGamma(float $x): float
    {
        if ($x < 0.5) {
            return log(M_PI / abs(sin(M_PI * $x))) - self::logGamma(1 - $x);
        }

        $x -= 1;
        $sum = self::LANCZOS[0];
        for ($i = 1; $i < 9; ++$i) {
            $sum += self::LANCZOS[$i] / ($x + $i);
        }
        $t = $x + 7.5;

        return 0.5 * log(2 * M_PI) + ($x + 0.5) * log($t) - $t + log($sum);
    }

    /**
     * Regularisierte unvollstaendige Betafunktion I_x(a, b).
     */
    public static function incompleteBeta(float $x, float $a, float $b): float
    {
        if ($x <= 0) {
            return 0.0;
        }
        if ($x >= 1) {
            return 1.0;
        }

        $front = exp(self::logGamma($a + $b) - self::logGamma($a) - self::logGamma($b) + $a * log($x) + $b * log(1 - $x));

        if ($x < ($a + 1) / ($a + $b + 2)) {
            return $front * self::betaFraction($x, $a, $b) / $a;
        }

        return 1 - $front * self::betaFraction(1 - $x, $b, $a) / $b;
    }

    /**
     * Regularisierte obere unvollstaendige Gammafunktion Q(a, x).
     */
    public static function upperGamma(float $a, float $x): float
    {
        if ($a <= 0 || $x < 0) {
            throw new \InvalidArgumentException('a > 0 und x >= 0 erwartet');
        }
        if ($x === 0.0) {
            return 1.0;
        }

        $logFront = -$x + $a * log($x) - self::logGamma($a);

        if ($x < $a + 1) {
            // Reihe fuer P(a, x), dann Q = 1 - P
            $term = 1 / $a;
            $sum = $term;
            for ($n = 1; $n <= self::MAX_ITERATIONS; ++$n) {
                $term *= $x / ($a + $n);
                $sum += $term;
                if (abs($term) < abs($sum) * self::EPS) {
                    return 1 - $sum * exp($logFront);
                }
            }

            throw new \RuntimeException('upperGamma: Reihe konvergiert nicht');
        }

        // Kettenbruch fuer Q(a, x)
        $b = $x + 1 - $a;
        $c = 1 / self::TINY;
        $d = 1 / $b;
        $h = $d;
        for ($i = 1; $i <= self::MAX_ITERATIONS; ++$i) {
            $an = -$i * ($i - $a);
            $b += 2;
            $d = self::nonZero($an * $d + $b);
            $c = self::nonZero($b + $an / $c);
            $d = 1 / $d;
            $delta = $d * $c;
            $h *= $delta;
            if (abs($delta - 1) < self::EPS) {
                return exp($logFront) * $h;
            }
        }

        throw new \RuntimeException('upperGamma: Kettenbruch konvergiert nicht');
    }

    private static function betaFraction(float $x, float $a, float $b): float
    {
        $qab = $a + $b;
        $qap = $a + 1;
        $qam = $a - 1;
        $c = 1.0;
        $d = 1 / self::nonZero(1 - $qab * $x / $qap);
        $h = $d;

        for ($m = 1; $m <= self::MAX_ITERATIONS; ++$m) {
            $m2 = 2 * $m;
            $aa = $m * ($b - $m) * $x / (($qam + $m2) * ($a + $m2));
            $d = 1 / self::nonZero(1 + $aa * $d);
            $c = self::nonZero(1 + $aa / $c);
            $h *= $d * $c;

            $aa = -($a + $m) * ($qab + $m) * $x / (($a + $m2) * ($qap + $m2));
            $d = 1 / self::nonZero(1 + $aa * $d);
            $c = self::nonZero(1 + $aa / $c);
            $delta = $d * $c;
            $h *= $delta;

            if (abs($delta - 1) < self::EPS) {
                return $h;
            }
        }

        throw new \RuntimeException('incompleteBeta: Kettenbruch konvergiert nicht');
    }

    private static function nonZero(float $value): float
    {
        return abs($value) < self::TINY ? self::TINY : $value;
    }
}
