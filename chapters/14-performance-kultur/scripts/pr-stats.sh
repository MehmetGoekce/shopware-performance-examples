#!/bin/bash
#
# PR Statistics für Performance-Reviews
#
# Analysiert GitHub PRs auf Performance-Review-Aktivität.
# Hilft Champions, den Review-Status zu tracken.
#
# Verwendung:
#   ./pr-stats.sh
#   ./pr-stats.sh --days 30
#   ./pr-stats.sh --verbose
#
# Voraussetzungen:
#   - GitHub CLI (gh) installiert und authentifiziert
#   - jq

set -e

DAYS="${DAYS:-30}"
VERBOSE=false

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            DAYS="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
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

echo "================================================"
echo "  PR Performance Review Statistics"
echo "================================================"
echo ""
echo "Zeitraum: Letzte $DAYS Tage"
echo "Datum: $(date)"
echo ""

# GitHub CLI prüfen
if ! command -v gh &> /dev/null; then
    echo -e "${RED}FEHLER: GitHub CLI (gh) nicht installiert${NC}"
    echo "Installation: https://cli.github.com/"
    exit 1
fi

# Authentifizierung prüfen
if ! gh auth status &> /dev/null; then
    echo -e "${RED}FEHLER: Nicht bei GitHub authentifiziert${NC}"
    echo "Führe aus: gh auth login"
    exit 1
fi

# Datum berechnen
SINCE_DATE=$(date -d "-$DAYS days" +%Y-%m-%d 2>/dev/null || date -v-${DAYS}d +%Y-%m-%d)

echo "Lade PRs seit $SINCE_DATE..."
echo ""

# PRs abrufen
PRS=$(gh pr list \
    --state merged \
    --limit 500 \
    --json number,title,labels,createdAt,mergedAt,comments,reviewDecision \
    --search "created:>$SINCE_DATE")

TOTAL_PRS=$(echo "$PRS" | jq 'length')

if [ "$TOTAL_PRS" -eq 0 ]; then
    echo "Keine PRs im Zeitraum gefunden."
    exit 0
fi

echo -e "Gefundene PRs: ${BLUE}$TOTAL_PRS${NC}"
echo ""

# Performance-Label PRs
PERF_LABELED=$(echo "$PRS" | jq '[.[] | select(.labels[].name | contains("performance"))] | length')

# PRs mit Performance-Kommentaren (vereinfacht)
# In Realität: Kommentar-Inhalt prüfen
PERF_COMMENTED=0

# Statistiken
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Statistiken"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Total
echo -e "Gesamt PRs:              ${BLUE}$TOTAL_PRS${NC}"

# Mit Performance-Label
PERF_RATE=$((PERF_LABELED * 100 / TOTAL_PRS))
if [ "$PERF_RATE" -ge 80 ]; then
    COLOR=$GREEN
elif [ "$PERF_RATE" -ge 50 ]; then
    COLOR=$YELLOW
else
    COLOR=$RED
fi
echo -e "Mit Performance-Label:   ${COLOR}$PERF_LABELED ($PERF_RATE%)${NC}"

# Review-Status
APPROVED=$(echo "$PRS" | jq '[.[] | select(.reviewDecision == "APPROVED")] | length')
CHANGES_REQUESTED=$(echo "$PRS" | jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length')

echo ""
echo "Review-Status:"
echo -e "  Approved:              $APPROVED"
echo -e "  Changes Requested:     $CHANGES_REQUESTED"

# Labels Breakdown
echo ""
echo "Labels (Performance-relevant):"

# Performance Labels zählen
PERF_CRITICAL=$(echo "$PRS" | jq '[.[] | select(.labels[].name == "performance-critical")] | length')
PERF_REVIEW=$(echo "$PRS" | jq '[.[] | select(.labels[].name == "performance-reviewed")] | length')
PERF_IMPROVEMENT=$(echo "$PRS" | jq '[.[] | select(.labels[].name == "performance-improvement")] | length')

echo "  performance-critical:  $PERF_CRITICAL"
echo "  performance-reviewed:  $PERF_REVIEW"
echo "  performance-improvement: $PERF_IMPROVEMENT"

# Empfehlung
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Empfehlung"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$PERF_RATE" -lt 50 ]; then
    echo -e "${RED}Review-Rate zu niedrig!${NC}"
    echo "Empfehlung:"
    echo "  - Performance-Checklist in PR-Template"
    echo "  - Automatisches Label bei Frontend-Changes"
    echo "  - Champion-Reminder in #performance"
elif [ "$PERF_RATE" -lt 80 ]; then
    echo -e "${YELLOW}Review-Rate verbesserungswürdig.${NC}"
    echo "Empfehlung:"
    echo "  - Weiter an Konsistenz arbeiten"
    echo "  - Positive Beispiele teilen"
else
    echo -e "${GREEN}Review-Rate gut!${NC}"
    echo "Weiter so!"
fi

# Verbose: Einzelne PRs auflisten
if [ "$VERBOSE" = true ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PRs ohne Performance-Review"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "$PRS" | jq -r '.[] | select(.labels | map(.name) | contains(["performance"]) | not) | "PR #\(.number): \(.title)"' | head -20

    echo ""
    echo "(Zeige max. 20)"
fi

echo ""
echo "Done."
