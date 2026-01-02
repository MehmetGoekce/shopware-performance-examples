#!/bin/bash
#
# Lokaler Lighthouse Test-Runner
#
# Führt Lighthouse-Tests lokal aus ohne CI/CD.
# Nützlich für schnelle Checks während der Entwicklung.
#
# Verwendung:
#   ./run-lighthouse.sh https://ihr-shop.de/
#   ./run-lighthouse.sh https://ihr-shop.de/ --view
#   ./run-lighthouse.sh https://ihr-shop.de/ --mobile
#
# Voraussetzungen:
#   npm install -g lighthouse @lhci/cli

set -e

URL="${1:-https://localhost/}"
VIEW_REPORT="${2:-}"
MOBILE="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "  Lighthouse Performance Test"
echo "================================================"
echo ""
echo "URL: ${URL}"
echo "Zeit: $(date)"
echo ""

# Prüfen ob Lighthouse installiert
if ! command -v lighthouse &> /dev/null; then
    echo -e "${RED}FEHLER: Lighthouse nicht installiert${NC}"
    echo "Installation: npm install -g lighthouse"
    exit 1
fi

# Output-Verzeichnis erstellen
mkdir -p "${OUTPUT_DIR}"

# Lighthouse-Optionen
LIGHTHOUSE_OPTS="--output=html,json --output-path=${OUTPUT_DIR}/report-${TIMESTAMP}"

# Mobile oder Desktop
if [[ "${MOBILE}" == "--mobile" ]] || [[ "$2" == "--mobile" ]]; then
    echo "Modus: Mobile (Throttling aktiv)"
    LIGHTHOUSE_OPTS="${LIGHTHOUSE_OPTS} --preset=perf"
else
    echo "Modus: Desktop"
    LIGHTHOUSE_OPTS="${LIGHTHOUSE_OPTS} --preset=desktop"
fi

echo ""
echo "Starte Lighthouse..."
echo ""

# Lighthouse ausführen
lighthouse "${URL}" ${LIGHTHOUSE_OPTS} --chrome-flags="--headless --no-sandbox"

# Ergebnis anzeigen
echo ""
echo -e "${GREEN}Test abgeschlossen!${NC}"
echo ""
echo "Reports gespeichert:"
echo "  HTML: ${OUTPUT_DIR}/report-${TIMESTAMP}.report.html"
echo "  JSON: ${OUTPUT_DIR}/report-${TIMESTAMP}.report.json"

# JSON parsen und Score anzeigen
if command -v jq &> /dev/null; then
    JSON_FILE="${OUTPUT_DIR}/report-${TIMESTAMP}.report.json"
    if [[ -f "${JSON_FILE}" ]]; then
        echo ""
        echo "Ergebnisse:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        PERF=$(jq -r '.categories.performance.score * 100 | floor' "${JSON_FILE}")
        A11Y=$(jq -r '.categories.accessibility.score * 100 | floor' "${JSON_FILE}")
        BP=$(jq -r '.categories["best-practices"].score * 100 | floor' "${JSON_FILE}")
        SEO=$(jq -r '.categories.seo.score * 100 | floor' "${JSON_FILE}")

        LCP=$(jq -r '.audits["largest-contentful-paint"].numericValue | floor' "${JSON_FILE}")
        TBT=$(jq -r '.audits["total-blocking-time"].numericValue | floor' "${JSON_FILE}")
        CLS=$(jq -r '.audits["cumulative-layout-shift"].numericValue' "${JSON_FILE}")

        # Performance Score mit Farbe
        if [[ "${PERF}" -ge 90 ]]; then
            echo -e "Performance:    ${GREEN}${PERF}${NC}"
        elif [[ "${PERF}" -ge 50 ]]; then
            echo -e "Performance:    ${YELLOW}${PERF}${NC}"
        else
            echo -e "Performance:    ${RED}${PERF}${NC}"
        fi

        echo "Accessibility:  ${A11Y}"
        echo "Best Practices: ${BP}"
        echo "SEO:            ${SEO}"
        echo ""
        echo "Core Web Vitals:"

        # LCP bewerten
        if [[ "${LCP}" -le 2500 ]]; then
            echo -e "  LCP: ${GREEN}${LCP}ms${NC} (gut ≤2500ms)"
        elif [[ "${LCP}" -le 4000 ]]; then
            echo -e "  LCP: ${YELLOW}${LCP}ms${NC} (verbesserungswürdig)"
        else
            echo -e "  LCP: ${RED}${LCP}ms${NC} (schlecht >4000ms)"
        fi

        # TBT bewerten (korreliert mit INP)
        if [[ "${TBT}" -le 200 ]]; then
            echo -e "  TBT: ${GREEN}${TBT}ms${NC} (gut ≤200ms)"
        elif [[ "${TBT}" -le 600 ]]; then
            echo -e "  TBT: ${YELLOW}${TBT}ms${NC} (verbesserungswürdig)"
        else
            echo -e "  TBT: ${RED}${TBT}ms${NC} (schlecht >600ms)"
        fi

        # CLS bewerten
        CLS_INT=$(echo "${CLS} * 1000" | bc | cut -d. -f1)
        if [[ "${CLS_INT}" -le 100 ]]; then
            echo -e "  CLS: ${GREEN}${CLS}${NC} (gut ≤0.1)"
        elif [[ "${CLS_INT}" -le 250 ]]; then
            echo -e "  CLS: ${YELLOW}${CLS}${NC} (verbesserungswürdig)"
        else
            echo -e "  CLS: ${RED}${CLS}${NC} (schlecht >0.25)"
        fi
    fi
fi

# Report öffnen
if [[ "${VIEW_REPORT}" == "--view" ]] || [[ "$2" == "--view" ]]; then
    HTML_FILE="${OUTPUT_DIR}/report-${TIMESTAMP}.report.html"
    if [[ -f "${HTML_FILE}" ]]; then
        echo ""
        echo "Öffne Report im Browser..."
        if command -v xdg-open &> /dev/null; then
            xdg-open "${HTML_FILE}"
        elif command -v open &> /dev/null; then
            open "${HTML_FILE}"
        fi
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
