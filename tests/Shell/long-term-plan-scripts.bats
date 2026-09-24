#!/usr/bin/env bats

# BATS-Tests fuer chapters/15-langfristiger-plan/scripts/.
#
# Die drei Skripte lesen eine Eingabedatei (MEM-320). Geprueft wird: die
# Demo-Dateien ergeben die alten Werte, nur sie sind als BEISPIELDATEN
# gekennzeichnet, ohne Eingabe gibt es Usage und Exit 1 statt Demo, kaputte
# Eingaben enden mit Meldung und Exit 65/66, und tech-debt-report.sh rechnet
# wie TechDebtTrackerService (gleiche Fixture wie
# tests/Unit/TechDebtTrackerServiceTest.php).

bats_require_minimum_version 1.5.0

DIR="./chapters/15-langfristiger-plan/scripts"
EX="./chapters/15-langfristiger-plan/examples"
EQUIV="./tests/Unit/fixtures/ch15-tech-debt-equivalence.json"
DEMO_NOTE="BEISPIELDATEN"

setup() {
    command -v jq >/dev/null 2>&1 || skip "jq fehlt (Image localhost/bats-ubuntu-jq-bc:24.04)"
    TMP="$(mktemp -d)"
    # quarterly-review.sh schreibt sonst nach chapters/15-langfristiger-plan/reports/
    export OUTPUT_DIR="$TMP/reports"
    unset ROADMAP_FILE
}

teardown() {
    if [ -n "${TMP:-}" ]; then rm -rf "$TMP"; fi
}

# ============================================================
# tech-debt-report.sh
# ============================================================

@test "tech-debt-report: Demo-Datei ergibt den alten Bericht und ist gekennzeichnet" {
    run bash "$DIR/tech-debt-report.sh" "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HINWEIS: BEISPIELDATEN aus tech-debt.demo.json, keine Messung"* ]]
    # high 40 + high 40 + critical 100 + medium 10 + high 40 (in Arbeit, offen)
    [[ "$output" == *"230"*"Punkte (attention; < 200 gesund, ab 500 kritisch)"* ]]
    [[ "$output" == *"Geschätzte Stunden: 60h (Backlog)"* ]]
    # 25-%-Budget 20 h: 8 h passen, 24 h und 16 h nicht, dann 12 h
    [[ "$output" == *"☐ Synchrone Third-Party Scripts (8h)"* ]]
    [[ "$output" == *"☐ Fehlende Cache-Invalidierung (12h)"* ]]
    [[ "$output" != *"☐ N+1 Queries in Produktliste"* ]]
    [[ "$output" != *"☐ Legacy jQuery Event Handlers"* ]]
}

@test "tech-debt-report: JSON der Demo nennt Beispieldaten, Score und Prioritaeten" {
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.data_source' <<<"$output")" = "BEISPIELDATEN aus tech-debt.demo.json, keine Messung" ]
    [ "$(jq -r '.demo' <<<"$output")" = "true" ]
    [ "$(jq -r '.summary.tech_debt_score' <<<"$output")" = "230" ]
    [ "$(jq -r '.summary.health' <<<"$output")" = "attention" ]
    # critical/medium = 100/5 = 20, high/small = 40/2 = 20, high/medium = 8, medium/medium = 2
    [ "$(jq -c '[.top_priority[].priority]' <<<"$output")" = "[20,20,20,8,2]" ]
}

@test "tech-debt-report: echte Eingabe traegt keinen Beispieldaten-Hinweis" {
    cp "$EX/tech-debt.demo.json" "$TMP/tech-debt.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/tech-debt.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Eingabe: $TMP/tech-debt.json"* ]]
    [[ "$output" != *"$DEMO_NOTE"* ]]
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/tech-debt.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.data_source' <<<"$output")" = "tech-debt.json" ]
    [ "$(jq -r '.demo' <<<"$output")" = "false" ]
    [ "$(jq -r '.summary.tech_debt_score' <<<"$output")" = "230" ]
}

@test "tech-debt-report: ohne Eingabe Usage und Exit 1, kein Bericht aus der Demo" {
    run bash "$DIR/tech-debt-report.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"Technical Debt Report"* ]]
    [[ "$output" != *"Tech Debt Score:"* ]]
    run bash "$DIR/tech-debt-report.sh" --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"tech_debt_score"* ]]
}

@test "tech-debt-report: kaputte Eingaben enden mit Meldung und Exit 65/66" {
    run bash "$DIR/tech-debt-report.sh" "$TMP/gibt-es-nicht.json"
    [ "$status" -eq 66 ]
    [[ "$output" == *"fehlt oder ist nicht lesbar"* ]]

    printf '[{"title": "x",' > "$TMP/kaputt.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/kaputt.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"kein gültiges JSON"* ]]

    : > "$TMP/leer.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/leer.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"kein gültiges JSON"* ]]

    echo '{"items": []}' > "$TMP/objekt.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/objekt.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"muss eine JSON-Liste sein"* ]]

    echo '[{"title": "ohne Severity", "effort": "small"}]' > "$TMP/feld.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/feld.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"Item 0 (ohne Severity): severity fehlt"* ]]
    [[ "$output" != *"Tech Debt Score:"* ]]

    echo '[{"title": "a", "severity": "low", "effort": "small", "estimated_hours": "8"}]' > "$TMP/stunden.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/stunden.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"estimated_hours ist keine Zahl"* ]]
}

@test "tech-debt-report: unbekannte Severity zaehlt wie medium und warnt auf stderr" {
    echo '[{"title": "Blocker", "severity": "blocker", "effort": "huge"}]' > "$TMP/unbekannt.json"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/unbekannt.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.summary.tech_debt_score' <<<"$output")" = "10" ]
    [ "$(jq -c '[.top_priority[].priority]' <<<"$output")" = "[2]" ]
    [[ "$stderr" == *'Warnung: Blocker: severity "blocker" unbekannt, zählt wie medium (10 Punkte)'* ]]
    [[ "$stderr" == *'Warnung: Blocker: effort "huge" unbekannt, zählt wie medium (Aufwand 5)'* ]]
}

@test "tech-debt-report: leere Liste ist gesund mit Score 0" {
    echo '[]' > "$TMP/leer.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/leer.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"*"Punkte (healthy; < 200 gesund, ab 500 kritisch)"* ]]
    [[ "$output" == *"Keine offenen Items."* ]]
    [[ "$output" == *"GUT: Tech Debt minimal."* ]]
}

@test "tech-debt-report: rechnet wie TechDebtTrackerService (gemeinsame Fixture)" {
    n="$(jq 'length' "$EQUIV")"
    [ "$n" -ge 7 ]
    for i in $(seq 0 $((n - 1))); do
        name="$(jq -r ".[$i].name" "$EQUIV")"
        jq ".[$i].items" "$EQUIV" > "$TMP/case.json"
        run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/case.json"
        [ "$status" -eq 0 ] || { echo "Fall $name: Exit $status"; false; }
        actual="$(jq -cS '{total_score: .summary.tech_debt_score, status: .summary.health,
            by_category: (.by_category | map({(.category): .points}) | add // {}),
            item_count: .summary.total_items, top_titles: [.top_priority[].title]}' <<<"$output")"
        expected="$(jq -cS ".[$i].expected" "$EQUIV")"
        [ "$actual" = "$expected" ] || { echo "Fall $name"; echo "Skript: $actual"; echo "PHP:    $expected"; false; }
    done
}

@test "tech-debt-report: Items ohne Stundenschaetzung werden genannt, nicht eingeplant" {
    echo '[{"title": "mit", "severity": "high", "effort": "small", "estimated_hours": 6},
           {"title": "ohne", "severity": "critical", "effort": "small"}]' > "$TMP/stunden.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/stunden.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Geschätzte Stunden: 6h (Backlog), 1 Items ohne Schätzung"* ]]
    [[ "$output" == *"☐ mit (6h)"* ]]
    [[ "$output" == *"ohne Stundenschätzung, nicht eingeplant: ohne"* ]]
    [[ "$output" == *"Hours: ?"* ]]
}

@test "tech-debt-report: --trend liest die Verlaufsdatei, Demo gekennzeichnet" {
    run bash "$DIR/tech-debt-report.sh" --trend "$EX/tech-debt-history.demo.json" "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HINWEIS: BEISPIELDATEN aus tech-debt-history.demo.json, keine Messung"* ]]
    [[ "$output" == *"Monat 3: Score 230 | Items: 5 | Hours: 68h"* ]]
    [[ "$output" == *"Trend: "*"improving ↓"* ]]

    echo '[{"month": "Jan", "score": 100}, {"month": "Feb", "score": 180}]' > "$TMP/verlauf.json"
    cp "$EX/tech-debt.demo.json" "$TMP/tech-debt.json"
    run bash "$DIR/tech-debt-report.sh" --trend "$TMP/verlauf.json" "$TMP/tech-debt.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Feb: Score 180"* ]]
    [[ "$output" == *"worsening ↑"* ]]
    [[ "$output" != *"$DEMO_NOTE"* ]]

    run bash "$DIR/tech-debt-report.sh" --trend
    [ "$status" -eq 1 ]
    [[ "$output" == *"--trend braucht eine Verlaufsdatei"* ]]
}

# ============================================================
# quarterly-review.sh
# ============================================================

@test "quarterly-review: Demo ergibt die alten Werte und ist gekennzeichnet" {
    run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HINWEIS: BEISPIELDATEN aus quarterly-review.demo.json, keine Messung"* ]]
    [[ "$output" == *"Quick Summary (BEISPIELDATEN aus quarterly-review.demo.json, keine Messung):"* ]]
    # (3200 - 2450) / 3200 = 23.4375 %, (220 - 175) / 220 = 20.45 %
    [[ "$output" == *"CWV Improvement: LCP 23.4%, INP 20.5%"* ]]
    [[ "$output" == *"OKR Score: 0.97 (Exceptional)"* ]]
    [[ "$output" == *"Tech Debt: 80h abgebaut, Score 230 (attention)"* ]]
    report="$OUTPUT_DIR/quarterly-review-Q2-2026.md"
    [ -f "$report" ]
    grep -qF "> **BEISPIELDATEN aus quarterly-review.demo.json, keine Messung.**" "$report"
    grep -qF "| **Total Q** | **CHF 11'250** | **CHF 11'125** | **-1%** |" "$report"
    grep -qF "| Infrastructure | CHF 5'000 | CHF 5'500 | +10% |" "$report"
    grep -qF "**Jahres-Budget Status**: 48% verbraucht (Ziel: 50%)" "$report"
    grep -qF "| LCP (p75) | 3200ms | 2450ms | **23.4%** ↓ |" "$report"
    grep -qF "| CLS (p75) | 0.12 | 0.06 | **50.0%** ↓ |" "$report"
    grep -qF "| **Total** | **4** |" "$report"
    grep -qF "| Backlog Items | 18 | 12 | ↓ 33% |" "$report"
    grep -qF "**Objective Score**: 0.94 (Exceptional)" "$report"
    grep -qF "## Planung Q3 2026" "$report"
    [ ! -e "$report.part" ]
}

@test "quarterly-review: echte Eingabe ohne Beispieldaten-Hinweis, Felder richtig zugeordnet" {
    cat > "$TMP/q3.json" <<'JSON'
{
    "quarter": "Q3", "year": 2027,
    "cwv": {"lcp_ms": {"start": 4000, "end": 3000}, "inp_ms": {"start": 300, "end": 240},
            "cls": {"start": 0.2, "end": 0.15}},
    "okrs": [{"objective": "O1", "key_results": [
        {"title": "KR a", "score": 0.9}, {"title": "KR b", "score": 0.9}, {"title": "KR c", "score": 0.89}]}],
    "incidents": {"p0": 2, "p1": 0, "p2": 5, "postmortems_done": 6},
    "tech_debt": {"start": {"items": 10, "hours": 100, "score": 199},
                  "end": {"items": 20, "hours": 100, "score": 500},
                  "resolved": [{"title": "R", "hours": 7}]},
    "budget": {"currency": "EUR", "categories": [{"category": "Tools", "planned": 1000, "spent": 1234}]}
}
JSON
    run bash "$DIR/quarterly-review.sh" "$TMP/q3.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *"$DEMO_NOTE"* ]]
    [[ "$output" == *"Quick Summary:"* ]]
    [[ "$output" == *"CWV Improvement: LCP 25.0%, INP 20.0%"* ]]
    # Mittel 0.8967 wird als 0.90 angezeigt; die Stufe haengt am angezeigten
    # Wert (Exceptional), nicht am ungerundeten (Strong)
    [[ "$output" == *"OKR Score: 0.90 (Exceptional)"* ]]
    [[ "$output" == *"Incidents: 2 P0, 0 P1"* ]]
    [[ "$output" == *"Tech Debt: 7h abgebaut, Score 500 (critical)"* ]]
    report="$OUTPUT_DIR/quarterly-review-Q3-2027.md"
    run ! grep -q "$DEMO_NOTE" "$report"
    grep -qF "**Eingabe**: q3.json" "$report"
    grep -qF "**Zeitraum**: 2027-07-01 bis 2027-09-30" "$report"
    grep -qF "| LCP (p75) | 4000ms | 3000ms | **25.0%** ↓ |" "$report"
    grep -qF "| INP (p75) | 300ms | 240ms | **20.0%** ↓ |" "$report"
    grep -qF "| CLS (p75) | 0.2 | 0.15 | **25.0%** ↓ |" "$report"
    grep -qF "Nicht im 'Good' Bereich: LCP (3000ms > 2500ms), INP (240ms > 200ms), CLS (0.15 > 0.1)." "$report"
    grep -qF "| **Total** | **7** |" "$report"
    grep -qF -- "- Abgeschlossen: 6/7 (86%)" "$report"
    grep -qF "| Backlog Items | 10 | 20 | ↑ 100% |" "$report"
    grep -qF "| Tech Debt Score (Severity-Punkte, Kapitel 15) | 199 | 500 | ↑ critical (< 200 gesund) |" "$report"
    grep -qF "| Tools | EUR 1'000 | EUR 1'234 | +23% |" "$report"
    run ! grep -q "Jahres-Budget" "$report"
}

@test "quarterly-review: Tech-Debt-Stufe an den Grenzen 200 und 500" {
    for pair in "199:healthy" "200:attention" "499:attention" "500:critical"; do
        score="${pair%%:*}"; health="${pair##*:}"
        echo "{\"quarter\": \"Q1\", \"year\": 2027, \"tech_debt\": {\"start\": {\"items\": 1, \"hours\": 1, \"score\": 1},
              \"end\": {\"items\": 1, \"hours\": 1, \"score\": $score}}}" > "$TMP/td.json"
        run bash "$DIR/quarterly-review.sh" "$TMP/td.json"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Tech Debt: 0h abgebaut, Score $score ($health)"* ]] || { echo "$score: $output"; false; }
    done
}

@test "quarterly-review: ohne Eingabe Usage und Exit 1, kein Report" {
    run bash "$DIR/quarterly-review.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"Quick Summary"* ]]
    [ ! -e "$OUTPUT_DIR" ]
    # alter Aufruf mit Quartal: Hinweis statt Demo
    run bash "$DIR/quarterly-review.sh" Q2
    [ "$status" -eq 1 ]
    [[ "$output" == *"Quartal und Jahr stehen jetzt in der Eingabedatei"* ]]
    [ ! -e "$OUTPUT_DIR" ]
}

@test "quarterly-review: kaputte Eingaben enden mit Meldung und Exit 65/66, ohne Report" {
    run bash "$DIR/quarterly-review.sh" "$TMP/gibt-es-nicht.json"
    [ "$status" -eq 66 ]

    printf '{"quarter": "Q2",' > "$TMP/kaputt.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/kaputt.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"kein gültiges JSON"* ]]

    echo '{"quarter": "Q9", "year": 2026}' > "$TMP/q9.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/q9.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"quarter muss Q1, Q2, Q3 oder Q4 sein"* ]]

    echo '{"quarter": "Q2", "year": 2026, "cwv": {"lcp_ms": {"start": 3000, "end": 2000}}}' > "$TMP/cwv.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/cwv.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"cwv.inp_ms.start fehlt oder ist keine Zahl"* ]]

    echo '{"quarter": "Q2", "year": 2026, "okrs": [{"objective": "O", "key_results": [{"title": "K", "score": 1.5}]}]}' > "$TMP/okr.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/okr.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"okrs.0.key_results.0.score muss eine Zahl von 0 bis 1 sein"* ]]

    echo '{"quarter": "Q2", "year": 2026, "budget": {"categories": []}}' > "$TMP/budget.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/budget.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"budget.categories muss eine nicht leere Liste sein"* ]]

    [ ! -e "$OUTPUT_DIR" ]
}

@test "quarterly-review: fehlende Bloecke heissen keine Daten, nicht null" {
    echo '{"quarter": "Q4", "year": 2026}' > "$TMP/min.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/min.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CWV Improvement: keine Daten"* ]]
    [[ "$output" == *"OKR Score: keine Daten"* ]]
    report="$OUTPUT_DIR/quarterly-review-Q4-2026.md"
    [ "$(grep -c '_Keine Daten in der Eingabe' "$report")" -eq 5 ]
    run ! grep -q "null" "$report"
}

@test "quarterly-review: --output schreibt genau dorthin" {
    run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json" --output "$TMP/out/mein-report.md"
    [ "$status" -eq 0 ]
    [ -f "$TMP/out/mein-report.md" ]
    [ ! -e "$OUTPUT_DIR" ]
}

# ============================================================
# roadmap-status.sh
# ============================================================

@test "roadmap-status: Demo zum Stichtag zeigt jeden Zweig und alle Milestones je Quartal" {
    run bash "$DIR/roadmap-status.sh" --file "$EX/roadmap-status.demo.json" --stichtag 2026-09-15
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"HINWEIS: BEISPIELDATEN aus roadmap-status.demo.json, keine Messung"* ]]
    [[ "$output" == *"Completed:"*" 2"* ]]
    [[ "$output" == *"At Risk:"*" 1"* ]]
    [[ "$output" == *"Overdue:"*" 1"* ]]
    [[ "$output" == *"Progress: "*"33%"* ]]
    [[ "$output" == *"[OVERDUE]"*"Checkout LCP < 2s"*"(5 days ago)"* ]]
    [[ "$output" == *"[AT RISK]"*"Redis produktiv (Kapitel 7)"*"(20 days remaining)"* ]]
    # volle Gruppierung: M-1 bis M-4 im Q3, M-5 und M-6 im Q4
    q3="$(sed -n '/2026-Q3/,/^$/p' <<<"$output")"
    q4="$(sed -n '/2026-Q4/,/^$/p' <<<"$output")"
    for id in M-1 M-2 M-3 M-4; do [[ "$q3" == *"[$id]"* ]]; [[ "$q4" != *"[$id]"* ]]; done
    for id in M-5 M-6; do [[ "$q4" == *"[$id]"* ]]; [[ "$q3" != *"[$id]"* ]]; done
    [[ "$output" == *"(10d remaining)"* ]]
    [[ "$output" == *"(45d remaining)"* ]]
    [[ "$output" == *"[R-003]"*"Black Friday Vorbereitung zu spät"* ]]
}

@test "roadmap-status: liest ROADMAP_FILE, echte Datei ohne Beispieldaten-Hinweis" {
    echo '{"milestones": [{"id": "X-1", "title": "Nur aus ROADMAP_FILE", "target_date": "2027-01-15", "status": "completed"}]}' \
        > "$TMP/status.json"
    ROADMAP_FILE="$TMP/status.json" run bash "$DIR/roadmap-status.sh" --stichtag 2027-02-01
    [ "$status" -eq 0 ]
    [[ "$output" == *"[X-1] Nur aus ROADMAP_FILE"* ]]
    [[ "$output" == *"Total:          1"* ]]
    [[ "$output" == *"Roadmap auf Kurs!"* ]]
    [[ "$output" == *"Keine Risiken in der Statusdatei."* ]]
    [[ "$output" != *"$DEMO_NOTE"* ]]
    [[ "$output" != *"[M-1]"* ]]
}

@test "roadmap-status: ohne Statusdatei Usage und Exit 1, keine Demo" {
    run bash "$DIR/roadmap-status.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"Roadmap Status Check"* ]]
    [[ "$output" != *"[M-1]"* ]]
    run bash "$DIR/roadmap-status.sh" --alerts-only
    [ "$status" -eq 1 ]
    [[ "$output" != *"No alerts."* ]]
}

@test "roadmap-status: kaputte Statusdateien enden mit Meldung und Exit 65/66" {
    run bash "$DIR/roadmap-status.sh" --file "$TMP/gibt-es-nicht.json"
    [ "$status" -eq 66 ]

    run bash "$DIR/roadmap-status.sh" --file "./chapters/15-langfristiger-plan/templates/roadmap.yaml"
    [ "$status" -eq 65 ]
    [[ "$output" == *"ist YAML"* ]]

    printf '{"milestones": [' > "$TMP/kaputt.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/kaputt.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"kein gültiges JSON"* ]]

    echo '{"risks": []}' > "$TMP/ohne.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/ohne.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"milestones fehlt oder ist keine Liste"* ]]

    echo '{"milestones": [{"id": "A", "title": "t", "target_date": "2026-03-01", "status": "done"}]}' > "$TMP/status.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/status.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"milestones.0 (A): status muss completed, in_progress, at_risk oder pending sein"* ]]

    echo '{"milestones": [{"id": "A", "title": "t", "target_date": "2026-02-30", "status": "pending"}]}' > "$TMP/datum.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/datum.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"target_date ist kein Datum"* ]]

    echo '{"milestones": [], "risks": [{"risk": "r", "probability": "huge", "impact": "low"}]}' > "$TMP/risk.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/risk.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"probability und impact"* ]]
}

@test "roadmap-status: leere Milestone-Liste ohne Division durch null" {
    echo '{"milestones": []}' > "$TMP/leer.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/leer.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total:          0"* ]]
    [[ "$output" == *"Keine Milestones in der Statusdatei."* ]]
}

@test "roadmap-status: am Zieltag nicht ueberfaellig, am Tag danach schon" {
    echo '{"milestones": [
        {"id": "H", "title": "heute faellig", "target_date": "2026-09-15", "status": "pending"},
        {"id": "G", "title": "gestern faellig", "target_date": "2026-09-14", "status": "in_progress"},
        {"id": "E", "title": "erledigt, alt", "target_date": "2026-01-01", "status": "completed"}]}' > "$TMP/grenze.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/grenze.json" --stichtag 2026-09-15 --alerts-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OVERDUE]"*"gestern faellig"*"(1 days ago)"* ]]
    [[ "$output" != *"heute faellig"* ]]
    [[ "$output" != *"erledigt, alt"* ]]
}

@test "roadmap-status: Monat 08 und 09 sind Q3, auch ueber das heutige Datum" {
    echo '{"milestones": []}' > "$TMP/leer.json"
    for day in 2026-08-01 2026-09-30; do
        run bash "$DIR/roadmap-status.sh" --file "$TMP/leer.json" --stichtag "$day"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Aktuelles Quartal: Q3 2026"* ]]
    done
    REAL_DATE="$(command -v date)"
    cat > "$TMP/date" <<STUB
#!/bin/sh
case "\$1" in
    +%Y-%m-%d) echo 2026-09-01 ;;
    *) exec "$REAL_DATE" "\$@" ;;
esac
STUB
    chmod +x "$TMP/date"
    PATH="$TMP:$PATH" run bash "$DIR/roadmap-status.sh" --file "$TMP/leer.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stichtag: 2026-09-01"* ]]
    [[ "$output" == *"Aktuelles Quartal: Q3 2026"* ]]
    [[ "$output" != *"Basis zu gro"* && "$output" != *"value too great"* ]]
}

@test "roadmap-status: --quarter und --stichtag ohne gueltigen Wert sind Exit 1" {
    run bash "$DIR/roadmap-status.sh" --quarter
    [ "$status" -eq 1 ]
    [[ "$output" == *"--quarter braucht"* ]]
    run bash "$DIR/roadmap-status.sh" --stichtag 15.09.2026
    [ "$status" -eq 1 ]
    [[ "$output" == *"--stichtag braucht"* ]]
}

@test "roadmap-status: --alerts-only ohne Alerts meldet No alerts." {
    echo '{"milestones": [{"id": "A", "title": "t", "target_date": "2026-12-01", "status": "pending"}]}' > "$TMP/ruhig.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/ruhig.json" --stichtag 2026-09-15 --alerts-only
    [ "$status" -eq 0 ]
    [ "$output" = "No alerts." ]
}
