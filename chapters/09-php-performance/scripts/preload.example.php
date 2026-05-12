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
 *   2. Pfade in php.ini eintragen:
 *        opcache.preload = /var/www/shopware/preload.php
 *        opcache.preload_user = www-data
 *   3. Syntax-Check:
 *        php -l /var/www/shopware/preload.php
 *   4. FPM reload:
 *        sudo systemctl reload php8.3-fpm
 *   5. Verifikation:
 *        php -r 'print_r(opcache_get_status()["preload_statistics"]);'
 *
 * Quelle: https://www.php.net/manual/en/opcache.preloading.php
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
// 2. Strategie A (Default): gesamten Symfony- und Doctrine-Tree
//    preloaden. Defensive Pattern: Test-Files werden ausgeschlossen,
//    weil diese Top-Level-Code ausfuehren und Preload abbrechen koennten.
// ---------------------------------------------------------------------
$preloadDirs = [
    __DIR__ . '/vendor/symfony',
    __DIR__ . '/vendor/doctrine',
    // Optional und vorsichtig hinzufuegen:
    //   __DIR__ . '/vendor/shopware/core'
    // -> nur preloaden, wenn Sie sicher sind, dass kein Plugin
    //    Klassen-Hooks zur Compile-Zeit registriert.
];

foreach ($preloadDirs as $dir) {
    if (! is_dir($dir)) {
        continue;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS)
    );
    $phpFiles = new RegexIterator(
        $iterator,
        '/(?<!Test)\.php$/i',
        RecursiveRegexIterator::GET_MATCH
    );

    foreach ($phpFiles as $file) {
        try {
            opcache_compile_file($file[0]);
        } catch (Throwable $e) {
            // Einzelne problematische Files werden geskipt,
            // damit der FPM-Master nicht abbricht.
            error_log("preload: skipping {$file[0]} ({$e->getMessage()})");
        }
    }
}

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
