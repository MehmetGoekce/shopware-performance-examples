#!/bin/bash
#
# Bundle Analyzer für Shopware 6 Themes
#
# Analysiert JavaScript- und CSS-Bundles auf Größe und Zusammensetzung.
#
# Verwendung:
#   ./analyze-bundle.sh [theme-name]
#
# Voraussetzungen:
#   - Node.js mit source-map-explorer oder webpack-bundle-analyzer
#   - Shopware 6 Installation
#

set -euo pipefail

# Konfiguration
THEME_NAME="${1:-PerformanceTheme}"
SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
PUBLIC_DIR="$SHOPWARE_ROOT/public"
BUNDLE_DIR="$PUBLIC_DIR/bundles"
OUTPUT_DIR="./reports"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Schwellenwerte (in KB)
THRESHOLD_JS=300
THRESHOLD_CSS=150
THRESHOLD_TOTAL=500

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Shopware Theme Bundle Analyzer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Verzeichnis erstellen
mkdir -p "$OUTPUT_DIR"

# Funktion: Dateigröße formatieren
format_size() {
    local size=$1
    if [ "$size" -lt 1024 ]; then
        echo "${size} B"
    elif [ "$size" -lt 1048576 ]; then
        echo "$(echo "scale=1; $size / 1024" | bc) KB"
    else
        echo "$(echo "scale=2; $size / 1048576" | bc) MB"
    fi
}

# Funktion: Gzip-Größe berechnen
gzip_size() {
    local file=$1
    if command -v gzip &> /dev/null; then
        gzip -c "$file" | wc -c
    else
        echo "0"
    fi
}

# Funktion: Brotli-Größe berechnen
brotli_size() {
    local file=$1
    if command -v brotli &> /dev/null; then
        brotli -c "$file" | wc -c
    else
        echo "0"
    fi
}

# JavaScript-Bundles analysieren
echo -e "${YELLOW}Analysiere JavaScript-Bundles...${NC}"
echo ""

JS_DIR="$BUNDLE_DIR/storefront/js"
TOTAL_JS=0
JS_FILES=()

if [ -d "$JS_DIR" ]; then
    while IFS= read -r -d '' file; do
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        TOTAL_JS=$((TOTAL_JS + size))
        JS_FILES+=("$size:$file")
    done < <(find "$JS_DIR" -name "*.js" -type f -print0)

    # Nach Größe sortieren
    IFS=$'\n' sorted=($(sort -t: -k1 -rn <<<"${JS_FILES[*]}")); unset IFS

    echo "JavaScript-Dateien (nach Größe):"
    echo "--------------------------------"
    for entry in "${sorted[@]}"; do
        size="${entry%%:*}"
        file="${entry#*:}"
        filename=$(basename "$file")
        gzip=$(gzip_size "$file")
        echo -e "  $(format_size $size) (gzip: $(format_size $gzip)) - $filename"
    done
    echo ""
else
    echo -e "${RED}JavaScript-Verzeichnis nicht gefunden: $JS_DIR${NC}"
fi

# CSS-Bundles analysieren
echo -e "${YELLOW}Analysiere CSS-Bundles...${NC}"
echo ""

CSS_DIR="$BUNDLE_DIR/storefront/css"
TOTAL_CSS=0
CSS_FILES=()

if [ -d "$CSS_DIR" ]; then
    while IFS= read -r -d '' file; do
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        TOTAL_CSS=$((TOTAL_CSS + size))
        CSS_FILES+=("$size:$file")
    done < <(find "$CSS_DIR" -name "*.css" -type f -print0)

    # Nach Größe sortieren
    IFS=$'\n' sorted=($(sort -t: -k1 -rn <<<"${CSS_FILES[*]}")); unset IFS

    echo "CSS-Dateien (nach Größe):"
    echo "------------------------"
    for entry in "${sorted[@]}"; do
        size="${entry%%:*}"
        file="${entry#*:}"
        filename=$(basename "$file")
        gzip=$(gzip_size "$file")
        echo -e "  $(format_size $size) (gzip: $(format_size $gzip)) - $filename"
    done
    echo ""
else
    echo -e "${RED}CSS-Verzeichnis nicht gefunden: $CSS_DIR${NC}"
fi

# Zusammenfassung
TOTAL=$((TOTAL_JS + TOTAL_CSS))
TOTAL_KB=$((TOTAL / 1024))
JS_KB=$((TOTAL_JS / 1024))
CSS_KB=$((TOTAL_CSS / 1024))

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Zusammenfassung${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "JavaScript:  $(format_size $TOTAL_JS)"
echo -e "CSS:         $(format_size $TOTAL_CSS)"
echo -e "Gesamt:      $(format_size $TOTAL)"
echo ""

# Bewertung
echo -e "${YELLOW}Bewertung:${NC}"
echo ""

if [ "$JS_KB" -gt "$THRESHOLD_JS" ]; then
    echo -e "  ${RED}[WARNUNG]${NC} JavaScript überschreitet Limit (${JS_KB}KB > ${THRESHOLD_JS}KB)"
else
    echo -e "  ${GREEN}[OK]${NC} JavaScript unter Limit (${JS_KB}KB <= ${THRESHOLD_JS}KB)"
fi

if [ "$CSS_KB" -gt "$THRESHOLD_CSS" ]; then
    echo -e "  ${RED}[WARNUNG]${NC} CSS überschreitet Limit (${CSS_KB}KB > ${THRESHOLD_CSS}KB)"
else
    echo -e "  ${GREEN}[OK]${NC} CSS unter Limit (${CSS_KB}KB <= ${THRESHOLD_CSS}KB)"
fi

if [ "$TOTAL_KB" -gt "$THRESHOLD_TOTAL" ]; then
    echo -e "  ${RED}[WARNUNG]${NC} Gesamt überschreitet Limit (${TOTAL_KB}KB > ${THRESHOLD_TOTAL}KB)"
else
    echo -e "  ${GREEN}[OK]${NC} Gesamt unter Limit (${TOTAL_KB}KB <= ${THRESHOLD_TOTAL}KB)"
fi

echo ""

# Bekannte Libraries erkennen
echo -e "${YELLOW}Erkannte Libraries:${NC}"
echo ""

LIBRARIES=(
    "jquery:jQuery:229"
    "bootstrap:Bootstrap:129"
    "flatpickr:Flatpickr:115"
    "tiny-slider:TinySlider:100"
    "hammer:Hammer.js:72"
    "luxon:Luxon:65"
    "lodash:Lodash:70"
    "moment:Moment.js:230"
)

for lib_info in "${LIBRARIES[@]}"; do
    IFS=':' read -r pattern name size <<< "$lib_info"

    if [ -d "$JS_DIR" ]; then
        if grep -rq "$pattern" "$JS_DIR" 2>/dev/null; then
            echo -e "  ${YELLOW}[GEFUNDEN]${NC} $name (~${size}KB)"
        fi
    fi
done

echo ""

# JSON-Report erstellen
REPORT_FILE="$OUTPUT_DIR/bundle-report-$(date +%Y%m%d-%H%M%S).json"

cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "theme": "$THEME_NAME",
  "summary": {
    "javascript": {
      "totalBytes": $TOTAL_JS,
      "totalKB": $JS_KB,
      "threshold": $THRESHOLD_JS,
      "passed": $([ "$JS_KB" -le "$THRESHOLD_JS" ] && echo "true" || echo "false")
    },
    "css": {
      "totalBytes": $TOTAL_CSS,
      "totalKB": $CSS_KB,
      "threshold": $THRESHOLD_CSS,
      "passed": $([ "$CSS_KB" -le "$THRESHOLD_CSS" ] && echo "true" || echo "false")
    },
    "total": {
      "totalBytes": $TOTAL,
      "totalKB": $TOTAL_KB,
      "threshold": $THRESHOLD_TOTAL,
      "passed": $([ "$TOTAL_KB" -le "$THRESHOLD_TOTAL" ] && echo "true" || echo "false")
    }
  }
}
EOF

echo -e "${GREEN}Report gespeichert: $REPORT_FILE${NC}"
echo ""

# Empfehlungen
if [ "$TOTAL_KB" -gt "$THRESHOLD_TOTAL" ]; then
    echo -e "${YELLOW}Empfehlungen zur Optimierung:${NC}"
    echo ""
    echo "  1. Nicht benötigte Plugins mit PluginManager.deregister() entfernen"
    echo "  2. @StorefrontBootstrap statt @Storefront verwenden"
    echo "  3. Selektive Bootstrap-Imports nutzen"
    echo "  4. Async Loading für selten genutzte Plugins"
    echo "  5. Vite statt Webpack für besseres Tree-Shaking (SW 6.7+)"
    echo ""
fi

# Exit-Code basierend auf Ergebnis
if [ "$TOTAL_KB" -gt "$THRESHOLD_TOTAL" ]; then
    exit 1
else
    exit 0
fi
