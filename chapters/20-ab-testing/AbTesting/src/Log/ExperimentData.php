<?php

declare(strict_types=1);

namespace AbTesting\Log;

use AbTesting\Experiment\ExperimentConfig;

/**
 * Macht aus RUM-Log-Kontexten (Kapitel 12) die Messwerte je Variante.
 */
final class ExperimentData
{
    /**
     * Meldungen mit derselben id sind ein Seitenaufruf (web-vitals meldet CLS
     * und INP mehrfach) und zaehlen einmal, mit dem letzten Wert - wie
     * RumStatistics::aggregate(). Zeilen ohne Variante zaehlen nicht.
     *
     * @param iterable<array<string, mixed>> $records Log-Kontexte in Log-Reihenfolge
     *
     * @return array<string, list<float>> Variante => Werte, in der Reihenfolge der Konfiguration
     */
    public static function valuesByVariant(
        iterable $records,
        ExperimentConfig $config,
        string $experiment,
        string $metric,
        ?string $device = null,
    ): array {
        $field = ExperimentConfig::cookieName($experiment);
        $latest = [];
        $n = 0;

        foreach ($records as $record) {
            if (($record['metric'] ?? null) !== $metric || !is_numeric($record['value'] ?? null)) {
                continue;
            }
            if ($device !== null && ($record['device'] ?? null) !== $device) {
                continue;
            }

            $variant = $record[$field] ?? null;
            if (!$config->isVariant($experiment, $variant)) {
                continue;
            }

            $id = \is_string($record['id'] ?? null) ? $record['id'] : '#' . $n++;
            $latest[$id] = [$variant, (float) $record['value']];
        }

        $values = array_fill_keys(array_keys($config->all()[$experiment]['variants']), []);
        foreach ($latest as [$variant, $value]) {
            $values[$variant][] = $value;
        }

        return $values;
    }
}
