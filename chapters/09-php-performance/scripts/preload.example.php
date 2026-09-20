<?php

/**
 * preload.example.php — OPcache-Preload-Template fuer Shopware 6.6 (Companion).
 *
 * Begleitend zu Buch-Kapitel 9 ("Shop-Performance in 30 Tagen", 2nd Edition).
 *
 * Vor Einsatz anpassen:
 *   1. Diese Datei nach /var/www/shopware/preload.php kopieren
 *      (NICHT in public/ ablegen - Preload-Files duerfen nicht via HTTP
 *      erreichbar sein).
 *   2. Pfade eintragen - in eine EIGENE Datei in conf.d, nicht in
 *      10-opcache.ini. Dieser Name ist auf Debian und Ubuntu der Symlink der
 *      Distribution, der als einziger `zend_extension=opcache.so` traegt; wer
 *      ihn ueberschreibt, schaltet OPcache komplett ab:
 *        /etc/php/8.3/fpm/conf.d/99-shopware-opcache.ini
 *          opcache.preload = /var/www/shopware/preload.php
 *          opcache.preload_user = www-data
 *   3. Syntax-Check:
 *        php -l /var/www/shopware/preload.php
 *   4. FPM reload:
 *        sudo systemctl reload php8.3-fpm
 *   5. Verifikation - MUSS ueber die FPM-SAPI laufen. `php -r ...` beantwortet
 *      die Frage nicht: Die CLI hat ihren eigenen OPcache und meldet
 *      "preloading inaktiv", waehrend FPM laengst preloadet. Legen Sie
 *      stattdessen kurzzeitig ein Skript im Webroot ab, rufen Sie es ueber
 *      HTTP auf und loeschen Sie es wieder:
 *        <?php print_r(opcache_get_status(false)['preload_statistics'] ?? 'inaktiv');
 *      Oder ueber die FastCGI-Schnittstelle:
 *        cachetool opcache:status --fcgi=/run/php/php8.3-fpm-shopware.sock
 *
 * Gemessen an Shopware 6.6.10.6 (Dockware, Demo-Daten) mit den beiden
 * Verzeichnissen unten: 4306 Dateien kompiliert, 2985 Klassen, 123 Funktionen,
 * 4324 Skripte, 31,2 MB, rund 2,4 s zusaetzliche Startzeit je FPM-Reload.
 *
 * Die 31 MB gehen ZUSAETZLICH von opcache.memory_consumption ab - bei 256 MB
 * ist das gut ein Achtel des Caches, bevor der erste Request kommt.
 *
 * @see https://www.php.net/manual/en/opcache.preloading.php
 */

declare(strict_types=1);

// ---------------------------------------------------------------------
// 1. Composer-Autoloader laden, damit Klassen-Aufloesung funktioniert.
//    __DIR__ zeigt auf das Shopware-Root (NICHT public/).
// ---------------------------------------------------------------------
$autoload = __DIR__ . '/vendor/autoload.php';
if (! file_exists($autoload)) {
    fwrite(STDERR, "Preload aborted: composer-autoload not found at {$autoload}\n");
    return;
}
require $autoload;

// ---------------------------------------------------------------------
// 2. Strategie A (Default): Symfony- und Doctrine-Tree preloaden.
//    Test-Files werden ausgeschlossen, weil sie Top-Level-Code ausfuehren
//    koennen.
// ---------------------------------------------------------------------
$preloadDirs = [
    __DIR__ . '/vendor/symfony',
    __DIR__ . '/vendor/doctrine',
    // Optional und vorsichtig hinzufuegen:
    //   __DIR__ . '/vendor/shopware/core'
    // -> nur preloaden, wenn Sie sicher sind, dass kein Plugin
    //    Klassen-Hooks zur Compile-Zeit registriert.
];

$compiled = 0;
$skipped  = 0;

foreach ($preloadDirs as $dir) {
    if (! is_dir($dir)) {
        continue;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS)
    );

    // WICHTIG: Der Pfad steht im SCHLUESSEL, nicht im Wert.
    //
    // RegexIterator mit GET_MATCH ersetzt den Wert durch das Ergebnis von
    // preg_match(). Bei dem Muster unten ist $match[0] deshalb der getroffene
    // Text ".php" - und opcache_compile_file('.php') scheitert lautlos an
    // jeder einzelnen Datei. Der vollstaendige Pfad bleibt der Schluessel des
    // Iterators, also iterieren wir ueber $path => $match.
    $phpFiles = new RegexIterator(
        $iterator,
        '/(?<!Test)\.php$/i',
        RecursiveRegexIterator::GET_MATCH
    );

    foreach ($phpFiles as $path => $match) {
        try {
            if (opcache_compile_file($path)) {
                ++$compiled;
            } else {
                ++$skipped;
            }
        } catch (Throwable $e) {
            // Einzelne problematische Files werden geskipt,
            // damit der FPM-Master nicht abbricht.
            ++$skipped;
            error_log("preload: skipping {$path} ({$e->getMessage()})");
        }
    }
}

// Eine Zeile ins Log, damit ein fehlgeschlagener Preload auffaellt. Stehen
// hier 0 kompilierte Dateien, ist etwas mit den Pfaden falsch - genau so sah
// der Fehler oben aus.
error_log(sprintf('preload: %d Dateien kompiliert, %d uebersprungen', $compiled, $skipped));

// ---------------------------------------------------------------------
// 3. Strategie B (Alternative): gezielter Bootstrap-Preload.
//    Kleiner, vorhersagbarer, schneller. Aktivieren statt Strategie A,
//    wenn Sie nur die heissesten Klassen aus Profiling-Output
//    (Blackfire / Tideways) preloaden moechten.
// ---------------------------------------------------------------------
//
// $bootstrap = [
//     __DIR__ . '/vendor/symfony/http-kernel/Kernel.php',
//     __DIR__ . '/vendor/symfony/dependency-injection/Container.php',
//     __DIR__ . '/vendor/symfony/http-foundation/Request.php',
//     __DIR__ . '/vendor/symfony/http-foundation/Response.php',
// ];
// foreach ($bootstrap as $file) {
//     if (file_exists($file)) {
//         opcache_compile_file($file);
//     }
// }
