#!/bin/bash
# Cache Warmup Script
# Kapitel 6: HTTP-Caching
#
# Wärmt den HTTP-Cache (eingebaut oder Varnish) auf, indem URLs als Gast
# ohne Cookies abgerufen werden.
#
# Wichtig:
#   - Shopware 6.6 hat keinen eigenen HTTP-Cache-Warmer mehr. "bin/console
#     cache:warmup" wärmt nur den Symfony-Container-Cache, nicht die Seiten.
#   - Gewärmt wird nur die Gast-Variante in der Standardwährung. Andere
#     Währungen (Cookie sw-currency) bekommen eigene Cache-Einträge.
#   - Nach "bin/console cache:clear" oder "cache:clear:http" ist der
#     HTTP-Cache leer - Warmup danach laufen lassen.
#
# Verwendung:
#   ./cache-warmup.sh https://ihr-shop.ch
#   ./cache-warmup.sh https://ihr-shop.ch --sitemap
#   ./cache-warmup.sh https://ihr-shop.ch --sitemap --parallel 4 --limit 500
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

PARALLEL=2
USE_SITEMAP=false
LIMIT=100

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_usage() {
    echo "Usage: $0 <base-url> [optionen]"
    echo ""
    echo "Optionen:"
    echo "  --sitemap       URLs aus der Shopware-Sitemap laden (sitemap.xml und .xml.gz-Teile)"
    echo "  --parallel N    Anzahl paralleler Requests (Standard: 2)"
    echo "  --limit N       Maximale Anzahl URLs aus der Sitemap (Standard: 100)"
    echo ""
    echo "Beispiele:"
    echo "  $0 https://ihr-shop.ch"
    echo "  $0 https://ihr-shop.ch --sitemap --parallel 4 --limit 500"
}

warmup_url() {
    local url=$1
    local result status ttfb
    result=$(curl -s -o /dev/null -w "%{http_code} %{time_starttransfer}" \
        -H "Accept-Encoding: gzip" \
        -H "User-Agent: CacheWarmup/1.0" \
        "${url}" 2>/dev/null || echo "000 0")
    status=${result%% *}
    ttfb=$(awk -v t="${result##* }" 'BEGIN { printf "%.0f", t * 1000 }')

    if [[ "${status}" == "200" ]]; then
        echo -e "${GREEN}OK${NC}  ${url} (${ttfb} ms)"
    else
        echo -e "${YELLOW}${status}${NC} ${url}"
    fi
}

# <loc>-Einträge aus XML auf stdin
extract_locs() {
    grep -o '<loc>[^<]*</loc>' | sed -e 's:<loc>::' -e 's:</loc>::' || true
}

sitemap_urls() {
    local base_url=$1
    local loc

    # Shopware liefert unter /sitemap.xml einen Index mit .xml.gz-Teildateien,
    # und zwar für alle Domains des Sales Channels. Nur die angefragte Domain wärmen.
    curl -s "${base_url}/sitemap.xml" | extract_locs | while read -r loc; do
        if [[ "${loc}" != "${base_url}/"* ]]; then
            continue
        elif [[ "${loc}" == *.xml.gz ]]; then
            curl -s "${loc}" | gunzip -c 2>/dev/null | extract_locs
        elif [[ "${loc}" == *.xml ]]; then
            curl -s "${loc}" | extract_locs
        else
            echo "${loc}"
        fi
    done | grep "^${base_url}/" || true
}

if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

case $1 in
    -h|--help)
        show_usage
        exit 0
        ;;
esac

BASE_URL="${1%/}"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --sitemap)
            USE_SITEMAP=true
            shift
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_usage
            exit 1
            ;;
    esac
done

export -f warmup_url
export GREEN YELLOW NC

echo -e "${BLUE}Cache Warmup${NC}"
echo "Base URL: ${BASE_URL}"
echo "Parallel: ${PARALLEL}"
echo ""

if [[ "${USE_SITEMAP}" = true ]]; then
    urls=$(sitemap_urls "${BASE_URL}" | head -n "${LIMIT}")
    if [[ -z "${urls}" ]]; then
        echo -e "${YELLOW}Keine URLs in der Sitemap gefunden (bin/console sitemap:generate gelaufen?)${NC}"
        urls="${BASE_URL}/"
    fi
else
    urls="${BASE_URL}/"
fi

echo "URLs: $(echo "${urls}" | wc -l)"
echo ""
echo "${urls}" | xargs -P "${PARALLEL}" -I {} bash -c 'warmup_url "$@"' _ {}

echo ""
echo "Nächster Schritt: ./cache-debug.sh ${BASE_URL}"
