#!/bin/bash
#
# Problem 9: Große Warenkorb-Berechnungen
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Profiled Warenkorb-Performance und Promotions/Rules.
#
# Verwendung: ./profile-cart.sh [SHOP_URL] [SHOP_PATH]
#

set -e

SHOP_URL="${1:-https://localhost}"
SHOP_PATH="${2:-.}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Schwellenwerte
CART_TIME_THRESHOLD_MS=500
RULE_COUNT_THRESHOLD=50
ADD_TO_CART_THRESHOLD_MS=300

echo "=== Warenkorb Performance Profiling ==="
echo "URL: ${SHOP_URL}"
echo ""

ISSUES=0

# Check 1: Add-to-Cart Performance
echo -e "${BLUE}1. Add-to-Cart Response Time${NC}"

# Wir messen die Cart-Seite als Proxy
START=$(date +%s%3N)
CART_RESPONSE=$(curl -sI -o /dev/null -w "%{http_code}" "${SHOP_URL}/checkout/cart" 2>/dev/null)
END=$(date +%s%3N)
CART_TIME=$((END - START))

echo "   Cart-Page Response: ${CART_TIME}ms (HTTP ${CART_RESPONSE})"

if [[ "${CART_TIME}" -gt "${CART_TIME_THRESHOLD_MS}" ]]; then
    echo -e "   ${RED}Langsam! (> ${CART_TIME_THRESHOLD_MS}ms)${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "   ${GREEN}OK${NC}"
fi

# Check 2: Anzahl aktiver Regeln
echo ""
echo -e "${BLUE}2. Aktive Promotion-Regeln${NC}"

if [[ -d "${SHOP_PATH}" ]]; then
    # Versuche über Datenbank zu zählen
    if [[ -f "${SHOP_PATH}/.env" ]]; then
        # Extrahiere DB-Credentials
        DB_URL=$(grep "DATABASE_URL" "${SHOP_PATH}/.env" 2>/dev/null | tail -1 | cut -d'=' -f2-)

        if [[ -n "${DB_URL}" ]]; then
            # Parse DATABASE_URL
            DB_HOST=$(echo "${DB_URL}" | sed -n 's|.*://[^:]*:\([^@]*\)@\([^:/]*\).*|\2|p')
            DB_NAME=$(echo "${DB_URL}" | sed -n 's|.*/\([^?]*\).*|\1|p')

            if command -v mysql &> /dev/null; then
                RULE_COUNT=$(mysql -N -e "SELECT COUNT(*) FROM rule WHERE active = 1" "${DB_NAME}" 2>/dev/null || echo "?")
                PROMOTION_COUNT=$(mysql -N -e "SELECT COUNT(*) FROM promotion WHERE active = 1" "${DB_NAME}" 2>/dev/null || echo "?")

                echo "   Aktive Regeln: ${RULE_COUNT}"
                echo "   Aktive Promotions: ${PROMOTION_COUNT}"

                if [[ "${RULE_COUNT}" != "?" ]] && [[ "${RULE_COUNT}" -gt "${RULE_COUNT_THRESHOLD}" ]]; then
                    echo -e "   ${YELLOW}Viele aktive Regeln (> ${RULE_COUNT_THRESHOLD})${NC}"
                    ISSUES=$((ISSUES + 1))
                fi
            else
                echo "   mysql CLI nicht verfügbar"
            fi
        fi
    fi

    # Alternative: Console Command
    if [[ -f "${SHOP_PATH}/bin/console" ]]; then
        echo ""
        echo "   Versuche Shopware Console..."

        # Rule-Liste
        RULE_OUTPUT=$(php "${SHOP_PATH}/bin/console" dbal:run-sql \
            "SELECT COUNT(*) as cnt FROM rule WHERE active = 1" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "?")

        if [[ "${RULE_OUTPUT}" != "?" ]]; then
            echo "   Aktive Regeln (Console): ${RULE_OUTPUT}"
        fi
    fi
else
    echo "   Shop-Pfad nicht verfügbar für DB-Analyse"
fi

# Check 3: Cart-Processor Analyse
echo ""
echo -e "${BLUE}3. Cart-Processor Konfiguration${NC}"

if [[ -f "${SHOP_PATH}/config/packages/shopware.yaml" ]]; then
    # Rule-Caching prüfen
    if grep -q "rule_caching:" "${SHOP_PATH}/config/packages/shopware.yaml"; then
        RULE_CACHING=$(grep -A1 "rule_caching:" "${SHOP_PATH}/config/packages/shopware.yaml" | tail -1)
        echo "   Rule-Caching: ${RULE_CACHING}"
    else
        echo -e "   ${YELLOW}Rule-Caching nicht explizit konfiguriert${NC}"
    fi
else
    echo "   shopware.yaml nicht gefunden"
fi

# Check 4: Cart-Größen-Test
echo ""
echo -e "${BLUE}4. Cart-Session-Größe${NC}"

if [[ -d "${SHOP_PATH}/var/sessions" ]]; then
    # Session-Dateien analysieren
    AVG_SESSION_SIZE=$(find "${SHOP_PATH}/var/sessions" -type f -name "sess_*" -print0 2>/dev/null | \
        xargs -0 ls -la 2>/dev/null | awk '{sum+=$5; count++} END {if(count>0) print int(sum/count/1024); else print "0"}')

    echo "   Durchschnittliche Session-Größe: ${AVG_SESSION_SIZE} KB"

    if [[ "${AVG_SESSION_SIZE}" -gt 50 ]]; then
        echo -e "   ${YELLOW}Große Sessions können Warenkorb verlangsamen${NC}"
    fi
else
    echo "   File-Sessions nicht gefunden (Redis?)"
fi

# Check 5: Typische Performance-Killer
echo ""
echo -e "${BLUE}5. Bekannte Performance-Killer${NC}"

KILLERS=0

# Zu viele Promotions
echo -n "   Komplexe Verschachtelung... "
if [[ -f "${SHOP_PATH}/bin/console" ]]; then
    NESTED=$(php "${SHOP_PATH}/bin/console" dbal:run-sql \
        "SELECT COUNT(*) FROM promotion_discount WHERE type = 'percentage' AND scope = 'cart'" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
    if [[ "${NESTED}" -gt 20 ]]; then
        echo -e "${YELLOW}${NESTED} Prozent-Rabatte${NC}"
        KILLERS=$((KILLERS + 1))
    else
        echo -e "${GREEN}OK${NC}"
    fi
else
    echo "N/A"
fi

# Check 6: Empfehlungen basierend auf Analyse
echo ""
echo "=== Zusammenfassung ==="

if [[ "${ISSUES}" -eq 0 ]] && [[ "${KILLERS}" -eq 0 ]]; then
    echo -e "${GREEN}Warenkorb-Performance scheint OK.${NC}"
    exit 0
else
    echo -e "${YELLOW}${ISSUES} Performance-Problem(e) erkannt.${NC}"
    echo ""
    echo "Empfohlene Optimierungen:"
    echo ""
    echo "  1. Inaktive Regeln löschen:"
    echo "     bin/console dbal:run-sql \\"
    echo "       \"DELETE FROM rule WHERE active = 0\""
    echo ""
    echo "  2. Rule-Caching aktivieren:"
    echo "     shopware.cart.rule_caching: true"
    echo ""
    echo "  3. Alte Warenkörbe bereinigen:"
    echo "     bin/console cart:cleanup"
    echo ""
    echo "  4. Redis für Sessions:"
    echo "     framework.session.handler_id: redis://..."
    exit 1
fi
