#!/bin/bash
#
# Problem 3: Zu große JavaScript-Bundles
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Analysiert JavaScript Bundle-Größen einer Shopware-Installation.
#
# Verwendung: ./analyze-bundles.sh [SHOP_URL] [SHOP_PATH]
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

# Schwellenwerte (in KB)
THRESHOLD_CRITICAL=500
THRESHOLD_WARNING=200
TOTAL_THRESHOLD=1000

echo "=== JavaScript Bundle Analyse ==="
echo "URL: $SHOP_URL"
echo "Path: $SHOP_PATH"
echo ""

ISSUES=0
TOTAL_SIZE=0

# Methode 1: Lokale Dateien analysieren
echo -e "${BLUE}=== Lokale Bundle-Analyse ===${NC}"
echo ""

if [ -d "$SHOP_PATH/public/bundles" ]; then
    echo "Bundle-Größen (komprimiert):"
    echo ""

    find "$SHOP_PATH/public/bundles" -name "*.js" -type f 2>/dev/null | while read -r file; do
        SIZE_BYTES=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        SIZE_KB=$((SIZE_BYTES / 1024))
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE_KB))

        BASENAME=$(basename "$file")

        if [ "$SIZE_KB" -gt "$THRESHOLD_CRITICAL" ]; then
            echo -e "  ${RED}$SIZE_KB KB${NC} - $BASENAME"
        elif [ "$SIZE_KB" -gt "$THRESHOLD_WARNING" ]; then
            echo -e "  ${YELLOW}$SIZE_KB KB${NC} - $BASENAME"
        else
            echo -e "  ${GREEN}$SIZE_KB KB${NC} - $BASENAME"
        fi
    done
fi

# Methode 2: Remote-Analyse via curl
echo ""
echo -e "${BLUE}=== Remote Bundle-Analyse ===${NC}"
echo ""

# HTML der Startseite holen und JS-URLs extrahieren
HTML=$(curl -s -L "$SHOP_URL" 2>/dev/null || echo "")

if [ -n "$HTML" ]; then
    # JavaScript URLs extrahieren
    JS_URLS=$(echo "$HTML" | grep -oE 'src="[^"]*\.js[^"]*"' | sed 's/src="//g' | sed 's/"//g' | head -20)

    echo "Remote JavaScript Dateien:"
    echo ""

    for js_url in $JS_URLS; do
        # Relative URLs ergänzen
        if [[ "$js_url" != http* ]]; then
            js_url="$SHOP_URL$js_url"
        fi

        # Größe via HEAD Request
        SIZE_HEADER=$(curl -sI "$js_url" 2>/dev/null | grep -i "content-length" | awk '{print $2}' | tr -d '\r')

        if [ -n "$SIZE_HEADER" ]; then
            SIZE_KB=$((SIZE_HEADER / 1024))
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE_KB))

            BASENAME=$(basename "$js_url" | cut -d'?' -f1)

            if [ "$SIZE_KB" -gt "$THRESHOLD_CRITICAL" ]; then
                echo -e "  ${RED}$SIZE_KB KB${NC} - $BASENAME"
                ISSUES=$((ISSUES + 1))
            elif [ "$SIZE_KB" -gt "$THRESHOLD_WARNING" ]; then
                echo -e "  ${YELLOW}$SIZE_KB KB${NC} - $BASENAME"
            else
                echo -e "  ${GREEN}$SIZE_KB KB${NC} - $BASENAME"
            fi
        fi
    done
else
    echo "  Konnte HTML nicht abrufen."
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="
echo ""
echo "Gesamt-JavaScript: ~${TOTAL_SIZE} KB"
echo ""

if [ "$TOTAL_SIZE" -gt "$TOTAL_THRESHOLD" ]; then
    echo -e "${RED}Kritisch: JavaScript > ${TOTAL_THRESHOLD} KB${NC}"
    echo ""
    echo "Empfohlene Optimierungen:"
    echo ""
    echo "  1. Code Splitting aktivieren:"
    echo "     const module = await import('./module.js');"
    echo ""
    echo "  2. Tree-Shaking in webpack:"
    echo "     optimization.usedExports: true"
    echo ""
    echo "  3. Ungenutzte Plugins deaktivieren"
    echo ""
    echo "  4. Third-Party Scripts prüfen:"
    echo "     GTM, Analytics, Chat-Widgets"
    exit 1
elif [ "$ISSUES" -gt 0 ]; then
    echo -e "${YELLOW}$ISSUES Bundle(s) über ${THRESHOLD_CRITICAL} KB${NC}"
    echo "Überprüfen Sie große Bundles auf Optimierungspotential."
    exit 1
else
    echo -e "${GREEN}JavaScript-Größe im akzeptablen Bereich.${NC}"
    exit 0
fi
