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
#   - Nach "bin/console cache:clear:http" ist der HTTP-Cache leer, nach
#     "cache:clear" mit Filesystem-Cache oder Varnish auch (mit Redis nicht,
#     siehe Kapitel 7) - Warmup danach laufen lassen.
#   - Bei --parallel > 1 ruft das Skript alle URLs zweimal ab. Nach
#     "cache:clear" sind die Tag-Versionen des Filesystem-Caches leer, und
#     parallele erste Requests legen für dieselben Tags verschiedene Versionen
#     an. Die Seiten mit der überschriebenen Version gelten beim nächsten
#     Aufruf als ungültig (Test 6.6.10.6, 21 Seiten: mit --parallel 2 1-6,
#     mit --parallel 4 6-10 kalt, mit dem zweiten Durchgang 0). Der zweite
#     Durchgang rendert nur die kalt gebliebenen Seiten neu.
#
# Verwendung:
#   ./cache-warmup.sh https://ihr-shop.ch
#   ./cache-warmup.sh https://ihr-shop.ch --sitemap
#   ./cache-warmup.sh https://ihr-shop.ch --sitemap --parallel 4 --limit 500
#
# Umgebungsvariablen:
#   CURL_CMD  curl-Befehl (Default: curl, für Tests austauschbar)
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

CURL_CMD="${CURL_CMD:-curl}"
# Steuert nur den zweiten Durchgang, nie aus der Umgebung übernehmen
unset QUIET

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
    echo "  --parallel N    Anzahl paralleler Requests (Standard: 2); ab 2 folgt ein"
    echo "                  zweiter Durchgang, der nur Fehler ausgibt"
    echo "  --limit N       Maximale Anzahl URLs aus der Sitemap (Standard: 100)"
    echo ""
    echo "Beispiele:"
    echo "  $0 https://ihr-shop.ch"
    echo "  $0 https://ihr-shop.ch --sitemap --parallel 4 --limit 500"
}

warmup_url() {
    local url=$1
    local result status ttfb
    result=$(${CURL_CMD} -s -o /dev/null -w "%{http_code} %{time_starttransfer}" \
        -H "Accept-Encoding: gzip" \
        -H "User-Agent: CacheWarmup/1.0" \
        "${url}" 2>/dev/null || echo "000 0")
    status=${result%% *}
    ttfb=$(awk -v t="${result##* }" 'BEGIN { printf "%.0f", t * 1000 }')

    if [[ "${status}" == "200" ]]; then
        # Im zweiten Durchgang nur Fehler ausgeben
        [[ -n "${QUIET:-}" ]] || echo -e "${GREEN}OK${NC}  ${url} (${ttfb} ms)"
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
    ${CURL_CMD} -s "${base_url}/sitemap.xml" | extract_locs | while read -r loc; do
        if [[ "${loc}" != "${base_url}/"* ]]; then
            continue
        elif [[ "${loc}" == *.xml.gz ]]; then
            ${CURL_CMD} -s "${loc}" | gunzip -c 2>/dev/null | extract_locs
        elif [[ "${loc}" == *.xml ]]; then
            ${CURL_CMD} -s "${loc}" | extract_locs
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
            PARALLEL="${2:-}"
            shift $(( $# > 1 ? 2 : 1 ))
            ;;
        --limit)
            LIMIT="${2:-}"
            shift $(( $# > 1 ? 2 : 1 ))
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_usage
            exit 1
            ;;
    esac
done

if ! [[ "${PARALLEL}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Fehler: --parallel braucht eine Zahl >= 1."
    exit 1
fi
if ! [[ "${LIMIT}" =~ ^[1-9][0-9]{0,5}$ ]]; then
    echo "Fehler: --limit braucht eine Zahl von 1 bis 999999."
    exit 1
fi

export -f warmup_url
export GREEN YELLOW NC CURL_CMD

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

if [[ "${PARALLEL}" -gt 1 ]]; then
    echo ""
    echo "Zweiter Durchgang (parallele erste Aufrufe lassen nach cache:clear Seiten kalt)"
    echo "${urls}" | QUIET=1 xargs -P "${PARALLEL}" -I {} bash -c 'warmup_url "$@"' _ {}
fi

echo ""
echo "Nächster Schritt: ./cache-debug.sh ${BASE_URL}"
