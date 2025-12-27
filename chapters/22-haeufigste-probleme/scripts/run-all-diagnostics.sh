#!/bin/bash
#
# Shopware 6 Performance Diagnostics - Run All Checks
# Companion Code zu Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Verwendung: ./run-all-diagnostics.sh [SHOP_URL] [SHOP_PATH]
#

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parameter
SHOP_URL="${1:-https://localhost}"
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
echo "Shop URL: $SHOP_URL"
echo "Shop Path: $SHOP_PATH"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Funktion: Check ausführen
run_check() {
    local name="$1"
    local script="$2"
    local number="$3"

    echo -e "${BLUE}[$number/20]${NC} Prüfe: $name..."

    if [ -f "$SCRIPT_DIR/$script" ]; then
        if bash "$SCRIPT_DIR/$script" "$SHOP_URL" "$SHOP_PATH" 2>/dev/null; then
            echo -e "  ${GREEN}✓ OK${NC}"
            PASSED+=("$name")
        else
            echo -e "  ${RED}✗ Problem gefunden${NC}"
            FAILED+=("$name")
        fi
    else
        echo -e "  ${YELLOW}⚠ Script nicht gefunden${NC}"
        WARNINGS+=("$name (Script fehlt)")
    fi
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
    echo "  ✓ $item"
done

echo ""
echo -e "${RED}Probleme: ${#FAILED[@]}${NC}"
for item in "${FAILED[@]}"; do
    echo "  ✗ $item"
done

echo ""
echo -e "${YELLOW}Warnungen: ${#WARNINGS[@]}${NC}"
for item in "${WARNINGS[@]}"; do
    echo "  ⚠ $item"
done

# Score berechnen
TOTAL=$((${#PASSED[@]} + ${#FAILED[@]}))
if [ $TOTAL -gt 0 ]; then
    SCORE=$((${#PASSED[@]} * 100 / $TOTAL))
else
    SCORE=0
fi

echo ""
echo -e "${BLUE}Performance Score: ${SCORE}%${NC}"

if [ $SCORE -ge 80 ]; then
    echo -e "${GREEN}Excellent! Ihr Shop ist gut optimiert.${NC}"
elif [ $SCORE -ge 60 ]; then
    echo -e "${YELLOW}Gut, aber es gibt Verbesserungspotential.${NC}"
else
    echo -e "${RED}Kritisch! Mehrere Performance-Probleme gefunden.${NC}"
fi

echo ""
echo "Detaillierte Lösungen finden Sie in Kapitel 22 des Buchs."
echo "Professionelles Audit: memotech.ch/performance-audit"
echo ""

# Exit-Code basierend auf Ergebnis
if [ ${#FAILED[@]} -gt 5 ]; then
    exit 2  # Kritisch
elif [ ${#FAILED[@]} -gt 0 ]; then
    exit 1  # Warnungen
else
    exit 0  # Alles OK
fi
