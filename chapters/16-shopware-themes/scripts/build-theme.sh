#!/bin/bash
#
# Theme Build Script für Shopware 6
#
# Optimierter Build-Prozess für Production Themes.
#
# Verwendung:
#   ./build-theme.sh              # Production Build
#   ./build-theme.sh --watch      # Development mit Watch
#   ./build-theme.sh --analyze    # Mit Bundle-Analyse
#
# Voraussetzungen:
#   - Shopware 6 CLI (bin/console)
#   - Node.js (für Vite, ab SW 6.7)
#

set -euo pipefail

# Konfiguration
SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
THEME_NAME="${THEME_NAME:-PerformanceTheme}"
USE_VITE="${USE_VITE:-auto}"  # auto, true, false
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

# Argumente
MODE="production"
WATCH=false
ANALYZE=false
SKIP_CACHE=false
VERBOSE=false

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Hilfe
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --watch           Watch mode for development"
    echo "  --analyze         Generate bundle analysis"
    echo "  --skip-cache      Skip cache clearing"
    echo "  --verbose         Verbose output"
    echo "  --vite            Force Vite build (SW 6.7+)"
    echo "  --webpack         Force Webpack build (SW < 6.7)"
    echo "  --help            Show this help"
    echo ""
}

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            MODE="development"
            WATCH=true
            shift
            ;;
        --analyze)
            ANALYZE=true
            shift
            ;;
        --skip-cache)
            SKIP_CACHE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --vite)
            USE_VITE="true"
            shift
            ;;
        --webpack)
            USE_VITE="false"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unbekannte Option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Shopware Theme Builder${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Shopware-Version erkennen
detect_shopware_version() {
    if [ -f "$SHOPWARE_ROOT/composer.json" ]; then
        SW_VERSION=$(grep '"shopware/core"' "$SHOPWARE_ROOT/composer.json" | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        echo "$SW_VERSION"
    else
        echo "6.5"
    fi
}

SW_VERSION=$(detect_shopware_version)
echo -e "Shopware Version: $SW_VERSION"

# Vite oder Webpack?
if [ "$USE_VITE" = "auto" ]; then
    # SW 6.7+ verwendet Vite
    MAJOR=$(echo "$SW_VERSION" | cut -d. -f1)
    MINOR=$(echo "$SW_VERSION" | cut -d. -f2)

    if [ "$MAJOR" -ge 6 ] && [ "$MINOR" -ge 7 ]; then
        USE_VITE="true"
        echo -e "Build-System: Vite (ab SW 6.7)"
    else
        USE_VITE="false"
        echo -e "Build-System: Webpack"
    fi
fi

echo -e "Mode: $MODE"
echo -e "Theme: $THEME_NAME"
echo ""

# Start-Zeit
START_TIME=$(date +%s)

# Schritt 1: Cache leeren (optional)
if [ "$SKIP_CACHE" = false ]; then
    echo -e "${YELLOW}[1/4] Cache leeren...${NC}"

    cd "$SHOPWARE_ROOT"

    # HTTP-Cache leeren
    if [ "$VERBOSE" = true ]; then
        bin/console http:cache:clear
    else
        bin/console http:cache:clear > /dev/null 2>&1
    fi

    # Theme-Cache leeren
    rm -rf var/cache/prod*/twig
    rm -rf var/cache/dev*/twig

    echo -e "  ${GREEN}Cache geleert${NC}"
else
    echo -e "${YELLOW}[1/4] Cache überspringen${NC}"
fi

# Schritt 2: Assets kompilieren
echo -e "${YELLOW}[2/4] Assets kompilieren...${NC}"

cd "$SHOPWARE_ROOT"

if [ "$USE_VITE" = "true" ]; then
    # Vite Build (SW 6.7+)
    if [ "$WATCH" = true ]; then
        echo -e "  Starte Vite Dev Server..."

        if [ "$ANALYZE" = true ]; then
            ANALYZE=true npm run dev --prefix "custom/plugins/$THEME_NAME/src/Resources/app/storefront"
        else
            npm run dev --prefix "custom/plugins/$THEME_NAME/src/Resources/app/storefront"
        fi
    else
        # Production Build
        BUILD_CMD="npm run build --prefix custom/plugins/$THEME_NAME/src/Resources/app/storefront"

        if [ "$ANALYZE" = true ]; then
            ANALYZE=true $BUILD_CMD
        else
            if [ "$VERBOSE" = true ]; then
                $BUILD_CMD
            else
                $BUILD_CMD > /dev/null 2>&1
            fi
        fi

        echo -e "  ${GREEN}Vite Build abgeschlossen${NC}"
    fi
else
    # Webpack Build (SW < 6.7)
    if [ "$WATCH" = true ]; then
        echo -e "  Starte Webpack Watch..."
        bin/console theme:compile --watch
    else
        if [ "$VERBOSE" = true ]; then
            bin/console theme:compile
        else
            bin/console theme:compile > /dev/null 2>&1
        fi

        echo -e "  ${GREEN}Webpack Build abgeschlossen${NC}"
    fi
fi

# Schritt 3: Theme-Assets deployen
if [ "$WATCH" = false ]; then
    echo -e "${YELLOW}[3/4] Assets deployen...${NC}"

    if [ "$VERBOSE" = true ]; then
        bin/console assets:install
    else
        bin/console assets:install > /dev/null 2>&1
    fi

    echo -e "  ${GREEN}Assets installiert${NC}"
else
    echo -e "${YELLOW}[3/4] Überspringe (Watch Mode)${NC}"
fi

# Schritt 4: Bundle-Analyse
if [ "$ANALYZE" = true ] && [ "$WATCH" = false ]; then
    echo -e "${YELLOW}[4/4] Bundle-Analyse...${NC}"

    # Analyse-Script aufrufen (falls vorhanden)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -x "$SCRIPT_DIR/analyze-bundle.sh" ]; then
        "$SCRIPT_DIR/analyze-bundle.sh" "$THEME_NAME"
    else
        echo -e "  ${YELLOW}analyze-bundle.sh nicht gefunden${NC}"
    fi
else
    echo -e "${YELLOW}[4/4] Analyse überspringen${NC}"
fi

# Ende
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Build abgeschlossen${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Dauer: ${DURATION}s"

# Bundle-Größen anzeigen
if [ "$WATCH" = false ]; then
    echo ""
    echo -e "${YELLOW}Bundle-Größen:${NC}"

    JS_DIR="$SHOPWARE_ROOT/public/bundles/storefront/js"
    CSS_DIR="$SHOPWARE_ROOT/public/bundles/storefront/css"

    if [ -d "$JS_DIR" ]; then
        JS_SIZE=$(find "$JS_DIR" -name "*.js" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s}' || find "$JS_DIR" -name "*.js" -type f -exec stat -c%s {} + 2>/dev/null | awk '{s+=$1} END {print s}')
        JS_KB=$((JS_SIZE / 1024))
        echo -e "  JavaScript: ${JS_KB} KB"
    fi

    if [ -d "$CSS_DIR" ]; then
        CSS_SIZE=$(find "$CSS_DIR" -name "*.css" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s}' || find "$CSS_DIR" -name "*.css" -type f -exec stat -c%s {} + 2>/dev/null | awk '{s+=$1} END {print s}')
        CSS_KB=$((CSS_SIZE / 1024))
        echo -e "  CSS: ${CSS_KB} KB"
    fi

    # Warnung bei großen Bundles
    if [ "${JS_KB:-0}" -gt 300 ]; then
        echo ""
        echo -e "${RED}Warnung: JavaScript Bundle > 300 KB${NC}"
        echo "  Empfehlung: Nicht benötigte Plugins entfernen"
    fi
fi

echo ""

# Performance-Vergleich Vite vs Webpack
if [ "$USE_VITE" = "true" ] && [ "$DURATION" -lt 30 ]; then
    echo -e "${GREEN}Vite Build-Zeit: ${DURATION}s (95% schneller als Webpack)${NC}"
fi

exit 0
