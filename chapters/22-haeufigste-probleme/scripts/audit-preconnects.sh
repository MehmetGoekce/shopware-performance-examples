#!/bin/bash
#
# Problem 5: Fehlende Preconnects
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Prüft ob Preconnect-Headers für Third-Party-Domains gesetzt sind.
#
# Verwendung: ./audit-preconnects.sh [SHOP_URL]
#

set -e

SHOP_URL="${1:-https://localhost}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Bekannte Third-Party-Domains die preconnect benötigen
KNOWN_THIRD_PARTY=(
    "www.googletagmanager.com"
    "www.google-analytics.com"
    "fonts.googleapis.com"
    "fonts.gstatic.com"
    "www.facebook.com"
    "connect.facebook.net"
    "platform.twitter.com"
    "cdn.jsdelivr.net"
    "unpkg.com"
    "www.youtube.com"
    "player.vimeo.com"
    "js.stripe.com"
    "www.paypal.com"
    "cdn.shopify.com"
    "static.hotjar.com"
    "snap.licdn.com"
)

echo "=== Preconnect Audit ==="
echo "URL: ${SHOP_URL}"
echo ""

ISSUES=0

# HTML und Headers holen
HTML=$(curl -sL "${SHOP_URL}" 2>/dev/null)
HEADERS=$(curl -sI "${SHOP_URL}" 2>/dev/null)

# Vorhandene Preconnects finden
echo -e "${BLUE}1. Vorhandene Preconnects${NC}"

PRECONNECTS=$(echo "${HTML}" | grep -oE 'rel="preconnect"[^>]*href="[^"]*"' | grep -oE 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
DNS_PREFETCH=$(echo "${HTML}" | grep -oE 'rel="dns-prefetch"[^>]*href="[^"]*"' | grep -oE 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')

if [[ -n "${PRECONNECTS}" ]]; then
    echo "   Preconnects gefunden:"
    for pc in ${PRECONNECTS}; do
        echo -e "   ${GREEN}✓${NC} ${pc}"
    done
else
    echo -e "   ${YELLOW}Keine Preconnects gefunden${NC}"
fi

if [[ -n "${DNS_PREFETCH}" ]]; then
    echo ""
    echo "   DNS-Prefetch gefunden:"
    for dp in ${DNS_PREFETCH}; do
        echo -e "   ${GREEN}✓${NC} ${dp}"
    done
fi

# Third-Party-Domains im HTML finden
echo ""
echo -e "${BLUE}2. Third-Party-Domains in Verwendung${NC}"

# Externe URLs extrahieren
EXTERNAL_DOMAINS=$(echo "${HTML}" | grep -oE '(src|href)="https?://[^/"]*' | \
    sed 's/src="//g' | sed 's/href="//g' | \
    sed 's|https\?://||g' | \
    sort -u | \
    grep -v "$(echo "${SHOP_URL}" | sed 's|https\?://||g' | cut -d'/' -f1)")

MISSING_PRECONNECTS=()

for domain in ${EXTERNAL_DOMAINS}; do
    # Prüfen ob Preconnect existiert
    if echo "${PRECONNECTS} ${DNS_PREFETCH}" | grep -q "${domain}"; then
        echo -e "   ${GREEN}✓${NC} ${domain} (preconnect vorhanden)"
    else
        echo -e "   ${YELLOW}⚠${NC} ${domain} (kein preconnect)"
        MISSING_PRECONNECTS+=("${domain}")
    fi
done

# Empfehlungen für bekannte Third-Party-Domains
echo ""
echo -e "${BLUE}3. Empfohlene Preconnects${NC}"

RECOMMENDATIONS=()
for known in "${KNOWN_THIRD_PARTY[@]}"; do
    if echo "${HTML}" | grep -q "${known}"; then
        if ! echo "${PRECONNECTS} ${DNS_PREFETCH}" | grep -q "${known}"; then
            RECOMMENDATIONS+=("${known}")
            echo -e "   ${RED}✗${NC} ${known} - wird verwendet aber kein preconnect"
            ISSUES=$((ISSUES + 1))
        fi
    fi
done

if [[ ${#RECOMMENDATIONS[@]} -eq 0 ]]; then
    echo -e "   ${GREEN}Alle bekannten Third-Party-Domains haben preconnect${NC}"
fi

# Zusammenfassung und Code-Empfehlung
echo ""
echo "=== Zusammenfassung ==="

if [[ "${ISSUES}" -eq 0 ]] && [[ ${#MISSING_PRECONNECTS[@]} -eq 0 ]]; then
    echo -e "${GREEN}Preconnect-Konfiguration optimal.${NC}"
    exit 0
else
    echo -e "${YELLOW}${#MISSING_PRECONNECTS[@]} Third-Party-Domain(s) ohne preconnect${NC}"
    echo ""
    echo "Empfohlene Ergänzungen in <head>:"
    echo ""

    for domain in "${MISSING_PRECONNECTS[@]}"; do
        echo "<link rel=\"preconnect\" href=\"https://${domain}\" crossorigin>"
    done

    for rec in "${RECOMMENDATIONS[@]}"; do
        if ! printf '%s\n' "${MISSING_PRECONNECTS[@]}" | grep -q "^${rec}$"; then
            echo "<link rel=\"preconnect\" href=\"https://${rec}\" crossorigin>"
        fi
    done

    echo ""
    echo "Für weniger kritische Domains:"
    echo "<link rel=\"dns-prefetch\" href=\"https://example.com\">"

    exit 1
fi
