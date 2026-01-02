#!/bin/bash
#
# Performance Budget Checker
#
# Prüft ob eine URL die definierten Performance-Budgets einhält.
# Kann in CI/CD oder als Git Pre-Push Hook verwendet werden.
#
# Verwendung:
#   ./budget-check.sh https://ihr-shop.de/
#   ./budget-check.sh https://ihr-shop.de/ --strict
#
# Exit-Codes:
#   0 - Alle Budgets eingehalten
#   1 - Warnung (soft budget exceeded)
#   2 - Fehler (hard budget exceeded)

set -e

URL="${1:-https://localhost/}"
STRICT="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Budget-Schwellenwerte (Hard Limits)
BUDGET_LCP=2500          # ms
BUDGET_CLS=100           # * 1000 (0.1)
BUDGET_TBT=300           # ms
BUDGET_FCP=1800          # ms
BUDGET_PERF_SCORE=75     # 0-100
BUDGET_JS_SIZE=307200    # 300KB in Bytes
BUDGET_TOTAL_SIZE=2097152 # 2MB in Bytes

# Warnschwellen (10% unter Hard Limit)
WARN_LCP=2250
WARN_CLS=90
WARN_TBT=270

EXIT_CODE=0

echo "================================================"
echo "  Performance Budget Check"
echo "================================================"
echo ""
echo -e "URL: ${BLUE}${URL}${NC}"
echo "Zeit: $(date)"
echo ""

# Prüfen ob Lighthouse installiert
if ! command -v lighthouse &> /dev/null; then
    echo -e "${RED}FEHLER: Lighthouse nicht installiert${NC}"
    echo "Installation: npm install -g lighthouse"
    exit 2
fi

# Temporäres Verzeichnis
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Führe Lighthouse-Test aus..."
echo ""

# Lighthouse ausführen (nur Performance)
lighthouse "${URL}" \
    --output=json \
    --output-path="${TMP_DIR}/report.json" \
    --only-categories=performance \
    --chrome-flags="--headless --no-sandbox" \
    --quiet

# Ergebnisse parsen
if [[ ! -f "${TMP_DIR}/report.json" ]]; then
    echo -e "${RED}FEHLER: Kein Report generiert${NC}"
    exit 2
fi

# Werte extrahieren
PERF_SCORE=$(jq -r '.categories.performance.score * 100 | floor' "${TMP_DIR}/report.json")
LCP=$(jq -r '.audits["largest-contentful-paint"].numericValue | floor' "${TMP_DIR}/report.json")
TBT=$(jq -r '.audits["total-blocking-time"].numericValue | floor' "${TMP_DIR}/report.json")
CLS_RAW=$(jq -r '.audits["cumulative-layout-shift"].numericValue' "${TMP_DIR}/report.json")
CLS=$(echo "${CLS_RAW} * 1000" | bc | cut -d. -f1)
FCP=$(jq -r '.audits["first-contentful-paint"].numericValue | floor' "${TMP_DIR}/report.json")
JS_SIZE=$(jq -r '.audits["total-byte-weight"].details.items[] | select(.url | contains(".js")) | .totalBytes' "${TMP_DIR}/report.json" | awk '{s+=$1} END {print s}')
TOTAL_SIZE=$(jq -r '.audits["total-byte-weight"].numericValue | floor' "${TMP_DIR}/report.json")

# Fallbacks
JS_SIZE=${JS_SIZE:-0}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Ergebnisse"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Funktion: Budget prüfen
check_budget() {
    local name="$1"
    local value="$2"
    local warn_limit="$3"
    local hard_limit="$4"
    local unit="$5"
    local invert="${6:-false}"  # true wenn niedriger = besser

    local status=""
    local color=""

    if [[ "${invert}" == "true" ]]; then
        # Für Scores: höher = besser
        if [[ "${value}" -ge "${hard_limit}" ]]; then
            status="PASS"
            color="${GREEN}"
        elif [[ "${value}" -ge "${warn_limit}" ]]; then
            status="WARN"
            color="${YELLOW}"
            [ ${EXIT_CODE} -lt 1 ] && EXIT_CODE=1
        else
            status="FAIL"
            color="${RED}"
            EXIT_CODE=2
        fi
    else
        # Für Metriken: niedriger = besser
        if [[ "${value}" -le "${warn_limit}" ]]; then
            status="PASS"
            color="${GREEN}"
        elif [[ "${value}" -le "${hard_limit}" ]]; then
            status="WARN"
            color="${YELLOW}"
            [ ${EXIT_CODE} -lt 1 ] && EXIT_CODE=1
        else
            status="FAIL"
            color="${RED}"
            EXIT_CODE=2
        fi
    fi

    printf "%-20s %8s${unit}  (limit: %s${unit})  ${color}[%s]${NC}\n" "${name}" "${value}" "${hard_limit}" "${status}"
}

# Budgets prüfen
echo "Core Web Vitals:"
check_budget "LCP" "${LCP}" "${WARN_LCP}" "${BUDGET_LCP}" "ms"
check_budget "CLS (×1000)" "${CLS}" "${WARN_CLS}" "${BUDGET_CLS}" ""
check_budget "TBT" "${TBT}" "${WARN_TBT}" "${BUDGET_TBT}" "ms"
check_budget "FCP" "${FCP}" "1620" "${BUDGET_FCP}" "ms"
echo ""

echo "Scores:"
check_budget "Performance" "${PERF_SCORE}" "80" "${BUDGET_PERF_SCORE}" "" "true"
echo ""

echo "Resource Sizes:"
JS_KB=$((JS_SIZE / 1024))
TOTAL_KB=$((TOTAL_SIZE / 1024))
check_budget "JavaScript" "${JS_KB}" "270" "300" "KB"
check_budget "Total Size" "${TOTAL_KB}" "1800" "2048" "KB"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Zusammenfassung
echo ""
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo -e "${GREEN}PASS: Alle Performance-Budgets eingehalten${NC}"
elif [[ ${EXIT_CODE} -eq 1 ]]; then
    echo -e "${YELLOW}WARN: Budget-Warnung(en) - Optimierung empfohlen${NC}"
    if [[ "${STRICT}" == "--strict" ]]; then
        echo -e "${RED}(--strict: Warnung als Fehler gewertet)${NC}"
        EXIT_CODE=2
    fi
else
    echo -e "${RED}FAIL: Performance-Budget(s) überschritten${NC}"
fi

echo ""
exit ${EXIT_CODE}
