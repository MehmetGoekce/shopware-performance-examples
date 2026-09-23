#!/bin/bash
#
# Tech Debt Report Generator
#
# Generiert einen Report über Performance-bezogene Technical Debt.
# Zeigt priorisierte Backlog-Items und Empfehlungen.
#
# BEISPIELDATEN: Die Items unten sind erfunden und stehen im Skript. Die
# Ausgabe sagt das in jeder Form (Text und JSON). Eigene Items tragen Sie in
# TECH_DEBT_DATA ein. Skala wie Kapitel 15 (src/TechDebtTrackerService.php):
# Score = Summe der Severity-Punkte offener Items, critical 100, high 40,
# medium 10, low 2; < 200 gesund, 200-499 Aufmerksamkeit, ab 500 kritisch.
# Priorität = Severity-Punkte / Aufwandspunkte (WSJF-ähnlich).
#
# Verwendung:
#   ./tech-debt-report.sh
#   ./tech-debt-report.sh --trend
#   ./tech-debt-report.sh --json
#
# Voraussetzungen:
#   - jq (jede Ausgabeform)

set -e

if ! command -v jq >/dev/null 2>&1; then
    echo "Fehler: jq fehlt (apt install jq)" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOW_TREND=false
OUTPUT_FORMAT="text"

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --trend)
            SHOW_TREND=true
            shift
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        *)
            echo "Unbekanntes Argument: $1"
            exit 1
            ;;
    esac
done

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Beispieldaten (erfunden, keine Messung)
# In Realität aus Ihrem Tracker laden
# ============================================================

DATA_NOTE="BEISPIELDATEN aus dem Skript, keine Messung"

# Tech Debt Items (JSON), severity: critical|high|medium|low,
# effort: trivial (<2h)|small (<1 Tag)|medium (1-5 Tage)|large|xlarge
TECH_DEBT_DATA='[
    {
        "id": "TD-001",
        "title": "Legacy jQuery Event Handlers",
        "category": "frontend",
        "severity": "high",
        "effort": "medium",
        "estimated_hours": 16,
        "affected_pages": ["checkout", "cart"],
        "status": "backlog"
    },
    {
        "id": "TD-002",
        "title": "Synchrone Third-Party Scripts",
        "category": "frontend",
        "severity": "high",
        "effort": "small",
        "estimated_hours": 8,
        "affected_pages": ["all"],
        "status": "backlog"
    },
    {
        "id": "TD-003",
        "title": "N+1 Queries in Produktliste",
        "category": "database",
        "severity": "critical",
        "effort": "medium",
        "estimated_hours": 24,
        "affected_pages": ["category", "search"],
        "status": "backlog"
    },
    {
        "id": "TD-004",
        "title": "Fehlende Cache-Invalidierung",
        "category": "backend",
        "severity": "medium",
        "effort": "medium",
        "estimated_hours": 12,
        "affected_pages": ["product"],
        "status": "backlog"
    },
    {
        "id": "TD-005",
        "title": "Unoptimierte Produktbilder",
        "category": "infrastructure",
        "severity": "high",
        "effort": "small",
        "estimated_hours": 8,
        "affected_pages": ["product", "category"],
        "status": "in_progress"
    }
]'

# Beispiel-Verlauf für --trend (erfunden). Eigene Werte: Score jeden Monat ablegen
HISTORICAL_DATA='[
    {"month": "Monat 1", "score": 410, "items": 9, "hours": 150},
    {"month": "Monat 2", "score": 330, "items": 7, "hours": 110},
    {"month": "Monat 3", "score": 230, "items": 5, "hours": 68}
]'

# Punkte wie in Kapitel 15, unbekannte Werte zählen wie medium
JQ_DEFS='def points: ({"critical": 100, "high": 40, "medium": 10, "low": 2}[.severity] // 10);
def prio: (points / ({"trivial": 1, "small": 2, "medium": 5, "large": 13, "xlarge": 21}[.effort] // 5) * 10 | round / 10);
def open_items: [.[] | select(.status != "resolved")];'

# ============================================================
# Statistiken berechnen
# ============================================================

TOTAL_ITEMS=$(echo "${TECH_DEBT_DATA}" | jq 'length')
BACKLOG_ITEMS=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "backlog")] | length')
IN_PROGRESS=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "in_progress")] | length')
TOTAL_HOURS=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "backlog") | .estimated_hours] | add')

# Tech Debt Score: Summe der Severity-Punkte offener Items (Kapitel 15)
TECH_DEBT_SCORE=$(echo "${TECH_DEBT_DATA}" | jq "${JQ_DEFS} open_items | map(points) | add // 0")

# Health Status
if [[ "${TECH_DEBT_SCORE}" -lt 200 ]]; then
    HEALTH="healthy"
    HEALTH_COLOR=${GREEN}
elif [[ "${TECH_DEBT_SCORE}" -lt 500 ]]; then
    HEALTH="attention"
    HEALTH_COLOR=${YELLOW}
else
    HEALTH="critical"
    HEALTH_COLOR=${RED}
fi

# ============================================================
# Output
# ============================================================

if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    # JSON Output
    cat << EOF
{
    "generated_at": "$(date -Iseconds)",
    "data_source": "${DATA_NOTE}",
    "summary": {
        "total_items": ${TOTAL_ITEMS},
        "backlog_items": ${BACKLOG_ITEMS},
        "in_progress": ${IN_PROGRESS},
        "total_hours": ${TOTAL_HOURS},
        "tech_debt_score": ${TECH_DEBT_SCORE},
        "health": "${HEALTH}"
    },
    "items": ${TECH_DEBT_DATA},
    "by_category": $(echo "${TECH_DEBT_DATA}" | jq 'group_by(.category) | map({category: .[0].category, count: length})'),
    "top_priority": $(echo "${TECH_DEBT_DATA}" | jq "${JQ_DEFS} open_items | map(. + {priority: prio}) | sort_by(-.priority) | .[0:3]")
}
EOF
    exit 0
fi

# Text Output
echo "================================================"
echo "  Technical Debt Report"
echo "================================================"
echo ""
echo "Datum: $(date)"
echo -e "${YELLOW}HINWEIS: ${DATA_NOTE}${NC}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Zusammenfassung"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "Tech Debt Score:    ${HEALTH_COLOR}${TECH_DEBT_SCORE}${NC} Punkte (${HEALTH}; < 200 gesund, ab 500 kritisch)"
echo "Backlog Items:      ${BACKLOG_ITEMS}"
echo "In Progress:        ${IN_PROGRESS}"
echo "Geschätzte Stunden: ${TOTAL_HOURS}h (Backlog)"
echo ""

# By Category
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Nach Kategorie"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "${TECH_DEBT_DATA}" | jq -r 'group_by(.category) | .[] | "\(.[0].category): \(length) Items"'
echo ""

# Top Priority Items
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Top Priority Items"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "${TECH_DEBT_DATA}" | jq -r "${JQ_DEFS}"' open_items | map(. + {priority: prio}) | sort_by(-.priority) | .[0:5] | .[] |
    "[\(.id)] \(.title)\n    Category: \(.category) | Severity: \(.severity) | Priority: \(.priority) | Hours: \(.estimated_hours)h\n"'

# Sprint Recommendation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Sprint Empfehlung (25% Regel)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SPRINT_CAPACITY=80  # Stunden pro Sprint
TECH_DEBT_BUDGET=$((SPRINT_CAPACITY * 25 / 100))

echo "Sprint-Kapazität:    ${SPRINT_CAPACITY}h"
echo "Tech Debt Budget:    ${TECH_DEBT_BUDGET}h (25%)"
echo ""
echo "Empfohlene Items für nächsten Sprint:"
echo ""

# Items die ins Budget passen
ACCUMULATED=0
echo "${TECH_DEBT_DATA}" | jq -r "${JQ_DEFS}"'
    map(. + {priority: prio}) |
    sort_by(-.priority) |
    .[] |
    select(.status == "backlog") |
    "  ☐ \(.title) (\(.estimated_hours)h)"
' | while read -r line; do
    hours="${line##*(}"
    hours="${hours%h)}"
    new_total=$((ACCUMULATED + hours))
    if [[ ${new_total} -le ${TECH_DEBT_BUDGET} ]]; then
        echo "${line}"
        ACCUMULATED=$new_total
    fi
done

echo ""

# Trend (optional)
if [[ "${SHOW_TREND}" = true ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Trend (Beispielverlauf, keine Messung)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "${HISTORICAL_DATA}" | jq -r '.[] | "\(.month): Score \(.score) | Items: \(.items) | Hours: \(.hours)h"'

    # Trend berechnen
    FIRST_SCORE=$(echo "${HISTORICAL_DATA}" | jq '.[0].score')
    LAST_SCORE=$(echo "${HISTORICAL_DATA}" | jq '.[-1].score')

    if [[ "${LAST_SCORE}" -lt "${FIRST_SCORE}" ]]; then
        TREND_TEXT="improving ↓"
        TREND_COLOR=${GREEN}
    elif [[ "${LAST_SCORE}" -gt "${FIRST_SCORE}" ]]; then
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
