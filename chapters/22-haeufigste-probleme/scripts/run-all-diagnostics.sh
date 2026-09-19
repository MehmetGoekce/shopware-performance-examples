#!/bin/bash
#
# Shopware 6 Performance Diagnostics - Run All Checks
# Companion Code zu Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Verwendung: ./run-all-diagnostics.sh [SHOP_URL] [SHOP_PATH]
#

set -uo pipefail

usage() {
    cat <<'USAGE'
Usage: run-all-diagnostics.sh [SHOP_URL] [SHOP_PATH]

Fuehrt alle 20 Diagnose-Skripte dieses Kapitels nacheinander aus und
fasst das Ergebnis zusammen.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parameter
SHOP_URL="${1:-http://localhost}"
SHOP_PATH="${2:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ergebnis-Arrays
declare -a PASSED=()
declare -a FAILED=()
declare -a WARNINGS=()

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Shopware 6 Performance Diagnostics${NC}"
echo -e "${BLUE}  Kapitel 22: Die 20 häufigsten Probleme${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "Shop URL: ${SHOP_URL}"
echo "Shop Path: ${SHOP_PATH}"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Funktion: Check ausführen
# Ruft ein Einzelskript auf. Alle Skripte dieses Kapitels nehmen dieselben
# beiden Argumente: $1 = SHOP_URL, $2 = SHOP_PATH.
#
# stderr wird NICHT verworfen. Ein "2>/dev/null" an dieser Stelle verbirgt
# genau die Faelle, in denen ein Skript selbst kaputt ist — es meldet dann
# stillschweigend "OK", obwohl es gar nichts gemessen hat.
run_check() {
    local name="$1"
    local script="$2"
    local problem="$3"
    local output status

    echo -e "${BLUE}[Problem ${problem}]${NC} ${name}"

    if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
        echo -e "  ${YELLOW}Script nicht gefunden: ${script}${NC}"
        WARNINGS+=("${name} (Script fehlt)")
        return
    fi

    output=$(bash "${SCRIPT_DIR}/${script}" "${SHOP_URL}" "${SHOP_PATH}" 2>&1)
    status=$?

    case "${status}" in
        0)
            echo -e "  ${GREEN}unauffaellig${NC}"
            PASSED+=("${name}")
            ;;
        1)
            echo -e "  ${YELLOW}etwas gefunden — Einzelaufruf fuer Details:${NC}"
            echo "    ./${script} '${SHOP_URL}' '${SHOP_PATH}'"
            FAILED+=("${name}")
            ;;
        64|69)
            echo -e "  ${YELLOW}nicht ausfuehrbar (Exit ${status}):${NC}"
            printf '%s\n' "${output}" | tail -3 | sed 's/^/    /'
            WARNINGS+=("${name} (Exit ${status})")
            ;;
        *)
            echo -e "  ${RED}Skript abgebrochen (Exit ${status}):${NC}"
            printf '%s\n' "${output}" | tail -5 | sed 's/^/    /'
            WARNINGS+=("${name} (Abbruch, Exit ${status})")
            ;;
    esac
}

# ============================================
# Die 20 Checks
# ============================================

echo -e "\n${YELLOW}=== Datenbank & Caching ===${NC}\n"

run_check "Langsame DB-Queries" "diagnose-slow-queries.sh" 1
run_check "HTTP-Cache Status" "check-http-cache.sh" 2
run_check "Session-Lock Blocking" "test-session-lock.sh" 8
run_check "Elasticsearch Konfiguration" "check-elasticsearch.sh" 11

echo -e "\n${YELLOW}=== Frontend Performance ===${NC}\n"

run_check "JavaScript Bundle-Größe" "analyze-bundles.sh" 3
run_check "Bildoptimierung" "check-images.sh" 4
run_check "Preconnect-Headers" "audit-preconnects.sh" 5
run_check "Render-Blocking CSS" "check-render-blocking.sh" 6
run_check "Browser-Cache-Headers" "check-cache-headers.sh" 20

echo -e "\n${YELLOW}=== Server & PHP ===${NC}\n"

run_check "OPcache Status" "check-opcache.sh" 12
run_check "Debug-Modus" "check-debug-mode.sh" 13
run_check "Gzip-Kompression" "check-compression.sh" 14
run_check "CDN-Konfiguration" "check-cdn.sh" 18

echo -e "\n${YELLOW}=== Shopware-spezifisch ===${NC}\n"

run_check "N+1 Query Pattern" "detect-n1-queries.sh" 7
run_check "Warenkorb-Performance" "profile-cart.sh" 9
run_check "Plugin-Anzahl" "audit-plugins.sh" 10
run_check "Theme-Konfiguration" "audit-themes.sh" 16

echo -e "\n${YELLOW}=== Wartung & Logging ===${NC}\n"

run_check "Cronjob-Scheduling" "analyze-cronjobs.sh" 15
run_check "Log-Dateien Größe" "check-logs.sh" 17
run_check "Synchrone API-Calls" "detect-sync-calls.sh" 19

# ============================================
# Zusammenfassung
# ============================================

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  ZUSAMMENFASSUNG${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

echo -e "${GREEN}Bestanden: ${#PASSED[@]}${NC}"
for item in "${PASSED[@]}"; do
    echo "  ✓ ${item}"
done

echo ""
echo -e "${RED}Probleme: ${#FAILED[@]}${NC}"
for item in "${FAILED[@]}"; do
    echo "  ✗ ${item}"
done

echo ""
echo -e "${YELLOW}Warnungen: ${#WARNINGS[@]}${NC}"
for item in "${WARNINGS[@]}"; do
    echo "  ⚠ ${item}"
done

echo ""
echo "${#FAILED[@]} von $(( ${#PASSED[@]} + ${#FAILED[@]} )) Pruefungen haben etwas gefunden."
echo ""
echo "Eine Prozentzahl steht hier bewusst nicht. Die Pruefungen sind weder"
echo "gleich gewichtet noch unabhaengig voneinander: ein abgeschalteter"
echo "HTTP-Cache wiegt schwerer als ein fehlender Preconnect, und beide"
echo "zaehlten in einem Score gleich viel. Gehen Sie die Liste oben durch."
echo ""
echo "Zu jedem Punkt steht die Erklaerung in Kapitel 22 des Buchs."
echo "Professionelles Audit: memotech.ch/performance-check"
echo ""

# Exit-Code wie bei den Einzelskripten: 0 unauffaellig, 1 etwas gefunden.
# Kein dritter Code fuer "viele Funde" — die Zahl steht in der Liste oben,
# und CI-Pipelines pruefen ueblicherweise nur auf 0 oder nicht 0.
if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
else
    exit 0
fi
