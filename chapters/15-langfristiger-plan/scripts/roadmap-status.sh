#!/bin/bash
#
# Roadmap Status Checker
#
# Prüft den aktuellen Status der Performance-Roadmap.
# Zeigt Fortschritt, überfällige Milestones und Risiken.
#
# Verwendung:
#   ./roadmap-status.sh
#   ./roadmap-status.sh --quarter Q1
#   ./roadmap-status.sh --alerts-only
#
# Voraussetzungen:
#   - yq oder jq für YAML/JSON Parsing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROADMAP_FILE="${ROADMAP_FILE:-${SCRIPT_DIR}/../templates/roadmap.yaml}"
CURRENT_QUARTER=""
ALERTS_ONLY=false

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --quarter)
            CURRENT_QUARTER="$2"
            shift 2
            ;;
        --alerts-only)
            ALERTS_ONLY=true
            shift
            ;;
        *)
            echo "Unbekanntes Argument: $1"
            exit 1
            ;;
    esac
done

# Aktuelles Quartal bestimmen
if [ -z "$CURRENT_QUARTER" ]; then
    MONTH=$(date +%m)
    if [ "$MONTH" -le 3 ]; then
        CURRENT_QUARTER="Q1"
    elif [ "$MONTH" -le 6 ]; then
        CURRENT_QUARTER="Q2"
    elif [ "$MONTH" -le 9 ]; then
        CURRENT_QUARTER="Q3"
    else
        CURRENT_QUARTER="Q4"
    fi
fi

YEAR=$(date +%Y)

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Simulierte Milestone-Daten
# In Realität aus Roadmap-File und Tracking-System
# ============================================================

# Milestones mit Status
declare -A MILESTONES
MILESTONES["M-Q1-1"]="completed|2025-01-28|RUM Dashboard vollständig"
MILESTONES["M-Q1-2"]="completed|2025-02-25|Top 10 Pages optimiert"
MILESTONES["M-Q1-3"]="in_progress|2025-03-15|Performance Champion Program gestartet"
MILESTONES["M-Q2-1"]="pending|2025-04-30|Checkout LCP < 2s"
MILESTONES["M-Q2-2"]="pending|2025-05-31|Mobile CWV alle 'Good'"
MILESTONES["M-Q2-3"]="at_risk|2025-06-15|Redis Cluster produktiv"

# Risiken
declare -A RISKS
RISKS["R-001"]="medium|high|Team-Kapazität durch andere Projekte"
RISKS["R-002"]="low|medium|Vendor-Delay bei CDN Migration"
RISKS["R-003"]="high|high|Black Friday Vorbereitung zu spät"

# ============================================================
# Funktionen
# ============================================================

get_status_color() {
    case $1 in
        completed) echo "$GREEN" ;;
        in_progress) echo "$CYAN" ;;
        at_risk) echo "$YELLOW" ;;
        overdue) echo "$RED" ;;
        pending) echo "$NC" ;;
        *) echo "$NC" ;;
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

check_overdue() {
    local target_date=$1
    local status=$2

    if [ "$status" == "completed" ]; then
        echo "false"
        return
    fi

    # Datum vergleichen
    target_ts=$(date -d "$target_date" +%s 2>/dev/null || echo "0")
    today_ts=$(date +%s)

    if [ "$target_ts" -lt "$today_ts" ]; then
        echo "true"
    else
        echo "false"
    fi
}

days_until() {
    local target_date=$1
    target_ts=$(date -d "$target_date" +%s 2>/dev/null || echo "0")
    today_ts=$(date +%s)
    diff=$(( (target_ts - today_ts) / 86400 ))
    echo "$diff"
}

# ============================================================
# Ausgabe
# ============================================================

if [ "$ALERTS_ONLY" = false ]; then
    echo "================================================"
    echo "  Roadmap Status Check"
    echo "================================================"
    echo ""
    echo "Datum: $(date)"
    echo "Aktuelles Quartal: $CURRENT_QUARTER $YEAR"
    echo ""
fi

# Statistiken sammeln
COMPLETED=0
IN_PROGRESS=0
AT_RISK=0
OVERDUE=0
PENDING=0

for key in "${!MILESTONES[@]}"; do
    IFS='|' read -r status date title <<< "${MILESTONES[$key]}"

    if [ "$(check_overdue "$date" "$status")" == "true" ]; then
        status="overdue"
    fi

    case $status in
        completed) ((COMPLETED++)) ;;
        in_progress) ((IN_PROGRESS++)) ;;
        at_risk) ((AT_RISK++)) ;;
        overdue) ((OVERDUE++)) ;;
        pending) ((PENDING++)) ;;
    esac
done

TOTAL=$((COMPLETED + IN_PROGRESS + AT_RISK + OVERDUE + PENDING))

if [ "$ALERTS_ONLY" = false ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Übersicht"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  ${GREEN}✓ Completed:${NC}    $COMPLETED"
    echo -e "  ${CYAN}⏳ In Progress:${NC}  $IN_PROGRESS"
    echo -e "  ${YELLOW}⚠ At Risk:${NC}      $AT_RISK"
    echo -e "  ${RED}✗ Overdue:${NC}      $OVERDUE"
    echo "  ○ Pending:      $PENDING"
    echo "  ─────────────────"
    echo "  Total:          $TOTAL"
    echo ""

    # Progress Bar
    PROGRESS=$((COMPLETED * 100 / TOTAL))
    PROGRESS_BAR=""
    for ((i=0; i<PROGRESS/5; i++)); do PROGRESS_BAR+="█"; done
    for ((i=PROGRESS/5; i<20; i++)); do PROGRESS_BAR+="░"; done

    echo -e "  Progress: [${GREEN}${PROGRESS_BAR}${NC}] ${PROGRESS}%"
    echo ""
fi

# Alerts (immer anzeigen bei Problemen)
if [ "$OVERDUE" -gt 0 ] || [ "$AT_RISK" -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${RED}⚠ ALERTS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    for key in "${!MILESTONES[@]}"; do
        IFS='|' read -r status date title <<< "${MILESTONES[$key]}"

        if [ "$(check_overdue "$date" "$status")" == "true" ]; then
            days=$(days_until "$date")
            echo -e "  ${RED}[OVERDUE]${NC} $title"
            echo "           Target: $date (${days#-} days ago)"
            echo ""
        elif [ "$status" == "at_risk" ]; then
            days=$(days_until "$date")
            echo -e "  ${YELLOW}[AT RISK]${NC} $title"
            echo "           Target: $date ($days days remaining)"
            echo ""
        fi
    done
fi

if [ "$ALERTS_ONLY" = true ]; then
    if [ "$OVERDUE" -eq 0 ] && [ "$AT_RISK" -eq 0 ]; then
        echo "No alerts."
    fi
    exit 0
fi

# Alle Milestones
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Alle Milestones"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Nach Quartal gruppieren
for q in Q1 Q2 Q3 Q4; do
    has_items=false

    for key in $(echo "${!MILESTONES[@]}" | tr ' ' '\n' | sort); do
        if [[ $key == *"$q"* ]]; then
            if [ "$has_items" = false ]; then
                echo -e "  ${BLUE}$q ${YEAR}${NC}"
                echo "  ──────────"
                has_items=true
            fi

            IFS='|' read -r status date title <<< "${MILESTONES[$key]}"

            # Status aktualisieren wenn overdue
            if [ "$(check_overdue "$date" "$status")" == "true" ]; then
                status="overdue"
            fi

            color=$(get_status_color "$status")
            icon=$(get_status_icon "$status")
            days=$(days_until "$date")

            if [ "$status" == "completed" ]; then
                days_text=""
            elif [ "$days" -lt 0 ]; then
                days_text="(${days#-}d overdue)"
            else
                days_text="(${days}d remaining)"
            fi

            echo -e "  ${color}${icon}${NC} [$key] $title"
            echo "      Target: $date $days_text"
        fi
    done

    if [ "$has_items" = true ]; then
        echo ""
    fi
done

# Risiken
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Aktive Risiken"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for key in "${!RISKS[@]}"; do
    IFS='|' read -r probability impact description <<< "${RISKS[$key]}"

    if [ "$probability" == "high" ] || [ "$impact" == "high" ]; then
        color=$RED
    elif [ "$probability" == "medium" ] || [ "$impact" == "medium" ]; then
        color=$YELLOW
    else
        color=$NC
    fi

    echo -e "  ${color}[$key]${NC} $description"
    echo "      Probability: $probability | Impact: $impact"
    echo ""
done

# Empfehlungen
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Empfehlungen"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$OVERDUE" -gt 0 ]; then
    echo -e "  ${RED}•${NC} Überfällige Milestones sofort adressieren"
    echo "    → Blockers identifizieren und eskalieren"
fi

if [ "$AT_RISK" -gt 0 ]; then
    echo -e "  ${YELLOW}•${NC} At-Risk Items priorisieren"
    echo "    → Tägliche Check-ins einführen"
fi

if [ "$PROGRESS" -lt 50 ]; then
    echo -e "  ${YELLOW}•${NC} Fortschritt unter 50%"
    echo "    → Scope Review durchführen"
fi

if [ "$OVERDUE" -eq 0 ] && [ "$AT_RISK" -eq 0 ] && [ "$PROGRESS" -ge 50 ]; then
    echo -e "  ${GREEN}•${NC} Roadmap auf Kurs!"
    echo "    → Weiter so, regelmässig reviewen"
fi

echo ""
echo "Done."
