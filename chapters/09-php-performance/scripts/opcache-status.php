<?php
/**
 * OPcache-Status fuer Monitoring (gehaertet, Companion).
 *
 * Begleitend zu Buch-Kapitel 9 ("Shop-Performance in 30 Tagen", 2nd Edition).
 *
 * Empfohlenes Setup:
 *   1. Ablage AUSSERHALB von public/ (z.B. /var/www/shopware/private/opcache-status.php),
 *      damit das Script nicht direkt via HTTP erreichbar ist. Wenn ein
 *      HTTP-Endpoint gebraucht wird, dann ueber eine eigene Location im
 *      Loopback-Server 127.0.0.1:8081 des vHosts aus Anhang C, zusaetzlich
 *      mit Quell-IP-Beschraenkung:
 *        location = /opcache-status {
 *            allow 127.0.0.1; deny all;
 *            include fastcgi_params;
 *            fastcgi_param SCRIPT_FILENAME /var/www/shopware/private/opcache-status.php;
 *            fastcgi_pass php-fpm-shopware;
 *        }
 *      NICHT `internal;` verwenden - damit ist die Seite auch fuer den
 *      Monitoring-Agenten nicht erreichbar, jeder Aufruf endet auf 404.
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
 * WICHTIG: Ueber die CLI aufgerufen misst dieses Skript den OPcache DER CLI -
 * und der ist ab Werk aus (opcache.enable_cli=0) bzw. lebt nur fuer die Dauer
 * des Aufrufs. Die Zahlen des FPM-Pools bekommt man nur ueber einen echten
 * HTTP-Request auf diese Datei oder ueber
 *   cachetool opcache:status --fcgi=/run/php/php8.3-fpm-shopware.sock
 *
 * @see https://www.php.net/manual/en/function.opcache-get-status.php
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

$scriptsUsed = $status['opcache_statistics']['num_cached_scripts'];

// Das Limit gilt fuer Schluessel, nicht fuer Skripte: Eine Datei, die per
// include/require ueber einen nicht kanonischen Pfad eingebunden wird
// (Composer: __DIR__ . '/..'), belegt einen zweiten Schluessel. Gemessen im warmen Shopware-Pool: 4552
// Schluessel fuer 2315 Skripte. Die Auslastung deshalb aus den Schluesseln rechnen.
$keysUsed = $status['opcache_statistics']['num_cached_keys'];

// Das WIRKSAME Maximum, nicht das eingetragene. PHP rundet
// opcache.max_accelerated_files auf die naechste Zahl einer festen Reihe auf
// (... 32531, 65407, 130987, 262237, ...), und opcache_get_configuration() meldet
// weiterhin stur den Eingabewert. Aus 50000 werden 65407 - wer gegen 50000
// rechnet, meldet eine Auslastung, die es nicht gibt.
$scriptsMax     = $status['opcache_statistics']['max_cached_keys'];
$scriptsEntered = $config['directives']['opcache.max_accelerated_files'];
$keysPercent    = round($keysUsed / $scriptsMax * 100, 1);

$hitRate = round($status['opcache_statistics']['opcache_hit_rate'], 2);

// Hits und Misses zaehlen seit dem Start des Pools oder dem letzten Reset.
// Nach jedem Neustart oder Reload - also nach jedem Deploy - und nach
// opcache_reset() beginnt die Rate bei 0 und steigt erst mit dem Verkehr.
// Ein Reset setzt nur last_restart_time neu, start_time bleibt stehen.
// Gemessen (Dockware 6.6.10.6, PHP 8.3.23, nach cache:clear): 93 % nach
// einem Durchgang ueber 23 Seiten, 99 % zwischen 500 und 1000 Requests.
$since      = max($status['opcache_statistics']['start_time'], $status['opcache_statistics']['last_restart_time']);
$uptime     = max(0, time() - $since);
$uptimeText = intdiv($uptime, 3600) . ' h ' . intdiv($uptime % 3600, 60) . ' min';

echo "=== OPcache Status ===\n\n";

echo "Speicher:\n";
echo "  Verwendet: " . round($memoryUsed / 1024 / 1024, 1) . " MB ({$memoryPercent}%)\n";
echo "  Frei: " . round($memoryFree / 1024 / 1024, 1) . " MB\n";
echo "  Gesamt: " . round($memoryTotal / 1024 / 1024, 1) . " MB\n\n";

echo "Skripte:\n";
echo "  Gecached: {$scriptsUsed}\n";
echo "  Schluessel: {$keysUsed} ({$keysPercent}%)\n";
echo "  Maximum: {$scriptsMax}";
if ($scriptsMax !== $scriptsEntered) {
    echo " (eingetragen: {$scriptsEntered}, aufgerundet)";
}
echo "\n\n";

echo "Performance:\n";
echo "  Hit Rate: {$hitRate}%\n";
echo "  Hits: " . number_format($status['opcache_statistics']['hits']) . "\n";
echo "  Misses: " . number_format($status['opcache_statistics']['misses']) . "\n";
echo "  Zaehlt seit: {$uptimeText} (Start oder letzter Reset)\n";
echo "  Cache voll: " . ($status['cache_full'] ? 'Ja' : 'Nein') . "\n\n";

// JIT-Status (PHP 8.0+)
if (isset($status['jit'])) {
    echo "JIT:\n";
    echo "  Aktiviert: " . ($status['jit']['enabled'] ? 'Ja' : 'Nein') . "\n";
    echo "  On: " . ($status['jit']['on'] ? 'Ja' : 'Nein') . "\n";
    // opcache_get_status()['jit'] kennt buffer_size und buffer_free -
    // einen Schluessel buffer_used gibt es nicht.
    $jitUsed = $status['jit']['buffer_size'] - $status['jit']['buffer_free'];
    echo "  Buffer Size: " . round($status['jit']['buffer_size'] / 1024 / 1024, 1) . " MB\n";
    echo "  Buffer Used: " . round($jitUsed / 1024 / 1024, 1) . " MB\n\n";
}

// Preload-Status (PHP 7.4+)
if (isset($status['preload_statistics'])) {
    // classes, functions und scripts sind LISTEN von Namen, keine Zaehler.
    // number_format() darauf ist ein TypeError und bricht das Skript ab.
    $preload = $status['preload_statistics'];
    echo "Preload:\n";
    echo "  Klassen: " . number_format(count($preload['classes'])) . "\n";
    echo "  Funktionen: " . number_format(count($preload['functions'])) . "\n";
    echo "  Skripte: " . number_format(count($preload['scripts'])) . "\n";
    echo "  Speicher: " . round($preload['memory_consumption'] / 1024 / 1024, 1) . " MB\n\n";
}

// Warnungen
$warnings = [];

if ($memoryPercent > 90) {
    $warnings[] = "WARNUNG: Speicher bei {$memoryPercent}% - opcache.memory_consumption erhoehen!";
}

if ($keysPercent > 90) {
    $warnings[] = "WARNUNG: Schluessel-Limit bei {$keysPercent}% - opcache.max_accelerated_files erhoehen!";
}

// cache_full deckt beide Grenzen ab, Speicher und Schluessel. Gemessen: Mit
// opcache.memory_consumption=32 blieb die Hit Rate bei 71 %.
if ($status['cache_full']) {
    $warnings[] = "WARNUNG: OPcache ist voll - neue Skripte werden nicht mehr gecacht. opcache.memory_consumption bzw. opcache.max_accelerated_files erhoehen!";
}

// validate_timestamps senkt die Hit Rate nicht: Eine unveraenderte Datei
// zaehlt auch mit Pruefung als Hit (gemessen: 93,30 % mit, 93,23 % ohne).
if ($hitRate < 95) {
    $warnings[] = "WARNUNG: Hit Rate nur {$hitRate}% seit {$uptimeText}. Kurz nach einem Neustart, Reload oder Reset ist das normal - spaeter erneut pruefen. Bleibt sie niedrig: Ist der Cache voll?";
}

if (! empty($warnings)) {
    echo "=== Warnungen ===\n";
    echo implode("\n", $warnings) . "\n";
} else {
    echo "=== Status: OK ===\n";
}
