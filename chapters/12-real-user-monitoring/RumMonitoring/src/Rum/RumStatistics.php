<?php

declare(strict_types=1);

namespace RumMonitoring\Rum;

/**
 * Perzentile und Bewertung wie Google: p75 der Seitenaufrufe, "gut" heisst
 * kleiner oder gleich der Schwelle.
 *
 * Schwellen = LCPThresholds/INPThresholds/... aus web-vitals 6.2.2
 * @see https://web.dev/articles/defining-core-web-vitals-thresholds
 */
final class RumStatistics
{
    /** [gut bis einschliesslich, verbesserungswuerdig bis einschliesslich] */
    public const THRESHOLDS = [
        'LCP' => [2500, 4000],
        'INP' => [200, 500],
        'CLS' => [0.1, 0.25],
        'FCP' => [1800, 3000],
        'TTFB' => [800, 1800],
    ];

    /**
     * Nearest-Rank: der kleinste Wert, unter oder auf dem p Prozent der Werte liegen.
     *
     * @param list<float> $sortedValues aufsteigend sortiert
     */
    public static function percentile(array $sortedValues, int $p): float
    {
        $count = \count($sortedValues);
        if ($count === 0) {
            throw new \InvalidArgumentException('Keine Werte');
        }

        $rank = (int) ceil($p / 100 * $count);

        return $sortedValues[max($rank, 1) - 1];
    }

    public static function rating(string $metric, float $value): string
    {
        [$good, $poor] = self::THRESHOLDS[$metric];

        if ($value <= $good) {
            return 'good';
        }

        return $value <= $poor ? 'needs-improvement' : 'poor';
    }

    /**
     * @param iterable<array<string, mixed>> $records Log-Kontexte aus RumLogReader
     *
     * @return array<string, array{metric: string, group: string, samples: int, p50: float, p75: float, p90: float, rating: string}>
     */
    public static function aggregate(iterable $records, ?string $groupBy = null): array
    {
        $values = [];
        foreach ($records as $record) {
            $metric = $record['metric'] ?? null;
            if (!\is_string($metric) || !isset(self::THRESHOLDS[$metric]) || !is_numeric($record['value'] ?? null)) {
                continue;
            }

            $group = $groupBy === null ? '*' : (string) ($record[$groupBy] ?? 'unbekannt');
            $values[$metric . "\0" . $group][] = (float) $record['value'];
        }

        ksort($values);

        $result = [];
        foreach ($values as $key => $list) {
            [$metric, $group] = explode("\0", $key, 2);
            sort($list);
            $p75 = self::percentile($list, 75);

            $result[$key] = [
                'metric' => $metric,
                'group' => $group,
                'samples' => \count($list),
                'p50' => self::percentile($list, 50),
                'p75' => $p75,
                'p90' => self::percentile($list, 90),
                'rating' => self::rating($metric, $p75),
            ];
        }

        return $result;
    }
}
