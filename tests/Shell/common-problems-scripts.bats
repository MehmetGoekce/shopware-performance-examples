#!/usr/bin/env bats

# BATS tests for the chapter 22 diagnostic scripts.
#
# Was hier geprueft wird, ist bewusst das, was ohne laufenden Shop pruefbar
# ist: die Aufrufkonvention, die Exit-Codes und die Auswertungslogik, die in
# der Vergangenheit falsche Ergebnisse geliefert hat. Alles, was einen echten
# Shopware-Shop braucht, gehoert in die Laufzeit-Tests des Kapitels, nicht
# hierher.

DIR="./chapters/22-haeufigste-probleme/scripts"
CONFIG="./chapters/22-haeufigste-probleme/config"

ALL_SCRIPTS=(
    analyze-bundles.sh analyze-cronjobs.sh audit-plugins.sh audit-preconnects.sh
    audit-themes.sh check-cache-headers.sh check-cdn.sh check-compression.sh
    check-debug-mode.sh check-elasticsearch.sh check-http-cache.sh check-images.sh
    check-logs.sh check-opcache.sh check-render-blocking.sh detect-n1-queries.sh
    detect-sync-calls.sh diagnose-slow-queries.sh generate-report.sh profile-cart.sh
    run-all-diagnostics.sh test-session-lock.sh
)

setup() {
    [ -d "$DIR" ] || skip "Script directory not found: $DIR"
}

# Gibt eine Datei ohne Kommentarzeilen aus. Die korrigierten Skripte nennen
# die falschen Befehle absichtlich in ihren Kopfkommentaren, um davor zu
# warnen — ein Regressionstest darf darauf nicht anspringen.
code_only() {
    grep -vE '^[[:space:]]*#' "$@"
}


@test "alle Skripte sind vorhanden" {
    for s in "${ALL_SCRIPTS[@]}"; do
        [ -f "$DIR/$s" ] || {
            echo "fehlt: $s"
            return 1
        }
    done
}

@test "alle Skripte sind syntaktisch gueltig" {
    for s in "${ALL_SCRIPTS[@]}"; do
        run bash -n "$DIR/$s"
        [ "$status" -eq 0 ] || {
            echo "Syntaxfehler in $s: $output"
            return 1
        }
    done
}

@test "alle Skripte zeigen mit --help eine Usage-Zeile und enden mit 0" {
    for s in "${ALL_SCRIPTS[@]}"; do
        run bash "$DIR/$s" --help
        [ "$status" -eq 0 ] || {
            echo "$s: --help endete mit $status"
            return 1
        }
        [[ "$output" == *"Usage:"* ]] || {
            echo "$s: keine Usage-Zeile"
            return 1
        }
    done
}

@test "alle Skripte lehnen ein drittes Argument mit Exit 64 ab" {
    for s in "${ALL_SCRIPTS[@]}"; do
        run bash "$DIR/$s" a b c
        [ "$status" -eq 64 ] || {
            echo "$s: drittes Argument ergab Exit $status statt 64"
            return 1
        }
    done
}

@test "alle Skripte dokumentieren die einheitliche Aufrufkonvention" {
    # Regressionstest zu F87: acht Skripte nahmen frueher SHOP_PATH als $1,
    # waehrend run-all-diagnostics.sh $1 = SHOP_URL uebergibt.
    for s in "${ALL_SCRIPTS[@]}"; do
        run grep -q 'Usage: .* \[SHOP_URL\] \[SHOP_PATH\]' "$DIR/$s"
        [ "$status" -eq 0 ] || {
            echo "$s: Usage nennt nicht [SHOP_URL] [SHOP_PATH]"
            return 1
        }
    done
}

@test "kein Skript benutzt das Muster 'grep -c ... || echo 0'" {
    # Regressionstest zu F86: grep -c liefert bei null Treffern Exit 1,
    # das angehaengte echo macht die Variable zweizeilig und bricht jeden
    # arithmetischen Vergleich.
    run grep -rn 'grep -c[^|]*|| *echo' "$DIR"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "kein Skript benutzt bc" {
    # Regressionstest zu F85: test-session-lock.sh starb an "bc: command not found".
    run grep -rnE '(^|[^a-z])bc ' "$DIR"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "kein Skript ruft dbal:run-sql auf" {
    # Regressionstest zu F1: der Befehl existiert in Shopware 6 nicht.
    run grep -rn 'dbal:run-sql' "$DIR"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "kein Skript filtert die rule-Tabelle auf eine Spalte active" {
    # Regressionstest zu F2/F82: die Tabelle hat keine solche Spalte.
    run bash -c "code_only() { grep -vE '^[[:space:]]*#' \"\$@\"; }; code_only $DIR/*.sh | grep -niE 'FROM +.?rule.? +WHERE +active'"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "kein Skript empfiehlt theme:compile --keep-all oder theme:change mit zwei Argumenten" {
    # Regressionstest zu F4/F5: --keep-all existiert nicht, der Sales Channel
    # ist eine Option.
    # Gesucht ist der Aufruf, nicht die Erwaehnung: die korrigierten Skripte
    # nennen --keep-all absichtlich, um davor zu warnen.
    run bash -c "grep -vhE '^[[:space:]]*#' $DIR/*.sh | grep -nE 'theme:compile[^\n]*--keep-all'"
    [ "$status" -ne 0 ] || {
        echo "theme:compile --keep-all gefunden: $output"
        return 1
    }
    run bash -c "grep -vhE '^[[:space:]]*#' $DIR/*.sh | grep -nE 'theme:change +[A-Za-z]+ +[A-Za-z0-9]'"
    [ "$status" -ne 0 ] || {
        echo "theme:change mit zweitem Argument gefunden: $output"
        return 1
    }
}

@test "kein Skript und keine Vorlage nennt shopware.http_cache.enabled oder default_ttl" {
    # Regressionstest zu F78/T25: beide Keys existieren nicht und lassen den
    # Container-Build abbrechen.
    run grep -rnE '^\s*(enabled|default_ttl):' "$CONFIG/shopware-cache.yaml"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "keine Vorlage und kein Skript verlinkt die 404-URL performance-audit" {
    # Regressionstest zu F75.
    run grep -rn 'performance-audit' "$DIR" "$CONFIG" \
        ./chapters/22-haeufigste-probleme/README.md \
        ./chapters/22-haeufigste-probleme/QUICKSTART.md
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "run-all-diagnostics.sh verwirft stderr der Einzelskripte nicht" {
    # Regressionstest zu F88: mit 2>/dev/null wurde ein an einem Parse-Error
    # gestorbenes Skript als bestanden gezaehlt.
    run bash -c "grep -vE '^[[:space:]]*#' $DIR/run-all-diagnostics.sh | grep -n '2>/dev/null'"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "run-all-diagnostics.sh gibt keinen Prozent-Score aus" {
    run grep -niE 'performance score|SCORE=' "$DIR/run-all-diagnostics.sh"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

# curl-Stub fuer check-http-cache.sh. Je Aufruf eine Argumentzeile:
#   "200|Age: 0|Date: A"        ein Headerblock (Status|Header|Header ...)
#   "301|Age: 5#200|Date: A"    Weiterleitung: Bloecke durch "#" getrennt
#   "FAIL"                      curl scheitert (Exit 7)
# Jeder Block bekommt "Cache-Control: no-cache, private" dazu. Der Stub
# protokolliert Sekunde und Argumente jedes Aufrufs in $BATS_TEST_TMPDIR/calls.
http_cache_stub() {
    stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/responses"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
n_file="$BATS_TEST_TMPDIR/count"
n=$(( $(cat "$n_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$n_file"
echo "$(date +%s) $*" >> "$BATS_TEST_TMPDIR/calls"
line=$(sed -n "${n}p" "$BATS_TEST_TMPDIR/responses")
[[ "$line" == "FAIL" ]] && exit 7
IFS='#' read -ra blocks <<< "$line"
for block in "${blocks[@]}"; do
    IFS='|' read -ra hs <<< "$block"
    printf 'HTTP/1.1 %s X\r\nCache-Control: no-cache, private\r\n' "${hs[0]}"
    for h in "${hs[@]:1}"; do printf '%s\r\n' "$h"; done
    printf '\r\n'
done
STUB
    chmod +x "$stub_dir/curl"
    export BATS_TEST_TMPDIR
}

D1="Date: Wed, 23 Sep 2026 15:53:33 GMT"
D2="Date: Wed, 23 Sep 2026 15:53:35 GMT"

@test "check-http-cache.sh: Age waechst um die Pause, Date gleich = Treffer" {
    http_cache_stub "200|Age: 0|$D1" "200|Age: 2|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Der HTTP-Cache arbeitet"* ]]
    [[ "$output" == *"zeigt der Test nicht"* ]]
}

@test "check-http-cache.sh: warmer Cache (Treffer -> Treffer) ist ein Treffer" {
    http_cache_stub "200|Age: 100|$D1" "200|Age: 102|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Der HTTP-Cache arbeitet"* ]]
}

@test "check-http-cache.sh: ruft zweimal per GET mit -L ab, mindestens 2 s auseinander" {
    http_cache_stub "200|Age: 0|$D1" "200|Age: 2|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq 2 ]
    while read -r _ args; do
        [[ " $args " == *" -L "* ]]
        [[ " $args " != *" -I "* && " $args " != *" --head "* ]]
        [[ "$args" == *"http://example.test"* ]]
    done < "$BATS_TEST_TMPDIR/calls"
    t1=$(sed -n 1p "$BATS_TEST_TMPDIR/calls" | cut -d' ' -f1)
    t2=$(sed -n 2p "$BATS_TEST_TMPDIR/calls" | cut -d' ' -f1)
    [ $((t2 - t1)) -ge 2 ]
}

@test "check-http-cache.sh: zwei MISS mit Age 0 -> 1 sind kein Treffer (MEM-316)" {
    # Gemessen in dev: jeder Abruf ein MISS, 2 von 20 Laeufen zeigten 0 -> 1.
    http_cache_stub "200|Age: 0|$D1" "200|Age: 1|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
    [[ "$output" == *"nicht um die Pause gewachsen"* ]]
}

@test "check-http-cache.sh: abgeschalteter Cache mit ESI-Age (6.7) nennt die Env-Variable" {
    # Gemessen auf 6.7.2.2 mit SHOPWARE_HTTP_CACHE_ENABLED=0: Age 0 -> 0.
    http_cache_stub "200|Age: 0|$D1" "200|Age: 0|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" == *"SHOPWARE_HTTP_CACHE_ENABLED=0"* ]]
}

@test "check-http-cache.sh: Grenze - Zuwachs Pause-1 bei gleichem Date ist kein Treffer, sondern nicht entscheidbar" {
    # Gleiches Date = gespeicherte Kopie, aber Age nicht fortgeschrieben (MEM-325 Review B9)
    http_cache_stub "200|Age: 10|$D1" "200|Age: 11|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
    [[ "$output" == *"Date ist gleich geblieben, Age aber nicht um die Pause gewachsen (10 -> 11)"* ]]
}

@test "check-http-cache.sh: gleiches Date bei gesunkenem Age = nicht entscheidbar (ESI-Fragment neu gespeichert)" {
    http_cache_stub "200|Age: 30|$D1" "200|Age: 2|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
    [[ "$output" == *"Date ist gleich geblieben"* ]]
}

@test "check-http-cache.sh: no-store-Seite ist ein Aufruffehler (64), nicht nicht entscheidbar" {
    stub_dir="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stub_dir"
    printf '#!/bin/bash\nprintf "HTTP/1.1 200 X\\r\\nCache-Control: no-store, private\\r\\nAge: 4\\r\\n%s\\r\\n\\r\\n" "$D1"\n' > "$stub_dir/curl"
    chmod +x "$stub_dir/curl"
    D1="$D1" PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 64 ]
    [[ "$output" == *"bewusst nicht cachebar (no-store)"* ]]
}

@test "check-http-cache.sh: Trace stale-while-revalidate / stale-if-error = Treffer (veraltete Kopie aus dem Cache)" {
    for t in "stale-while-revalidate" "stale/stale-if-error"; do
        rm -f "$BATS_TEST_TMPDIR/count"
        http_cache_stub "200|Age: 0|$D1|X-Symfony-Cache: miss/store" "200|Age: 0|$D2|X-Symfony-Cache: $t"
        PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
        [ "$status" -eq 0 ]
    done
}

@test "check-http-cache.sh: Hinweis nicht entscheidbar nennt Apache mit mod_php" {
    http_cache_stub "200|Age: 4|$D1" "200|Age: 6|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
    [[ "$output" == *"Apache mit mod_php"* ]]
}

@test "check-http-cache.sh: ESI - Age waechst um die Pause, Date auch = nicht entscheidbar" {
    # Gemessen auf 6.7.2.2: /checkout/cart wird nie gecacht, traegt aber das
    # Age des gecachten Header-Fragments (0 -> 2 -> 4), Date wandert mit.
    http_cache_stub "200|Age: 0|$D1" "200|Age: 2|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
    [[ "$output" == *"KEIN Nachweis"* ]]
    [[ "$output" == *"trace_level: short"* ]]
    [[ "$output" == *"proxy_pass_header Date;"* ]]
}

@test "check-http-cache.sh: Age waechst, aber kein Date-Header = nicht entscheidbar" {
    http_cache_stub "200|Age: 0" "200|Age: 2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
    [[ "$output" == *"ohne Date-Header"* ]]
}

@test "check-http-cache.sh: Header ohne Leerzeichen nach dem Doppelpunkt werden gelesen" {
    http_cache_stub "200|age:0|date:Wed, 23 Sep 2026 15:53:33 GMT" "200|AGE:2|DATE:Wed, 23 Sep 2026 15:53:33 GMT"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Der HTTP-Cache arbeitet"* ]]
}

@test "check-http-cache.sh: Trace fresh beim 2. Abruf entscheidet, auch wenn Date wandert" {
    # Hinter einem Proxy, der Date neu setzt, ist der Trace der einzige Beleg.
    http_cache_stub "200|Age: 0|$D1|X-Symfony-Cache: miss/store" "200|Age: 2|$D2|X-Symfony-Cache: fresh"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Der HTTP-Cache arbeitet"* ]]
}

@test "check-http-cache.sh: Trace miss entscheidet, auch wenn Age und Date nach Treffer aussehen" {
    http_cache_stub "200|Age: 0|$D1|X-Symfony-Cache: GET /: miss, store" "200|Age: 2|$D1|X-Symfony-Cache: GET /: miss, store; GET /_esi/global/header: fresh"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
    [[ "$output" == *"Debug-Modus"* ]]
}

@test "check-http-cache.sh: Trace invalid ist kein Treffer" {
    http_cache_stub "200|Age: 0|$D1|X-Symfony-Cache: stale/invalid/store" "200|Age: 2|$D1|X-Symfony-Cache: stale/invalid/store"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
}

@test "check-http-cache.sh: Trace valid (Backend gefragt, 304) ist kein Treffer" {
    http_cache_stub "200|Age: 0|$D1|X-Symfony-Cache: stale/valid/store" "200|Age: 2|$D1|X-Symfony-Cache: stale/valid/store"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" != *"Der HTTP-Cache arbeitet"* ]]
}

@test "check-http-cache.sh: Age gesunken = kein Treffer, mit Hinweis auf Ablauf" {
    http_cache_stub "200|Age: 7000|$D1" "200|Age: 0|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" == *"Age gesunken"* ]]
}

@test "check-http-cache.sh: zwei MISS mit Age 1 -> 0 (Cache aus, 6.7) nennen die Env-Variable" {
    # Gemessen auf 6.7.2.2 mit SHOPWARE_HTTP_CACHE_ENABLED=0 direkt nach cache:clear.
    http_cache_stub "200|Age: 1|$D1" "200|Age: 0|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" == *"SHOPWARE_HTTP_CACHE_ENABLED=0"* ]]
}

@test "check-http-cache.sh: Age nur beim 2. Abruf = nicht entscheidbar" {
    http_cache_stub "200|$D1" "200|Age: 0|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
    [[ "$output" == *"Age nur bei einem"* ]]
}

@test "check-http-cache.sh meldet fehlenden Age-Header als Problem" {
    http_cache_stub "200|$D1" "200|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kein Age-Header"* ]]
}

@test "check-http-cache.sh: Age einer gecachten Weiterleitung zaehlt nicht fuer das Ziel" {
    http_cache_stub "301|Age: 10|$D1|Location: /de/#200|$D2" "301|Age: 12|$D1|Location: /de/#200|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" == *"weitergeleitet"* ]]
    [[ "$output" == *"Kein Age-Header"* ]]
}

@test "check-http-cache.sh: Ziel liefert 404 = Aufruffehler 64" {
    http_cache_stub "404|Age: 55|$D1" "404|Age: 55|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 64 ]
    [[ "$output" == *"HTTP 404"* ]]
}

@test "check-http-cache.sh: scheitert der 2. Abruf, endet es mit 69" {
    http_cache_stub "200|Age: 0|$D1" "FAIL"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 69 ]
}

@test "check-http-cache.sh: Abschnitt 4 liest auch .env.prod und .env.prod.local, in Symfonys Reihenfolge (MEM-325)" {
    # Gemessen (MEM-325 A1): =0 in .env.prod.local schaltet den Cache ab, grep .env .env.local zeigt 1.
    shop="$BATS_TEST_TMPDIR/shop"; mkdir -p "$shop"
    printf 'SHOPWARE_HTTP_CACHE_ENABLED=1\n' > "$shop/.env"
    printf 'SHOPWARE_HTTP_DEFAULT_TTL=600\n' > "$shop/.env.prod"
    printf 'SHOPWARE_HTTP_CACHE_ENABLED=0\n' > "$shop/.env.prod.local"
    http_cache_stub "200|$D1" "200|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test "$shop"
    [ "$status" -eq 1 ]
    [[ "$output" == *".env: SHOPWARE_HTTP_CACHE_ENABLED=1"*".env.prod: SHOPWARE_HTTP_DEFAULT_TTL=600"*".env.prod.local: SHOPWARE_HTTP_CACHE_ENABLED=0"* ]]
    [[ "$output" == *"Caches & Indizes"* ]]
}

@test "check-http-cache.sh: Abschnitt 4 - Reihenfolge .env, .env.local, .env.prod, .env.prod.local; export-Zeilen zaehlen" {
    shop="$BATS_TEST_TMPDIR/shop"; mkdir -p "$shop"
    printf 'SHOPWARE_HTTP_DEFAULT_TTL=100\n' > "$shop/.env"
    printf 'SHOPWARE_HTTP_DEFAULT_TTL=200\n' > "$shop/.env.local"
    printf 'export SHOPWARE_HTTP_DEFAULT_TTL=300\n' > "$shop/.env.prod"
    printf 'SHOPWARE_HTTP_DEFAULT_TTL=400\n' > "$shop/.env.prod.local"
    http_cache_stub "200|$D1" "200|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test "$shop"
    [[ "$output" == *"=100"*"=200"*"export SHOPWARE_HTTP_DEFAULT_TTL=300"*"=400"* ]]
}

@test "check-http-cache.sh: Abschnitt 4 warnt vor .env.local.php" {
    shop="$BATS_TEST_TMPDIR/shop"; mkdir -p "$shop"
    : > "$shop/.env"
    printf '<?php return [];\n' > "$shop/.env.local.php"
    http_cache_stub "200|$D1" "200|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test "$shop"
    [[ "$output" == *".env.local.php vorhanden"* ]]
}

@test "check-http-cache.sh: ohne .env-Eintrag nennt es die Umgebung des Webservers" {
    shop="$BATS_TEST_TMPDIR/shop"; mkdir -p "$shop"
    : > "$shop/.env"
    http_cache_stub "200|Age: 0|$D1" "200|Age: 0|$D2"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test "$shop"
    [[ "$output" == *"In keiner .env-Datei gesetzt"* ]]
    [[ "$output" == *"FPM env[]"* ]]
}

@test "check-http-cache.sh: Hinweise empfehlen debug:dotenv und die Administration statt grep .env .env.local" {
    for resp in "200|$D1" "200|Age: 0|$D1"; do
        rm -f "$BATS_TEST_TMPDIR/count"
        http_cache_stub "$resp" "${resp/$D1/$D2}"
        PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
        [ "$status" -eq 1 ]
        [[ "$output" == *"bin/console debug:dotenv SHOPWARE_HTTP"* ]]
        [[ "$output" == *"Einstellungen > System > Caches & Indizes"* ]]
        [[ "$output" != *".env .env.local"* ]]
    done
}

@test "check-http-cache.sh wertet no-cache, private nicht als Defekt" {
    # Regressionstest zu F41: eine gesunde Storefront antwortet genau so.
    http_cache_stub "200|Age: 5|$D1" "200|Age: 7|$D1"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Normalfall"* ]]
}

@test "analyze-cronjobs.sh erkennt relativen Pfad und fehlendes --no-wait" {
    cronfile="$BATS_TEST_TMPDIR/crontab"
    printf '0 3 * * * bin/console scheduled-task:run\n' > "$cronfile"
    CRONTAB_FILE="$cronfile" run bash "$DIR/analyze-cronjobs.sh" http://example.test /nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"Relativer Pfad"* ]]
    [[ "$output" == *"ohne --no-wait"* ]]
}

@test "analyze-cronjobs.sh akzeptiert eine korrekte Crontab-Zeile" {
    cronfile="$BATS_TEST_TMPDIR/crontab-ok"
    printf '*/5 * * * * cd /var/www/shop && /usr/bin/php bin/console scheduled-task:run --no-wait\n' > "$cronfile"
    CRONTAB_FILE="$cronfile" run bash "$DIR/analyze-cronjobs.sh" http://example.test /nonexistent
    [[ "$output" != *"Relativer Pfad"* ]]
    [[ "$output" != *"ohne --no-wait"* ]]
}

@test "config/logrotate.conf enthaelt copytruncate und keine ueberlappenden Muster" {
    # Regressionstest zu F90/T28.
    run grep -q 'copytruncate' "$CONFIG/logrotate.conf"
    [ "$status" -eq 0 ]

    # Aktive (nicht auskommentierte) Log-Muster einsammeln.
    patterns=$(grep -oE '^/[^ {]+\.log' "$CONFIG/logrotate.conf" || true)
    # Ein catch-all *.log neben spezifischeren Mustern ist genau die Kollision.
    if echo "$patterns" | grep -q '/\*\.log$'; then
        [ "$(echo "$patterns" | wc -l)" -eq 1 ] || {
            echo "catch-all *.log zusammen mit weiteren Mustern: $patterns"
            return 1
        }
    fi
}

@test "README und QUICKSTART behaupten nicht, eine conf.d-Datei werde uebergangen" {
    # MEM-280, hier als Review-Fund nachgezogen: Die Korrektur war bisher nur in
    # der kanonischen ini angekommen. Gemessen gilt eine root-eigene
    # 0600-Datei in conf.d - still ist nur die Kontrolle per "php-fpm -i".
    for f in "$CONFIG/../README.md" "$CONFIG/../QUICKSTART.md"; do
        strom="$(tr '\n' ' ' < "$f" | tr -s '[:space:]' ' ')"
        run grep -qF 'die Werte gelten einfach nicht' <<< "$strom"
        [ "$status" -ne 0 ]
        run grep -qF 'stillschweigend ignoriert' <<< "$strom"
        [ "$status" -ne 0 ]
    done
}

@test "QUICKSTART.md kopiert die OPcache-Vorlage nicht nach 10-opcache.ini" {
    # Regressionstest zu MEM-279: hier stand ein fertiges sudo-cp-Kommando,
    # das beim Leser OPcache komplett abgeschaltet haette.
    run grep -nE '^sudo (cp|chmod).*10-opcache\.ini' "$CONFIG/../QUICKSTART.md"
    [ "$status" -ne 0 ]
    run grep -q 'conf.d/99-shopware-opcache.ini' "$CONFIG/../QUICKSTART.md"
    [ "$status" -eq 0 ]
    # MEM-282: dieses Kapitel liefert keine eigene Vorlage mehr, es kopiert die
    # kanonische aus Kapitel 9.
    run grep -q '09-php-performance/config/99-shopware-opcache.ini' "$CONFIG/../QUICKSTART.md"
    [ "$status" -eq 0 ]
    run test -e "$CONFIG/php-opcache.ini"
    [ "$status" -ne 0 ]
}

@test "check-opcache.sh druckt 10-opcache.ini nicht als Zielpfad" {
    # Regressionstest zu MEM-279: das Skript laeuft genau dann, wenn OPcache
    # schon kaputt ist - der ausgegebene Vorschlag darf ihn nicht kaputt lassen.
    run grep -nE '^; /etc/php/.*conf\.d/10-opcache\.ini' "$DIR/check-opcache.sh"
    [ "$status" -ne 0 ]
    run grep -qE '^; /etc/php/.*conf\.d/99-shopware-opcache\.ini' "$DIR/check-opcache.sh"
    [ "$status" -eq 0 ]
}

@test "config/redis-session.yaml benutzt REDIS_SESSION_URL, nicht REDIS_URL" {
    # Regressionstest zu F19: REDIS_URL ist die Cache-Instanz.
    run grep -q "handler_id: '%env(REDIS_SESSION_URL)%'" "$CONFIG/redis-session.yaml"
    [ "$status" -eq 0 ]
    run grep -nE "handler_id: '%env\(REDIS_URL\)" "$CONFIG/redis-session.yaml"
    [ "$status" -ne 0 ]
}

@test "config/redis-session.yaml zeigt eine parsebare Sentinel-DSN" {
    # Regressionstest zu F72: die Form mit Schraegstrichen wirft
    # "Invalid Redis DSN.", Hosts gehoeren als host[...]-Parameter.
    run grep -qE 'REDIS_SESSION_URL=redis:\?host\[' "$CONFIG/redis-session.yaml"
    [ "$status" -eq 0 ]
    run grep -nE 'redis://[^ ]*,[^ ]*redis_sentinel' "$CONFIG/redis-session.yaml"
    [ "$status" -ne 0 ]
}


# --- Phase 5, Review-Funde ---------------------------------------------

@test "kein Skript behauptet ein 500er-Limit des RuleLoaders" {
    # Regressionstest zu F99: die 500 in RuleLoader.php sind die Seitengroesse
    # eines RepositoryIterator, keine Obergrenze. profile-cart.sh meldete
    # darauf eine Fehlfunktion, die es nicht gibt.
    run bash -c "code_only() { grep -vE '^[[:space:]]*#' \"\$@\"; }; \
        code_only $DIR/*.sh | grep -nE 'RULES_LOADED[^\n]*-ge 500'"
    [ "$status" -ne 0 ] || {
        echo "500er-Schwelle gefunden: $output"
        return 1
    }
    run grep -rn 'begrenzt auf 500' "$DIR"
    [ "$status" -ne 0 ] || {
        echo "Limit-Behauptung gefunden: $output"
        return 1
    }
}

@test "kein Skript und keine Vorlage empfiehlt REQUEST_FILENAME}.webp" {
    # Regressionstest zu F100: die Kurzform prueft auf "bild.jpg.webp" und
    # passt nicht zur Regel, die "bild.webp" ausliefert. Gesucht ist die
    # Empfehlung, nicht die Warnung davor — also ohne Kommentarzeilen.
    run bash -c "grep -vhE '^[[:space:]]*#' $CONFIG/apache-webp.conf \
        | grep -nF 'REQUEST_FILENAME}.webp'"
    [ "$status" -ne 0 ] || {
        echo "in der Vorlage gefunden: $output"
        return 1
    }
    # In check-images.sh steht die Kurzform nur als Warnung im Fliesstext.
    # Ein Fund waere eine Zeile, die NUR aus der Direktive besteht.
    run bash -c "grep -nE '^[[:space:]]*RewriteCond %\\{REQUEST_FILENAME\\}\\.webp -f[[:space:]]*$' $DIR/check-images.sh"
    [ "$status" -ne 0 ] || {
        echo "in check-images.sh als Direktive gefunden: $output"
        return 1
    }
    # Und die empfohlene Form muss dastehen.
    run grep -nF 'RewriteCond %1.webp -f' "$DIR/check-images.sh"
    [ "$status" -eq 0 ]
}

@test "check-debug-mode.sh erkennt APP_ENV=dev in .env.local.php" {
    # Regressionstest zu F101: .env.local.php schlaegt .env und .env.local.
    # Vorher meldete das Skript hier "korrekt konfiguriert", Exit 0.
    shop="$BATS_TEST_TMPDIR/shop"
    mkdir -p "$shop"
    printf 'APP_ENV=prod\nAPP_DEBUG=0\n' > "$shop/.env"
    printf "<?php\nreturn array (\n  'APP_ENV' => 'dev',\n);\n" > "$shop/.env.local.php"
    run bash "$DIR/check-debug-mode.sh" http://example.test "$shop"
    [ "$status" -eq 1 ]
    [[ "$output" == *".env.local.php"* ]]
}

@test "check-debug-mode.sh quittiert einen Pfad ohne env-Dateien mit 69" {
    # Regressionstest zu F101: ohne .env meldete das Skript vorher Exit 0.
    shop="$BATS_TEST_TMPDIR/leer"
    mkdir -p "$shop"
    run bash "$DIR/check-debug-mode.sh" http://example.test "$shop"
    [ "$status" -eq 69 ]
}

@test "check-debug-mode.sh prueft das Cache-Verzeichnis mit Hash-Suffix" {
    # Regressionstest zu F102: Shopware 6.6 legt var/cache/prod_h<hash> an;
    # die festen Pfade var/cache/dev und var/cache/prod trafen nie.
    run bash -c "grep -nE 'var/cache/(dev|prod)\"' $DIR/check-debug-mode.sh"
    [ "$status" -ne 0 ] || {
        echo "fester Cache-Pfad gefunden: $output"
        return 1
    }
    run grep -n 'compgen -G' "$DIR/check-debug-mode.sh"
    [ "$status" -eq 0 ]
}

@test "analyze-bundles.sh zaehlt nicht in einer Subshell" {
    # Regressionstest zu F103: "find ... | while read" erhoeht TOTAL_SIZE in
    # einer Subshell; der Wert ging verloren, und die Zusammenfassung meldete
    # eine Zahl, die nichts mit der Liste darueber zu tun hatte.
    run bash -c "grep -nE 'find[^\n]*\\| *while read' $DIR/analyze-bundles.sh"
    [ "$status" -ne 0 ] || {
        echo "Pipeline in eine while-Schleife gefunden: $output"
        return 1
    }
    run grep -nF 'done < <(find' "$DIR/analyze-bundles.sh"
    [ "$status" -eq 0 ]
}

@test "check-compression.sh behauptet nichts ueber uebersprungene Ressourcen" {
    # Regressionstest zu F104: ohne CSS/JS-URL im HTML meldete das Skript
    # "HTML, CSS und JavaScript werden komprimiert ausgeliefert", Exit 0.
    stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
for a in "$@"; do
    if [ "$a" = "-D" ]; then
        printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Encoding: gzip\r\n\r\n'
        exit 0
    fi
done
echo "<html><head></head><body>nichts</body></html>"
STUB
    chmod +x "$stub_dir/curl"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-compression.sh" http://example.test
    [ "$status" -ne 0 ]
    [[ "$output" != *"HTML, CSS und JavaScript werden komprimiert ausgeliefert"* ]]
}

@test "detect-sync-calls.sh liest den Timeout-Wert, nicht die Zeilennummer" {
    # Regressionstest zu F105: die erste Ziffernfolge der grep-Zeile war der
    # Pfad oder die Zeilennummer — aus "'timeout' => 5" wurde "1000s".
    # detect-sync-calls.sh filtert mit "grep --include" auf *.php. BusyBox-grep
    # kennt die Option nicht; dort ist der Test gegenstandslos.
    echo x > "$BATS_TEST_TMPDIR/probe.php"
    grep -rq --include='*.php' x "$BATS_TEST_TMPDIR" 2>/dev/null \
        || skip "grep ohne --include (BusyBox) — Skript setzt GNU-grep voraus"
    shop="$BATS_TEST_TMPDIR/shop2"
    mkdir -p "$shop/custom/plugins/Erp"
    printf "<?php\n\n\n\n\n\n\n\n\n\$c = ['timeout' => 5];\n" \
        > "$shop/custom/plugins/Erp/ErpClient.php"
    run bash "$DIR/detect-sync-calls.sh" http://example.test "$shop"
    [[ "$output" == *"ErpClient.php:10: 5s"* ]]
    [[ "$output" != *"Warnung: Timeout > 10s"* ]]
}

@test "check-cdn.sh meldet kein fehlendes CDN unter einem CDN-Header" {
    # Regressionstest zu F106: x-cache, x-cdn, x-vercel-cache und x-akamai-
    # setzten CDN_DETECTED nicht — die Ausgabe zeigte den Header und darunter
    # "Kein CDN erkannt".
    stub_dir="$BATS_TEST_TMPDIR/bin2"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
printf 'HTTP/1.1 200 OK\r\nX-Cache: HIT\r\nContent-Type: text/html\r\n\r\n'
STUB
    chmod +x "$stub_dir/curl"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-cdn.sh" http://example.test
    [[ "$output" != *"Kein CDN erkannt"* ]]
}

@test "audit-preconnects.sh findet einen Preconnect mit href vor rel" {
    # Regressionstest zu F107: das Muster verlangte rel vor href auf einer
    # Zeile. Shopware umbricht Link-Attribute, und die Reihenfolge ist frei.
    stub_dir="$BATS_TEST_TMPDIR/bin3"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
for a in "$@"; do
    if [ "$a" = "-D" ]; then printf 'HTTP/1.1 200 OK\r\n\r\n'; exit 0; fi
done
printf '%s\n' '<html><head>' '<link href="https://fonts.gstatic.com"' \
    '      rel="preconnect" crossorigin>' '</head><body></body></html>'
STUB
    chmod +x "$stub_dir/curl"
    PATH="$stub_dir:$PATH" run bash "$DIR/audit-preconnects.sh" http://example.test
    [[ "$output" == *"fonts.gstatic.com"* ]]
    [[ "$output" != *"fonts.gstatic.com (kein preconnect)"* ]]
}

@test "alle Skripte nennen als Default http://localhost, nicht https" {
    # Regressionstest zu F108: drei Skripte setzten https://localhost, obwohl
    # ihre Usage-Zeile http nennt — run-all reichte das an alle 20 weiter.
    run bash -c "grep -nF 'SHOP_URL=\"\${1:-https://localhost}\"' $DIR/*.sh"
    [ "$status" -ne 0 ] || {
        echo "https-Default gefunden: $output"
        return 1
    }
}

@test "run-all-diagnostics.sh kennt keinen dritten Exit-Code" {
    # Regressionstest zu F109: bei mehr als fuenf Funden lieferte das Skript
    # Exit 2, was in der Exit-Code-Tabelle nicht vorkommt.
    run bash -c "grep -vE '^[[:space:]]*#' $DIR/run-all-diagnostics.sh | grep -nE '^[[:space:]]*exit 2'"
    [ "$status" -ne 0 ] || {
        echo "exit 2 gefunden: $output"
        return 1
    }
}

@test "generate-report.sh entfernt ANSI-Sequenzen aus dem Markdown-Report" {
    # Regressionstest zu F110: der Report enthielt 6390 Farbcodes.
    run grep -n 'x1b' "$DIR/generate-report.sh"
    [ "$status" -eq 0 ]
}

@test "config/apache-compression.conf setzt keinen SetOutputFilter DEFLATE" {
    # Regressionstest zu F113: das komprimiert auch JPEG, PNG, PDF und ZIP
    # und macht die Typenliste darunter wirkungslos.
    run bash -c "grep -vE '^[[:space:]]*#' $CONFIG/apache-compression.conf | grep -nE 'SetOutputFilter +DEFLATE'"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "config/nginx-gzip.conf nennt keinen MIME-Typ application/xml+rss" {
    # Regressionstest zu F114: den Typ gibt es nicht, richtig ist
    # application/rss+xml.
    run grep -nF 'application/xml+rss' "$CONFIG/nginx-gzip.conf"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "config/shopware-cache.yaml setzt keinen Cache-Adapter" {
    # Regressionstest zu F115: config/packages/*.yaml wird alphabetisch
    # geladen — eine aktive framework.cache-Zeile haette einen bestehenden
    # Redis-Cache still auf das Dateisystem zurueckgeschaltet.
    run bash -c "grep -vE '^[[:space:]]*#' $CONFIG/shopware-cache.yaml | grep -nE '^[[:space:]]*(framework:|app: cache\.adapter)'"
    [ "$status" -ne 0 ] || {
        echo "gefunden: $output"
        return 1
    }
}

@test "detect-n1-queries.sh raet den Slow-Log-Pfad nicht" {
    # Regressionstest zu F116: /var/log/mysql/slow.log ist nicht der
    # Standardwert — MySQL schreibt nach <hostname>-slow.log im Datenverzeichnis.
    run bash -c "grep -vE '^[[:space:]]*#' $DIR/detect-n1-queries.sh | grep -nF '/var/log/mysql/slow.log'"
    [ "$status" -ne 0 ] || {
        echo "fester Pfad gefunden: $output"
        return 1
    }
    run grep -nF 'slow_query_log_file' "$DIR/detect-n1-queries.sh"
    [ "$status" -eq 0 ]
}

@test "die DATABASE_URL-Zerlegung haelt ein @ im Passwort aus" {
    # Regressionstest zu F117: "${DB_REST%%@*}" bricht am ersten @, und die
    # Prozentkodierung blieb stehen.
    for s in diagnose-slow-queries.sh profile-cart.sh audit-themes.sh detect-n1-queries.sh; do
        run bash -c "grep -nF 'DB_CRED=\"\${DB_REST%%@*}\"' $DIR/$s"
        [ "$status" -ne 0 ] || {
            echo "$s zerlegt am ersten @"
            return 1
        }
        run grep -nF 'urldecode' "$DIR/$s"
        [ "$status" -eq 0 ] || {
            echo "$s dekodiert die Prozentkodierung nicht"
            return 1
        }
    done
}

# --- MEM-293: check-opcache.sh sieht, was "php-fpm -i" nicht zeigt ---------

# Stub fuer php-fpm8.3: "-m" und "-i" aus Variablen, damit jeder Fall
# einzeln einstellbar ist. SCAN_DIR zeigt auf ein Testverzeichnis.
fpm_stub() {
    stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir" "$BATS_TEST_TMPDIR/conf.d"
    cat > "$stub_dir/php-fpm8.3" <<STUB
#!/usr/bin/env bash
case "\$1" in
  -m) printf '%s\\n' "\${STUB_MODULES:-Zend OPcache}" ;;
  -i) printf '%s\\n' \
        "Scan this dir for additional .ini files => $BATS_TEST_TMPDIR/conf.d" \
        "opcache.enable => On => On" \
        "opcache.memory_consumption => 256 => 256" \
        "opcache.interned_strings_buffer => 20 => 20" \
        "opcache.max_accelerated_files => 32531 => 32531" \
        "opcache.validate_timestamps => Off => Off" \
        "opcache.revalidate_freq => 0 => 0" ;;
esac
STUB
    chmod +x "$stub_dir/php-fpm8.3"
}

@test "check-opcache.sh erkennt eine nicht geladene Erweiterung statt still nichts zu melden" {
    fpm_stub
    STUB_MODULES="Core" PHP_FPM_BINARY="$stub_dir/php-fpm8.3" run bash "$DIR/check-opcache.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gar nicht geladen"* ]]
}

@test "check-opcache.sh bricht bei unlesbarer conf.d-Datei mit Exit 77 ab" {
    [ "$(id -u)" -ne 0 ] || skip "root liest jede Datei"
    fpm_stub
    echo 'opcache.enable=1' > "$BATS_TEST_TMPDIR/conf.d/99-x.ini"
    chmod 0 "$BATS_TEST_TMPDIR/conf.d/99-x.ini"
    PHP_FPM_BINARY="$stub_dir/php-fpm8.3" run bash "$DIR/check-opcache.sh"
    chmod 644 "$BATS_TEST_TMPDIR/conf.d/99-x.ini"
    [ "$status" -eq 77 ]
    [[ "$output" == *"99-x.ini"* ]]
    [[ "$output" != *"brauchbar konfiguriert"* ]]
}

# Stub fuer cgi-fcgi: gibt RT_LINE aus und merkt sich die Probe-Datei, damit
# der Test pruefen kann, dass das Skript sie wieder loescht. Review MEM-293:
# Ohne diesen Stub lief kein Test durch den Socket-Zweig, und eine Probe,
# die nur "=== false" prueft, blieb gruen.
cgi_stub() {
    cat > "$stub_dir/cgi-fcgi" <<'STUB'
#!/usr/bin/env bash
echo "$SCRIPT_FILENAME" > "$BATS_TEST_TMPDIR/probe-pfad"
[ -f "$SCRIPT_FILENAME" ] && echo ja > "$BATS_TEST_TMPDIR/probe-da"
printf 'Content-type: text/html\r\n\r\n%s\n' "$RT_LINE"
STUB
    chmod +x "$stub_dir/cgi-fcgi"
    : > "$BATS_TEST_TMPDIR/sock"
}

@test "check-opcache.sh meldet die Laufzeitmessung als uebersprungen, wenn der Socket fehlt" {
    fpm_stub
    cgi_stub
    PATH="$stub_dir:$PATH" FPM_SOCKET="$BATS_TEST_TMPDIR/gibt-es-nicht.sock" \
        PHP_FPM_BINARY="$stub_dir/php-fpm8.3" run bash "$DIR/check-opcache.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3. Laufzeit (echter Request)"* ]]
    [[ "$output" == *"gibt-es-nicht.sock fehlt"* ]]
}

@test "check-opcache.sh wertet opcache_enabled im Request aus und raeumt die Probe weg" {
    fpm_stub
    cgi_stub
    PATH="$stub_dir:$PATH" FPM_SOCKET="$BATS_TEST_TMPDIR/sock" RT_LINE="RT OPCACHE=0 JIT=0 KEYS=0" \
        PHP_FPM_BINARY="$stub_dir/php-fpm8.3" run bash "$DIR/check-opcache.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"OPcache im Request:      AUS"* ]]
    [[ "$output" == *"opcache_enabled = false"* ]]
    [ -s "$BATS_TEST_TMPDIR/probe-pfad" ]
    [ -f "$BATS_TEST_TMPDIR/probe-da" ]
    [ ! -e "$(cat "$BATS_TEST_TMPDIR/probe-pfad")" ]
}

@test "check-opcache.sh zeigt JIT und wirksames max_cached_keys aus dem Request" {
    fpm_stub
    cgi_stub
    PATH="$stub_dir:$PATH" FPM_SOCKET="$BATS_TEST_TMPDIR/sock" RT_LINE="RT OPCACHE=1 JIT=1 KEYS=65407" \
        PHP_FPM_BINARY="$stub_dir/php-fpm8.3" run bash "$DIR/check-opcache.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"JIT im Request:          an"* ]]
    [[ "$output" == *"max_cached_keys (wirksam): 65407"* ]]
}

@test "die Probe prueft opcache_enabled, nicht nur ein false aus opcache_get_status" {
    # Gemessen: php_admin_value[opcache.enable] = 0 im Pool liefert ein Array
    # mit opcache_enabled = false. Der Stub oben sieht den PHP-Code nicht.
    run grep -c "!empty(\$s\['opcache_enabled'\])" "$DIR/check-opcache.sh"
    [ "$output" -eq 1 ]
}

@test "check-opcache.sh und die OPcache-Vorlage nennen dieselbe interned-Schwelle" {
    local tpl="./chapters/09-php-performance/config/99-shopware-opcache.ini"
    local wert schwelle
    wert=$(sed -nE 's/^opcache\.interned_strings_buffer=([0-9]+)$/\1/p' "$tpl")
    schwelle=$(sed -nE 's/.*"\$\{INTERNED\}" -lt ([0-9]+) .*/\1/p' "$DIR/check-opcache.sh")
    [ -n "$wert" ]
    [ "$wert" = "$schwelle" ]
}
