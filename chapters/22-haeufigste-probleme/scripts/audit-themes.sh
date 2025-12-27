#!/bin/bash
#
# Problem 16: Zu viele aktive Themes / Theme-Probleme
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Analysiert Theme-Konfiguration und Performance-Impact.
#
# Verwendung: ./audit-themes.sh [SHOP_PATH]
#

set -e

SHOP_PATH="${1:-.}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Schwellenwerte
MAX_THEME_DEPTH=3
MAX_CSS_SIZE_KB=500
MAX_JS_SIZE_KB=300

echo "=== Theme Audit ==="
echo "Shop: $SHOP_PATH"
echo ""

ISSUES=0

# Check 1: Installierte Themes
echo -e "${BLUE}1. Installierte Themes${NC}"

THEME_DIR="$SHOP_PATH/custom/plugins"
VENDOR_THEMES="$SHOP_PATH/vendor/shopware"

CUSTOM_THEMES=0
if [ -d "$THEME_DIR" ]; then
    CUSTOM_THEMES=$(find "$THEME_DIR" -maxdepth 2 -name "theme.json" 2>/dev/null | wc -l)
fi

echo "   Custom Themes: $CUSTOM_THEMES"

# Storefront als Basis
if [ -d "$VENDOR_THEMES/storefront" ]; then
    echo "   Storefront: vorhanden"
fi

# Check 2: Theme-Vererbung
echo ""
echo -e "${BLUE}2. Theme-Vererbungstiefe${NC}"

if [ -d "$THEME_DIR" ]; then
    find "$THEME_DIR" -name "theme.json" 2>/dev/null | while read -r theme_file; do
        THEME_NAME=$(dirname "$theme_file" | xargs basename)
        EXTENDS=$(grep -o '"extends"[[:space:]]*:[[:space:]]*"[^"]*"' "$theme_file" 2>/dev/null | cut -d'"' -f4)

        if [ -n "$EXTENDS" ]; then
            echo "   $THEME_NAME extends $EXTENDS"

            # Tiefe zählen (vereinfacht)
            DEPTH=1
            CURRENT_EXTENDS="$EXTENDS"
            while [ -n "$CURRENT_EXTENDS" ] && [ "$DEPTH" -lt 10 ]; do
                PARENT_THEME=$(find "$THEME_DIR" -name "theme.json" -path "*$CURRENT_EXTENDS*" 2>/dev/null | head -1)
                if [ -f "$PARENT_THEME" ]; then
                    CURRENT_EXTENDS=$(grep -o '"extends"[[:space:]]*:[[:space:]]*"[^"]*"' "$PARENT_THEME" 2>/dev/null | cut -d'"' -f4)
                    DEPTH=$((DEPTH + 1))
                else
                    break
                fi
            done

            if [ "$DEPTH" -gt "$MAX_THEME_DEPTH" ]; then
                echo -e "   ${YELLOW}Vererbungstiefe: $DEPTH (> $MAX_THEME_DEPTH)${NC}"
                ISSUES=$((ISSUES + 1))
            fi
        else
            echo "   $THEME_NAME (Basis-Theme)"
        fi
    done
fi

# Check 3: Kompilierte Theme-Größe
echo ""
echo -e "${BLUE}3. Kompilierte Theme-Assets${NC}"

THEME_BUILD="$SHOP_PATH/public/theme"

if [ -d "$THEME_BUILD" ]; then
    # CSS-Größe
    CSS_TOTAL=$(find "$THEME_BUILD" -name "*.css" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1)
    CSS_KB=$((${CSS_TOTAL:-0} / 1024))

    # JS-Größe
    JS_TOTAL=$(find "$THEME_BUILD" -name "*.js" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1)
    JS_KB=$((${JS_TOTAL:-0} / 1024))

    echo "   CSS gesamt: ${CSS_KB} KB"
    echo "   JS gesamt: ${JS_KB} KB"

    if [ "$CSS_KB" -gt "$MAX_CSS_SIZE_KB" ]; then
        echo -e "   ${RED}CSS zu groß (> ${MAX_CSS_SIZE_KB} KB)${NC}"
        ISSUES=$((ISSUES + 1))
    fi

    if [ "$JS_KB" -gt "$MAX_JS_SIZE_KB" ]; then
        echo -e "   ${RED}JS zu groß (> ${MAX_JS_SIZE_KB} KB)${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "   ${YELLOW}Theme nicht kompiliert?${NC}"
    echo "   Führen Sie aus: bin/console theme:compile"
fi

# Check 4: Theme-Konfiguration
echo ""
echo -e "${BLUE}4. Theme-Konfiguration${NC}"

if [ -f "$SHOP_PATH/bin/console" ]; then
    # Theme-Dump
    THEME_CONFIG=$(php "$SHOP_PATH/bin/console" theme:dump-config 2>/dev/null | head -20 || echo "")

    if [ -n "$THEME_CONFIG" ]; then
        echo "   Theme-Konfiguration geladen"

        # Prüfe auf bekannte Performance-Probleme
        if echo "$THEME_CONFIG" | grep -q "sw-color-brand-primary"; then
            echo -e "   ${GREEN}Standard-Variablen verwendet${NC}"
        fi
    fi
else
    echo "   Console nicht verfügbar"
fi

# Check 5: Ungenutzte Theme-Assets
echo ""
echo -e "${BLUE}5. Potentiell ungenutzte Assets${NC}"

if [ -d "$THEME_DIR" ]; then
    # Zähle SCSS-Dateien die nicht importiert werden
    SCSS_FILES=$(find "$THEME_DIR" -name "*.scss" 2>/dev/null | wc -l)
    echo "   SCSS-Dateien: $SCSS_FILES"

    # Zähle JS-Plugins
    JS_PLUGINS=$(find "$THEME_DIR" -path "*/Resources/app/storefront/src/*" -name "*.js" 2>/dev/null | wc -l)
    echo "   JS-Plugins: $JS_PLUGINS"
fi

# Check 6: Theme-Compile Zeit (wenn möglich)
echo ""
echo -e "${BLUE}6. Theme-Compile Performance${NC}"

if [ -f "$SHOP_PATH/bin/console" ]; then
    echo "   Teste Theme-Compile..."

    START=$(date +%s)
    php "$SHOP_PATH/bin/console" theme:compile --no-interaction 2>/dev/null || true
    END=$(date +%s)

    COMPILE_TIME=$((END - START))
    echo "   Compile-Zeit: ${COMPILE_TIME}s"

    if [ "$COMPILE_TIME" -gt 60 ]; then
        echo -e "   ${YELLOW}Lange Compile-Zeit (> 60s)${NC}"
        ISSUES=$((ISSUES + 1))
    fi
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}Theme-Konfiguration OK.${NC}"
    exit 0
else
    echo -e "${YELLOW}$ISSUES Theme-Problem(e) gefunden.${NC}"
    echo ""
    echo "Empfohlene Optimierungen:"
    echo ""
    echo "  1. Ungenutzte Themes entfernen:"
    echo "     bin/console theme:change Storefront SalesChannelId"
    echo ""
    echo "  2. CSS/JS minifizieren:"
    echo "     bin/console theme:compile --keep-all"
    echo ""
    echo "  3. Vererbungstiefe reduzieren"
    echo "     Weniger Theme-Ebenen = schnelleres Kompilieren"
    echo ""
    echo "  4. Critical CSS extrahieren:"
    echo "     Above-the-fold CSS inline laden"
    exit 1
fi
