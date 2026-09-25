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

@test "die OPcache-Vorlage nennt die gemessene Dateizahl und laesst die Reihe offen" {
    # MEM-286: Dieselbe Dateizahl stand an fuenf Stellen verschieden da
    # (14177, 14.200, 14400, 14.400). Gemessen in dockware/dev:6.6.10.6 mit den
    # beiden Demo-Plugins: 14177, davon 14160 unter vendor/ (ohne var/).
    # MEM-294: Die Reihe endet nicht bei 130987 - gemessen 262237 und 524521.
    tr '\n' ' ' < "$CONFIG/99-shopware-opcache.ini" | sed 's/ *; */ /g' > "$BATS_TEST_TMPDIR/k"
    run grep -qF '14177 PHP-Dateien, davon 14160 unter vendor/' "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -qF '130987, 262237, 524521 und so fort' "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -qE '14\.?(200|400)' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -ne 0 ]
}

@test "die OPcache-Vorlage begruendet log_verbosity_level nicht mit der JIT-Warnung" {
    # MEM-284: Die JIT-Warnung (pcov/Xdebug) erscheint bei 0, 1 und 2 gleich.
    # Stufe 2 zeigt OPcaches eigene Warnungen, u. a. zu ungueltigen Werten.
    tr '\n' ' ' < "$CONFIG/99-shopware-opcache.ini" | sed 's/ *; */ /g' > "$BATS_TEST_TMPDIR/k"
    run grep -qF 'darunter die Meldung, dass JIT' "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
    run grep -qF 'must be set between 1 and 50' "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -cE '^opcache\.log_verbosity_level=2$' "$CONFIG/99-shopware-opcache.ini"
    [ "$output" -eq 1 ]
}

@test "die OPcache-Vorlage laesst enable_cli aus" {
    run grep -cE '^opcache\.enable_cli=0$' "$CONFIG/99-shopware-opcache.ini"
    [ "$output" -eq 1 ]
}

# Kopfkommentar als Fliesstext: ';' weg, Zeilen zu einem Strom verbunden.
# Noetig, weil die Prosa umbrochen ist - ein zeilenweises grep trifft sie nie.
# Gleiche Hilfsfunktion wie in pool-template-drift.bats.
fliesstext() {
    grep '^[[:space:]]*;' "$1" \
        | sed 's/^[[:space:]]*;[[:space:]]*//' \
        | tr '\n' ' ' \
        | tr -s '[:space:]' ' '
}

# --- MEM-282: diese Datei ist die kanonische OPcache-Vorlage ----------------
#
# Bis September 2026 lag OPcache doppelt vor: hier und in
# chapters/22-haeufigste-probleme/config/php-opcache.ini, beide mit derselben
# Zieldatei conf.d/99-shopware-opcache.ini. Die folgenden Zusicherungen
# standen deshalb in common-problems-scripts.bats und gelten jetzt hier.

@test "es gibt genau eine OPcache-Vorlage im ganzen Companion" {
    # Grundregel 33: die Behauptung "es gibt nur eine" braucht ihr eigenes
    # Gate. Ohne das kehrt die zweite Vorlage beim naechsten Kapitel zurueck.
    # Die Ausnahme gilt dem EINEN Pfad, nicht dem Dateinamen: eine gleichnamige
    # Datei in einem anderen Kapitel waere genau die Rueckkehr der Doppelung.
    kanonisch="chapters/09-php-performance/config/99-shopware-opcache.ini"
    [ -f "$kanonisch" ]
    gefunden=""
    for f in $(find chapters -type f \( -name '*.ini' -o -name '*.conf' -o -name '*.sh' \)); do
        [ "$f" = "$kanonisch" ] && continue
        # Direkte Direktive oder der Pool-Weg php_value[opcache.*].
        if grep -qE '^[[:space:]]*(opcache\.[a-z_]+[[:space:]]*=|php_(admin_)?value\[opcache\.)' "$f"; then
            gefunden="$gefunden $f"
        fi
    done
    [ -z "$gefunden" ] || {
        echo "weitere Datei(en) mit opcache.*-Direktiven:$gefunden"
        return 1
    }
}

@test "die OPcache-Vorlage nennt 99-shopware-opcache.ini als Ziel, nicht 10-opcache.ini" {
    # Regressionstest zu MEM-279: 10-opcache.ini ist auf Debian/Ubuntu der
    # Symlink der Distribution und traegt als einziger zend_extension=opcache.so.
    # Die Vorlage DARF den Namen nennen - aber nur warnend, nie als Zielpfad.
    run grep -q 'conf.d/99-shopware-opcache.ini' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    run grep -nE '^;[[:space:]]+sudo cp .*conf\.d/10-opcache\.ini' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -ne 0 ]
    run grep -q 'NICHT nach 10-opcache.ini kopieren' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
}

@test "die OPcache-Vorlage setzt kein fast_shutdown" {
    # Regressionstest zu F111: opcache.fast_shutdown gibt es seit PHP 7.2
    # nicht mehr.
    run bash -c "grep -vE '^[[:space:]]*;' $CONFIG/99-shopware-opcache.ini | grep -nE 'fast_shutdown'"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "die OPcache-Vorlage empfiehlt keinen CLI-Reset nach dem Deploy" {
    # Regressionstest zu F112: "php -r opcache_reset()" und "cache:clear"
    # erreichen den FPM-OPcache nicht - und die Datei setzt enable_cli=0.
    # Die Datei darf den Irrtum benennen, aber nicht empfehlen.
    fliesstext "$CONFIG/99-shopware-opcache.ini" > "$BATS_TEST_TMPDIR/k"
    run grep -qF "erreichen den FPM-OPcache NICHT" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -q 'systemctl reload php8.3-fpm' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
}

@test "die OPcache-Vorlage behauptet nicht, eine 0600-Datei werde uebergangen" {
    # Regressionstest zu MEM-280: Gemessen (Ubuntu 24.04, PHP 8.3.6) gilt eine
    # root-eigene 0600-Datei in conf.d sehr wohl - der FPM-Master liest conf.d
    # als root, bevor er die Worker auf www-data herunterstuft. Still ist nicht
    # das Laden, sondern die Kontrolle mit "php-fpm -i" als unprivilegierter
    # Benutzer.
    fliesstext "$CONFIG/99-shopware-opcache.ini" > "$BATS_TEST_TMPDIR/k"
    run grep -qF 'die Werte gelten einfach nicht' "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
    run grep -qF 'wird NICHT uebergangen' "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    # Der Messbeleg steht mit in der Datei, nicht nur die Behauptung.
    run grep -q 'opcache.memory_consumption=333' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    # chmod 644 bleibt die Empfehlung - nur die Begruendung ist eine andere.
    run grep -q 'chmod 644' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
}

@test "die OPcache-Vorlage warnt im JIT-Block vor pcov und Xdebug" {
    # Regressionstest zu MEM-278: PHP schaltet den JIT ab, sobald eine
    # Erweiterung zend_execute_ex() ueberschreibt. ini_get() meldet trotzdem
    # weiter den konfigurierten Wert.
    run grep -q 'zend_execute_ex()' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    run grep -qF "opcache_get_status(false)['jit']['enabled']" "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    # Die Bedingung muss die aktive Einstellung nennen, nicht bloss "geladen":
    # mit xdebug.mode=off laeuft der JIT.
    run grep -q 'pcov.enabled=1' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    run grep -q 'xdebug.mode=off' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
}

@test "die OPcache-Vorlage nennt den stillen Fall ohne jit_buffer_size" {
    # T7: opcache.jit=tracing ohne Buffer laeuft nicht, und es gibt dazu an
    # keiner der drei Stellen eine Meldung - der wirklich stille Fall.
    # Die auskommentierte Direktive selbst, nicht die Prosa darueber: ein
    # blosses grep auf den Namen trifft schon den erklaerenden Satz.
    run grep -qE '^;[[:space:]]*opcache\.jit_buffer_size=100M$' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    run grep -qE '^;[[:space:]]*opcache\.jit=1255$' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    fliesstext "$CONFIG/99-shopware-opcache.ini" > "$BATS_TEST_TMPDIR/k"
    run grep -qF "Die Vorgabe des Buffers ist 0" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -qF "dann gibt es GAR KEINE Meldung" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
}

@test "die OPcache-Vorlage verortet die JIT-Warnung nicht im error_log" {
    # MEM-283, T5: gemessen landet die Zeile weder im error_log des Pools noch
    # im globalen FPM-Log, sondern auf stderr des Masters - mit der Unit der
    # Distribution (--nodaemonize, Type=notify) also im journal.
    fliesstext "$CONFIG/99-shopware-opcache.ini" > "$BATS_TEST_TMPDIR/k"
    run grep -qiF "steht nur im Error-Log" "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
    run grep -qF "sondern auf stderr des FPM-Masters" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -q 'journalctl -u php8.3-fpm' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    # Review-Fund: die Zeile traegt unter FPM ein Praefix, ein grep auf
    # "^PHP Warning" findet sie deshalb nicht.
    run grep -qF 'NOTICE: PHP message: ' "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
}

@test "die zwei Werte, die der Kopf als Opfer der Drift nennt, stehen wirklich drin" {
    # Grundregel 33: Der Kopfkommentar behauptet, der Zusammenstoss habe
    # max_wasted_percentage 10 -> 5 und log_verbosity_level 2 -> 1 gekostet
    # (gemessen, T3). Ohne Gate veraltet diese Aussage beim naechsten Eingriff
    # genauso wie das "es ist dieselbe Datei" davor.
    run grep -qE '^opcache\.max_wasted_percentage=10$' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    run grep -qE '^opcache\.log_verbosity_level=2$' "$CONFIG/99-shopware-opcache.ini"
    [ "$status" -eq 0 ]
    fliesstext "$CONFIG/99-shopware-opcache.ini" > "$BATS_TEST_TMPDIR/k"
    run grep -qF 'max_wasted_percentage 10 -> 5 und log_verbosity_level' "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
}

@test "die OPcache-Vorlage begruendet den Vorrang nicht mit der hoeheren Nummer" {
    # T11: conf.d ist zeichenkettensortiert. Gemessen auf Ubuntu 24.04 gewann
    # 99-a.ini gegen 100-b.ini. Der Rat des Buchs (99 gegen 10) stimmt, die
    # Begruendung "eine Datei mit hoeherer Nummer gewinnt" nicht.
    fliesstext "$CONFIG/99-shopware-opcache.ini" > "$BATS_TEST_TMPDIR/k"
    run grep -qiF "hoeherer Nummer" "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
    run grep -qF "Ordnung ist dabei die der ZEICHENKETTEN" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -qF "99-a.ini gewinnt gegen 100-b.ini" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
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

@test "der vHost hat aktive Locations fuer Status und Ping auf dem Loopback" {
    # Ohne sie landet /fpm-status per try_files in der Anwendung. MEM-289:
    # Der alte Test griff eine auskommentierte Zeile in nginx-php-fpm.conf
    # und waere auch ohne die Bloecke gruen geblieben. Seit MEM-290 liegt
    # der vHost nur noch in Anhang C; gezaehlt werden nur aktive Zeilen.
    # Review MEM-290: gezaehlt wird im Loopback-Server, nicht in der ganzen
    # Datei - sonst bliebe der Test gruen, wenn die Status-Location in den
    # oeffentlichen 443-Server rutscht. Port 8081, weil Kapitel 6 Varnish
    # das Backend auf 127.0.0.1:8080 suchen laesst.
    local vhost="./chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
    grep -v '^[[:space:]]*#' "$vhost" | awk '
        /^server \{/ { inb=1; blk="" }
        inb { blk = blk $0 "\n" }
        /^\}/ && inb { inb=0; if (blk ~ /listen 127\.0\.0\.1:8081;/) print blk > "/dev/stderr"; else print blk }
    ' > "$BATS_TEST_TMPDIR/andere" 2> "$BATS_TEST_TMPDIR/loopback"
    run grep -cE '^[[:space:]]*location = /fpm-status \{' "$BATS_TEST_TMPDIR/loopback"
    [ "$output" -eq 1 ]
    run grep -cE '^[[:space:]]*location = /fpm-ping \{' "$BATS_TEST_TMPDIR/loopback"
    [ "$output" -eq 1 ]
    run grep -cE 'fastcgi_pass php-fpm-shopware;' "$BATS_TEST_TMPDIR/loopback"
    [ "$output" -eq 2 ]
    # Nirgends sonst: keine Status-Location in einem oeffentlichen Server.
    run grep -cE 'location = /fpm-(status|ping)' "$BATS_TEST_TMPDIR/andere"
    [ "$output" -eq 0 ]
    run grep -cE '127\.0\.0\.1:8080' "$vhost"
    [ "$output" -le 1 ]
}

@test "der vHost haelt keine Keepalive-Verbindungen zu FPM" {
    # Review MEM-290, nachgestellt: keepalive + fastcgi_keep_conn binden
    # FPM-Worker an offene Leerlaufverbindungen; mit 4 Kindern und 4
    # nginx-Workern warteten Requests 30 bis 90 s, ohne unter 1 s.
    local vhost="./chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
    run grep -cE '^[[:space:]]*(keepalive[[:space:]]|fastcgi_keep_conn[[:space:]]+on)' "$vhost"
    [ "$output" -eq 0 ]
}

@test "vHost und Pool staffeln die Timeouts 300 < 330 < 360" {
    local vhost="./chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
    run grep -cE '^[[:space:]]*fastcgi_read_timeout 360s;' "$vhost"
    [ "$output" -eq 1 ]
    run grep -cE '^request_terminate_timeout = 330$' "$CONFIG/shopware-fpm.conf"
    [ "$output" -eq 1 ]
}

@test "der vHost setzt kein internal im PHP-Location-Block" {
    run grep -cE '^[[:space:]]*internal;' \
        "./chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
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

@test "opcache-status meldet einen vollen Cache ueber cache_full" {
    # MEM-328: Mit max_accelerated_files=200 war der Cache voll, die
    # Skript-Auslastung stand bei 52 % und schlug nicht an. Nur cache_full
    # deckt Speicher und Schluessel gemeinsam ab.
    run grep -cxF "if (\$status['cache_full']) {" "$DIR/opcache-status.php"
    [ "$output" -eq 1 ]
}

@test "opcache-status raet bei niedriger Hit Rate nicht zu validate_timestamps" {
    # MEM-328: validate_timestamps=1 aenderte die Hit Rate nicht (93,30 gegen
    # 93,23 %). Der alte Rat zeigte auf den falschen Hebel.
    run grep -c "validate_timestamps=0 setzen" "$DIR/opcache-status.php"
    [ "$output" -eq 0 ]
}

@test "opcache-status ordnet die Hit Rate an der Laufzeit seit Poolstart ein" {
    # MEM-328: Die Zaehler beginnen nach jedem Reload bei 0. Ohne Laufzeit
    # schlaegt die Warnung nach jedem Deploy an und sagt nicht, warum.
    run grep -c "opcache_statistics'\]\['start_time'\]" "$DIR/opcache-status.php"
    [ "$output" -eq 1 ]
    run grep -c 'seit dem Start vor {\$uptimeText}' "$DIR/opcache-status.php"
    [ "$output" -eq 1 ]
}

@test "das Kapitel-Listing des Monitoring-Skripts hat genau einen PHP-Opener" {
    # Beim programmatischen Uebernehmen entstand ein zweites <?php - das
    # abgedruckte Listing war damit ein Parse-Error.
    run grep -c '^<?php$' "$DIR/opcache-status.php"
    [ "$output" -eq 1 ]
}

@test "OPcache-Vorlage und README nennen den Reparaturweg nach cp auf 10-opcache.ini" {
    # MEM-299: --reinstall repariert nichts (ucf behaelt die Datei, dazu
    # 20-opcache.ini). Die CI fuehrt die Befehle aus; hier steht, dass sie da sind.
    # Auf ganze Zeilen geankert: in der Vorlage als ';   sudo ...', im README
    # als nackter Befehl. Ein auskommentierter Befehl im README zaehlt nicht.
    local cp_='sudo cp /usr/share/php8.3-opcache/opcache/opcache.ini /etc/php/8.3/mods-available/opcache.ini'
    local rm_='sudo rm -f /etc/php/8.3/*/conf.d/20-opcache.ini'
    for c in "$cp_" "$rm_"; do
        run grep -qxF ";   $c" "$CONFIG/99-shopware-opcache.ini"
        [ "$status" -eq 0 ]
        run grep -qxF "$c" "$CONFIG/../README.md"
        [ "$status" -eq 0 ]
    done
}
