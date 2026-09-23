#!/usr/bin/env bats

# BATS-Tests fuer chapters/15-langfristiger-plan/scripts/.
#
# Die drei Skripte laufen mit Beispieldaten, die im Skript stehen (MEM-317).
# Geprueft wird, dass jede Ausgabe das sagt, dass tech-debt-report.sh auf der
# Skala von Kapitel 15 rechnet (tests/Unit/TechDebtTrackerServiceTest.php) und
# dass roadmap-status.sh August und September dem richtigen Quartal zuordnet.

DIR="./chapters/15-langfristiger-plan/scripts"

setup() {
    TMP="$(mktemp -d)"
}

teardown() {
    if [ -n "${TMP:-}" ]; then rm -rf "$TMP"; fi
}

@test "tech-debt-report: Text nennt Beispieldaten und die Kapitel-Skala" {
    command -v jq >/dev/null 2>&1 || skip "jq fehlt (Image localhost/bats-ubuntu-jq:24.04)"
    run bash "$DIR/tech-debt-report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HINWEIS: BEISPIELDATEN aus dem Skript, keine Messung"* ]]
    # high 40 + high 40 + critical 100 + medium 10 + high 40 (in Arbeit, offen)
    [[ "$output" == *"230"*"Punkte (attention; < 200 gesund, ab 500 kritisch)"* ]]
}

@test "tech-debt-report: JSON nennt Beispieldaten, Score und Prioritaet wie Kapitel 15" {
    command -v jq >/dev/null 2>&1 || skip "jq fehlt (Image localhost/bats-ubuntu-jq:24.04)"
    run bash "$DIR/tech-debt-report.sh" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.data_source' <<<"$output")" = "BEISPIELDATEN aus dem Skript, keine Messung" ]
    [ "$(jq -r '.summary.tech_debt_score' <<<"$output")" = "230" ]
    [ "$(jq -r '.summary.health' <<<"$output")" = "attention" ]
    # critical/medium = 100/5 = 20, high/small = 40/2 = 20, high/medium = 40/5 = 8
    [ "$(jq -c '[.top_priority[].priority]' <<<"$output")" = "[20,20,20]" ]
}

@test "tech-debt-report: Sprint-Empfehlung bleibt im 25-%-Budget (20 h)" {
    command -v jq >/dev/null 2>&1 || skip "jq fehlt (Image localhost/bats-ubuntu-jq:24.04)"
    run bash "$DIR/tech-debt-report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synchrone Third-Party Scripts (8h)"* ]]
    [[ "$output" == *"Fehlende Cache-Invalidierung (12h)"* ]]
    [[ "$output" != *"N+1 Queries in Produktliste (24h)"* ]]
}

@test "quarterly-review: Konsole und Report nennen Beispieldaten" {
    command -v bc >/dev/null 2>&1 || skip "bc fehlt"
    OUTPUT_DIR="$TMP" run bash "$DIR/quarterly-review.sh" Q2
    [ "$status" -eq 0 ]
    [[ "$output" == *"HINWEIS: BEISPIELDATEN aus dem Skript, keine Messung"* ]]
    [[ "$output" == *"Quick Summary (BEISPIELDATEN aus dem Skript, keine Messung):"* ]]
    run grep -c "BEISPIELDATEN aus dem Skript, keine Messung" "$TMP"/quarterly-review-Q2-*.md
    [ "$output" -ge 1 ]
}

@test "roadmap-status: nennt Beispieldaten auch mit --alerts-only" {
    run bash "$DIR/roadmap-status.sh" --alerts-only
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"HINWEIS: BEISPIELDATEN aus dem Skript, keine Messung"* ]]
}

@test "roadmap-status: Monat 08 und 09 sind Q3, nicht Oktal-Fehler und Q4" {
    REAL_DATE="$(command -v date)"
    for month in 08 09; do
        cat > "$TMP/date" <<STUB
#!/bin/sh
case "\$1" in
    +%m) echo $month ;;
    +%Y) echo 2026 ;;
    *) exec "$REAL_DATE" "\$@" ;;
esac
STUB
        chmod +x "$TMP/date"
        PATH="$TMP:$PATH" run bash "$DIR/roadmap-status.sh"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Aktuelles Quartal: Q3 2026"* ]]
        [[ "$output" != *"Basis zu gro"* && "$output" != *"value too great"* ]]
    done
}
