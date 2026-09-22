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
     * Der Log-Processor schreibt die Variante in jede Zeile eines Besuchers mit
     * Cookie, auch auf Seiten ausserhalb des Experiments. Deshalb nach Route filtern.
     *
     * @param iterable<array<string, mixed>> $records Log-Kontexte in Log-Reihenfolge
     * @param list<string>|null $routes nur diese Routen (null = alle)
     *
     * @return array<string, list<float>> Variante => Werte, in der Reihenfolge der Konfiguration
     */
    public static function valuesByVariant(
        iterable $records,
        ExperimentConfig $config,
        string $experiment,
        string $metric,
        ?string $device = null,
        ?array $routes = null,
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
            if ($routes !== null && !\in_array($record['route'] ?? null, $routes, true)) {
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
