#!/bin/bash
#
# Tech Debt Report Generator
#
# Generiert einen Report über Performance-bezogene Technical Debt aus einer
# Eingabedatei. Zeigt priorisierte Backlog-Items und Empfehlungen.
#
# Eingabe: JSON-Liste im Format von TechDebtRepository::findAllPerformanceDebt()
# (src/TechDebtRepository.php), also nur offene Items:
#   [{"title": "...", "severity": "high", "effort": "small", "category": "frontend"}]
# Pflicht: title, severity, effort. Optional: category (fehlt = "other"), id,
# estimated_hours (Stunden, für Stundensumme und Sprint-Empfehlung) und
# status ("backlog", "in_progress" = in Arbeit, "resolved" fällt überall heraus;
# andere Werte zählen als offen, mit Warnung). null gilt wie ein fehlendes Feld.
#
# Skala wie Kapitel 15 (src/TechDebtTrackerService.php): Score = Summe der
# Severity-Punkte offener Items, critical 100, high 40, medium 10, low 2;
# < 200 gesund, 200-499 Aufmerksamkeit, ab 500 kritisch. Priorität =
# Severity-Punkte / Aufwandspunkte (trivial 1, small 2, medium 5, large 13,
# xlarge 21). Unbekannte Werte zählen wie medium (10 Punkte, Aufwand 5) wie im
# Service; das Skript warnt dann auf stderr.
#
# Beispieldaten: examples/tech-debt.demo.json und
# examples/tech-debt-history.demo.json. Nur wenn eine Datei auf .demo.json
# endet, kennzeichnet die Ausgabe sie als BEISPIELDATEN.
#
# Verwendung:
#   ./tech-debt-report.sh tech-debt.json
#   ./tech-debt-report.sh --trend verlauf.json tech-debt.json
#   ./tech-debt-report.sh --json tech-debt.json
#   ./tech-debt-report.sh ../examples/tech-debt.demo.json   # Demo
#
# Exit-Codes: 0 ok, 1 Aufruf falsch, 2 jq fehlt, 65 Eingabe ungültig,
# 66 Eingabe fehlt oder ist nicht lesbar.
#
# Voraussetzungen:
#   - jq ab 1.6

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--trend VERLAUF.json] [--json] EINGABE.json" >&2
    echo "  EINGABE.json: Liste offener Items wie TechDebtRepository::findAllPerformanceDebt()" >&2
    echo "  Demo: $(basename "$0") examples/tech-debt.demo.json" >&2
}

SHOW_TREND=false
TREND_FILE=""
OUTPUT_FORMAT="text"
INPUT_FILE=""

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --trend)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "Fehler: --trend braucht eine Verlaufsdatei" >&2
                usage
                exit 1
            fi
            SHOW_TREND=true
            TREND_FILE="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unbekanntes Argument: $1" >&2
            usage
            exit 1
            ;;
        *)
            if [[ -n "${INPUT_FILE}" ]]; then
                echo "Fehler: nur eine Eingabedatei" >&2
                usage
                exit 1
            fi
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "${INPUT_FILE}" ]]; then
    echo "Fehler: keine Eingabedatei" >&2
    usage
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Fehler: jq fehlt (apt install jq)" >&2
    exit 2
fi

# Datei vorhanden, lesbar, gültiges JSON?
read_json() {
    local file=$1
    if [[ ! -f "${file}" || ! -r "${file}" ]]; then
        echo "Fehler: ${file} fehlt oder ist nicht lesbar" >&2
        exit 66
    fi
    # genau ein JSON-Wert: eine leere Datei ist für "jq empty" gültig
    if [[ "$(jq -s 'length' "${file}" 2>/dev/null)" != "1" ]]; then
        echo "Fehler: ${file} ist kein gültiges JSON (genau ein Wert erwartet)" >&2
        exit 65
    fi
}

# Beispieldaten erkennt das Skript am Dateinamen, nicht am Inhalt
is_demo() {
    [[ "$(basename "$1")" == *.demo.json ]]
}

read_json "${INPUT_FILE}"

# Pflichtfelder prüfen: die erste Verletzung je Item, mit Position
INPUT_ERRORS=$(jq -r '
    if type != "array" then "Die Eingabe muss eine JSON-Liste sein, nicht \(type)"
    else to_entries[] | .key as $i | .value |
        if type != "object" then "Item \($i): kein Objekt"
        elif (.title | type) != "string" or .title == "" then "Item \($i): title fehlt oder ist kein Text"
        elif (.severity | type) != "string" then "Item \($i) (\(.title)): severity fehlt oder ist kein Text"
        elif (.effort | type) != "string" then "Item \($i) (\(.title)): effort fehlt oder ist kein Text"
        elif .category != null and (.category | type) != "string" then "Item \($i) (\(.title)): category ist kein Text"
        elif .estimated_hours != null and ((.estimated_hours | type) != "number" or .estimated_hours < 0) then "Item \($i) (\(.title)): estimated_hours ist keine Zahl >= 0"
        elif .status != null and (.status | type) != "string" then "Item \($i) (\(.title)): status ist kein Text"
        elif .id != null and (.id | type) != "string" then "Item \($i) (\(.title)): id ist kein Text"
        else empty end
    end' "${INPUT_FILE}")
if [[ -n "${INPUT_ERRORS}" ]]; then
    echo "Fehler: ${INPUT_FILE} hat nicht das Format von findAllPerformanceDebt():" >&2
    echo "${INPUT_ERRORS}" | sed 's/^/  /' >&2
    exit 65
fi

if [[ "${SHOW_TREND}" = true ]]; then
    read_json "${TREND_FILE}"
    TREND_ERRORS=$(jq -r '
        if type != "array" then "Der Verlauf muss eine JSON-Liste sein, nicht \(type)"
        elif length == 0 then "Der Verlauf ist leer"
        else to_entries[] | .key as $i | .value |
            if type != "object" then "Eintrag \($i): kein Objekt"
            elif (.month | type) != "string" then "Eintrag \($i): month fehlt oder ist kein Text"
            elif (.score | type) != "number" then "Eintrag \($i) (\(.month)): score fehlt oder ist keine Zahl"
            elif .items != null and (.items | type) != "number" then "Eintrag \($i) (\(.month)): items ist keine Zahl"
            elif .hours != null and (.hours | type) != "number" then "Eintrag \($i) (\(.month)): hours ist keine Zahl"
            else empty end
        end' "${TREND_FILE}")
    if [[ -n "${TREND_ERRORS}" ]]; then
        echo "Fehler: ${TREND_FILE}:" >&2
        echo "${TREND_ERRORS}" | sed 's/^/  /' >&2
        exit 65
    fi
fi

# Unbekannte Werte: rechnen wie der Service (medium), aber sagen
jq -r '.[] |
    (select(.severity | IN("critical", "high", "medium", "low") | not)
        | "Warnung: \(.title): severity \"\(.severity)\" unbekannt, zählt wie medium (10 Punkte)"),
    (select(.effort | IN("trivial", "small", "medium", "large", "xlarge") | not)
        | "Warnung: \(.title): effort \"\(.effort)\" unbekannt, zählt wie medium (Aufwand 5)"),
    (select(.status != null and (.status | IN("backlog", "in_progress", "resolved") | not))
        | "Warnung: \(.title): status \"\(.status)\" unbekannt, zählt als offen im Backlog")' \
    "${INPUT_FILE}" >&2

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if is_demo "${INPUT_FILE}"; then
    DATA_NOTE="BEISPIELDATEN aus $(basename "${INPUT_FILE}"), keine Messung"
else
    DATA_NOTE=""
fi

# Punkte und Grenzen wie in Kapitel 15, an einer Stelle für Text und JSON
JQ_DEFS='def points: ({"critical": 100, "high": 40, "medium": 10, "low": 2}[.severity] // 10);
def prio: (points / ({"trivial": 1, "small": 2, "medium": 5, "large": 13, "xlarge": 21}[.effort] // 5) * 10 | round / 10);
def num: . * 1000 | round / 1000;
def open_items: [.[] | select(.status != "resolved")];
def backlog: [open_items[] | select(.status != "in_progress")];
def score: (open_items | map(points) | add // 0);
def health: if score < 200 then "healthy" elif score < 500 then "attention" else "critical" end;
def ranked: open_items | map(. + {priority: prio}) | sort_by(-.priority);
def by_category: open_items | group_by(.category // "other")
    | map({category: (.[0].category // "other"), count: length, points: (map(points) | add)});'

SPRINT_CAPACITY=80  # Stunden pro Sprint
TECH_DEBT_BUDGET=$((SPRINT_CAPACITY * 25 / 100))

# Sprint-Empfehlung: critical-Items kommen nach Kapitel 15 zuerst ("Sofort
# beheben", SLA < 1 Sprint), unabhängig vom Budget. Die übrigen nach
# Priorität, soweit sie ins 25-%-Budget passen. Items ohne Stundenschätzung
# plant das Skript nicht ein
JQ_SPRINT='def critical_now: [backlog[] | select(.severity == "critical")];
def sprint($budget): reduce (ranked[] | select(.status != "in_progress") | select(.severity != "critical")
        | select(.estimated_hours != null)) as $i
    ({used: 0, items: []};
     if .used + $i.estimated_hours <= $budget
     then .used += $i.estimated_hours | .items += [$i] else . end) | .items;'

# ============================================================
# Output
# ============================================================

if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    jq --arg now "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg source "$(basename "${INPUT_FILE}")" \
        --argjson demo "$(is_demo "${INPUT_FILE}" && echo true || echo false)" \
        --argjson budget "${TECH_DEBT_BUDGET}" "${JQ_DEFS} ${JQ_SPRINT}"'
        {
            generated_at: $now,
            data_source: (if $demo then "BEISPIELDATEN aus \($source), keine Messung" else $source end),
            demo: $demo,
            summary: {
                total_items: (open_items | length),
                backlog_items: (backlog | length),
                in_progress: (open_items | map(select(.status == "in_progress")) | length),
                total_hours: (backlog | map(.estimated_hours // 0) | add // 0 | num),
                items_without_estimate: (backlog | map(select(.estimated_hours == null)) | length),
                tech_debt_score: score,
                health: health
            },
            items: .,
            by_category: by_category,
            top_priority: (ranked | .[0:5]),
            sprint: {budget_hours: $budget, critical_first: [critical_now[] | .title], items: [sprint($budget)[] | .title]}
        }' "${INPUT_FILE}"
    exit 0
fi

TECH_DEBT_SCORE=$(jq "${JQ_DEFS} score" "${INPUT_FILE}")
HEALTH=$(jq -r "${JQ_DEFS} health" "${INPUT_FILE}")
case "${HEALTH}" in
    healthy) HEALTH_COLOR=${GREEN} ;;
    attention) HEALTH_COLOR=${YELLOW} ;;
    *) HEALTH_COLOR=${RED} ;;
esac

# Text Output
echo "================================================"
echo "  Technical Debt Report"
echo "================================================"
echo ""
echo "Datum: $(date)"
echo "Eingabe: ${INPUT_FILE}"
if [[ -n "${DATA_NOTE}" ]]; then
    echo -e "${YELLOW}HINWEIS: ${DATA_NOTE}${NC}"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Zusammenfassung"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "Tech Debt Score:    ${HEALTH_COLOR}${TECH_DEBT_SCORE}${NC} Punkte (${HEALTH}; < 200 gesund, ab 500 kritisch)"
jq -r "${JQ_DEFS}"'
    "Backlog Items:      \(backlog | length)",
    "In Progress:        \(open_items | map(select(.status == "in_progress")) | length)",
    "Geschätzte Stunden: \(backlog | map(.estimated_hours // 0) | add // 0 | num)h (Backlog)"
        + (backlog | map(select(.estimated_hours == null)) | length
           | if . > 0 then ", \(.) Items ohne Schätzung" else "" end)' "${INPUT_FILE}"
echo ""

# By Category
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Nach Kategorie"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

jq -r "${JQ_DEFS}"' by_category | if length == 0 then "Keine offenen Items."
    else .[] | "\(.category): \(.count) Items, \(.points) Punkte" end' "${INPUT_FILE}"
echo ""

# Top Priority Items
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Top Priority Items"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

jq -r "${JQ_DEFS}"' ranked | .[0:5] | .[] |
    "\(if .id then "[\(.id)] " else "" end)\(.title)\n    Category: \(.category // "other") | Severity: \(.severity) | Priority: \(.priority) | Hours: \(if .estimated_hours == null then "?" else "\(.estimated_hours | num)h" end)\n"' \
    "${INPUT_FILE}"

# Sprint Recommendation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Sprint Empfehlung (25% Regel)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Sprint-Kapazität:    ${SPRINT_CAPACITY}h"
echo "Tech Debt Budget:    ${TECH_DEBT_BUDGET}h (25%, critical-Items zusätzlich)"
echo ""
echo "Empfohlene Items für nächsten Sprint:"
echo ""

jq -r --argjson budget "${TECH_DEBT_BUDGET}" "${JQ_DEFS} ${JQ_SPRINT}"'
    (critical_now[] | "☐ \(.title) (\(if .estimated_hours == null then "ohne Stundenschätzung" else "\(.estimated_hours | num)h" end), critical: sofort, vor dem Budget)"),
    ([sprint($budget)[] | "☐ \(.title) (\(.estimated_hours | num)h)"] as $picked
     | if ($picked | length) == 0 then "(im Budget: keins mit Stundenschätzung passt)" else $picked[] end),
      (backlog | map(select(.estimated_hours == null and .severity != "critical")) | .[]
       | "  ohne Stundenschätzung, nicht eingeplant: \(.title)")' "${INPUT_FILE}"

echo ""

# Trend (optional)
if [[ "${SHOW_TREND}" = true ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Trend (${TREND_FILE})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    if is_demo "${TREND_FILE}"; then
        echo -e "${YELLOW}HINWEIS: BEISPIELDATEN aus $(basename "${TREND_FILE}"), keine Messung${NC}"
    fi

    jq -r 'def num: . * 1000 | round / 1000;
        .[] | "\(.month): Score \(.score | num)"
        + (if .items != null then " | Items: \(.items | num)" else "" end)
        + (if .hours != null then " | Hours: \(.hours | num)h" else "" end)' "${TREND_FILE}"

    # Trend berechnen
    FIRST_SCORE=$(jq '.[0].score' "${TREND_FILE}")
    LAST_SCORE=$(jq '.[-1].score' "${TREND_FILE}")

    if jq -e -n --argjson a "${FIRST_SCORE}" --argjson b "${LAST_SCORE}" '$b < $a' >/dev/null; then
        TREND_TEXT="improving ↓"
        TREND_COLOR=${GREEN}
    elif jq -e -n --argjson a "${FIRST_SCORE}" --argjson b "${LAST_SCORE}" '$b > $a' >/dev/null; then
        TREND_TEXT="worsening ↑"
        TREND_COLOR=${RED}
    else
        TREND_TEXT="stable →"
        TREND_COLOR=${YELLOW}
    fi

    echo ""
    echo -e "Trend: ${TREND_COLOR}${TREND_TEXT}${NC}"
    echo ""
fi

# Empfehlungen
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Empfehlungen"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "${HEALTH}" == "critical" ]]; then
    echo -e "${RED}KRITISCH: Tech Debt Sprint empfohlen!${NC}"
    echo "  - Dedizierter Sprint für Tech Debt"
    echo "  - Feature Freeze erwägen"
    echo "  - Root Cause Analysis durchführen"
elif [[ "${HEALTH}" == "attention" ]]; then
    echo -e "${YELLOW}ACHTUNG: Tech Debt braucht Aufmerksamkeit.${NC}"
    echo "  - 25% Regel strikt einhalten"
    echo "  - Priorisierung überprüfen"
else
    echo -e "${GREEN}GUT: Tech Debt minimal.${NC}"
    echo "  - Weiter so!"
    echo "  - Prävention beibehalten"
fi

echo ""
echo "Done."
