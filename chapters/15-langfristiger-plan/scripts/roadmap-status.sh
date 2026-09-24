#!/bin/bash
#
# Roadmap Status Checker
#
# Prüft den Status der Performance-Roadmap aus einer Statusdatei (ROADMAP_FILE).
# Zeigt Fortschritt, überfällige Milestones und Risiken.
#
# Die Statusdatei ist JSON, mit den Feldnamen der Vorlage
# templates/roadmap.yaml plus dem Status, den Ihr Tracker kennt:
#   {"milestones": [{"id": "M-Q1-1", "title": "...", "target_date": "2026-03-15",
#                    "status": "completed|in_progress|at_risk|pending", "owner": "..."}],
#    "risks": [{"id": "R-1", "risk": "...", "probability": "low|medium|high",
#               "impact": "low|medium|high", "mitigation": "..."}]}
# Pflicht: milestones mit id, title, target_date, status. risks ist optional.
# Die YAML-Vorlage ist der Plan und hat keinen Status; sie wird nicht gelesen.
#
# Überfällig ist ein offener Milestone, dessen Zieldatum vor dem Stichtag
# liegt (Vorgabe: heute). Beispieldaten: examples/roadmap-status.demo.json,
# Stichtag 2026-09-15. Nur wenn die Datei auf .demo.json endet, kennzeichnet
# die Ausgabe sie als BEISPIELDATEN.
#
# Verwendung:
#   ROADMAP_FILE=roadmap-status.json ./roadmap-status.sh
#   ./roadmap-status.sh --file roadmap-status.json --alerts-only
#   ./roadmap-status.sh --file roadmap-status.json --stichtag 2026-09-30
#   ./roadmap-status.sh --file ../examples/roadmap-status.demo.json --stichtag 2026-09-15   # Demo
#
# Exit-Codes: 0 ok, 1 Aufruf falsch, 2 jq fehlt, 65 Eingabe ungültig,
# 66 Eingabe fehlt oder ist nicht lesbar.
#
# Voraussetzungen:
#   - jq

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--file STATUS.json] [--stichtag JJJJ-MM-TT] [--quarter Qn] [--alerts-only]" >&2
    echo "  Ohne --file gilt ROADMAP_FILE." >&2
    echo "  Demo: $(basename "$0") --file examples/roadmap-status.demo.json --stichtag 2026-09-15" >&2
}

ROADMAP_FILE="${ROADMAP_FILE:-}"
STICHTAG=""
CURRENT_QUARTER=""
ALERTS_ONLY=false

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "Fehler: --file braucht eine Statusdatei" >&2
                usage
                exit 1
            fi
            ROADMAP_FILE="$2"
            shift 2
            ;;
        --stichtag)
            if [[ ! "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -d "$2" >/dev/null 2>&1; then
                echo "Fehler: --stichtag braucht ein Datum JJJJ-MM-TT" >&2
                exit 1
            fi
            STICHTAG="$2"
            shift 2
            ;;
        --quarter)
            # nur die Anzeige des aktuellen Quartals
            case "${2:-}" in
                Q1|Q2|Q3|Q4) CURRENT_QUARTER="$2"; shift 2 ;;
                *) echo "Fehler: --quarter braucht Q1, Q2, Q3 oder Q4" >&2; exit 1 ;;
            esac
            ;;
        --alerts-only)
            ALERTS_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unbekanntes Argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "${ROADMAP_FILE}" ]]; then
    echo "Fehler: keine Statusdatei (--file oder ROADMAP_FILE)" >&2
    usage
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Fehler: jq fehlt (apt install jq)" >&2
    exit 2
fi

if [[ ! -f "${ROADMAP_FILE}" || ! -r "${ROADMAP_FILE}" ]]; then
    echo "Fehler: ${ROADMAP_FILE} fehlt oder ist nicht lesbar" >&2
    exit 66
fi
case "${ROADMAP_FILE}" in
    *.yaml|*.yml)
        echo "Fehler: ${ROADMAP_FILE} ist YAML. roadmap-status.sh liest eine JSON-Statusdatei;" >&2
        echo "  die Vorlage templates/roadmap.yaml ist der Plan und hat keinen Status (README.md)." >&2
        exit 65
        ;;
esac
# genau ein JSON-Wert: eine leere Datei ist für "jq empty" gültig
if [[ "$(jq -s 'length' "${ROADMAP_FILE}" 2>/dev/null)" != "1" ]]; then
    echo "Fehler: ${ROADMAP_FILE} ist kein gültiges JSON (genau ein Wert erwartet)" >&2
    exit 65
fi

INPUT_ERRORS=$(jq -r '
    def valid_date: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
        and ((try (strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")) catch null) == .);
    def level: IN("low", "medium", "high");
    if type != "object" then "Die Statusdatei muss ein JSON-Objekt sein, nicht \(type)"
    elif (.milestones | type) != "array" then "milestones fehlt oder ist keine Liste"
    else
        (.milestones | to_entries[] | .key as $i | .value |
            if type != "object" then "milestones.\($i): kein Objekt"
            elif (.id | type) != "string" or .id == "" then "milestones.\($i): id fehlt"
            elif (.title | type) != "string" or .title == "" then "milestones.\($i) (\(.id)): title fehlt"
            elif (.target_date | valid_date | not) then "milestones.\($i) (\(.id)): target_date ist kein Datum JJJJ-MM-TT"
            elif (.status | IN("completed", "in_progress", "at_risk", "pending") | not)
                then "milestones.\($i) (\(.id)): status muss completed, in_progress, at_risk oder pending sein"
            else empty end),
        (if has("risks") then
            if (.risks | type) != "array" then "risks muss eine Liste sein"
            else .risks | to_entries[] | .key as $i | .value |
                if type != "object" then "risks.\($i): kein Objekt"
                elif (.risk | type) != "string" or .risk == "" then "risks.\($i): risk fehlt"
                elif (.probability | level | not) or (.impact | level | not)
                    then "risks.\($i): probability und impact müssen low, medium oder high sein"
                else empty end
            end
         else empty end)
    end' "${ROADMAP_FILE}")

if [[ -n "${INPUT_ERRORS}" ]]; then
    echo "Fehler: ${ROADMAP_FILE} ist keine gültige Statusdatei:" >&2
    echo "${INPUT_ERRORS}" | sed 's/^/  /' >&2
    exit 65
fi

STICHTAG="${STICHTAG:-$(date +%Y-%m-%d)}"

# Aktuelles Quartal aus dem Stichtag
if [[ -z "${CURRENT_QUARTER}" ]]; then
    # 10#: "08" und "09" sonst als Oktalzahl gelesen (Fehler, dann Q4)
    MONTH=$((10#${STICHTAG:5:2}))
    CURRENT_QUARTER="Q$(( (MONTH - 1) / 3 + 1 ))"
fi
YEAR="${STICHTAG:0:4}"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Milestones auswerten: eine Zeile je Milestone, Tabulator-getrennt
# id, Titel, Zieldatum, Status (offen + vor dem Stichtag = overdue),
# Tage bis zum Ziel (negativ = vorbei), Quartal des Zieldatums (JJJJ-Qn)
# ============================================================

MILESTONE_ROWS=$(jq -r --arg today "${STICHTAG}" '
    def day: strptime("%Y-%m-%d") | mktime / 86400 | floor;
    ($today | day) as $t |
    .milestones[] |
    (.target_date | day - $t) as $days |
    (if .status != "completed" and $days < 0 then "overdue" else .status end) as $status |
    (.target_date[5:7] | tonumber) as $month |
    [.id, (.title | gsub("[\t\n]"; " ")), .target_date, $status, $days,
     "\(.target_date[0:4])-Q\(($month - 1) / 3 | floor + 1)"] | @tsv' "${ROADMAP_FILE}")

count_status() {
    if [[ -z "${MILESTONE_ROWS}" ]]; then echo 0; return; fi
    awk -F'\t' -v s="$1" '$4 == s { n++ } END { print n + 0 }' <<< "${MILESTONE_ROWS}"
}

COMPLETED=$(count_status completed)
IN_PROGRESS=$(count_status in_progress)
AT_RISK=$(count_status at_risk)
OVERDUE=$(count_status overdue)
PENDING=$(count_status pending)
TOTAL=$((COMPLETED + IN_PROGRESS + AT_RISK + OVERDUE + PENDING))

get_status_color() {
    case $1 in
        completed) echo "${GREEN}" ;;
        in_progress) echo "${CYAN}" ;;
        at_risk) echo "${YELLOW}" ;;
        overdue) echo "${RED}" ;;
        *) echo "${NC}" ;;
    esac
}

get_status_icon() {
    case $1 in
        completed) echo "✓" ;;
        in_progress) echo "⏳" ;;
        at_risk) echo "⚠" ;;
        overdue) echo "✗" ;;
        pending) echo "○" ;;
        *) echo "?" ;;
    esac
}

# ============================================================
# Ausgabe
# ============================================================

if [[ "$(basename "${ROADMAP_FILE}")" == *.demo.json ]]; then
    echo -e "${YELLOW}HINWEIS: BEISPIELDATEN aus $(basename "${ROADMAP_FILE}"), keine Messung${NC}"
fi

if [[ "${ALERTS_ONLY}" = false ]]; then
    echo "================================================"
    echo "  Roadmap Status Check"
    echo "================================================"
    echo ""
    echo "Statusdatei: ${ROADMAP_FILE}"
    echo "Stichtag: ${STICHTAG}"
    echo "Aktuelles Quartal: ${CURRENT_QUARTER} ${YEAR}"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Übersicht"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  ${GREEN}✓ Completed:${NC}    ${COMPLETED}"
    echo -e "  ${CYAN}⏳ In Progress:${NC}  ${IN_PROGRESS}"
    echo -e "  ${YELLOW}⚠ At Risk:${NC}      ${AT_RISK}"
    echo -e "  ${RED}✗ Overdue:${NC}      ${OVERDUE}"
    echo "  ○ Pending:      ${PENDING}"
    echo "  ─────────────────"
    echo "  Total:          ${TOTAL}"
    echo ""

    if [[ "${TOTAL}" -eq 0 ]]; then
        echo "  Keine Milestones in der Statusdatei."
        echo ""
    else
        # Progress Bar
        PROGRESS=$((COMPLETED * 100 / TOTAL))
        PROGRESS_BAR=""
        for ((i=0; i<PROGRESS/5; i++)); do PROGRESS_BAR+="█"; done
        for ((i=PROGRESS/5; i<20; i++)); do PROGRESS_BAR+="░"; done

        echo -e "  Progress: [${GREEN}${PROGRESS_BAR}${NC}] ${PROGRESS}%"
        echo ""
    fi
fi

# Alerts (immer anzeigen bei Problemen)
if [[ "${OVERDUE}" -gt 0 ]] || [[ "${AT_RISK}" -gt 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${RED}⚠ ALERTS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    while IFS=$'\t' read -r _ title date status days _; do
        if [[ "${status}" == "overdue" ]]; then
            echo -e "  ${RED}[OVERDUE]${NC} ${title}"
            echo "           Target: ${date} (${days#-} days ago)"
            echo ""
        elif [[ "${status}" == "at_risk" ]]; then
            echo -e "  ${YELLOW}[AT RISK]${NC} ${title}"
            echo "           Target: ${date} (${days} days remaining)"
            echo ""
        fi
    done <<< "${MILESTONE_ROWS}"
fi

if [[ "${ALERTS_ONLY}" = true ]]; then
    if [[ "${OVERDUE}" -eq 0 ]] && [[ "${AT_RISK}" -eq 0 ]]; then
        echo "No alerts."
    fi
    exit 0
fi

# Alle Milestones, nach dem Quartal des Zieldatums gruppiert
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Alle Milestones"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ -n "${MILESTONE_ROWS}" ]]; then
    PERIODS=$(cut -f6 <<< "${MILESTONE_ROWS}" | sort -u)
    for q in ${PERIODS}; do
        echo -e "  ${BLUE}${q}${NC}"
        echo "  ──────────"
        while IFS=$'\t' read -r key title date status days quarter; do
            [[ "${quarter}" == "${q}" ]] || continue

            color=$(get_status_color "${status}")
            icon=$(get_status_icon "${status}")

            if [[ "${status}" == "completed" ]]; then
                days_text=""
            elif [[ "${days}" -lt 0 ]]; then
                days_text="(${days#-}d overdue)"
            else
                days_text="(${days}d remaining)"
            fi

            echo -e "  ${color}${icon}${NC} [${key}] ${title}"
            echo "      Target: ${date} ${days_text}"
        done <<< "${MILESTONE_ROWS}"
        echo ""
    done
fi

# Risiken
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Aktive Risiken"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RISK_ROWS=$(jq -r '.risks // [] | to_entries[] |
    [(.value.id // "R-\(.key + 1)"), (.value.risk | gsub("[\t\n]"; " ")), .value.probability, .value.impact,
     ((.value.mitigation // "") | gsub("[\t\n]"; " "))] | @tsv' "${ROADMAP_FILE}")

if [[ -z "${RISK_ROWS}" ]]; then
    echo "  Keine Risiken in der Statusdatei."
    echo ""
else
    while IFS=$'\t' read -r key description probability impact mitigation; do
        if [[ "${probability}" == "high" ]] || [[ "${impact}" == "high" ]]; then
            color=${RED}
        elif [[ "${probability}" == "medium" ]] || [[ "${impact}" == "medium" ]]; then
            color=${YELLOW}
        else
            color=${NC}
        fi

        echo -e "  ${color}[${key}]${NC} ${description}"
        echo "      Probability: ${probability} | Impact: ${impact}"
        if [[ -n "${mitigation}" ]]; then
            echo "      Mitigation: ${mitigation}"
        fi
        echo ""
    done <<< "${RISK_ROWS}"
fi

# Empfehlungen
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Empfehlungen"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "${TOTAL}" -eq 0 ]]; then
    echo -e "  ${YELLOW}•${NC} Keine Milestones erfasst"
    echo "    → Milestones aus templates/roadmap.yaml mit Status in die Statusdatei übernehmen"
else
    if [[ "${OVERDUE}" -gt 0 ]]; then
        echo -e "  ${RED}•${NC} Überfällige Milestones sofort adressieren"
        echo "    → Blockers identifizieren und eskalieren"
    fi

    if [[ "${AT_RISK}" -gt 0 ]]; then
        echo -e "  ${YELLOW}•${NC} At-Risk Items priorisieren"
        echo "    → Tägliche Check-ins einführen"
    fi

    if [[ "${PROGRESS}" -lt 50 ]]; then
        echo -e "  ${YELLOW}•${NC} Fortschritt unter 50%"
        echo "    → Scope Review durchführen"
    fi

    if [[ "${OVERDUE}" -eq 0 ]] && [[ "${AT_RISK}" -eq 0 ]] && [[ "${PROGRESS}" -ge 50 ]]; then
        echo -e "  ${GREEN}•${NC} Roadmap auf Kurs!"
        echo "    → Weiter so, regelmässig reviewen"
    fi
fi

echo ""
echo "Done."
