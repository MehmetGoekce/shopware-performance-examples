#!/bin/bash
#
# Performance Report Generator
#
# Generiert einen Performance-Report für Stakeholder.
# Kann wöchentlich oder monatlich per Cron ausgeführt werden.
#
# Verwendung:
#   ./generate-report.sh weekly
#   ./generate-report.sh monthly
#
# Voraussetzungen:
#   - jq (JSON parsing)
#   - curl (API calls)
#   - Zugang zu RUM/Monitoring APIs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_TYPE="${1:-weekly}"
OUTPUT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP=$(date +%Y%m%d)

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "  Performance Report Generator"
echo "================================================"
echo ""
echo "Report-Typ: $REPORT_TYPE"
echo "Datum: $(date)"
echo ""

# Output-Verzeichnis
mkdir -p "$OUTPUT_DIR"

# Konfiguration (anpassen!)
RUM_API_URL="${RUM_API_URL:-http://localhost:8080/api/rum}"
LIGHTHOUSE_API_URL="${LIGHTHOUSE_API_URL:-http://localhost:9001/api}"

# Zeitraum
case "$REPORT_TYPE" in
    weekly)
        DAYS=7
        PERIOD="Letzte 7 Tage"
        ;;
    monthly)
        DAYS=30
        PERIOD="Letzte 30 Tage"
        ;;
    *)
        echo "Unbekannter Report-Typ: $REPORT_TYPE"
        echo "Verwendung: $0 [weekly|monthly]"
        exit 1
        ;;
esac

# Report-Datei
REPORT_FILE="${OUTPUT_DIR}/performance-report-${REPORT_TYPE}-${TIMESTAMP}.md"

# Header
cat > "$REPORT_FILE" << EOF
# Performance Report

**Zeitraum**: $PERIOD
**Erstellt**: $(date '+%Y-%m-%d %H:%M')
**Typ**: ${REPORT_TYPE^}

---

## Executive Summary

EOF

# Core Web Vitals (Simulation - in Realität aus API)
echo "Sammle Core Web Vitals..."

# Simulierte Daten (ersetzen mit echten API-Calls)
LCP_P75=2340
LCP_PREV=2580
INP_P75=185
INP_PREV=195
CLS_P75=0.08
CLS_PREV=0.09

# Status berechnen
get_status() {
    local metric=$1
    local value=$2

    case $metric in
        LCP)
            if [ "$value" -le 2500 ]; then echo "good"
            elif [ "$value" -le 4000 ]; then echo "needs-improvement"
            else echo "poor"
            fi
            ;;
        INP)
            if [ "$value" -le 200 ]; then echo "good"
            elif [ "$value" -le 500 ]; then echo "needs-improvement"
            else echo "poor"
            fi
            ;;
    esac
}

LCP_STATUS=$(get_status LCP $LCP_P75)
INP_STATUS=$(get_status INP $INP_P75)

# Trend berechnen
get_trend() {
    local current=$1
    local previous=$2

    if [ "$current" -lt "$previous" ]; then
        echo "↓ verbessert"
    elif [ "$current" -gt "$previous" ]; then
        echo "↑ verschlechtert"
    else
        echo "→ stabil"
    fi
}

LCP_TREND=$(get_trend $LCP_P75 $LCP_PREV)
INP_TREND=$(get_trend $INP_P75 $INP_PREV)

# Core Web Vitals Tabelle
cat >> "$REPORT_FILE" << EOF
## Core Web Vitals (p75)

| Metrik | Aktuell | Vorperiode | Trend | Status |
|--------|---------|------------|-------|--------|
| LCP | ${LCP_P75}ms | ${LCP_PREV}ms | $LCP_TREND | $LCP_STATUS |
| INP | ${INP_P75}ms | ${INP_PREV}ms | $INP_TREND | $INP_STATUS |
| CLS | $CLS_P75 | $CLS_PREV | → stabil | good |

EOF

# Error Budget Status
echo "Berechne Error Budget..."

cat >> "$REPORT_FILE" << EOF
## Error Budget Status

| Metrik | Verbraucht | Verbleibend | Policy |
|--------|------------|-------------|--------|
| Gesamt | 35% | 65% | **Green** |

**Empfehlung**: Normale Entwicklung möglich.

EOF

# Top Issues
cat >> "$REPORT_FILE" << EOF
## Top Performance Issues

1. **Checkout LCP erhöht** (2.8s → Ziel: 2.5s)
   - Ursache: Synchrones Laden von Payment-Icons
   - Status: In Bearbeitung (PR #456)

2. **Produktseite CLS auf Mobile** (0.15)
   - Ursache: Bilder ohne dimensions
   - Status: Geplant für nächsten Sprint

3. **Suche langsam bei > 50 Ergebnissen**
   - Ursache: Fehlende Pagination
   - Status: Backlog

EOF

# Erfolge
cat >> "$REPORT_FILE" << EOF
## Erfolge diese Periode

- **LCP um 10% verbessert** auf Startseite
- **3 Performance-PRs** gemerged
- **0 Performance-Incidents**

EOF

# Nächste Schritte
cat >> "$REPORT_FILE" << EOF
## Nächste Schritte

1. Checkout-Optimierung abschließen
2. Image-Dimensions auf allen Produktseiten
3. Performance-Budget für JavaScript verschärfen

---

*Report generiert von: Performance Champion*
*Tool: generate-report.sh v1.0*
EOF

echo ""
echo -e "${GREEN}Report erstellt: $REPORT_FILE${NC}"
echo ""

# Optional: Report per Slack/Email senden
if [ -n "$SLACK_WEBHOOK" ]; then
    echo "Sende Report an Slack..."

    SUMMARY="Performance Report ($REPORT_TYPE): LCP ${LCP_P75}ms (${LCP_STATUS}), INP ${INP_P75}ms (${INP_STATUS})"

    curl -s -X POST "$SLACK_WEBHOOK" \
        -H 'Content-type: application/json' \
        -d "{\"text\": \"$SUMMARY\n\nVollständiger Report: [Link zum Report]\"}" > /dev/null

    echo "Slack-Nachricht gesendet."
fi

echo ""
echo "Done."
