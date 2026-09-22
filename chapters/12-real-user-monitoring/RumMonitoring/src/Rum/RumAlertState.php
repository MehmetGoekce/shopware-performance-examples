<?php

declare(strict_types=1);

namespace RumMonitoring\Rum;

/**
 * Entscheidet, welche Bewertungen gemeldet werden: nur Wechsel.
 *
 * Eine Regression, die drei Tage anhaelt, meldet der Cron sonst alle 15 Minuten
 * erneut - 96 Mal am Tag, und nach dem zweiten Tag liest die Meldungen niemand
 * mehr. Deshalb: melden, wenn eine Metrik schlechter wird, wieder "good" wird
 * oder die Daten ausbleiben/wiederkommen. Metriken ohne genug Samples behalten
 * ihren alten Zustand.
 */
final class RumAlertState
{
    public const NO_DATA = 'keine-daten';

    /**
     * @param array<string, string> $previous Zustand des letzten erfolgreichen Laufs
     * @param array<string, string> $current  Bewertung dieses Laufs (nur Metriken mit genug Samples)
     *
     * @return list<string> Metriken, deren Zustand gemeldet werden muss
     */
    public static function changes(array $previous, array $current, bool $repeat = false): array
    {
        $changed = [];
        foreach ($current as $metric => $level) {
            $before = $previous[$metric] ?? 'good';

            if ($repeat ? $level !== 'good' : $level !== $before) {
                $changed[] = $metric;
            }
        }

        return $changed;
    }

    /**
     * @return array<string, string>
     */
    public static function load(string $file): array
    {
        if (!is_file($file)) {
            return [];
        }

        $data = json_decode((string) file_get_contents($file), true);

        return \is_array($data) ? array_filter($data, 'is_string') : [];
    }

    /**
     * @param array<string, string> $state
     */
    public static function save(string $file, array $state): void
    {
        file_put_contents($file . '.part', json_encode($state, \JSON_PRETTY_PRINT | \JSON_THROW_ON_ERROR));
        rename($file . '.part', $file);
    }
}
