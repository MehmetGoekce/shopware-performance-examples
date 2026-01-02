#!/bin/bash
#
# Tech Debt Report Generator
#
# Generiert einen Report über Performance-bezogene Technical Debt.
# Zeigt priorisierte Backlog-Items und Empfehlungen.
#
# Verwendung:
#   ./tech-debt-report.sh
#   ./tech-debt-report.sh --trend
#   ./tech-debt-report.sh --json
#
# Voraussetzungen:
#   - jq (für JSON-Output)

set -e

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
# Simulierte Tech Debt Daten
# In Realität aus Datenbank/API laden
# ============================================================

# Tech Debt Items (JSON)
TECH_DEBT_DATA='[
    {
        "id": "TD-001",
        "title": "Legacy jQuery Event Handlers",
        "category": "frontend",
        "priority_score": 85,
        "estimated_hours": 16,
        "affected_pages": ["checkout", "cart"],
        "status": "backlog"
    },
    {
        "id": "TD-002",
        "title": "Synchrone Third-Party Scripts",
        "category": "frontend",
        "priority_score": 92,
        "estimated_hours": 8,
        "affected_pages": ["all"],
        "status": "backlog"
    },
    {
        "id": "TD-003",
        "title": "N+1 Queries in Produktliste",
        "category": "database",
        "priority_score": 78,
        "estimated_hours": 24,
        "affected_pages": ["category", "search"],
        "status": "backlog"
    },
    {
        "id": "TD-004",
        "title": "Fehlende Cache-Invalidierung",
        "category": "backend",
        "priority_score": 65,
        "estimated_hours": 12,
        "affected_pages": ["product"],
        "status": "backlog"
    },
    {
        "id": "TD-005",
        "title": "Unoptimierte Produktbilder",
        "category": "infrastructure",
        "priority_score": 88,
        "estimated_hours": 8,
        "affected_pages": ["product", "category"],
        "status": "in_progress"
    }
]'

# Historische Daten für Trend
HISTORICAL_DATA='[
    {"month": "2024-10", "score": 52, "items": 18, "hours": 280},
    {"month": "2024-11", "score": 45, "items": 15, "hours": 220},
    {"month": "2024-12", "score": 38, "items": 12, "hours": 180}
]'

# ============================================================
# Statistiken berechnen
# ============================================================

TOTAL_ITEMS=$(echo "${TECH_DEBT_DATA}" | jq 'length')
BACKLOG_ITEMS=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "backlog")] | length')
IN_PROGRESS=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "in_progress")] | length')
TOTAL_HOURS=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "backlog") | .estimated_hours] | add')
AVG_PRIORITY=$(echo "${TECH_DEBT_DATA}" | jq '[.[] | select(.status == "backlog") | .priority_score] | add / length | floor')

# Tech Debt Score (vereinfacht)
TECH_DEBT_SCORE=$(echo "scale=0; (${BACKLOG_ITEMS} * 3) + (${TOTAL_HOURS} / 10)" | bc)

# Health Status
if [[ "${TECH_DEBT_SCORE}" -le 25 ]]; then
    HEALTH="healthy"
    HEALTH_COLOR=${GREEN}
elif [[ "${TECH_DEBT_SCORE}" -le 50 ]]; then
    HEALTH="manageable"
    HEALTH_COLOR=${YELLOW}
elif [[ "${TECH_DEBT_SCORE}" -le 75 ]]; then
    HEALTH="concerning"
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
    "top_priority": $(echo "${TECH_DEBT_DATA}" | jq 'sort_by(-.priority_score) | .[0:3]')
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
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Zusammenfassung"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "Tech Debt Score:    ${HEALTH_COLOR}${TECH_DEBT_SCORE}${NC} (${HEALTH})"
echo "Backlog Items:      ${BACKLOG_ITEMS}"
echo "In Progress:        ${IN_PROGRESS}"
echo "Geschätzte Stunden: ${TOTAL_HOURS}h"
echo "Ø Priority Score:   ${AVG_PRIORITY}"
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

echo "${TECH_DEBT_DATA}" | jq -r 'sort_by(-.priority_score) | .[0:5] | .[] |
    "[\(.id)] \(.title)\n    Category: \(.category) | Priority: \(.priority_score) | Hours: \(.estimated_hours)h\n"'

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
echo "${TECH_DEBT_DATA}" | jq -r --argjson budget "${TECH_DEBT_BUDGET}" '
    sort_by(-.priority_score) |
    .[] |
    select(.status == "backlog") |
    "  ☐ \(.title) (\(.estimated_hours)h)"
' | while read -r line; do
    hours=$(echo "${line}" | grep -oP '\(\K[0-9]+(?=h\))')
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
    echo "  Trend (letzte 3 Monate)"
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
elif [[ "${HEALTH}" == "concerning" ]]; then
    echo -e "${YELLOW}ACHTUNG: Tech Debt wächst.${NC}"
    echo "  - 25% Regel strikt einhalten"
    echo "  - Priorisierung überprüfen"
    echo "  - Mehr Automatisierung"
elif [[ "${HEALTH}" == "manageable" ]]; then
    echo -e "${YELLOW}OK: Tech Debt unter Kontrolle.${NC}"
    echo "  - Weiter 25% Regel anwenden"
    echo "  - Regelmässig reviewen"
else
    echo -e "${GREEN}GUT: Tech Debt minimal.${NC}"
    echo "  - Weiter so!"
    echo "  - Prävention beibehalten"
fi

echo ""
echo "Done."
