#!/bin/bash
#
# Problem 6: Render-Blocking CSS
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Identifiziert render-blocking CSS und JavaScript Ressourcen.
#
# Verwendung: ./check-render-blocking.sh [SHOP_URL]
#

set -e

SHOP_URL="${1:-https://localhost}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Schwellenwerte
CSS_SIZE_THRESHOLD_KB=50
JS_SIZE_THRESHOLD_KB=100

echo "=== Render-Blocking Ressourcen Check ==="
echo "URL: $SHOP_URL"
echo ""

ISSUES=0

# HTML holen
HTML=$(curl -sL "$SHOP_URL" 2>/dev/null)

# HEAD-Bereich extrahieren
HEAD=$(echo "$HTML" | sed -n '/<head/,/<\/head>/p')

# Check 1: Render-blocking CSS
echo -e "${BLUE}1. CSS im <head>${NC}"

CSS_LINKS=$(echo "$HEAD" | grep -oE '<link[^>]*rel="stylesheet"[^>]*>' || echo "")
CSS_COUNT=$(echo "$CSS_LINKS" | grep -c "stylesheet" 2>/dev/null || echo "0")

echo "   Gefunden: $CSS_COUNT CSS-Dateien"

BLOCKING_CSS=0
if [ -n "$CSS_LINKS" ]; then
    echo "$CSS_LINKS" | while read -r link; do
        HREF=$(echo "$link" | grep -oE 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')

        if [ -n "$HREF" ]; then
            # Prüfen auf async/defer/preload
            if echo "$link" | grep -qE 'media="print"|rel="preload"|onload='; then
                echo -e "   ${GREEN}✓${NC} $(basename "$HREF" | cut -c1-40) (async)"
            else
                # Größe prüfen
                if [[ "$HREF" != http* ]]; then
                    HREF="$SHOP_URL$HREF"
                fi
                SIZE=$(curl -sI "$HREF" 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r')
                SIZE_KB=$((${SIZE:-0} / 1024))

                if [ "$SIZE_KB" -gt "$CSS_SIZE_THRESHOLD_KB" ]; then
                    echo -e "   ${RED}✗${NC} $(basename "$HREF" | cut -c1-40) (${SIZE_KB}KB, blocking)"
                    BLOCKING_CSS=$((BLOCKING_CSS + 1))
                else
                    echo -e "   ${YELLOW}⚠${NC} $(basename "$HREF" | cut -c1-40) (${SIZE_KB}KB, blocking)"
                fi
            fi
        fi
    done
fi

if [ "$BLOCKING_CSS" -gt 0 ]; then
    ISSUES=$((ISSUES + 1))
fi

# Check 2: Render-blocking JavaScript
echo ""
echo -e "${BLUE}2. JavaScript im <head>${NC}"

JS_SCRIPTS=$(echo "$HEAD" | grep -oE '<script[^>]*src="[^"]*"[^>]*>' || echo "")
JS_COUNT=$(echo "$JS_SCRIPTS" | grep -c "src=" 2>/dev/null || echo "0")

echo "   Gefunden: $JS_COUNT Script-Tags"

BLOCKING_JS=0
if [ -n "$JS_SCRIPTS" ]; then
    echo "$JS_SCRIPTS" | while read -r script; do
        SRC=$(echo "$script" | grep -oE 'src="[^"]*"' | sed 's/src="//g' | sed 's/"//g')

        if [ -n "$SRC" ]; then
            if echo "$script" | grep -qE 'async|defer|type="module"'; then
                echo -e "   ${GREEN}✓${NC} $(basename "$SRC" | cut -c1-40) (async/defer)"
            else
                echo -e "   ${RED}✗${NC} $(basename "$SRC" | cut -c1-40) (blocking!)"
                BLOCKING_JS=$((BLOCKING_JS + 1))
            fi
        fi
    done
fi

if [ "$BLOCKING_JS" -gt 0 ]; then
    ISSUES=$((ISSUES + 1))
fi

# Check 3: Critical CSS inline?
echo ""
echo -e "${BLUE}3. Critical CSS${NC}"
echo -n "   Inline <style> im <head>... "

INLINE_STYLE=$(echo "$HEAD" | grep -c "<style" 2>/dev/null || echo "0")
INLINE_STYLE=$(echo "$INLINE_STYLE" | tr -d '[:space:]' | head -c 10)

if [ -n "$INLINE_STYLE" ] && [ "$INLINE_STYLE" -gt 0 ] 2>/dev/null; then
    STYLE_SIZE=$(echo "$HEAD" | sed -n '/<style/,/<\/style>/p' | wc -c)
    STYLE_KB=$((STYLE_SIZE / 1024))
    echo -e "${GREEN}Ja (${STYLE_KB}KB inline)${NC}"
else
    echo -e "${YELLOW}Nein${NC}"
    echo "   Empfehlung: Critical CSS inline für schnelleres FCP"
    ISSUES=$((ISSUES + 1))
fi

# Check 4: Preload für wichtige Ressourcen
echo ""
echo -e "${BLUE}4. Resource Hints${NC}"

PRELOAD_COUNT=$(echo "$HEAD" | grep -c 'rel="preload"' 2>/dev/null | tr -d '[:space:]' || echo "0")
PREFETCH_COUNT=$(echo "$HEAD" | grep -c 'rel="prefetch"' 2>/dev/null | tr -d '[:space:]' || echo "0")

echo "   Preload: $PRELOAD_COUNT"
echo "   Prefetch: $PREFETCH_COUNT"

if [ "$PRELOAD_COUNT" -eq 0 ]; then
    echo -e "   ${YELLOW}Keine Preloads gefunden${NC}"
    echo "   Empfehlung: LCP-Bild und wichtige Fonts preloaden"
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}Keine kritischen Render-Blocking Ressourcen.${NC}"
    exit 0
else
    echo -e "${RED}$ISSUES Problem(e) gefunden.${NC}"
    echo ""
    echo "Empfohlene Optimierungen:"
    echo ""
    echo "  1. CSS async laden:"
    echo '     <link rel="preload" href="style.css" as="style"'
    echo '           onload="this.rel='\''stylesheet'\''">'
    echo ""
    echo "  2. Critical CSS inline:"
    echo "     <style>/* Above-the-fold CSS */</style>"
    echo ""
    echo "  3. JS mit defer laden:"
    echo '     <script src="app.js" defer></script>'
    echo ""
    echo "  4. Wichtige Ressourcen preloaden:"
    echo '     <link rel="preload" href="hero.webp" as="image">'
    exit 1
fi
