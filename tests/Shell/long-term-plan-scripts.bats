#!/usr/bin/env bats

# BATS-Tests fuer chapters/15-langfristiger-plan/scripts/.
#
# Die drei Skripte lesen eine Eingabedatei (MEM-320). Geprueft wird: die
# Demo-Dateien ergeben die alten Werte, nur sie sind als BEISPIELDATEN
# gekennzeichnet, ohne Eingabe gibt es Usage und Exit 1 statt Demo, kaputte
# Eingaben enden mit Meldung und Exit 65/66, und tech-debt-report.sh rechnet
# wie TechDebtTrackerService (gleiche Fixture wie
# tests/Unit/TechDebtTrackerServiceTest.php).
#
# Zusicherungen auf Zahlen laufen gegen die Ausgabe ohne Farbcodes und
# ganze Zeilen: "*0*" traefe sonst schon die Datumszeile.

bats_require_minimum_version 1.5.0

DIR="./chapters/15-langfristiger-plan/scripts"
EX="./chapters/15-langfristiger-plan/examples"
EQUIV="./tests/Unit/fixtures/ch15-tech-debt-equivalence.json"
DEMO_NOTE="BEISPIELDATEN"

setup() {
    TMP="$(mktemp -d)"
    # quarterly-review.sh schreibt sonst nach chapters/15-langfristiger-plan/reports/
    export OUTPUT_DIR="$TMP/reports"
    unset ROADMAP_FILE
}

teardown() {
    if [ -n "${TMP:-}" ]; then rm -rf "$TMP"; fi
}

need_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq fehlt"
}

# Ausgabe ohne ANSI-Farben, eine Zeile je Element, fuer Vergleiche ganzer Zeilen
plain() {
    printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g'
}

has_line() {
    plain | grep -qxF -- "$1" || { echo "Zeile fehlt: [$1]"; plain; false; }
}

lacks_text() {
    if plain | grep -qF -- "$1"; then echo "unerwartet: [$1]"; plain; false; fi
}

# ============================================================
# tech-debt-report.sh
# ============================================================

@test "tech-debt-report: Demo-Datei ergibt den alten Bericht und ist gekennzeichnet" {
    need_jq
    run bash "$DIR/tech-debt-report.sh" "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    has_line "HINWEIS: BEISPIELDATEN aus tech-debt.demo.json, keine Messung"
    # high 40 + high 40 + critical 100 + medium 10 + high 40 (in Arbeit, offen)
    has_line "Tech Debt Score:    230 Punkte (attention; < 200 gesund, ab 500 kritisch)"
    has_line "Backlog Items:      4"
    has_line "In Progress:        1"
    has_line "Geschätzte Stunden: 60h (Backlog)"
    has_line "database: 1 Items, 100 Punkte"
    has_line "frontend: 2 Items, 80 Punkte"
    has_line "    Category: database | Severity: critical | Priority: 20 | Hours: 24h"
    has_line "ACHTUNG: Tech Debt braucht Aufmerksamkeit."
}

@test "tech-debt-report: Sprint plant critical zuerst, den Rest im 25-%-Budget" {
    need_jq
    run bash "$DIR/tech-debt-report.sh" "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    # Kapitel 15: critical "Sofort beheben", SLA < 1 Sprint - auch ueber dem Budget
    has_line "☐ N+1 Queries in Produktliste (24h, critical: sofort, vor dem Budget)"
    # 20 h Budget: 8 h passen, 16 h nicht mehr, dann 12 h
    has_line "☐ Synchrone Third-Party Scripts (8h)"
    has_line "☐ Fehlende Cache-Invalidierung (12h)"
    lacks_text "☐ Legacy jQuery Event Handlers"
    # in Arbeit wird nicht erneut eingeplant
    lacks_text "☐ Unoptimierte Produktbilder"
}

@test "tech-debt-report: critical-Items verbrauchen kein Budget" {
    need_jq
    # 4 h critical ausserhalb, dann 10 h + 10 h genau im 20-h-Budget
    echo '[{"title": "krit", "severity": "critical", "effort": "small", "estimated_hours": 4},
           {"title": "h1", "severity": "high", "effort": "small", "estimated_hours": 10},
           {"title": "h2", "severity": "high", "effort": "small", "estimated_hours": 10}]' > "$TMP/sprint.json"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/sprint.json"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.sprint' <<<"$output")" = '{"budget_hours":20,"critical_first":["krit"],"items":["h1","h2"]}' ]
}

@test "tech-debt-report: JSON der Demo nennt Beispieldaten, Zusammenfassung und Prioritaeten" {
    need_jq
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.data_source' <<<"$output")" = "BEISPIELDATEN aus tech-debt.demo.json, keine Messung" ]
    [ "$(jq -r '.demo' <<<"$output")" = "true" ]
    [ "$(jq -c '.summary' <<<"$output")" = '{"total_items":5,"backlog_items":4,"in_progress":1,"total_hours":60,"items_without_estimate":0,"tech_debt_score":230,"health":"attention"}' ]
    # critical/medium = 100/5 = 20, high/small = 40/2 = 20, high/medium = 8, medium/medium = 2
    [ "$(jq -c '[.top_priority[].priority]' <<<"$output")" = "[20,20,20,8,2]" ]
    [ "$(jq -c '.sprint' <<<"$output")" = '{"budget_hours":20,"critical_first":["N+1 Queries in Produktliste"],"items":["Synchrone Third-Party Scripts","Fehlende Cache-Invalidierung"]}' ]
}

@test "tech-debt-report: echte Eingabe traegt keinen Beispieldaten-Hinweis" {
    need_jq
    cp "$EX/tech-debt.demo.json" "$TMP/tech-debt.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/tech-debt.json"
    [ "$status" -eq 0 ]
    has_line "Eingabe: $TMP/tech-debt.json"
    has_line "Tech Debt Score:    230 Punkte (attention; < 200 gesund, ab 500 kritisch)"
    lacks_text "$DEMO_NOTE"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/tech-debt.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.data_source' <<<"$output")" = "tech-debt.json" ]
    [ "$(jq -r '.demo' <<<"$output")" = "false" ]
}

@test "tech-debt-report: ohne Eingabe Usage und Exit 1, kein Bericht aus der Demo" {
    run bash "$DIR/tech-debt-report.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"Technical Debt Report"* ]]
    run bash "$DIR/tech-debt-report.sh" --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "tech-debt-report: kaputte Eingaben enden mit Meldung und Exit 65/66" {
    need_jq
    run bash "$DIR/tech-debt-report.sh" "$TMP/gibt-es-nicht.json"
    [ "$status" -eq 66 ]
    [[ "$output" == *"fehlt oder ist nicht lesbar"* ]]

    printf '[{"title": "x",' > "$TMP/kaputt.json"
    : > "$TMP/leer.json"
    echo '[] []' > "$TMP/zwei.json"
    for f in kaputt leer zwei; do
        run bash "$DIR/tech-debt-report.sh" "$TMP/$f.json"
        [ "$status" -eq 65 ] || { echo "$f: $status"; false; }
        [[ "$output" == *"kein gültiges JSON"* ]]
    done

    # Eingabe | erwartete Meldung
    while IFS='|' read -r json message; do
        echo "$json" > "$TMP/fall.json"
        run bash "$DIR/tech-debt-report.sh" "$TMP/fall.json"
        [ "$status" -eq 65 ] || { echo "$json -> $status: $output"; false; }
        [[ "$output" == *"$message"* ]] || { echo "$json -> $output"; false; }
        [[ "$output" != *"Tech Debt Score:"* ]]
    done <<'CASES'
{"items": []}|muss eine JSON-Liste sein
[1]|Item 0: kein Objekt
[{"severity": "low", "effort": "small"}]|Item 0: title fehlt oder ist kein Text
[{"title": "a", "effort": "small"}]|Item 0 (a): severity fehlt oder ist kein Text
[{"title": "a", "severity": 40, "effort": "small"}]|Item 0 (a): severity fehlt oder ist kein Text
[{"title": "a", "severity": "low"}]|Item 0 (a): effort fehlt oder ist kein Text
[{"title": "a", "severity": "low", "effort": "small", "category": 3}]|category ist kein Text
[{"title": "a", "severity": "low", "effort": "small", "estimated_hours": "8"}]|estimated_hours ist keine Zahl >= 0
[{"title": "a", "severity": "low", "effort": "small", "estimated_hours": -1}]|estimated_hours ist keine Zahl >= 0
[{"title": "a", "severity": "low", "effort": "small", "status": 1}]|status ist kein Text
[{"title": "a", "severity": "low", "effort": "small", "id": 7}]|id ist kein Text
CASES
}

@test "tech-debt-report: null gilt wie ein fehlendes Feld" {
    need_jq
    echo '[{"title": "a", "severity": "high", "effort": "small", "category": null, "estimated_hours": null, "status": null, "id": null}]' > "$TMP/null.json"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/null.json"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.by_category' <<<"$output")" = '[{"category":"other","count":1,"points":40}]' ]
    [ "$(jq -r '.summary.items_without_estimate' <<<"$output")" = "1" ]
}

@test "tech-debt-report: resolved faellt ueberall heraus, unbekannter Status warnt" {
    need_jq
    echo '[{"title": "erledigt", "severity": "high", "effort": "trivial", "status": "resolved", "estimated_hours": 1},
           {"title": "offen", "severity": "low", "effort": "small", "estimated_hours": 2},
           {"title": "geschlossen", "severity": "low", "effort": "small", "status": "closed", "estimated_hours": 2}]' > "$TMP/status.json"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/status.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.summary.tech_debt_score' <<<"$output")" = "4" ]
    [ "$(jq -r '.summary.total_items' <<<"$output")" = "2" ]
    [ "$(jq -r '.summary.total_hours' <<<"$output")" = "4" ]
    [ "$(jq -c '[.top_priority[].title]' <<<"$output")" = '["offen","geschlossen"]' ]
    [ "$(jq -c '.sprint.items' <<<"$output")" = '["offen","geschlossen"]' ]
    [ "$(jq -c '.by_category' <<<"$output")" = '[{"category":"other","count":2,"points":4}]' ]
    [[ "$stderr" == *'Warnung: geschlossen: status "closed" unbekannt, zählt als offen im Backlog'* ]]
    [[ "$stderr" != *"erledigt"* ]]
}

@test "tech-debt-report: unbekannte Severity zaehlt wie medium und warnt auf stderr" {
    need_jq
    echo '[{"title": "Blocker", "severity": "blocker", "effort": "huge"}]' > "$TMP/unbekannt.json"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/unbekannt.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.summary.tech_debt_score' <<<"$output")" = "10" ]
    [ "$(jq -c '[.top_priority[].priority]' <<<"$output")" = "[2]" ]
    [[ "$stderr" == *'Warnung: Blocker: severity "blocker" unbekannt, zählt wie medium (10 Punkte)'* ]]
    [[ "$stderr" == *'Warnung: Blocker: effort "huge" unbekannt, zählt wie medium (Aufwand 5)'* ]]
}

@test "tech-debt-report: leere Liste ist gesund mit Score 0" {
    need_jq
    echo '[]' > "$TMP/leer.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/leer.json"
    [ "$status" -eq 0 ]
    has_line "Tech Debt Score:    0 Punkte (healthy; < 200 gesund, ab 500 kritisch)"
    has_line "Keine offenen Items."
    has_line "GUT: Tech Debt minimal."
}

@test "tech-debt-report: ab 500 Punkten KRITISCH, Top-Liste hat fuenf Eintraege" {
    need_jq
    # 5 x critical/xlarge (100 / 21 = 4.8) + low/trivial (2 / 1 = 2)
    jq -n '[range(5) | {title: "c\(.)", severity: "critical", effort: "xlarge"}]
           + [{title: "klein", severity: "low", effort: "trivial"}]' > "$TMP/krit.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/krit.json"
    [ "$status" -eq 0 ]
    has_line "Tech Debt Score:    502 Punkte (critical; < 200 gesund, ab 500 kritisch)"
    has_line "KRITISCH: Tech Debt Sprint empfohlen!"
    has_line "☐ c0 (ohne Stundenschätzung, critical: sofort, vor dem Budget)"
    [ "$(plain | grep -c '^    Category: ')" -eq 5 ]
    has_line "    Category: other | Severity: critical | Priority: 4.8 | Hours: ?"
    run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/krit.json"
    [ "$(jq -c '[.top_priority[].priority]' <<<"$output")" = "[4.8,4.8,4.8,4.8,4.8]" ]
}

@test "tech-debt-report: rechnet wie TechDebtTrackerService (gemeinsame Fixture)" {
    need_jq
    n="$(jq 'length' "$EQUIV")"
    [ "$n" -ge 7 ]
    for i in $(seq 0 $((n - 1))); do
        name="$(jq -r ".[$i].name" "$EQUIV")"
        jq ".[$i].items" "$EQUIV" > "$TMP/case.json"
        run --separate-stderr bash "$DIR/tech-debt-report.sh" --json "$TMP/case.json"
        [ "$status" -eq 0 ] || { echo "Fall $name: Exit $status"; false; }
        # by_category: Skript alphabetisch, Service in Reihenfolge des Auftretens
        actual="$(jq -cS '{total_score: .summary.tech_debt_score, status: .summary.health,
            by_category: (.by_category | map({(.category): .points}) | add // {}),
            item_count: .summary.total_items, top_titles: [.top_priority[].title]}' <<<"$output")"
        expected="$(jq -cS ".[$i].expected" "$EQUIV")"
        [ "$actual" = "$expected" ] || { echo "Fall $name"; echo "Skript: $actual"; echo "PHP:    $expected"; false; }
    done
}

@test "tech-debt-report: Items ohne Stundenschaetzung werden genannt, nicht eingeplant" {
    need_jq
    echo '[{"title": "mit", "severity": "high", "effort": "small", "estimated_hours": 0.1},
           {"title": "auch mit", "severity": "high", "effort": "small", "estimated_hours": 0.2},
           {"title": "ohne", "severity": "medium", "effort": "small"}]' > "$TMP/stunden.json"
    run bash "$DIR/tech-debt-report.sh" "$TMP/stunden.json"
    [ "$status" -eq 0 ]
    # 0.1 + 0.2 ohne Binaerrest
    has_line "Geschätzte Stunden: 0.3h (Backlog), 1 Items ohne Schätzung"
    has_line "☐ mit (0.1h)"
    has_line "  ohne Stundenschätzung, nicht eingeplant: ohne"
    has_line "    Category: other | Severity: medium | Priority: 5 | Hours: ?"
}

@test "tech-debt-report: --trend liest die Verlaufsdatei, Demo gekennzeichnet" {
    need_jq
    run bash "$DIR/tech-debt-report.sh" --trend "$EX/tech-debt-history.demo.json" "$EX/tech-debt.demo.json"
    [ "$status" -eq 0 ]
    has_line "HINWEIS: BEISPIELDATEN aus tech-debt-history.demo.json, keine Messung"
    has_line "Monat 3: Score 230 | Items: 5 | Hours: 60h"
    has_line "Trend: improving ↓"

    cp "$EX/tech-debt.demo.json" "$TMP/tech-debt.json"
    echo '[{"month": "Jan", "score": 100}, {"month": "Feb", "score": 180}]' > "$TMP/steigt.json"
    run bash "$DIR/tech-debt-report.sh" --trend "$TMP/steigt.json" "$TMP/tech-debt.json"
    [ "$status" -eq 0 ]
    has_line "Feb: Score 180"
    has_line "Trend: worsening ↑"
    lacks_text "$DEMO_NOTE"

    echo '[{"month": "Jan", "score": 100}, {"month": "Feb", "score": 100}]' > "$TMP/gleich.json"
    run bash "$DIR/tech-debt-report.sh" --trend "$TMP/gleich.json" "$TMP/tech-debt.json"
    has_line "Trend: stable →"
}

@test "tech-debt-report: --trend ohne gueltige Verlaufsdatei" {
    need_jq
    run bash "$DIR/tech-debt-report.sh" --trend
    [ "$status" -eq 1 ]
    [[ "$output" == *"--trend braucht eine Verlaufsdatei"* ]]
    run bash "$DIR/tech-debt-report.sh" --trend --json "$EX/tech-debt.demo.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--trend braucht eine Verlaufsdatei"* ]]
    while IFS='|' read -r json message; do
        echo "$json" > "$TMP/verlauf.json"
        run bash "$DIR/tech-debt-report.sh" --trend "$TMP/verlauf.json" "$EX/tech-debt.demo.json"
        [ "$status" -eq 65 ] || { echo "$json -> $status"; false; }
        [[ "$output" == *"$message"* ]] || { echo "$json -> $output"; false; }
    done <<'CASES'
[]|Der Verlauf ist leer
{"a": 1}|muss eine JSON-Liste sein
[{"score": 1}]|month fehlt
[{"month": "M"}]|score fehlt
[{"month": "M", "score": 1, "items": "5"}]|items ist keine Zahl
[{"month": "M", "score": 1, "hours": {}}]|hours ist keine Zahl
CASES
}

@test "jq fehlt: alle drei Skripte enden mit Exit 2" {
    mkdir "$TMP/nojq"
    for tool in dirname basename; do ln -s "$(command -v "$tool")" "$TMP/nojq/$tool"; done
    echo '[]' > "$TMP/e.json"
    PATH="$TMP/nojq" run "$BASH" "$DIR/tech-debt-report.sh" "$TMP/e.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"jq fehlt"* ]]
    PATH="$TMP/nojq" run "$BASH" "$DIR/quarterly-review.sh" "$TMP/e.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"jq fehlt"* ]]
    PATH="$TMP/nojq" run "$BASH" "$DIR/roadmap-status.sh" --file "$TMP/e.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"jq fehlt"* ]]
}

# ============================================================
# quarterly-review.sh
# ============================================================

@test "quarterly-review: Demo ergibt die alten Werte und ist gekennzeichnet" {
    need_jq
    run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json"
    [ "$status" -eq 0 ]
    has_line "HINWEIS: BEISPIELDATEN aus quarterly-review.demo.json, keine Messung"
    has_line "Quick Summary (BEISPIELDATEN aus quarterly-review.demo.json, keine Messung):"
    # (3200 - 2450) / 3200 = 23.4375 %, (220 - 175) / 220 = 20.45 %
    has_line "  - CWV Improvement: LCP 23.4%, INP 20.5%"
    has_line "  - OKR Score: 0.97 (Exceptional)"
    has_line "  - Incidents: 0 P0, 1 P1"
    has_line "  - Tech Debt: 80h abgebaut, Score 230 (attention)"
    report="$OUTPUT_DIR/quarterly-review-Q2-2026.md"
    [ -f "$report" ]
    grep -qxF "> **BEISPIELDATEN aus quarterly-review.demo.json, keine Messung.** Die Zahlen zeigen nur den Aufbau des Reports." "$report"
    grep -qxF "| **Total Q** | **CHF 11'250** | **CHF 11'125** | **-1%** |" "$report"
    grep -qxF "| Infrastructure | CHF 5'000 | CHF 5'500 | +10% |" "$report"
    grep -qxF "**Jahres-Budget Status**: 48% verbraucht (Ziel: 50%)" "$report"
    grep -qxF "| LCP (p75) | 3200ms | 2450ms | **23.4%** ↓ |" "$report"
    grep -qxF "| CLS (p75) | 0.12 | 0.06 | **50.0%** ↓ |" "$report"
    grep -qxF "Alle Core Web Vitals im 'Good' Bereich." "$report"
    grep -qxF "| **Total** | **4** |" "$report"
    grep -qxF -- "- MTTR (Mean Time to Recovery): 1.8 Stunden" "$report"
    grep -qxF "1. Third-Party Script Blocking (2 Incidents)" "$report"
    grep -qxF "2. Cache Invalidation Issue (1 Incident)" "$report"
    grep -qxF "| Backlog Items | 18 | 12 | ↓ 33% |" "$report"
    grep -qxF "**Objective Score**: 0.94 (Exceptional)" "$report"
    grep -qxF "## Planung Q3 2026" "$report"
}

@test "quarterly-review: echte Eingabe ohne Beispieldaten-Hinweis, Felder richtig zugeordnet" {
    need_jq
    cat > "$TMP/q3.json" <<'JSON'
{
    "quarter": "Q3", "year": 2027,
    "cwv": {"lcp_ms": {"start": 4000, "end": 3000}, "inp_ms": {"start": 300, "end": 240},
            "cls": {"start": 0.2, "end": 0.15}},
    "okrs": [{"objective": "O1", "key_results": [
        {"title": "KR a", "score": 0.9}, {"title": "KR b", "score": 0.9}, {"title": "KR c", "score": 0.89}]}],
    "incidents": {"p0": 2, "p1": 0, "p2": 5, "postmortems_done": 6},
    "tech_debt": {"start": {"items": 0, "hours": 100, "score": 199},
                  "end": {"items": 20, "hours": 100, "score": 500},
                  "resolved": [{"title": "R", "hours": 7}]},
    "budget": {"annual_total": 10000, "spent_year_to_date": 7000,
               "categories": [{"category": "Tools | Lizenzen", "planned": 1000, "spent": 1234}]}
}
JSON
    run bash "$DIR/quarterly-review.sh" "$TMP/q3.json"
    [ "$status" -eq 0 ]
    lacks_text "$DEMO_NOTE"
    has_line "Quick Summary:"
    has_line "  - CWV Improvement: LCP 25.0%, INP 20.0%"
    # Mittel 0.8967 wird als 0.90 angezeigt; die Stufe haengt am angezeigten
    # Wert (Exceptional), nicht am ungerundeten (Strong)
    has_line "  - OKR Score: 0.90 (Exceptional)"
    has_line "  - Incidents: 2 P0, 0 P1"
    has_line "  - Tech Debt: 7h abgebaut, Score 500 (critical)"
    report="$OUTPUT_DIR/quarterly-review-Q3-2027.md"
    run ! grep -q "$DEMO_NOTE" "$report"
    grep -qxF "**Eingabe**: q3.json" "$report"
    grep -qxF "**Zeitraum**: 2027-07-01 bis 2027-09-30" "$report"
    grep -qxF "| LCP (p75) | 4000ms | 3000ms | **25.0%** ↓ |" "$report"
    grep -qxF "| INP (p75) | 300ms | 240ms | **20.0%** ↓ |" "$report"
    grep -qxF "| CLS (p75) | 0.2 | 0.15 | **25.0%** ↓ |" "$report"
    grep -qxF "Nicht im 'Good' Bereich: LCP (3000ms > 2500ms), INP (240ms > 200ms), CLS (0.15 > 0.1)." "$report"
    grep -qxF "| **Total** | **7** |" "$report"
    grep -qxF -- "- Abgeschlossen: 6/7 (86%)" "$report"
    # Start 0: keine Veraenderung in Prozent
    grep -qxF "| Backlog Items | 0 | 20 | ↑ – |" "$report"
    grep -qxF "| Tech Debt Score (Severity-Punkte, Kapitel 15) | 199 | 500 | ↑ critical (< 200 gesund) |" "$report"
    # Vorgabe-Waehrung CHF, "|" im Text zerlegt die Tabelle nicht
    grep -qxF '| Tools \| Lizenzen | CHF 1'"'"'000 | CHF 1'"'"'234 | +23% |' "$report"
    # Q3: linear 75 % des Jahres
    grep -qxF "**Jahres-Budget Status**: 70% verbraucht (Ziel: 75%)" "$report"
}

@test "quarterly-review: OKR-Stufen an den Grenzen, Gewichte wie der Service" {
    need_jq
    # Score | erwartete Anzeige und Stufe (Stufe am angezeigten, gerundeten Wert)
    while IFS='|' read -r score expected; do
        echo "{\"quarter\": \"Q1\", \"year\": 2027, \"okrs\": [{\"objective\": \"O\",
              \"key_results\": [{\"title\": \"K\", \"score\": $score}]}]}" > "$TMP/okr.json"
        run bash "$DIR/quarterly-review.sh" "$TMP/okr.json"
        [ "$status" -eq 0 ]
        has_line "  - OKR Score: $expected"
        grep -qxF "**Objective Score**: $expected" "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
    done <<'CASES'
0.895|0.90 (Exceptional)
0.894|0.89 (Strong)
0.7|0.70 (Strong)
0.694|0.69 (On Track)
0.495|0.50 (On Track)
0.494|0.49 (At Risk)
0.3|0.30 (At Risk)
0.294|0.29 (Off Track)
CASES
    # wie PHP round(): (0.44 + 0.49) / 2 = 0.46499999999999997 -> 0.46
    echo '{"quarter": "Q1", "year": 2027, "okrs": [{"objective": "O", "key_results": [
          {"title": "a", "score": 0.44}, {"title": "b", "score": 0.49}]}]}' > "$TMP/okr.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/okr.json"
    has_line "  - OKR Score: 0.46 (At Risk)"
    # Gewicht: (1.0 * 3 + 0.0 * 1) / 4 = 0.75
    echo '{"quarter": "Q1", "year": 2027, "okrs": [{"objective": "O", "key_results": [
          {"title": "a", "score": 1.0, "weight": 3}, {"title": "b", "score": 0.0}]}]}' > "$TMP/okr.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/okr.json"
    has_line "  - OKR Score: 0.75 (Strong)"
    # Gesamt (0.70 + 0.69) / 2 = 0.695 -> angezeigt 0.70, Stufe am angezeigten Wert
    echo '{"quarter": "Q1", "year": 2027, "okrs": [
          {"objective": "A", "key_results": [{"title": "a", "score": 0.7}]},
          {"objective": "B", "key_results": [{"title": "b", "score": 0.69}]}]}' > "$TMP/okr.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/okr.json"
    has_line "  - OKR Score: 0.70 (Strong)"
    grep -qxF "| **Durchschnitt** | **0.70** | **Strong** |" "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
    grep -qxF "| B | 0.69 | On Track |" "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
    # Gesamtwert = Mittel der gerundeten Objective-Scores wie der Service:
    # (0.00 + 0.11) / 2 = 0.055 -> 0.06; ungerundet (0 + 0.105) / 2 -> 0.05
    echo '{"quarter": "Q1", "year": 2027, "okrs": [
          {"objective": "A", "key_results": [{"title": "a", "score": 0}]},
          {"objective": "B", "key_results": [{"title": "b", "score": 0.105}]}]}' > "$TMP/okr.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/okr.json"
    has_line "  - OKR Score: 0.06 (Off Track)"
}

@test "quarterly-review: CWV-Grenzen 2500 ms, 200 ms, 0.1 sind noch Good" {
    need_jq
    cwv() {
        echo "{\"quarter\": \"Q1\", \"year\": 2027, \"cwv\": {\"lcp_ms\": {\"start\": 3000, \"end\": $1},
              \"inp_ms\": {\"start\": 300, \"end\": $2}, \"cls\": {\"start\": 0.2, \"end\": $3}}}" > "$TMP/cwv.json"
        run bash "$DIR/quarterly-review.sh" "$TMP/cwv.json"
        [ "$status" -eq 0 ]
    }
    cwv 2500 200 0.1
    grep -qxF "Alle Core Web Vitals im 'Good' Bereich." "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
    cwv 2501 200 0.1
    grep -qxF "Nicht im 'Good' Bereich: LCP (2501ms > 2500ms)." "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
    cwv 2500 201 0.1
    grep -qxF "Nicht im 'Good' Bereich: INP (201ms > 200ms)." "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
    cwv 2500 200 0.11
    grep -qxF "Nicht im 'Good' Bereich: CLS (0.11 > 0.1)." "$OUTPUT_DIR/quarterly-review-Q1-2027.md"
}

@test "quarterly-review: Tech-Debt-Stufe an den Grenzen 200 und 500" {
    need_jq
    for pair in "199:healthy" "200:attention" "499:attention" "500:critical"; do
        score="${pair%%:*}"; health="${pair##*:}"
        echo "{\"quarter\": \"Q1\", \"year\": 2027, \"tech_debt\": {\"start\": {\"items\": 1, \"hours\": 1, \"score\": 1},
              \"end\": {\"items\": 1, \"hours\": 1, \"score\": $score}}}" > "$TMP/td.json"
        run bash "$DIR/quarterly-review.sh" "$TMP/td.json"
        [ "$status" -eq 0 ]
        has_line "  - Tech Debt: 0h abgebaut, Score $score ($health)"
    done
}

@test "quarterly-review: Zahlen aus der Eingabe unabhaengig von der jq-Version" {
    need_jq
    # jq ab 1.7 behielte die Schreibweise der Eingabe: 2026.0, 2.45E+3, 8.0
    echo '{"quarter": "Q1", "year": 2026.0,
           "cwv": {"lcp_ms": {"start": 3.2E+3, "end": 2.45E+3}, "inp_ms": {"start": 220.0, "end": 175},
                   "cls": {"start": 0.12, "end": 0.06}},
           "incidents": {"p0": 0, "p1": 1.0, "p2": 3, "mttr_hours": 1.80},
           "tech_debt": {"start": {"items": 18.0, "hours": 240, "score": 410}, "end": {"items": 12, "hours": 160, "score": 230},
                         "resolved": [{"title": "a", "hours": 0.1}, {"title": "b", "hours": 0.2}]}}' > "$TMP/lit.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/lit.json"
    [ "$status" -eq 0 ]
    report="$OUTPUT_DIR/quarterly-review-Q1-2026.md"
    [ -f "$report" ]
    grep -qxF "**Zeitraum**: 2026-01-01 bis 2026-03-31" "$report"
    grep -qxF "| LCP (p75) | 3200ms | 2450ms | **23.4%** ↓ |" "$report"
    grep -qxF "| INP (p75) | 220ms | 175ms | **20.5%** ↓ |" "$report"
    grep -qxF "| P1 (High) | 1 |" "$report"
    grep -qxF -- "- MTTR (Mean Time to Recovery): 1.8 Stunden" "$report"
    grep -qxF "| Backlog Items | 18 | 12 | ↓ 33% |" "$report"
    grep -qxF "**Total**: 0.3 Stunden Tech Debt abgebaut" "$report"
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
    need_jq
    run bash "$DIR/quarterly-review.sh" "$TMP/gibt-es-nicht.json"
    [ "$status" -eq 66 ]

    printf '{"quarter": "Q2",' > "$TMP/kaputt.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/kaputt.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"kein gültiges JSON"* ]]

    # Eingabe (nach quarter und year) | erwartete Meldung
    while IFS='|' read -r json message; do
        echo "{\"quarter\": \"Q2\", \"year\": 2026 $json}" > "$TMP/fall.json"
        run bash "$DIR/quarterly-review.sh" "$TMP/fall.json"
        [ "$status" -eq 65 ] || { echo "$json -> $status: $output"; false; }
        [[ "$output" == *"$message"* ]] || { echo "$json -> $output"; false; }
    done <<'CASES'
, "cwv": {"lcp_ms": {"start": 3000, "end": 2000}}|cwv.inp_ms.start fehlt oder ist keine Zahl
, "cwv": {"lcp_ms": {"start": 0, "end": 1}, "inp_ms": {"start": 1, "end": 1}, "cls": {"start": 1, "end": 1}}|cwv.lcp_ms.start muss > 0 sein
, "cwv": {"lcp_ms": {"start": 1, "end": -1}, "inp_ms": {"start": 1, "end": 1}, "cls": {"start": 1, "end": 1}}|cwv.lcp_ms.end ist negativ
, "cwv": "x"|cwv muss ein Objekt sein
, "okrs": []|okrs muss eine nicht leere Liste sein
, "okrs": [{"objective": "O", "key_results": [{"title": "K", "score": 1.5}]}]|okrs.0.key_results.0.score muss eine Zahl von 0 bis 1 sein
, "okrs": [{"objective": "O", "key_results": [{"title": "K", "score": 1, "weight": 0}]}]|weight muss eine Zahl > 0 sein
, "okrs": [{"key_results": [{"title": "K", "score": 1}]}]|okrs.0.objective fehlt
, "okrs": [{"objective": "O", "key_results": []}]|okrs.0.key_results muss eine nicht leere Liste sein
, "incidents": {"p0": 0.5, "p1": 0, "p2": 0}|incidents.p0 muss eine ganze Zahl sein
, "incidents": {"p0": 1, "p1": 0, "p2": 0, "postmortems_done": 2}|postmortems_done ist grösser als p0 + p1 + p2
, "incidents": {"p0": 1, "p1": 0, "p2": 0, "root_causes": [{"cause": "x", "count": -3}]}|root_causes.0 braucht cause (Text) und count (ganze Zahl >= 0)
, "tech_debt": {"start": {"items": 1, "hours": 1, "score": 1}}|tech_debt.end.items fehlt oder ist keine Zahl
, "budget": {"categories": []}|budget.categories muss eine nicht leere Liste sein
, "budget": {"categories": [{"category": "a", "planned": 0, "spent": 1}]}|budget.categories.0 braucht category, planned (> 0) und spent (>= 0)
, "budget": {"currency": 5, "categories": [{"category": "a", "planned": 1, "spent": 1}]}|budget.currency muss ein Text sein
, "budget": {"annual_total": 5, "categories": [{"category": "a", "planned": 1, "spent": 1}]}|budget.annual_total und budget.spent_year_to_date nur zusammen
, "sections": [{"title": "T"}]|sections.0 braucht title und markdown
CASES

    for bad in '{"year": 2026}' '{"quarter": "Q9", "year": 2026}' '{"quarter": "Q1", "year": 2026.5}' '{"quarter": "Q1", "year": 1999}' '[1]'; do
        echo "$bad" > "$TMP/fall.json"
        run bash "$DIR/quarterly-review.sh" "$TMP/fall.json"
        [ "$status" -eq 65 ] || { echo "$bad -> $status"; false; }
    done
    [ ! -e "$OUTPUT_DIR" ]
}

@test "quarterly-review: fehlende Bloecke heissen keine Daten, nicht null" {
    need_jq
    echo '{"quarter": "Q4", "year": 2026}' > "$TMP/min.json"
    run bash "$DIR/quarterly-review.sh" "$TMP/min.json"
    [ "$status" -eq 0 ]
    has_line "  - CWV Improvement: keine Daten"
    has_line "  - OKR Score: keine Daten"
    has_line "  - Incidents: keine Daten"
    has_line "  - Tech Debt: keine Daten"
    report="$OUTPUT_DIR/quarterly-review-Q4-2026.md"
    [ "$(grep -c '_Keine Daten in der Eingabe' "$report")" -eq 5 ]
    run ! grep -q "null" "$report"
}

@test "quarterly-review: --output schreibt genau dorthin, ein Verzeichnis ist Exit 1" {
    need_jq
    run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json" --output "$TMP/out/mein-report.md"
    [ "$status" -eq 0 ]
    [ -f "$TMP/out/mein-report.md" ]
    [ ! -e "$OUTPUT_DIR" ]
    mkdir -p "$TMP/ziel"
    run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json" --output "$TMP/ziel/"
    [ "$status" -eq 1 ]
    [[ "$output" == *"kein Verzeichnis"* ]]
    run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json" --output "$TMP/ziel"
    [ "$status" -eq 1 ]
    [ -z "$(ls -A "$TMP/ziel")" ]
}

@test "quarterly-review: ohne OUTPUT_DIR landet der Report in reports/ neben scripts/" {
    need_jq
    mkdir -p "$TMP/kapitel/scripts"
    cp "$DIR/quarterly-review.sh" "$TMP/kapitel/scripts/"
    unset OUTPUT_DIR
    run bash "$TMP/kapitel/scripts/quarterly-review.sh" "$EX/quarterly-review.demo.json"
    [ "$status" -eq 0 ]
    [ -f "$TMP/kapitel/reports/quarterly-review-Q2-2026.md" ]
}

@test "quarterly-review: bricht jq beim Report ab, bleibt keine halbe Datei" {
    need_jq
    REAL_JQ="$(command -v jq)"
    mkdir "$TMP/bin"
    # Stub: scheitert nur beim Programm, das den Report schreibt
    cat > "$TMP/bin/jq" <<STUB
#!/bin/sh
for a in "\$@"; do
    case "\$a" in *"## Executive Summary"*) echo "jq-Stub: Abbruch" >&2; exit 5 ;; esac
done
exec "$REAL_JQ" "\$@"
STUB
    chmod +x "$TMP/bin/jq"
    PATH="$TMP/bin:$PATH" run bash "$DIR/quarterly-review.sh" "$EX/quarterly-review.demo.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"jq-Stub: Abbruch"* ]]
    [ -d "$OUTPUT_DIR" ]
    [ -z "$(ls -A "$OUTPUT_DIR")" ]
}

# ============================================================
# roadmap-status.sh
# ============================================================

@test "roadmap-status: Demo zum Stichtag zeigt jeden Zweig und alle Milestones je Quartal" {
    need_jq
    run bash "$DIR/roadmap-status.sh" --file "$EX/roadmap-status.demo.json" --stichtag 2026-09-15
    [ "$status" -eq 0 ]
    [ "$(plain | head -1)" = "HINWEIS: BEISPIELDATEN aus roadmap-status.demo.json, keine Messung" ]
    has_line "Stichtag: 2026-09-15"
    has_line "Aktuelles Quartal: Q3 2026"
    has_line "  ✓ Completed:    2"
    has_line "  ⏳ In Progress:  1"
    has_line "  ⚠ At Risk:      1"
    has_line "  ✗ Overdue:      1"
    has_line "  ○ Pending:      1"
    has_line "  Total:          6"
    has_line "  Progress: [██████░░░░░░░░░░░░░░] 33%"
    has_line "  [OVERDUE] Checkout LCP < 2s"
    has_line "           Target: 2026-09-10 (5 days ago)"
    has_line "  [AT RISK] Redis produktiv (Kapitel 7)"
    has_line "           Target: 2026-10-05 (20 days remaining)"
    # volle Gruppierung: M-1 bis M-4 im Q3, M-5 und M-6 im Q4
    q3="$(plain | sed -n '/^  2026-Q3$/,/^$/p')"
    q4="$(plain | sed -n '/^  2026-Q4$/,/^$/p')"
    for id in M-1 M-2 M-3 M-4; do [[ "$q3" == *"[$id]"* ]]; [[ "$q4" != *"[$id]"* ]]; done
    for id in M-5 M-6; do [[ "$q4" == *"[$id]"* ]]; [[ "$q3" != *"[$id]"* ]]; done
    has_line "      Target: 2026-09-10 (5d overdue)"
    has_line "      Target: 2026-09-25 (10d remaining)"
    has_line "      Target: 2026-10-30 (45d remaining)"
    has_line "      Target: 2026-07-17 "
    has_line "  [R-003] Black Friday Vorbereitung zu spät"
    has_line "      Probability: high | Impact: high"
    has_line "      Mitigation: 20% Performance-Zeit vertraglich festlegen"
    has_line "  • Überfällige Milestones sofort adressieren"
    has_line "  • At-Risk Items priorisieren"
    has_line "  • Fortschritt unter 50%"
    lacks_text "Roadmap auf Kurs!"
}

@test "roadmap-status: liest ROADMAP_FILE, echte Datei ohne Beispieldaten-Hinweis" {
    need_jq
    echo '{"milestones": [{"id": "X-1", "title": "Nur aus ROADMAP_FILE", "target_date": "2027-01-15", "status": "completed"}],
           "risks": [{"id": "", "risk": "leere id", "probability": "high", "impact": "low"},
                     {"risk": "ohne id\tmit Tab", "probability": "low", "impact": "low", "mitigation": null}]}' \
        > "$TMP/status.json"
    ROADMAP_FILE="$TMP/status.json" run bash "$DIR/roadmap-status.sh" --stichtag 2027-02-01 --quarter Q3
    [ "$status" -eq 0 ]
    has_line "  ✓ [X-1] Nur aus ROADMAP_FILE"
    has_line "  Total:          1"
    # --quarter setzt nur die Anzeige, der Stichtag laege in Q1
    has_line "Aktuelles Quartal: Q3 2027"
    has_line "  • Roadmap auf Kurs!"
    # fehlende oder leere id wird R-n, die Spalten verschieben sich nicht
    has_line "  [R-1] leere id"
    has_line "      Probability: high | Impact: low"
    has_line "  [R-2] ohne id mit Tab"
    lacks_text "$DEMO_NOTE"
    lacks_text "[M-1]"
}

@test "roadmap-status: ohne Statusdatei Usage und Exit 1, keine Demo" {
    run bash "$DIR/roadmap-status.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"Roadmap Status Check"* ]]
    run bash "$DIR/roadmap-status.sh" --alerts-only
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "roadmap-status: kaputte Statusdateien enden mit Meldung und Exit 65/66" {
    need_jq
    run bash "$DIR/roadmap-status.sh" --file "$TMP/gibt-es-nicht.json"
    [ "$status" -eq 66 ]

    run bash "$DIR/roadmap-status.sh" --file "./chapters/15-langfristiger-plan/templates/roadmap.yaml"
    [ "$status" -eq 65 ]
    [[ "$output" == *"ist YAML"* ]]

    printf '{"milestones": [' > "$TMP/kaputt.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/kaputt.json"
    [ "$status" -eq 65 ]
    [[ "$output" == *"kein gültiges JSON"* ]]

    while IFS='|' read -r json message; do
        echo "$json" > "$TMP/fall.json"
        run bash "$DIR/roadmap-status.sh" --file "$TMP/fall.json"
        [ "$status" -eq 65 ] || { echo "$json -> $status: $output"; false; }
        [[ "$output" == *"$message"* ]] || { echo "$json -> $output"; false; }
    done <<'CASES'
[]|muss ein JSON-Objekt sein
{"risks": []}|milestones fehlt oder ist keine Liste
{"milestones": [{"title": "t", "target_date": "2026-03-01", "status": "pending"}]}|milestones.0: id fehlt oder ist kein Text
{"milestones": [{"id": 5, "title": "t", "target_date": "2026-03-01", "status": "pending"}]}|milestones.0: id fehlt oder ist kein Text
{"milestones": [{"id": "A", "target_date": "2026-03-01", "status": "pending"}]}|milestones.0 (A): title fehlt
{"milestones": [{"id": "A", "title": "t", "target_date": "2026-03-01", "status": "done"}]}|milestones.0 (A): status muss completed, in_progress, at_risk oder pending sein
{"milestones": [{"id": "A", "title": "t", "target_date": "2026-02-30", "status": "pending"}]}|target_date ist kein Datum
{"milestones": [{"id": "A", "title": "t", "target_date": "1.3.2026", "status": "pending"}]}|target_date ist kein Datum
{"milestones": [], "risks": [{"risk": "r", "probability": "huge", "impact": "low"}]}|probability und impact
{"milestones": [], "risks": [{"probability": "low", "impact": "low"}]}|risks.0: risk fehlt
{"milestones": [], "risks": [{"risk": "r", "probability": "low", "impact": "low", "mitigation": 5}]}|risks.0: mitigation ist kein Text
{"milestones": [], "risks": [{"id": 1, "risk": "r", "probability": "low", "impact": "low"}]}|risks.0: id ist kein Text
{"milestones": [], "risks": {}}|risks muss eine Liste sein
CASES
}

@test "roadmap-status: leere Milestone-Liste ohne Division durch null" {
    need_jq
    echo '{"milestones": []}' > "$TMP/leer.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/leer.json"
    [ "$status" -eq 0 ]
    has_line "  Total:          0"
    has_line "  Keine Milestones in der Statusdatei."
    has_line "  Keine Risiken in der Statusdatei."
}

@test "roadmap-status: am Zieltag nicht ueberfaellig, am Tag danach schon" {
    need_jq
    echo '{"milestones": [
        {"id": "H", "title": "heute faellig", "target_date": "2026-09-15", "status": "pending"},
        {"id": "G", "title": "gestern faellig", "target_date": "2026-09-14", "status": "in_progress"},
        {"id": "E", "title": "erledigt, alt", "target_date": "2026-01-01", "status": "completed"}]}' > "$TMP/grenze.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/grenze.json" --stichtag 2026-09-15 --alerts-only
    [ "$status" -eq 0 ]
    has_line "  [OVERDUE] gestern faellig"
    has_line "           Target: 2026-09-14 (1 days ago)"
    lacks_text "heute faellig"
    lacks_text "erledigt, alt"
}

@test "roadmap-status: Monat 08 und 09 sind Q3, auch ueber das heutige Datum" {
    need_jq
    echo '{"milestones": []}' > "$TMP/leer.json"
    for day in 2026-08-01 2026-09-30; do
        run bash "$DIR/roadmap-status.sh" --file "$TMP/leer.json" --stichtag "$day"
        [ "$status" -eq 0 ]
        has_line "Aktuelles Quartal: Q3 2026"
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
    has_line "Stichtag: 2026-09-01"
    has_line "Aktuelles Quartal: Q3 2026"
}

@test "roadmap-status: --quarter und --stichtag ohne gueltigen Wert sind Exit 1" {
    run bash "$DIR/roadmap-status.sh" --quarter
    [ "$status" -eq 1 ]
    [[ "$output" == *"--quarter braucht"* ]]
    run bash "$DIR/roadmap-status.sh" --stichtag 15.09.2026
    [ "$status" -eq 1 ]
    [[ "$output" == *"--stichtag braucht"* ]]
}

@test "roadmap-status: --stichtag prueft den Kalender" {
    need_jq
    run bash "$DIR/roadmap-status.sh" --file "$EX/roadmap-status.demo.json" --stichtag 2026-02-30
    [ "$status" -eq 1 ]
    [[ "$output" == *"--stichtag 2026-02-30 ist kein gültiges Datum"* ]]
}

@test "roadmap-status: --alerts-only ohne Alerts meldet No alerts." {
    need_jq
    echo '{"milestones": [{"id": "A", "title": "t", "target_date": "2026-12-01", "status": "pending"}]}' > "$TMP/ruhig.json"
    run bash "$DIR/roadmap-status.sh" --file "$TMP/ruhig.json" --stichtag 2026-09-15 --alerts-only
    [ "$status" -eq 0 ]
    [ "$output" = "No alerts." ]
}
