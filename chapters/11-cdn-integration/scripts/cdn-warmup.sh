#!/bin/bash
#
# CDN Cache Warming Script
# Wärmt den CDN-Cache nach Deployment vor
#
# Verwendung:
#   ./cdn-warmup.sh https://shop.de
#   ./cdn-warmup.sh https://shop.de --critical-only
#   ./cdn-warmup.sh https://shop.de --sitemap
#
# Voraussetzungen:
#   - curl installiert
#   - xmllint (optional, für Sitemap-Parsing)

set -e

SHOP_URL="${1:-}"
MODE="${2:---all}"
CONCURRENCY=5
USER_AGENT="CDN-Warmup/1.0"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Verwendung: $0 <shop-url> [--critical-only|--sitemap|--all]"
    echo ""
    echo "Optionen:"
    echo "  --critical-only  Nur kritische URLs (Homepage, Top-Kategorien)"
    echo "  --sitemap        URLs aus Sitemap extrahieren"
    echo "  --all            Kritische URLs + Sitemap (default)"
    exit 1
}

if [[ -z "${SHOP_URL}" ]]; then
    usage
fi

# URL normalisieren
SHOP_URL="${SHOP_URL%/}"

echo "=== CDN Cache Warming ==="
echo ""
echo "Shop:        ${SHOP_URL}"
echo "Modus:       ${MODE}"
echo "Parallelität: ${CONCURRENCY}"
echo ""

# ============================================================================
# Kritische URLs
# ============================================================================

warm_critical() {
    echo "=== Wärme kritische URLs ==="

    CRITICAL_URLS=(
        "/"
        "/navigation/hauptkategorie"
        "/search"
        # CSS/JS werden durch HTML-Requests automatisch gewärmt
    )

    for url in "${CRITICAL_URLS[@]}"; do
        full_url="${SHOP_URL}${url}"
        echo -n "  ${url} ... "

        status=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "User-Agent: ${USER_AGENT}" \
            "${full_url}")

        if [[ "${status}" == "200" ]]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}${status}${NC}"
        fi
    done
}

# ============================================================================
# Sitemap-basiertes Warming
# ============================================================================

warm_sitemap() {
    echo ""
    echo "=== Wärme URLs aus Sitemap ==="

    SITEMAP_URL="${SHOP_URL}/sitemap.xml"

    echo "Lade Sitemap: ${SITEMAP_URL}"

    # Prüfen ob xmllint verfügbar
    if ! command -v xmllint &> /dev/null; then
        echo -e "${YELLOW}WARNUNG: xmllint nicht installiert, überspringe Sitemap${NC}"
        echo "         sudo apt install libxml2-utils"
        return
    fi

    # Sitemap herunterladen und URLs extrahieren
    URLS=$(curl -s "${SITEMAP_URL}" | \
        xmllint --xpath "//*[local-name()='loc']/text()" - 2>/dev/null || echo "")

    if [[ -z "${URLS}" ]]; then
        echo -e "${YELLOW}Keine URLs in Sitemap gefunden${NC}"
        return
    fi

    URL_COUNT=$(echo "${URLS}" | wc -l)
    echo "Gefundene URLs: ${URL_COUNT}"
    echo ""

    # Parallel ausführen
    echo "${URLS}" | xargs -P ${CONCURRENCY} -I {} sh -c "
        status=\$(curl -s -o /dev/null -w '%{http_code}' -H 'User-Agent: ${USER_AGENT}' '{}')
        if [[ \"\${status}\" == \"200\" ]]; then
            echo \"  {} ... OK\"
        else
            echo \"  {} ... \${status}\"
        fi
    "
}

# ============================================================================
# Asset Warming (CSS, JS, Fonts)
# ============================================================================

warm_assets() {
    echo ""
    echo "=== Wärme statische Assets ==="

    # Homepage laden und Asset-URLs extrahieren
    ASSETS=$(curl -s "${SHOP_URL}" | \
        grep -oE '(href|src)="[^"]+\.(css|js|woff2?)"' | \
        sed -E 's/(href|src)="([^"]+)"/\2/' | \
        sort -u)

    if [[ -z "${ASSETS}" ]]; then
        echo "Keine Assets gefunden"
        return
    fi

    ASSET_COUNT=$(echo "${ASSETS}" | wc -l)
    echo "Gefundene Assets: ${ASSET_COUNT}"

    echo "${ASSETS}" | while read -r asset; do
        # Relative URLs zu absoluten machen
        if [[ "${asset}" == /* ]]; then
            asset="${SHOP_URL}${asset}"
        elif [[ "${asset}" != http* ]]; then
            asset="${SHOP_URL}/${asset}"
        fi

        echo -n "  $(basename "${asset}") ... "
        status=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "User-Agent: ${USER_AGENT}" \
            "${asset}")

        if [[ "${status}" == "200" ]]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}${status}${NC}"
        fi
    done
}

# ============================================================================
# Cache-Header prüfen
# ============================================================================

check_cache_headers() {
    echo ""
    echo "=== Cache-Header Prüfung ==="

    TEST_URL="${SHOP_URL}/bundles/storefront/assets/icon/default/info.svg"

    echo "Test-URL: ${TEST_URL}"
    echo ""

    headers=$(curl -sI "${TEST_URL}")

    # Cache-Control
    cache_control=$(echo "${headers}" | grep -i "cache-control" | head -1)
    if [[ -n "${cache_control}" ]]; then
        echo -e "${GREEN}Cache-Control:${NC} ${cache_control}"
    else
        echo -e "${RED}Cache-Control: FEHLT${NC}"
    fi

    # CDN-Status (Cloudflare)
    cf_status=$(echo "${headers}" | grep -i "cf-cache-status" | head -1)
    if [[ -n "${cf_status}" ]]; then
        echo -e "${GREEN}CF-Cache-Status:${NC} ${cf_status}"
    fi

    # CDN-Status (Bunny)
    bunny_status=$(echo "${headers}" | grep -i "cdn-cache" | head -1)
    if [[ -n "${bunny_status}" ]]; then
        echo -e "${GREEN}CDN-Cache:${NC} ${bunny_status}"
    fi
}

# ============================================================================
# Hauptlogik
# ============================================================================

START_TIME=$(date +%s)

case ${MODE} in
    --critical-only)
        warm_critical
        warm_assets
        ;;
    --sitemap)
        warm_sitemap
        ;;
    --all|*)
        warm_critical
        warm_assets
        warm_sitemap
        ;;
esac

check_cache_headers

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=== Zusammenfassung ==="
echo "Dauer: ${DURATION}s"
echo ""
echo "Nächste Schritte:"
echo "  1. CDN-Dashboard auf Hit-Rate prüfen"
echo "  2. curl -I ${SHOP_URL} | grep -i cache"
