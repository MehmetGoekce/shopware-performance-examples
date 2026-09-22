#!/usr/bin/env bats

# BATS-Tests fuer chapters/14-performance-kultur/scripts/generate-report.sh.
#
# rum:report und error-budget.php sind Stubs, die ihre Argumente protokollieren.
# Die Werkzeuge selbst sind getestet: rum:report in Kapitel 12,
# error-budget.php in tests/Unit/ErrorBudgetScriptTest.php.

SCRIPT="./chapters/14-performance-kultur/scripts/generate-report.sh"

setup() {
    [ -f "$SCRIPT" ] || skip "Skript fehlt: $SCRIPT"
    TMP="$(mktemp -d)"
    export OUTPUT_DIR="$TMP/out"
    export SHOPWARE_DIR="$TMP/shop-x"
    export CALLS="$TMP/calls"
    unset SLACK_WEBHOOK

    cat > "$TMP/console" <<'EOF'
#!/bin/sh
echo "console $*" >> "$CALLS"
# CONSOLE_FAIL=all: jeder Aufruf scheitert, =route: nur der mit --by=route
case "$CONSOLE_FAIL:$*" in
    all:*|route:*--by=route*) echo "console kaputt"; exit 1 ;;
esac
echo "RUM-TABELLE $*"
EOF
    cat > "$TMP/php" <<'EOF'
#!/bin/sh
echo "php $*" >> "$CALLS"
echo "BUDGET-TABELLE"
echo "Gesamt: ${BUDGET_OVERALL:-green}"
[ -n "$BUDGET_UNRATED" ] && echo "Ohne Bewertung (unter 100 Seitenaufrufen): $BUDGET_UNRATED"
exit "${STUB_BUDGET_RC:-0}"
EOF
    cat > "$TMP/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$CALLS"
# wie curl: ein HTTP-Fehler wird nur mit -f zum Exit-Code (22)
rc=0
case " $* " in *" -f "*) rc="${CURL_RC:-0}" ;; esac
# Body (nach -d) einzeln ablegen
while [ $# -gt 0 ]; do [ "$1" = "-d" ] && printf '%s\n' "$2" > "$CALLS.body"; shift; done
exit "$rc"
EOF
    chmod +x "$TMP/console" "$TMP/php" "$TMP/curl"
    export CONSOLE="$TMP/console" PHP="$TMP/php" CURL="$TMP/curl"
}

teardown() {
    rm -rf "$TMP"
}

report() {
    cat "$OUTPUT_DIR"/performance-report-*.md
}

@test "--help zeigt Usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unbekannter Report-Typ endet mit Exit 1" {
    run "$SCRIPT" daily
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "weekly fragt rum:report fuer 168 Stunden, gesamt und je Route" {
    run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$CALLS")" = "console rum:report --hours=168" ]
    [ "$(sed -n 2p "$CALLS")" = "console rum:report --hours=168 --by=route" ]
}

@test "monthly fragt 28 Tage (672 Stunden), Monolog behaelt 30 Tagesdateien" {
    run "$SCRIPT" monthly
    [ "$status" -eq 0 ]
    grep -qx "console rum:report --hours=672" "$CALLS"
}

@test "ohne OUTPUT_DIR landet der Report unter var/ im Shopware-Verzeichnis" {
    unset OUTPUT_DIR
    run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    [ "$(ls "$SHOPWARE_DIR/var/performance-reports" | wc -l)" -eq 1 ]
}

@test "error-budget.php bekommt das Shopware-Verzeichnis" {
    run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    [ "$(sed -n 3p "$CALLS")" = "php $(cd chapters/14-performance-kultur/scripts && pwd)/error-budget.php $SHOPWARE_DIR" ]
}

@test "Report enthaelt die Ausgaben der Werkzeuge und keine erfundenen Werte" {
    run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    run report
    [[ "$output" == *"RUM-TABELLE rum:report --hours=168"* ]]
    [[ "$output" == *"RUM-TABELLE rum:report --hours=168 --by=route"* ]]
    [[ "$output" == *"BUDGET-TABELLE"* ]]
    [[ "$output" == *"Keine bewertete Metrik ist rot."* ]]
    # Zahlen mit Einheit kommen nur aus den Werkzeugen, und die Stubs liefern keine
    run grep -nE '[0-9]+ ?(ms|%|s\b)' "$OUTPUT_DIR"/performance-report-*.md
    [ "$status" -eq 1 ]
    # nur der fertige Report, keine liegengebliebene .part-Datei
    [ "$(ls "$OUTPUT_DIR" | wc -l)" -eq 1 ]
}

@test "verletztes SLO (Exit 1) bricht nicht ab und steht im Report" {
    STUB_BUDGET_RC=1 BUDGET_OVERALL=red run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    run report
    [[ "$output" == *"Mindestens ein SLO ist verletzt"* ]]
}

@test "unbewertete Metrik steht neben der Gesamtstufe" {
    BUDGET_UNRATED=INP run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    run report
    [[ "$output" == *"Keine bewertete Metrik ist rot. Ohne Bewertung (unter 100 Seitenaufrufen): INP."* ]]
}

@test "zu wenig Daten (Exit 3) steht im Report" {
    STUB_BUDGET_RC=3 run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    run report
    [[ "$output" == *"Zu wenig Seitenaufrufe"* ]]
}

@test "error-budget.php mit Exit 2 bricht ab, ohne Report" {
    STUB_BUDGET_RC=2 run "$SCRIPT" weekly
    [ "$status" -eq 2 ]
    [ -z "$(ls "$OUTPUT_DIR")" ]
}

@test "gescheitertes rum:report bricht ab, ohne Report" {
    CONSOLE_FAIL=all run "$SCRIPT" weekly
    [ "$status" -eq 2 ]
    [[ "$output" == *"console kaputt"* ]]
    [ -z "$(ls "$OUTPUT_DIR")" ]
}

@test "gescheitertes rum:report --by=route bricht ebenfalls ab" {
    CONSOLE_FAIL=route run "$SCRIPT" weekly
    [ "$status" -eq 2 ]
    [ -z "$(ls "$OUTPUT_DIR")" ]
}

@test "ohne SLACK_WEBHOOK kein curl" {
    run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    run grep -c '^curl' "$CALLS"
    [ "$output" = "0" ]
}

@test "mit SLACK_WEBHOOK geht die Gesamtstufe an den Webhook" {
    SLACK_WEBHOOK=https://hooks.example/x STUB_BUDGET_RC=1 BUDGET_OVERALL=red run "$SCRIPT" weekly
    [ "$status" -eq 0 ]
    grep -q '^curl .*https://hooks.example/x' "$CALLS"
    [ "$(cat "$CALLS.body")" = '{"text": "Performance Report (weekly): Error Budget red"}' ]
}

@test "Slack bekommt die Stufe aus error-budget.php, nicht eine feste" {
    SLACK_WEBHOOK=https://hooks.example/x BUDGET_OVERALL=yellow run "$SCRIPT" monthly
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS.body")" = '{"text": "Performance Report (monthly): Error Budget yellow"}' ]
}

@test "gescheiterter Slack-Versand endet mit Exit 2, Report bleibt" {
    SLACK_WEBHOOK=https://hooks.example/x CURL_RC=22 run "$SCRIPT" weekly
    [ "$status" -eq 2 ]
    [ -n "$(ls "$OUTPUT_DIR")" ]
}
