#!/bin/bash
#
# Problem 19: Synchrone API-Calls
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Erkennt synchrone externe API-Calls die das Rendering blockieren.
#
# Verwendung: ./detect-sync-calls.sh [SHOP_PATH]
#

set -e

SHOP_PATH="${1:-.}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=== Synchrone API-Call Detection ==="
echo "Shop: $SHOP_PATH"
echo ""

ISSUES=0

# Check 1: HTTP Client Calls in Subscribers/Controllers
echo -e "${BLUE}1. HTTP Client Usage in kritischen Pfaden${NC}"

SEARCH_DIRS=(
    "$SHOP_PATH/custom/plugins"
    "$SHOP_PATH/src"
)

SYNC_PATTERNS=(
    'HttpClient'
    'Guzzle'
    'file_get_contents.*http'
    'curl_exec'
    'fopen.*http'
)

FOUND_SYNC=0

for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "   Suche in: $dir"

        for pattern in "${SYNC_PATTERNS[@]}"; do
            MATCHES=$(grep -rln "$pattern" "$dir" --include="*.php" 2>/dev/null | head -10)

            if [ -n "$MATCHES" ]; then
                echo ""
                echo -e "   ${YELLOW}Pattern: $pattern${NC}"

                for file in $MATCHES; do
                    BASENAME=$(basename "$file")
                    DIRNAME=$(dirname "$file" | sed "s|$SHOP_PATH/||g")

                    # Prüfe ob in kritischem Pfad (Subscriber, Controller, Service)
                    if echo "$file" | grep -qE "Subscriber|Controller|Service"; then
                        echo -e "   ${RED}✗${NC} $DIRNAME/$BASENAME"
                        FOUND_SYNC=$((FOUND_SYNC + 1))
                    else
                        echo -e "   ${YELLOW}⚠${NC} $DIRNAME/$BASENAME"
                    fi
                done
            fi
        done
    fi
done

if [ "$FOUND_SYNC" -gt 0 ]; then
    ISSUES=$((ISSUES + 1))
fi

# Check 2: Bekannte ERP/PIM Integrationen
echo ""
echo -e "${BLUE}2. ERP/PIM Integration Analyse${NC}"

INTEGRATION_PATTERNS=(
    "erp"
    "pim"
    "wawi"
    "sap"
    "dynamics"
    "navision"
    "odoo"
    "akeneo"
)

for pattern in "${INTEGRATION_PATTERNS[@]}"; do
    FOUND=$(find "$SHOP_PATH/custom/plugins" -iname "*$pattern*" -type d 2>/dev/null | head -1)

    if [ -n "$FOUND" ]; then
        echo -e "   ${YELLOW}Integration gefunden:${NC} $pattern"

        # Prüfe ob async
        ASYNC_CHECK=$(grep -rl "MessageBus\|dispatch\|async" "$FOUND" --include="*.php" 2>/dev/null | wc -l)

        if [ "$ASYNC_CHECK" -gt 0 ]; then
            echo -e "   ${GREEN}   → Async-Pattern erkannt${NC}"
        else
            echo -e "   ${RED}   → Möglicherweise synchron!${NC}"
            ISSUES=$((ISSUES + 1))
        fi
    fi
done

# Check 3: Payment Provider Calls
echo ""
echo -e "${BLUE}3. Payment Provider Calls${NC}"

PAYMENT_PATTERNS=(
    "PayPal"
    "Stripe"
    "Klarna"
    "Mollie"
    "Adyen"
)

for pattern in "${PAYMENT_PATTERNS[@]}"; do
    PAYMENT_PLUGIN=$(find "$SHOP_PATH/custom/plugins" -iname "*$pattern*" -type d 2>/dev/null | head -1)

    if [ -n "$PAYMENT_PLUGIN" ]; then
        echo "   $pattern Integration gefunden"

        # Zahlungen sollten nicht im Storefront synchron sein
        STOREFRONT_CALLS=$(grep -rl "StorefrontController\|PageLoader" "$PAYMENT_PLUGIN" --include="*.php" 2>/dev/null | \
            xargs grep -l "HttpClient\|request(" 2>/dev/null | wc -l)

        if [ "$STOREFRONT_CALLS" -gt 0 ]; then
            echo -e "   ${YELLOW}   → HTTP-Calls in Storefront-Context${NC}"
        fi
    fi
done

# Check 4: Externe Service Timeouts
echo ""
echo -e "${BLUE}4. Timeout-Konfiguration${NC}"

# Suche nach Timeout-Konfigurationen
TIMEOUT_CONFIG=$(grep -rn "timeout" "$SHOP_PATH/custom/plugins" --include="*.php" 2>/dev/null | \
    grep -E "['\"](timeout|connect_timeout)['\"]" | head -5)

if [ -n "$TIMEOUT_CONFIG" ]; then
    echo "   Timeout-Konfigurationen gefunden:"
    echo "$TIMEOUT_CONFIG" | while read -r line; do
        FILE=$(echo "$line" | cut -d':' -f1 | xargs basename)
        TIMEOUT=$(echo "$line" | grep -oE "[0-9]+" | head -1)
        echo "   - $FILE: ${TIMEOUT}s"

        if [ -n "$TIMEOUT" ] && [ "$TIMEOUT" -gt 10 ]; then
            echo -e "     ${YELLOW}Warnung: Timeout > 10s${NC}"
        fi
    done
else
    echo -e "   ${YELLOW}Keine expliziten Timeouts gefunden${NC}"
    echo "   Empfehlung: Immer Timeouts für externe Calls setzen"
fi

# Check 5: Message Queue für Async
echo ""
echo -e "${BLUE}5. Async Message Handler${NC}"

ASYNC_HANDLERS=$(grep -rln "MessageHandlerInterface\|#\[AsMessageHandler\]" "$SHOP_PATH/custom/plugins" --include="*.php" 2>/dev/null | wc -l)
SYNC_SERVICES=$(grep -rln "implements.*Service\|class.*Service" "$SHOP_PATH/custom/plugins" --include="*.php" 2>/dev/null | wc -l)

echo "   Async Message Handler: $ASYNC_HANDLERS"
echo "   Service-Klassen: $SYNC_SERVICES"

if [ "$ASYNC_HANDLERS" -eq 0 ] && [ "$SYNC_SERVICES" -gt 5 ]; then
    echo -e "   ${YELLOW}Keine async Handler aber viele Services${NC}"
    echo "   Empfehlung: Externe Calls über Message Queue abwickeln"
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}Keine kritischen synchronen Calls erkannt.${NC}"
    exit 0
else
    echo -e "${RED}$ISSUES potentielle(s) Problem(e) gefunden.${NC}"
    echo ""
    echo "Empfohlene Lösungen:"
    echo ""
    echo "  1. Caching für externe Daten:"
    echo '     $cache->get("erp_stock_$id", fn() => $erp->getStock($id), 300);'
    echo ""
    echo "  2. Message Queue verwenden:"
    echo '     $bus->dispatch(new SyncErpMessage($productId));'
    echo ""
    echo "  3. Timeouts setzen (max 5s für Storefront):"
    echo "     'timeout' => 5,"
    echo "     'connect_timeout' => 2,"
    echo ""
    echo "  4. Circuit Breaker implementieren:"
    echo "     Bei Fehlern Fallback-Werte verwenden"
    exit 1
fi
