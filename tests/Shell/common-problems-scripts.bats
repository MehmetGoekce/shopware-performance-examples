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
    run bash -c "grep -rnE 'theme:compile[^\n]*--keep-all' $DIR"
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

@test "check-http-cache.sh erkennt einen wachsenden Age-Header als Treffer" {
    stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
# Zaehlt die Aufrufe mit und liefert beim zweiten ein hoeheres Age.
n_file="${CURL_COUNT_FILE}"
n=$(( $(cat "$n_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$n_file"
age=$(( 10 * n ))
printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nAge: %s\r\n\r\n' "$age"
STUB
    chmod +x "$stub_dir/curl"
    export CURL_COUNT_FILE="$BATS_TEST_TMPDIR/count"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Der HTTP-Cache arbeitet"* ]]
}

@test "check-http-cache.sh meldet fehlenden Age-Header als Problem" {
    stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\n\r\n'
STUB
    chmod +x "$stub_dir/curl"
    PATH="$stub_dir:$PATH" run bash "$DIR/check-http-cache.sh" http://example.test
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kein Age-Header"* ]]
}

@test "check-http-cache.sh wertet no-cache, private nicht als Defekt" {
    # Regressionstest zu F41: eine gesunde Storefront antwortet genau so.
    stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<'STUB'
#!/bin/bash
n_file="${CURL_COUNT_FILE}"
n=$(( $(cat "$n_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$n_file"
printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nAge: %s\r\n\r\n' "$(( 5 * n ))"
STUB
    chmod +x "$stub_dir/curl"
    export CURL_COUNT_FILE="$BATS_TEST_TMPDIR/count2"
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

@test "config/php-opcache.ini setzt den wirksamen max_accelerated_files-Wert" {
    # Regressionstest zu F91/T29: PHP rundet 20000 auf 32531 auf.
    run grep -q '^opcache.max_accelerated_files=32531' "$CONFIG/php-opcache.ini"
    [ "$status" -eq 0 ]
    run grep -q '^opcache.enable_cli=0' "$CONFIG/php-opcache.ini"
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
