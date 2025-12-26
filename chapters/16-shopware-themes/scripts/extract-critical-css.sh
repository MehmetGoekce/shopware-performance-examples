#!/bin/bash
#
# Critical CSS Extractor für Shopware 6 Themes
#
# Extrahiert Above-the-Fold CSS aus einer URL für inline Loading.
#
# Verwendung:
#   ./extract-critical-css.sh https://shop.example.com
#   ./extract-critical-css.sh https://shop.example.com --viewport 1920x1080
#
# Voraussetzungen:
#   - Node.js (>= 18)
#   - critical (npm install -g critical)
#   - puppeteer (wird automatisch installiert)
#

set -euo pipefail

# Konfiguration
URL="${1:-}"
OUTPUT_DIR="./dist/critical"
VIEWPORT_WIDTH="${VIEWPORT_WIDTH:-1300}"
VIEWPORT_HEIGHT="${VIEWPORT_HEIGHT:-900}"
TIMEOUT="${TIMEOUT:-30000}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Hilfe anzeigen
show_help() {
    echo "Usage: $0 <url> [options]"
    echo ""
    echo "Options:"
    echo "  --viewport WxH    Viewport size (default: 1300x900)"
    echo "  --output DIR      Output directory (default: ./dist/critical)"
    echo "  --timeout MS      Timeout in milliseconds (default: 30000)"
    echo "  --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 https://shop.example.com"
    echo "  $0 https://shop.example.com --viewport 1920x1080"
    echo ""
}

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --viewport)
            IFS='x' read -r VIEWPORT_WIDTH VIEWPORT_HEIGHT <<< "$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            if [ -z "$URL" ]; then
                URL="$1"
            fi
            shift
            ;;
    esac
done

# URL prüfen
if [ -z "$URL" ]; then
    echo -e "${RED}Fehler: URL ist erforderlich${NC}"
    echo ""
    show_help
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Critical CSS Extractor${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "URL:       $URL"
echo -e "Viewport:  ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}"
echo -e "Timeout:   ${TIMEOUT}ms"
echo -e "Output:    $OUTPUT_DIR"
echo ""

# Verzeichnis erstellen
mkdir -p "$OUTPUT_DIR"

# Prüfen ob critical installiert ist
if ! command -v critical &> /dev/null && ! npx critical --version &> /dev/null; then
    echo -e "${YELLOW}Installing critical package...${NC}"
    npm install -g critical
fi

# Temporäre HTML-Datei für critical
TEMP_HTML=$(mktemp)
TEMP_CSS=$(mktemp)

# HTML herunterladen
echo -e "${YELLOW}Lade HTML von $URL...${NC}"
curl -sL "$URL" > "$TEMP_HTML"

# Critical CSS extrahieren
echo -e "${YELLOW}Extrahiere Critical CSS...${NC}"

# Node.js Script für critical
cat > "$TEMP_CSS.mjs" << 'NODESCRIPT'
import { generate } from 'critical';
import { readFileSync, writeFileSync } from 'fs';
import { resolve } from 'path';

const args = process.argv.slice(2);
const url = args[0];
const outputDir = args[1];
const width = parseInt(args[2], 10);
const height = parseInt(args[3], 10);
const timeout = parseInt(args[4], 10);

async function extractCritical() {
  try {
    const { css, html } = await generate({
      src: url,
      width: width,
      height: height,
      timeout: timeout,
      inline: false,
      extract: true,
      penthouse: {
        timeout: timeout,
        renderWaitTime: 500,
        blockJSRequests: true,
      },
    });

    // Critical CSS speichern
    writeFileSync(resolve(outputDir, 'critical.css'), css);

    // Statistiken ausgeben
    const originalSize = css.length;
    console.log(JSON.stringify({
      success: true,
      size: originalSize,
      sizeKB: (originalSize / 1024).toFixed(2),
    }));

  } catch (error) {
    console.log(JSON.stringify({
      success: false,
      error: error.message,
    }));
    process.exit(1);
  }
}

extractCritical();
NODESCRIPT

# Critical ausführen
RESULT=$(node "$TEMP_CSS.mjs" "$URL" "$OUTPUT_DIR" "$VIEWPORT_WIDTH" "$VIEWPORT_HEIGHT" "$TIMEOUT" 2>/dev/null || echo '{"success":false,"error":"Critical extraction failed"}')

# Aufräumen
rm -f "$TEMP_HTML" "$TEMP_CSS" "$TEMP_CSS.mjs"

# Ergebnis prüfen
SUCCESS=$(echo "$RESULT" | grep -o '"success":\s*true' || true)

if [ -n "$SUCCESS" ]; then
    SIZE_KB=$(echo "$RESULT" | grep -o '"sizeKB":"[^"]*"' | cut -d'"' -f4)

    echo -e "${GREEN}Critical CSS erfolgreich extrahiert!${NC}"
    echo ""
    echo -e "Größe: ${SIZE_KB} KB"
    echo -e "Datei: $OUTPUT_DIR/critical.css"
    echo ""

    # Twig-Template erstellen
    TWIG_FILE="$OUTPUT_DIR/critical.css.twig"
    cat > "$TWIG_FILE" << 'TWIG'
{#
    Auto-generated Critical CSS

    Einbindung in base.html.twig:

    {% block base_head_stylesheets %}
        <style>{% sw_include '@YourTheme/storefront/critical/critical.css.twig' %}</style>
        {{ parent() }}
    {% endblock %}
#}
TWIG

    cat "$OUTPUT_DIR/critical.css" >> "$TWIG_FILE"
    echo -e "Twig:  $TWIG_FILE"

    # Minified Version
    if command -v cssnano &> /dev/null || npx cssnano --version &> /dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}Minifying...${NC}"
        npx cssnano "$OUTPUT_DIR/critical.css" "$OUTPUT_DIR/critical.min.css" 2>/dev/null || true

        if [ -f "$OUTPUT_DIR/critical.min.css" ]; then
            MIN_SIZE=$(stat -f%z "$OUTPUT_DIR/critical.min.css" 2>/dev/null || stat -c%s "$OUTPUT_DIR/critical.min.css" 2>/dev/null)
            echo -e "Minified: $(echo "scale=2; $MIN_SIZE / 1024" | bc) KB"
        fi
    fi

    echo ""
    echo -e "${BLUE}Empfehlungen:${NC}"
    echo "  1. Critical CSS sollte < 14 KB sein (für erstes TCP-Paket)"
    echo "  2. Inline in <head> mit <style> Tag"
    echo "  3. Rest-CSS async mit preload laden"
    echo "  4. Bei jeder Theme-Änderung neu generieren"
    echo ""

else
    ERROR=$(echo "$RESULT" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
    echo -e "${RED}Fehler bei Critical CSS Extraktion:${NC}"
    echo -e "$ERROR"
    echo ""
    echo -e "${YELLOW}Mögliche Lösungen:${NC}"
    echo "  1. URL erreichbar? (curl -I $URL)"
    echo "  2. puppeteer installiert? (npm install puppeteer)"
    echo "  3. Timeout erhöhen (--timeout 60000)"
    echo ""
    exit 1
fi

# Empfohlene Limits prüfen
CRITICAL_SIZE=$(stat -f%z "$OUTPUT_DIR/critical.css" 2>/dev/null || stat -c%s "$OUTPUT_DIR/critical.css" 2>/dev/null)
CRITICAL_KB=$((CRITICAL_SIZE / 1024))

if [ "$CRITICAL_KB" -gt 14 ]; then
    echo -e "${YELLOW}Warnung: Critical CSS ist größer als 14 KB (${CRITICAL_KB} KB)${NC}"
    echo "  - Erwäge manuelle Optimierung"
    echo "  - Entferne Styles für Elemente unter dem Fold"
    echo ""
fi

exit 0
