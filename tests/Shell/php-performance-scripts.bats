#!/usr/bin/env bats

# BATS tests for the chapter 9 PHP performance scripts.
#
# Geprueft wird, was ohne laufenden Shop pruefbar ist: Aufrufkonvention,
# Exit-Codes und die Rechen- bzw. Erkennungslogik, die in der alten Fassung
# falsche Ergebnisse geliefert hat. Alles, was einen echten Shopware-Shop
# braucht (die eigentliche Messung, die JIT-Laufzeitpruefung), gehoert in die
# Laufzeit-Tests des Kapitels, nicht hierher.

DIR="./chapters/09-php-performance/scripts"
CONFIG="./chapters/09-php-performance/config"

ALL_SCRIPTS=(php-fpm-memory.sh calculate-max-children.sh jit-benchmark.sh)

setup() {
    TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP"
}

# --- Aufrufkonvention -------------------------------------------------------

@test "alle Skripte zeigen mit --help eine Usage-Zeile" {
    for script in "${ALL_SCRIPTS[@]}"; do
        run bash "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "alle Skripte zeigen mit -h eine Usage-Zeile" {
    for script in "${ALL_SCRIPTS[@]}"; do
        run bash "$DIR/$script" -h
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "alle Skripte lehnen eine unbekannte Option mit Exit 1 ab" {
    for script in "${ALL_SCRIPTS[@]}"; do
        run bash "$DIR/$script" -Q
        [ "$status" -eq 1 ]
    done
}

@test "alle Skripte dokumentieren ihre Exit-Codes in der Hilfe" {
    for script in "${ALL_SCRIPTS[@]}"; do
        run bash "$DIR/$script" --help
        [[ "$output" == *"Exit-Codes:"* ]]
    done
}

# --- calculate-max-children.sh: Rechenlogik ---------------------------------

@test "calculate-max-children rechnet den Beispielserver des Buchs" {
    # 16384 - 3072 - 9216 = 4096 MB fuer PHP-FPM, davon 80 MB je Worker.
    run bash "$DIR/calculate-max-children.sh" -r 16384 -o 3072 -s 9216 -b 0 -w 80
    [ "$status" -eq 0 ]
    [[ "$output" == *"pm.max_children = 51"* ]]
    [[ "$output" == *"pm.start_servers = 10"* ]]
    [[ "$output" == *"pm.min_spare_servers = 5"* ]]
    [[ "$output" == *"pm.max_spare_servers = 20"* ]]
}

@test "calculate-max-children beruecksichtigt den Sicherheitspuffer" {
    # 4096 MB minus 20 Prozent = 3276 MB, davon 80 MB je Worker = 40.
    run bash "$DIR/calculate-max-children.sh" -r 16384 -o 3072 -s 9216 -b 20 -w 80
    [ "$status" -eq 0 ]
    [[ "$output" == *"pm.max_children = 40"* ]]
}

@test "calculate-max-children rechnet mit gemessenem Worker-RAM" {
    # Der warm gemessene Wert aus dem Kapitel: 4096 / 82 = 49.
    run bash "$DIR/calculate-max-children.sh" -r 16384 -o 3072 -s 9216 -b 0 -w 82
    [ "$status" -eq 0 ]
    [[ "$output" == *"pm.max_children = 49"* ]]
}

@test "calculate-max-children haelt die Untergrenze von 8 Workern" {
    run bash "$DIR/calculate-max-children.sh" -r 2048 -o 512 -s 1024 -b 0 -w 200
    [ "$status" -eq 0 ]
    [[ "$output" == *"pm.max_children = 8"* ]]
    [[ "$output" == *"Minimum"* ]]
}

@test "calculate-max-children meldet ein Budget, das nicht aufgeht, mit Exit 2" {
    run bash "$DIR/calculate-max-children.sh" -r 4096 -o 2048 -s 4096
    [ "$status" -eq 2 ]
    [[ "$output" == *"bleibt nichts uebrig"* ]]
}

@test "calculate-max-children weist unsinnige Eingaben mit Exit 1 ab" {
    run bash "$DIR/calculate-max-children.sh" -r abc
    [ "$status" -eq 1 ]

    run bash "$DIR/calculate-max-children.sh" -w 0
    [ "$status" -eq 1 ]

    run bash "$DIR/calculate-max-children.sh" -b 95
    [ "$status" -eq 1 ]
}

@test "calculate-max-children nennt keine Zahl ohne die Rundung auf die Vorlage" {
    run bash "$DIR/calculate-max-children.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shopware-fpm.conf traegt 50 ein"* ]]
}

# --- php-fpm-memory.sh: Prozesserkennung ------------------------------------

@test "php-fpm-memory meldet einen nicht existierenden Prozess mit Exit 1" {
    command -v pgrep > /dev/null || skip "pgrep nicht vorhanden"
    run bash "$DIR/php-fpm-memory.sh" -p php-fpm-existiert-nicht-9x
    [ "$status" -eq 1 ]
    [[ "$output" == *"Es laeuft kein Prozess"* ]]
}

@test "php-fpm-memory kodiert den Prozessnamen nicht fest auf php-fpm" {
    # Der Fehler der alten Fassung: `pgrep -x php-fpm` und `ps -C php-fpm`
    # finden auf Debian/Ubuntu nichts, weil der Prozess php-fpm8.3 heisst.
    run grep -c 'php-fpm8\.4 php-fpm8\.3 php-fpm8\.2 php-fpm' "$DIR/php-fpm-memory.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "php-fpm-memory zaehlt den Master-Prozess nicht als Worker" {
    # Der Master belegt rund 12 MB, ein warmer Worker 80 MB. Ohne Filter auf
    # 'pool' faellt der Durchschnitt und pm.max_children wird zu gross.
    run grep -c "grep 'pool'" "$DIR/php-fpm-memory.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- jit-benchmark.sh: Voraussetzungen --------------------------------------

@test "jit-benchmark bricht ohne Apache Benchmark mit Exit 1 ab" {
    # PATH laesst sich nicht leeren, ohne auch bash zu verlieren. Der Pfad ist
    # deshalb nur dort pruefbar, wo ab ohnehin fehlt - etwa im bats-Image.
    command -v ab > /dev/null && skip "ab ist installiert, Pfad nicht erreichbar"
    run bash "$DIR/jit-benchmark.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Apache Benchmark"* ]]
}

@test "jit-benchmark verlangt Root-Rechte" {
    [ "$EUID" -ne 0 ] || skip "Test laeuft als root - der Pfad ist dann nicht erreichbar"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    chmod +x "$TMP/bin/ab"
    run env PATH="$TMP/bin:$PATH" bash "$DIR/jit-benchmark.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Root-Rechte"* ]]
}

@test "jit-benchmark bricht bei fehlender OPcache-Datei mit Exit 1 ab" {
    [ "$EUID" -eq 0 ] || skip "braucht Root, sonst greift die Root-Pruefung zuerst"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    chmod +x "$TMP/bin/ab"
    run env PATH="$TMP/bin:$PATH" bash "$DIR/jit-benchmark.sh" -i "$TMP/gibtsnicht.ini"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht gefunden"* ]]
}

@test "jit-benchmark lehnt eine gecachte URL mit Exit 3 ab" {
    [ "$EUID" -eq 0 ] || skip "braucht Root, sonst greift die Root-Pruefung zuerst"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    # curl-Stub: antwortet wie Shopware auf einer gecachten Seite.
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/sh
printf 'HTTP/1.1 200 OK\r\nAge: 1655\r\nCache-Control: no-cache, private\r\n\r\n'
STUB
    printf '#!/bin/sh\necho "Zend OPcache"\n' > "$TMP/bin/php-fpm8.3"
    printf 'opcache.enable=1\n' > "$TMP/opcache.ini"
    chmod +x "$TMP/bin/ab" "$TMP/bin/curl" "$TMP/bin/php-fpm8.3"
    run env PATH="$TMP/bin:$PATH" bash "$DIR/jit-benchmark.sh" -i "$TMP/opcache.ini" -u http://example.test/
    [ "$status" -eq 3 ]
    [[ "$output" == *"HTTP-Cache"* ]]
}

@test "jit-benchmark akzeptiert no-cache NICHT als ungecacht" {
    # Shopware schickt auf den CACHEBAREN Seiten 'no-cache, private'.
    # Eine Pruefung, die no-cache durchlaesst, misst den HTTP-Cache.
    [ "$EUID" -eq 0 ] || skip "braucht Root, sonst greift die Root-Pruefung zuerst"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/sh
printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\n\r\n'
STUB
    printf '#!/bin/sh\necho "Zend OPcache"\n' > "$TMP/bin/php-fpm8.3"
    printf 'opcache.enable=1\n' > "$TMP/opcache.ini"
    chmod +x "$TMP/bin/ab" "$TMP/bin/curl" "$TMP/bin/php-fpm8.3"
    run env PATH="$TMP/bin:$PATH" bash "$DIR/jit-benchmark.sh" -i "$TMP/opcache.ini" -u http://example.test/
    [ "$status" -eq 3 ]
    [[ "$output" == *"no-store"* ]]
}

@test "jit-benchmark laesst eine no-store-Route durch" {
    [ "$EUID" -eq 0 ] || skip "braucht Root, sonst greift die Root-Pruefung zuerst"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/sh
printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store, private\r\n\r\n'
STUB
    # php-fpm-Stub ohne blockierende Erweiterung, Neustart als No-Op.
    printf '#!/bin/sh\necho "Zend OPcache"\n' > "$TMP/bin/php-fpm8.3"
    printf 'opcache.enable=1\n' > "$TMP/opcache.ini"
    chmod +x "$TMP/bin/ab" "$TMP/bin/curl" "$TMP/bin/php-fpm8.3"
    run env PATH="$TMP/bin:$PATH" FPM_RESTART_CMD="true" \
        bash "$DIR/jit-benchmark.sh" -i "$TMP/opcache.ini" -u http://example.test/account/login -r 1
    # Die Messung selbst liefert mit dem ab-Stub keinen Wert; entscheidend
    # ist, dass die Vorpruefungen die Route durchlassen.
    [[ "$output" != *"gecacht"* ]]
    [[ "$output" != *"HTTP-Cache"* ]]
}

@test "jit-benchmark erkennt blockierende Erweiterungen" {
    [ "$EUID" -eq 0 ] || skip "braucht Root, sonst greift die Root-Pruefung zuerst"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    printf '#!/bin/sh\nprintf "Zend OPcache\\npcov\\n"\n' > "$TMP/bin/php-fpm8.3"
    printf 'opcache.enable=1\n' > "$TMP/opcache.ini"
    chmod +x "$TMP/bin/ab" "$TMP/bin/php-fpm8.3"
    run env PATH="$TMP/bin:$PATH" bash "$DIR/jit-benchmark.sh" -i "$TMP/opcache.ini"
    [ "$status" -eq 2 ]
    [[ "$output" == *"pcov"* ]]
}

# --- Konfigurationsvorlagen -------------------------------------------------

@test "die OPcache-Vorlage warnt vor dem Zielpfad 10-opcache.ini" {
    run grep -c '10-opcache.ini' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "die OPcache-Vorlage schaltet JIT nicht ein" {
    run grep -cE '^[[:space:]]*opcache\.jit[[:space:]]*=' "$CONFIG/99-shopware-opcache.ini"
    [ "$output" -eq 0 ]
}

@test "die OPcache-Vorlage nennt einen Wert aus der Rundungsreihe" {
    # 50000 wuerde still zu 65407 werden - die Vorlage traegt den wirksamen
    # Wert direkt ein.
    run grep -cE '^opcache\.max_accelerated_files=32531$' "$CONFIG/99-shopware-opcache.ini"
    [ "$output" -eq 1 ]
}

@test "die OPcache-Vorlage laesst enable_cli aus" {
    run grep -cE '^opcache\.enable_cli=0$' "$CONFIG/99-shopware-opcache.ini"
    [ "$output" -eq 1 ]
}

@test "die php.ini-Vorlage setzt realpath_cache_size nicht auf den Default" {
    # 4096K ist seit PHP 7.0.16 der Vorgabewert - die Zeile aendert nichts
    # und behauptete frueher, der Default sei 4K.
    run grep -cE '^[[:space:]]*realpath_cache_size' "$CONFIG/99-shopware.ini"
    [ "$output" -eq 0 ]
}

@test "die Pool-Vorlage staffelt die Timeouts hinter max_execution_time" {
    run grep -cE '^request_terminate_timeout = 330$' "$CONFIG/shopware-fpm.conf"
    [ "$output" -eq 1 ]
    run grep -cE '^php_value\[max_execution_time\] = 300$' "$CONFIG/shopware-fpm.conf"
    [ "$output" -eq 1 ]
}

@test "die Pool-Vorlage weist auf das anzulegende Logverzeichnis hin" {
    # Fehlt es, startet PHP-FPM nicht.
    run grep -c 'mkdir -p /var/log/php-fpm' "$CONFIG/shopware-fpm.conf"
    [ "$output" -ge 1 ]
}

@test "die nginx-Vorlage enthaelt eine eigene Location fuer die Statusseite" {
    # Ohne sie landet /fpm-status per try_files in der Anwendung.
    run grep -c 'location = /fpm-status' "$CONFIG/nginx-php-fpm.conf"
    [ "$output" -ge 1 ]
}

@test "die nginx-Vorlage setzt kein internal im PHP-Location-Block" {
    run grep -cE '^[[:space:]]*internal;' "$CONFIG/nginx-php-fpm.conf"
    [ "$output" -eq 0 ]
}

@test "das Preload-Skript nutzt den Iterator-Schluessel statt des Treffertexts" {
    # $match[0] ist bei GET_MATCH der getroffene Text '.php', nicht der Pfad.
    # Mit ihm scheitert opcache_compile_file() an jeder einzelnen Datei.
    run grep -c 'as \$path => \$match' "$DIR/preload.example.php"
    [ "$output" -ge 1 ]

    run grep -c 'opcache_compile_file(\$path)' "$DIR/preload.example.php"
    [ "$output" -ge 1 ]
}

@test "das Preload-Skript verweist nicht auf die CLI als Verifikation" {
    # `php -r '...preload_statistics...'` meldet "inaktiv", waehrend FPM
    # laengst preloadet.
    run grep -cE "php -r .*preload_statistics" "$DIR/preload.example.php"
    [ "$output" -eq 0 ]
}

# --- Befunde der Review-Runde -----------------------------------------------

@test "jit-benchmark weist unsinnige Zahlenargumente mit Exit 1 ab" {
    for bad in "-n abc" "-n 0" "-c 0" "-c x" "-r 0" "-r abc"; do
        # shellcheck disable=SC2086
        run bash "$DIR/jit-benchmark.sh" $bad
        [ "$status" -eq 1 ]
        [[ "$output" == *"ganze Zahl groesser 0"* ]]
    done
}

@test "jit-benchmark lehnt weniger Requests als Verbindungen ab" {
    run bash "$DIR/jit-benchmark.sh" -n 5 -c 10
    [ "$status" -eq 1 ]
    [[ "$output" == *"mindestens so gross"* ]]
}

@test "jit-benchmark meldet eine nicht vorhandene PHP-Version" {
    # Ohne diese Pruefung liefert php-fpm<version> -m nichts, die Blocker-Liste
    # bleibt leer und das Skript meldet "sauber" fuer ein Binary, das fehlt.
    [ "$EUID" -eq 0 ] || skip "braucht Root, sonst greift die Root-Pruefung zuerst"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ab"
    chmod +x "$TMP/bin/ab"
    printf 'opcache.enable=1\n' > "$TMP/o.ini"
    run env PATH="$TMP/bin:$PATH" bash "$DIR/jit-benchmark.sh" -i "$TMP/o.ini" -v 9.9
    [ "$status" -eq 1 ]
    [[ "$output" == *"php-fpm9.9 nicht gefunden"* ]]
}

@test "opcache-status liest das wirksame Maximum, nicht den eingetragenen Wert" {
    # opcache_get_configuration() meldet 50000, wirksam sind 65407.
    run grep -c "opcache_statistics'\]\['max_cached_keys'\]" "$DIR/opcache-status.php"
    [ "$output" -ge 1 ]
}

@test "opcache-status greift nicht auf den nicht existierenden jit-Schluessel zu" {
    # opcache_get_status()['jit'] kennt buffer_size und buffer_free,
    # kein buffer_used - der Zugriff erzeugte eine Warning und zeigte 0 MB.
    run grep -c "buffer_used'\]" "$DIR/opcache-status.php"
    [ "$output" -eq 0 ]
}

@test "opcache-status zaehlt die Preload-Listen, statt sie zu formatieren" {
    # classes/functions/scripts sind Namenslisten. number_format() darauf ist
    # ein TypeError und brach das Skript ab, sobald Preloading aktiv war.
    run grep -cE "number_format\(\\\$(status|preload)\[?'?(preload_statistics)?'?\]?\['(classes|functions|scripts)'\]\)" "$DIR/opcache-status.php"
    [ "$output" -eq 0 ]

    run grep -c "number_format(count(" "$DIR/opcache-status.php"
    [ "$output" -ge 3 ]
}

@test "das Kapitel-Listing des Monitoring-Skripts hat genau einen PHP-Opener" {
    # Beim programmatischen Uebernehmen entstand ein zweites <?php - das
    # abgedruckte Listing war damit ein Parse-Error.
    run grep -c '^<?php$' "$DIR/opcache-status.php"
    [ "$output" -eq 1 ]
}
