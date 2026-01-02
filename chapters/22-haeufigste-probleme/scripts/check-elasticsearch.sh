#!/bin/bash
#
# Problem 11: Elasticsearch nicht konfiguriert
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Prüft ob Elasticsearch aktiv und korrekt konfiguriert ist.
#
# Verwendung: ./check-elasticsearch.sh [SHOP_PATH] [ES_HOST]
#

set -e

SHOP_PATH="${1:-.}"
ES_HOST="${2:-localhost:9200}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Elasticsearch Konfiguration Check ==="
echo "Shop: ${SHOP_PATH}"
echo "ES Host: ${ES_HOST}"
echo ""

ISSUES=0

# Check 1: Elasticsearch erreichbar?
echo -n "1. Elasticsearch erreichbar... "
if curl -s --connect-timeout 5 "http://${ES_HOST}" > /dev/null 2>&1; then
    ES_VERSION=$(curl -s "http://${ES_HOST}" | grep -o '"number" *: *"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}OK${NC} (Version: ${ES_VERSION})"
else
    echo -e "${RED}FEHLER${NC}"
    echo "  Elasticsearch nicht erreichbar unter ${ES_HOST}"
    ISSUES=$((ISSUES + 1))
fi

# Check 2: Cluster Health
echo -n "2. Cluster Health... "
HEALTH=$(curl -s "http://${ES_HOST}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [[ "${HEALTH}" = "green" ]]; then
    echo -e "${GREEN}${HEALTH}${NC}"
elif [[ "${HEALTH}" = "yellow" ]]; then
    echo -e "${YELLOW}${HEALTH}${NC} (Replicas fehlen - OK für Single-Node)"
else
    echo -e "${RED}${HEALTH:-nicht erreichbar}${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Check 3: Shopware ES Konfiguration
echo -n "3. Shopware ES aktiviert... "

ES_CONFIG="${SHOP_PATH}/config/packages/shopware.yaml"
ES_ENABLED=false

if [[ -f "${ES_CONFIG}" ]]; then
    if grep -q "es:" "${ES_CONFIG}" && grep -q "enabled: true" "${ES_CONFIG}"; then
        ES_ENABLED=true
    fi
fi

# Auch .env prüfen
if [[ -f "${SHOP_PATH}/.env" ]]; then
    if grep -q "SHOPWARE_ES_ENABLED=1" "${SHOP_PATH}/.env" 2>/dev/null; then
        ES_ENABLED=true
    fi
fi

if [[ "${ES_ENABLED}" = true ]]; then
    echo -e "${GREEN}Ja${NC}"
else
    echo -e "${RED}Nein${NC}"
    echo "  Elasticsearch in Shopware nicht aktiviert!"
    ISSUES=$((ISSUES + 1))
fi

# Check 4: Shopware Indizes vorhanden?
echo -n "4. Shopware Indizes... "
INDEX_COUNT=$(curl -s "http://${ES_HOST}/_cat/indices?format=json" 2>/dev/null | grep -c "sw" || echo "0")

if [[ "${INDEX_COUNT}" -gt 0 ]]; then
    echo -e "${GREEN}${INDEX_COUNT} Indizes gefunden${NC}"
else
    echo -e "${YELLOW}Keine sw-Indizes${NC}"
    echo "  Führen Sie aus: bin/console es:index"
    ISSUES=$((ISSUES + 1))
fi

# Check 5: Index Größe
echo -n "5. Index Größe... "
STORE_SIZE=$(curl -s "http://${ES_HOST}/_cat/indices?format=json&bytes=mb" 2>/dev/null | \
    grep "sw" | awk -F'"' '{sum += $26} END {print sum}' || echo "0")

if [[ -n "${STORE_SIZE}" ]] && [[ "${STORE_SIZE}" != "0" ]]; then
    echo -e "${GREEN}${STORE_SIZE} MB${NC}"
else
    echo -e "${YELLOW}Unbekannt${NC}"
fi

# Check 6: Suchperformance testen
echo -n "6. Such-Performance... "
START=$(date +%s%3N)
curl -s -X GET "http://${ES_HOST}/sw*/_search?size=1" -H 'Content-Type: application/json' \
    -d '{"query":{"match_all":{}}}' > /dev/null 2>&1
END=$(date +%s%3N)
SEARCH_TIME=$((END - START))

if [[ "${SEARCH_TIME}" -lt 100 ]]; then
    echo -e "${GREEN}${SEARCH_TIME}ms${NC}"
elif [[ "${SEARCH_TIME}" -lt 500 ]]; then
    echo -e "${YELLOW}${SEARCH_TIME}ms${NC} (könnte schneller sein)"
else
    echo -e "${RED}${SEARCH_TIME}ms${NC} (zu langsam!)"
    ISSUES=$((ISSUES + 1))
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [[ ${ISSUES} -eq 0 ]]; then
    echo -e "${GREEN}Elasticsearch korrekt konfiguriert.${NC}"
    exit 0
else
    echo -e "${RED}${ISSUES} Problem(e) gefunden.${NC}"
    echo ""
    echo "Empfohlene Aktionen:"
    echo "  1. Elasticsearch aktivieren:"
    echo "     shopware.es.enabled: true"
    echo ""
    echo "  2. Indizes erstellen:"
    echo "     bin/console es:index"
    echo ""
    echo "  3. Indexing aktivieren:"
    echo "     shopware.es.indexing_enabled: true"
    exit 1
fi
