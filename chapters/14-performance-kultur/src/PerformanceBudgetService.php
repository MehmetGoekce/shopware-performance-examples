<?php

declare(strict_types=1);

namespace PerformanceKultur;

use RumMonitoring\Rum\RumStatistics;

/**
 * Error Budget je Core Web Vital aus den RUM-Logs von Kapitel 12.
 *
 * Das SLO lautet wie bei Google "p75 <= Schwelle". Daraus folgt das Budget:
 * Hoechstens 25 % der Seitenaufrufe duerfen ueber der Schwelle liegen, sonst
 * kippt das p75. Verbraucht = Anteil ueber der Schwelle / 25 %.
 * Bei 100 % verbraucht ist das p75 noch "gut", darueber nicht mehr.
 *
 * Eingabe sind die Log-Kontexte aus RumLogReader::read() (Plugin RumMonitoring).
 * Wie RumStatistics zaehlt jeder Seitenaufruf (id) einmal, mit seinem letzten Wert.
 *
 * @see https://sre.google/workbook/error-budget-policy/
 * @see https://web.dev/articles/defining-core-web-vitals-thresholds
 */
final class PerformanceBudgetService
{
    public const METRICS = ['LCP', 'INP', 'CLS'];

    /** p75-SLO: 25 % der Seitenaufrufe duerfen die Schwelle ueberschreiten */
    public const ALLOWED_PERCENT = 25;

    /**
     * @param iterable<array<string, mixed>> $records    Log-Kontexte, in Log-Reihenfolge
     * @param int                            $minSamples darunter keine Bewertung (wie rum:check-alerts)
     *
     * @return array<string, array{samples: int, over: int, used_percent: float|null, remaining_percent: float|null, policy: string}>
     */
    public static function calculate(iterable $records, int $minSamples = 100): array
    {
        $latest = [];
        $n = 0;
        foreach ($records as $record) {
            $metric = $record['metric'] ?? null;
            if (!\in_array($metric, self::METRICS, true) || !is_numeric($record['value'] ?? null)) {
                continue;
            }

            $id = \is_string($record['id'] ?? null) ? $record['id'] : '#' . $n++;
            $latest[$metric][$id] = (float) $record['value'];
        }

        $result = [];
        foreach (self::METRICS as $metric) {
            $values = $latest[$metric] ?? [];
            $samples = \count($values);

            // "gut" heisst <= Schwelle, also zaehlt erst ein Wert darueber gegen das Budget
            $threshold = RumStatistics::THRESHOLDS[$metric][0];
            $over = \count(array_filter($values, static fn (float $v): bool => $v > $threshold));

            if ($samples === 0 || $samples < $minSamples) {
                $result[$metric] = [
                    'samples' => $samples,
                    'over' => $over,
                    'used_percent' => null,
                    'remaining_percent' => null,
                    'policy' => 'no-data',
                ];
                continue;
            }

            // In Zehntelprozent, verbraucht aufgerundet: Anzeige und Stufe passen
            // immer zusammen, und "uebrig unter 0" heisst genau "p75 nicht mehr gut"
            $denominator = $samples * self::ALLOWED_PERCENT;
            $usedTenths = intdiv($over * 100 * 1000 + $denominator - 1, $denominator);
            $remaining = (1000 - $usedTenths) / 10.0;

            $result[$metric] = [
                'samples' => $samples,
                'over' => $over,
                'used_percent' => $usedTenths / 10.0,
                'remaining_percent' => $remaining,
                'policy' => self::policy($remaining),
            ];
        }

        return $result;
    }

    /**
     * Stufen wie in templates/error-budget-policy.yaml
     */
    public static function policy(float $remainingPercent): string
    {
        return match (true) {
            $remainingPercent > 50 => 'green',   // normale Entwicklung
            $remainingPercent >= 20 => 'yellow', // vorsichtige Releases
            $remainingPercent >= 0 => 'orange',  // Performance-Fokus, p75 noch gut
            default => 'red',                    // SLO verletzt: Feature Freeze
        };
    }

    /**
     * Gesamtstatus = schlechteste bewertete Metrik; ist keine bewertet, "no-data".
     * Welche Metriken ohne Bewertung sind, liefert unrated().
     *
     * @param array<string, array{policy: string}> $budget
     */
    public static function overall(array $budget): string
    {
        $order = ['red', 'orange', 'yellow', 'green'];
        $policies = array_column($budget, 'policy');

        foreach ($order as $policy) {
            if (\in_array($policy, $policies, true)) {
                return $policy;
            }
        }

        return 'no-data';
    }

    /**
     * Metriken unter der Mindestzahl: Sie fehlen im Gesamtstatus und muessen
     * daneben stehen, sonst liest sich "green" wie "alles gut"
     *
     * @param array<string, array{policy: string}> $budget
     *
     * @return list<string>
     */
    public static function unrated(array $budget): array
    {
        return array_keys(array_filter($budget, static fn (array $row): bool => $row['policy'] === 'no-data'));
    }
}
