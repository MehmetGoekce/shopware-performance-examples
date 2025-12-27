#!/bin/bash
#
# Problem 18: CDN nicht konfiguriert
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Prüft ob ein CDN für statische Assets konfiguriert ist.
#
# Verwendung: ./check-cdn.sh [SHOP_URL] [SHOP_PATH]
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

# Bekannte CDN-Header
CDN_HEADERS=(
    "cf-ray"           # Cloudflare
    "x-cdn"            # Generic
    "x-cache"          # CloudFront, Fastly
    "x-served-by"      # Fastly
    "x-amz-cf-id"      # CloudFront
    "x-vercel-cache"   # Vercel
    "x-bunny-"         # BunnyCDN
    "x-akamai-"        # Akamai
)

echo "=== CDN Konfiguration Check ==="
echo "URL: $SHOP_URL"
echo ""

ISSUES=0
CDN_DETECTED=""

# Check 1: CDN-Header prüfen
echo -e "${BLUE}1. CDN-Header Analyse${NC}"

HEADERS=$(curl -sI "$SHOP_URL" 2>/dev/null)

for header in "${CDN_HEADERS[@]}"; do
    if echo "$HEADERS" | grep -qi "$header"; then
        HEADER_VALUE=$(echo "$HEADERS" | grep -i "$header" | head -1)
        echo -e "   ${GREEN}✓${NC} $HEADER_VALUE"

        # CDN identifizieren
        if echo "$header" | grep -qi "cf-ray"; then
            CDN_DETECTED="Cloudflare"
        elif echo "$header" | grep -qi "x-amz-cf"; then
            CDN_DETECTED="CloudFront"
        elif echo "$header" | grep -qi "x-served-by"; then
            CDN_DETECTED="Fastly"
        elif echo "$header" | grep -qi "bunny"; then
            CDN_DETECTED="BunnyCDN"
        fi
    fi
done

if [ -z "$CDN_DETECTED" ]; then
    echo -e "   ${YELLOW}Kein CDN erkannt${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo ""
    echo -e "   CDN erkannt: ${GREEN}$CDN_DETECTED${NC}"
fi

# Check 2: Asset-URLs prüfen
echo ""
echo -e "${BLUE}2. Asset-URL Analyse${NC}"

HTML=$(curl -sL "$SHOP_URL" 2>/dev/null)
ORIGIN_DOMAIN=$(echo "$SHOP_URL" | sed 's|https\?://||g' | cut -d'/' -f1)

# CSS-URLs
CSS_URLS=$(echo "$HTML" | grep -oE 'href="[^"]*\.css[^"]*"' | sed 's/href="//g' | sed 's/"//g' | head -5)
# JS-URLs
JS_URLS=$(echo "$HTML" | grep -oE 'src="[^"]*\.js[^"]*"' | sed 's/src="//g' | sed 's/"//g' | head -5)
# Bild-URLs
IMG_URLS=$(echo "$HTML" | grep -oE 'src="[^"]*\.(jpg|png|webp)[^"]*"' | sed 's/src="//g' | sed 's/"//g' | head -5)

ALL_ASSETS="$CSS_URLS $JS_URLS $IMG_URLS"

ORIGIN_ASSETS=0
CDN_ASSETS=0

for url in $ALL_ASSETS; do
    if [ -n "$url" ]; then
        if [[ "$url" == http* ]]; then
            ASSET_DOMAIN=$(echo "$url" | sed 's|https\?://||g' | cut -d'/' -f1)
        else
            ASSET_DOMAIN="$ORIGIN_DOMAIN"
        fi

        if [ "$ASSET_DOMAIN" = "$ORIGIN_DOMAIN" ]; then
            ORIGIN_ASSETS=$((ORIGIN_ASSETS + 1))
        else
            CDN_ASSETS=$((CDN_ASSETS + 1))
        fi
    fi
done

echo "   Assets vom Origin: $ORIGIN_ASSETS"
echo "   Assets von CDN: $CDN_ASSETS"

if [ "$CDN_ASSETS" -eq 0 ] && [ "$ORIGIN_ASSETS" -gt 0 ]; then
    echo -e "   ${YELLOW}Alle Assets kommen vom Origin${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Check 3: Shopware CDN-Konfiguration
echo ""
echo -e "${BLUE}3. Shopware CDN-Konfiguration${NC}"

if [ -f "$SHOP_PATH/config/packages/shopware.yaml" ]; then
    if grep -q "cdn:" "$SHOP_PATH/config/packages/shopware.yaml"; then
        CDN_URL=$(grep -A2 "cdn:" "$SHOP_PATH/config/packages/shopware.yaml" | grep "url:" | awk '{print $2}' | tr -d '"' | tr -d "'")
        if [ -n "$CDN_URL" ]; then
            echo -e "   ${GREEN}CDN URL konfiguriert: $CDN_URL${NC}"
        else
            echo -e "   ${YELLOW}CDN-Block vorhanden aber keine URL${NC}"
        fi
    else
        echo -e "   ${YELLOW}Keine CDN-Konfiguration in shopware.yaml${NC}"
    fi
else
    echo "   shopware.yaml nicht gefunden"
fi

# Check 4: Response-Zeit vergleichen
echo ""
echo -e "${BLUE}4. Response-Zeit Test${NC}"

# Origin TTFB
ORIGIN_TIME=$(curl -sI -o /dev/null -w "%{time_starttransfer}" "$SHOP_URL" 2>/dev/null)
echo "   Origin TTFB: ${ORIGIN_TIME}s"

# Wenn CDN erkannt, auch CDN-Zeit messen
if [ -n "$CDN_DETECTED" ]; then
    # Cache-Hit prüfen
    CACHE_STATUS=$(echo "$HEADERS" | grep -iE "x-cache|cf-cache-status" | head -1)
    echo "   Cache Status: $CACHE_STATUS"
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [ "$ISSUES" -eq 0 ] && [ -n "$CDN_DETECTED" ]; then
    echo -e "${GREEN}CDN korrekt konfiguriert ($CDN_DETECTED).${NC}"
    exit 0
else
    echo -e "${YELLOW}CDN-Optimierung empfohlen.${NC}"
    echo ""
    echo "Empfohlene Optionen:"
    echo ""
    echo "  1. Cloudflare (kostenloser Tier):"
    echo "     - DNS umstellen"
    echo "     - Page Rules für Caching"
    echo ""
    echo "  2. BunnyCDN (günstig, EU):"
    echo "     - Pull Zone erstellen"
    echo "     - Origin auf Shop setzen"
    echo ""
    echo "  3. Shopware CDN-URL konfigurieren:"
    echo "     shopware:"
    echo "       cdn:"
    echo "         url: 'https://cdn.your-shop.com'"
    exit 1
fi
