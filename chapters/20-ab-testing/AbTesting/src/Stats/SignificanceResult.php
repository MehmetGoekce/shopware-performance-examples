<?php

declare(strict_types=1);

namespace AbTesting\Stats;

/**
 * Ergebnis eines Welch-t-Tests Variante gegen Kontrolle.
 *
 * difference = Mittel Variante - Mittel Kontrolle. Bei Zeiten (LCP, INP) und
 * CLS ist negativ besser.
 */
final class SignificanceResult
{
    public function __construct(
        public readonly int $controlN,
        public readonly int $variantN,
        public readonly float $controlMean,
        public readonly float $variantMean,
        public readonly float $difference,
        public readonly float $relativeChange,
        public readonly float $tStatistic,
        public readonly float $degreesOfFreedom,
        public readonly float $pValue,
        public readonly float $confidence,
        public readonly float $ciLow,
        public readonly float $ciHigh,
    ) {
    }

    public function isSignificant(): bool
    {
        return $this->pValue < 1 - $this->confidence;
    }

    /**
     * Kleiner ist besser. "inconclusive" heisst: kein Unterschied nachgewiesen -
     * nicht: kein Unterschied vorhanden.
     */
    public function winner(): string
    {
        if (!$this->isSignificant()) {
            return 'inconclusive';
        }

        return $this->difference < 0 ? 'variant' : 'control';
    }
}
