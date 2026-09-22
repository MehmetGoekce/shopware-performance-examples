<?php

declare(strict_types=1);

/*
 * Error Budget je Core Web Vital aus den RUM-Logs von Kapitel 12.
 *
 * Usage: php error-budget.php <shopware-verzeichnis> [--days=28] [--min-samples=100]
 *
 * Liest <shopware-verzeichnis>/var/log/rum-*.log mit den Klassen des
 * installierten Plugins (custom/plugins/RumMonitoring) und rechnet mit
 * ../src/PerformanceBudgetService.php. Braucht nur PHP, keinen Shopware-Kernel.
 *
 * Exit-Codes: 0 = keine bewertete Metrik rot, 1 = mindestens eine Metrik rot,
 *             2 = Aufruf-, Pfad- oder Rechtefehler, 3 = keine Metrik bewertbar
 * Metriken unter --min-samples stehen in der Zeile "Ohne Bewertung".
 *
 * 28 Tage = Zeitfenster des Chrome UX Report (collectionPeriod der CrUX API).
 * Mehr als 29 Tage deckt das Plugin nicht ab: Monolog behaelt 30 Tagesdateien.
 * Speicher: rund 130 MB je Million Seitenaufrufe und Metrik (die CLI-php.ini
 * von Debian/Ubuntu setzt memory_limit = -1).
 */

use PerformanceKultur\PerformanceBudgetService;
use RumMonitoring\Rum\RumLogReader;

$usage = 'Usage: php error-budget.php <shopware-verzeichnis> [--days=28] [--min-samples=100]';

$shopDir = null;
$days = '28';
$minSamples = '100';

foreach (array_slice($argv, 1) as $arg) {
    if ($arg === '-h' || $arg === '--help') {
        echo $usage, "\n";
        exit(0);
    } elseif (str_starts_with($arg, '--days=')) {
        $days = substr($arg, 7);
    } elseif (str_starts_with($arg, '--min-samples=')) {
        $minSamples = substr($arg, 14);
    } elseif (!str_starts_with($arg, '-') && $shopDir === null) {
        $shopDir = rtrim($arg, '/');
    } else {
        fwrite(STDERR, "Unbekanntes Argument: $arg\n$usage\n");
        exit(2);
    }
}

$days = filter_var($days, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
$minSamples = filter_var($minSamples, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);

if ($shopDir === null || $days === false || $minSamples === false) {
    fwrite(STDERR, "$usage\n--days und --min-samples brauchen eine ganze Zahl >= 1\n");
    exit(2);
}

$rumDir = $shopDir . '/custom/plugins/RumMonitoring/src/Rum';
$logDir = $shopDir . '/var/log';

foreach ([$rumDir . '/RumLogReader.php', $rumDir . '/RumStatistics.php'] as $file) {
    if (!is_file($file)) {
        fwrite(STDERR, "Nicht gefunden: $file (Plugin RumMonitoring aus Kapitel 12 installiert?)\n");
        exit(2);
    }
    require_once $file;
}
require_once __DIR__ . '/../src/PerformanceBudgetService.php';

if (!is_dir($logDir) || !is_readable($logDir)) {
    fwrite(STDERR, "Nicht gefunden oder nicht lesbar: $logDir\n");
    exit(2);
}

// Eine nicht lesbare Datei wuerde sonst still als "keine Daten" zaehlen
$logFiles = glob($logDir . '/rum-*.log') ?: [];
foreach ($logFiles as $file) {
    if (!is_readable($file)) {
        fwrite(STDERR, "Nicht lesbar: $file (als Benutzer mit Leserecht auf var/log aufrufen)\n");
        exit(2);
    }
}
if ($logFiles === []) {
    fwrite(STDERR, "Keine rum-*.log in $logDir (Plugin aktiv, schon Beacons angekommen?)\n");
}

$since = new DateTimeImmutable(sprintf('-%d days', $days));
$budget = PerformanceBudgetService::calculate((new RumLogReader($logDir))->read($since), $minSamples);
$overall = PerformanceBudgetService::overall($budget);

printf(
    "Error Budget seit %s (%d Tage, SLO p75 <= Schwelle, Budget 25 %% der Seitenaufrufe)\n\n",
    $since->format('Y-m-d H:i T'),
    $days,
);
printf("%-7s %14s %14s %11s %8s  %s\n", 'Metrik', 'Seitenaufrufe', 'ueber Schwelle', 'verbraucht', 'uebrig', 'Stufe');

foreach ($budget as $metric => $row) {
    printf(
        "%-7s %14d %14d %11s %8s  %s\n",
        $metric,
        $row['samples'],
        $row['over'],
        $row['used_percent'] === null ? '-' : sprintf('%.1f %%', $row['used_percent']),
        $row['remaining_percent'] === null ? '-' : sprintf('%.1f %%', $row['remaining_percent']),
        $row['policy'] === 'no-data' ? sprintf('zu wenig Daten (< %d)', $minSamples) : $row['policy'],
    );
}

printf("\nGesamt: %s\n", $overall === 'no-data' ? 'zu wenig Daten' : $overall);

$unrated = PerformanceBudgetService::unrated($budget);
if ($overall !== 'no-data' && $unrated !== []) {
    printf("Ohne Bewertung (unter %d Seitenaufrufen): %s\n", $minSamples, implode(', ', $unrated));
}

exit(match ($overall) {
    'red' => 1,
    'no-data' => 3,
    default => 0,
});
