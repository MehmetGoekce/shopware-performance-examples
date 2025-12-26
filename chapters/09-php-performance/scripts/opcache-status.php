<?php
/**
 * OPcache-Status fuer Monitoring
 *
 * Installation:
 *   cp opcache-status.php /var/www/shopware/public/
 *   curl http://localhost/opcache-status.php
 *
 * SICHERHEITSHINWEIS: Nur von localhost erreichbar machen!
 * In Production: IP-Restriction oder HTTP-Auth verwenden.
 */

declare(strict_types=1);

// Nur localhost erlauben
if ($_SERVER['REMOTE_ADDR'] !== '127.0.0.1' &&
    $_SERVER['REMOTE_ADDR'] !== '::1') {
    http_response_code(403);
    exit('Forbidden');
}

$status = opcache_get_status(false);
$config = opcache_get_configuration();

if (!$status) {
    echo "OPcache ist NICHT aktiviert!\n";
    exit(1);
}

$memoryUsed = $status['memory_usage']['used_memory'];
$memoryFree = $status['memory_usage']['free_memory'];
$memoryTotal = $memoryUsed + $memoryFree;
$memoryPercent = round($memoryUsed / $memoryTotal * 100, 1);

$scriptsUsed = $status['opcache_statistics']['num_cached_scripts'];
$scriptsMax = $config['directives']['opcache.max_accelerated_files'];
$scriptsPercent = round($scriptsUsed / $scriptsMax * 100, 1);

$hitRate = round($status['opcache_statistics']['opcache_hit_rate'], 2);

echo "=== OPcache Status ===\n\n";

echo "Speicher:\n";
echo "  Verwendet: " . round($memoryUsed / 1024 / 1024, 1) . " MB ({$memoryPercent}%)\n";
echo "  Frei: " . round($memoryFree / 1024 / 1024, 1) . " MB\n";
echo "  Gesamt: " . round($memoryTotal / 1024 / 1024, 1) . " MB\n\n";

echo "Skripte:\n";
echo "  Gecached: {$scriptsUsed} ({$scriptsPercent}%)\n";
echo "  Maximum: {$scriptsMax}\n\n";

echo "Performance:\n";
echo "  Hit Rate: {$hitRate}%\n";
echo "  Hits: " . number_format($status['opcache_statistics']['hits']) . "\n";
echo "  Misses: " . number_format($status['opcache_statistics']['misses']) . "\n\n";

// JIT-Status (PHP 8.0+)
if (isset($status['jit'])) {
    echo "JIT:\n";
    echo "  Aktiviert: " . ($status['jit']['enabled'] ? 'Ja' : 'Nein') . "\n";
    echo "  On: " . ($status['jit']['on'] ? 'Ja' : 'Nein') . "\n";
    echo "  Buffer Size: " . round($status['jit']['buffer_size'] / 1024 / 1024, 1) . " MB\n";
    echo "  Buffer Used: " . round($status['jit']['buffer_used'] / 1024 / 1024, 1) . " MB\n\n";
}

// Warnungen
$warnings = [];

if ($memoryPercent > 90) {
    $warnings[] = "WARNUNG: Speicher bei {$memoryPercent}% - opcache.memory_consumption erhoehen!";
}

if ($scriptsPercent > 90) {
    $warnings[] = "WARNUNG: Skript-Limit bei {$scriptsPercent}% - opcache.max_accelerated_files erhoehen!";
}

if ($hitRate < 95) {
    $warnings[] = "WARNUNG: Hit Rate nur {$hitRate}% - validate_timestamps=0 setzen?";
}

if (!empty($warnings)) {
    echo "=== Warnungen ===\n";
    echo implode("\n", $warnings) . "\n";
} else {
    echo "=== Status: OK ===\n";
}
