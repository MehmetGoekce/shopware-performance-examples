<?php
/**
 * OPcache-Status fuer Monitoring (gehaertet, Companion).
 *
 * Begleitend zu Buch-Kapitel 9 ("Shop-Performance in 30 Tagen", 2nd Edition).
 *
 * Empfohlenes Setup:
 *   1. Ablage AUSSERHALB von public/ (z.B. /var/www/shopware/private/opcache-status.php),
 *      damit das Script nicht direkt via HTTP erreichbar ist. Wenn ein HTTP-Endpoint
 *      gebraucht wird, ueber dedizierte Nginx-Location mit `internal;` ausliefern.
 *   2. Zugriff via CLI (`php /var/www/shopware/private/opcache-status.php`) ist
 *      immer am sichersten und reicht fuer Cron / Monitoring-Agents.
 *   3. Falls HTTP-Zugriff zwingend noetig:
 *        - HTTP-Basic-Auth (zwingend) - Credentials kommen aus Env-Vars,
 *          niemals hardcoden, niemals committen.
 *        - REMOTE_ADDR-Whitelist als zweite Schicht. ACHTUNG: hinter CDN/Reverse-
 *          Proxy ist REMOTE_ADDR die Proxy-IP - dann via X-Forwarded-For
 *          mit trusted_proxies-Logik, oder bei Cloudflare ueber den
 *          CF-Connecting-IP-Header mit Cloudflare-IP-Range-Validierung.
 *
 * Quelle: https://www.php.net/manual/en/opcache.preloading.php
 */

declare(strict_types=1);

// ---------------------------------------------------------------------
// SICHERHEIT (HTTP-SAPI): Wenn ueber HTTP aufgerufen, mehrschichtig pruefen.
// CLI-Aufrufe (Cron, manuelle Diagnose) ueberspringen die Pruefung automatisch.
// ---------------------------------------------------------------------
if (PHP_SAPI !== 'cli') {

    // 1) HTTP-Basic-Auth (Primary). Credentials aus Env-Vars.
    $expectedUser = getenv('OPCACHE_STATUS_USER') ?: '';
    $expectedPass = getenv('OPCACHE_STATUS_PASS') ?: '';

    if ($expectedUser === '' || $expectedPass === '') {
        http_response_code(503);
        exit("OPCACHE_STATUS_USER / OPCACHE_STATUS_PASS env vars not set.\n");
    }

    $providedUser = $_SERVER['PHP_AUTH_USER'] ?? '';
    $providedPass = $_SERVER['PHP_AUTH_PW']   ?? '';

    if (! hash_equals($expectedUser, $providedUser) ||
        ! hash_equals($expectedPass, $providedPass)) {
        header('WWW-Authenticate: Basic realm="OPcache Status"');
        http_response_code(401);
        exit('Unauthorized');
    }

    // 2) IP-Whitelist (Secondary). REMOTE_ADDR ist hinter CDN/Reverse-Proxy
    //    NICHT zuverlaessig - dort die Trusted-Proxies-Konfiguration des
    //    Web-Frameworks / Reverse-Proxys nutzen statt $_SERVER['REMOTE_ADDR'].
    $allowedIps   = ['127.0.0.1', '::1'];
    $remoteAddr   = $_SERVER['REMOTE_ADDR'] ?? '';
    if (! in_array($remoteAddr, $allowedIps, true)) {
        http_response_code(403);
        exit('Forbidden');
    }
}

$status = opcache_get_status(false);
$config = opcache_get_configuration();

if (! $status) {
    echo "OPcache ist NICHT aktiviert!\n";
    exit(1);
}

$memoryUsed    = $status['memory_usage']['used_memory'];
$memoryFree    = $status['memory_usage']['free_memory'];
$memoryTotal   = $memoryUsed + $memoryFree;
$memoryPercent = round($memoryUsed / $memoryTotal * 100, 1);

$scriptsUsed    = $status['opcache_statistics']['num_cached_scripts'];
$scriptsMax     = $config['directives']['opcache.max_accelerated_files'];
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

// Preload-Status (PHP 7.4+)
if (isset($status['preload_statistics'])) {
    echo "Preload:\n";
    echo "  Klassen: " . number_format($status['preload_statistics']['classes']) . "\n";
    echo "  Funktionen: " . number_format($status['preload_statistics']['functions']) . "\n";
    echo "  Speicher: " . round($status['preload_statistics']['memory_consumption'] / 1024 / 1024, 1) . " MB\n\n";
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

if (! empty($warnings)) {
    echo "=== Warnungen ===\n";
    echo implode("\n", $warnings) . "\n";
} else {
    echo "=== Status: OK ===\n";
}
