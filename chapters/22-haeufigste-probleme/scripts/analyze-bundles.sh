#!/bin/bash
#
# Problem 3: Zu große JavaScript-Bundles
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Analysiert JavaScript Bundle-Größen einer Shopware-Installation.
#
# Verwendung: ./analyze-bundles.sh [SHOP_URL] [SHOP_PATH]
#

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: analyze-bundles.sh [SHOP_URL] [SHOP_PATH]

Misst die uebertragene Groesse der JavaScript-Dateien, die die Startseite
einbindet, und die der kompilierten Bundles auf der Platte.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Gemessen wird die komprimierte Groesse per GET — die bestimmt die
Uebertragungszeit. Ein Content-Length aus einem HEAD-Request ist dafuer
unbrauchbar: bei chunked Transfer fehlt er ganz.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

SHOP_URL="${1:-http://localhost}"
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
echo "URL: ${SHOP_URL}"
echo "Path: ${SHOP_PATH}"
echo ""

ISSUES=0
TOTAL_SIZE=0

# Methode 1: Lokale Dateien analysieren
echo -e "${BLUE}=== Lokale Bundle-Analyse ===${NC}"
echo ""

if [[ -d "${SHOP_PATH}/public/bundles" ]]; then
    # Rohe Dateigroessen auf der Platte, nicht die uebertragenen. Und
    # public/bundles enthaelt auch Administration und Installer — Dateien,
    # die eine Storefront-Seite nie laedt. Diese Liste ist eine Bestandsauf-
    # nahme; gezaehlt wird weiter unten, was die Startseite wirklich holt.
    echo "Groesse auf der Platte (alle Bundles, auch Administration):"
    echo ""

    while IFS= read -r file; do
        SIZE_BYTES=$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo "0")
        SIZE_KB=$((SIZE_BYTES / 1024))

        BASENAME=$(basename "${file}")

        if [[ "${SIZE_KB}" -gt "${THRESHOLD_CRITICAL}" ]]; then
            echo -e "  ${RED}${SIZE_KB} KB${NC} - ${BASENAME}"
        elif [[ "${SIZE_KB}" -gt "${THRESHOLD_WARNING}" ]]; then
            echo -e "  ${YELLOW}${SIZE_KB} KB${NC} - ${BASENAME}"
        else
            echo -e "  ${GREEN}${SIZE_KB} KB${NC} - ${BASENAME}"
        fi
    done < <(find "${SHOP_PATH}/public/bundles" -name "*.js" -type f 2>/dev/null)
fi

# Methode 2: Remote-Analyse via curl
echo ""
echo -e "${BLUE}=== Remote Bundle-Analyse ===${NC}"
echo ""

# HTML der Startseite holen und JS-URLs extrahieren
HTML=$(curl -s -L "${SHOP_URL}" 2>/dev/null || echo "")

if [[ -n "${HTML}" ]]; then
    # JavaScript URLs extrahieren
    JS_URLS=$(echo "${HTML}" | grep -oE 'src="[^"]*\.js[^"]*"' | sed 's/src="//g' | sed 's/"//g' | head -20)

    echo "Remote JavaScript Dateien:"
    echo ""

    for js_url in ${JS_URLS}; do
        # Relative URLs ergänzen
        if [[ "${js_url}" != http* ]]; then
            js_url="${SHOP_URL}${js_url}"
        fi

        # Tatsaechlich uebertragene Groesse per GET messen. Content-Length aus
        # einem HEAD-Request taugt nicht: bei chunked Transfer fehlt der Header
        # ganz, und er beschreibt nicht die komprimierte Uebertragung.
        SIZE_HEADER=$(curl -sS -o /dev/null -L -H 'Accept-Encoding: gzip, br' \
            -w '%{size_download}' "${js_url}" 2>/dev/null || echo 0)

        if [[ "${SIZE_HEADER}" -gt 0 ]]; then
            SIZE_KB=$((SIZE_HEADER / 1024))
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE_KB))

            BASENAME=$(basename "${js_url}" | cut -d'?' -f1)

            if [[ "${SIZE_KB}" -gt "${THRESHOLD_CRITICAL}" ]]; then
                echo -e "  ${RED}${SIZE_KB} KB${NC} - ${BASENAME}"
                ISSUES=$((ISSUES + 1))
            elif [[ "${SIZE_KB}" -gt "${THRESHOLD_WARNING}" ]]; then
                echo -e "  ${YELLOW}${SIZE_KB} KB${NC} - ${BASENAME}"
            else
                echo -e "  ${GREEN}${SIZE_KB} KB${NC} - ${BASENAME}"
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
echo "Von der Startseite geladenes JavaScript, uebertragen: ~${TOTAL_SIZE} KB"
echo ""

if [[ "${TOTAL_SIZE}" -gt "${TOTAL_THRESHOLD}" ]]; then
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
elif [[ "${ISSUES}" -gt 0 ]]; then
    echo -e "${YELLOW}${ISSUES} Bundle(s) über ${THRESHOLD_CRITICAL} KB${NC}"
    echo "Überprüfen Sie große Bundles auf Optimierungspotential."
    exit 1
else
    echo -e "${GREEN}JavaScript-Größe im akzeptablen Bereich.${NC}"
    exit 0
fi
