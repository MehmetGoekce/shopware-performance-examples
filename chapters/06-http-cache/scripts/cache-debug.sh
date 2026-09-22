#!/bin/bash
# Cache Debug Script
# Kapitel 6: HTTP-Caching
#
# Ruft jede URL zweimal ohne Cookies ab (mit kurzer Pause dazwischen) und zeigt,
# ob die zweite Antwort aus dem Cache kommt. Erkennt drei Fälle:
#   1. Varnish mit config/varnish.vcl  -> Header "X-Cache: HIT/MISS"
#   2. Anderer Reverse Proxy / CDN     -> "Cache-Control: public, s-maxage=..." vom Backend
#   3. Eingebauter Shopware-Cache      -> Browser sieht immer "no-cache, private";
#                                         Treffer nur daran erkennbar, dass Age
#                                         zwischen den Aufrufen um mindestens die
#                                         Pause wächst. Age > 0 allein reicht nicht:
#                                         Symfony setzt beim Speichern Age = Sekunden
#                                         seit dem Date-Header, und Shopware erzeugt
#                                         die Response vor dem Twig-Rendern. Ein MISS
#                                         trägt so Age 1 über eine Sekundengrenze und
#                                         mehr bei langsamem Rendern.
#
# Umgebungsvariablen:
#   CACHE_DEBUG_WAIT  Pause zwischen den Aufrufen in ganzen Sekunden (Default: 2,
#                     mindestens 1). Bei einem Treffer wächst Age um mindestens
#                     diesen Wert, bei zwei MISS nur, wenn der zweite so viel
#                     langsamer rendert.
#   CURL_CMD          curl-Befehl (Default: curl, für Tests austauschbar)
#
# Verwendung (im Ordner chapters/06-http-cache):
#   ./scripts/cache-debug.sh https://ihr-shop.ch
#   ./scripts/cache-debug.sh https://ihr-shop.ch / /kategorie/ /produkt/SW10001
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

CACHE_DEBUG_WAIT="${CACHE_DEBUG_WAIT:-2}"
CURL_CMD="${CURL_CMD:-curl}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_usage() {
    echo "Usage: $0 <base-url> [pfade...]"
    echo ""
    echo "Ruft jeden Pfad zweimal ohne Cookies ab und bewertet die Cache-Header."
    echo "Ohne Pfade wird nur / geprüft."
    echo ""
    echo "Umgebungsvariablen:"
    echo "  CACHE_DEBUG_WAIT  Pause zwischen den Aufrufen in ganzen Sekunden (Default: 2, mindestens 1)"
    echo "  CURL_CMD          curl-Befehl (Default: curl)"
    echo ""
    echo "Beispiele:"
    echo "  $0 https://ihr-shop.ch"
    echo "  $0 https://ihr-shop.ch / /kategorie/ /produkt/SW10001"
}

# Wert eines Headers (case-insensitive) aus einem Header-Block
header_value() {
    local headers=$1
    local name=$2
    echo "${headers}" | grep -i "^${name}:" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//' || true
}

fetch() {
    # Gibt Header-Block aus, danach eine Zeile "TTFB=<sekunden>"
    ${CURL_CMD} -s -o /dev/null -D - -w 'TTFB=%{time_starttransfer}\n' \
        -H "Accept-Encoding: gzip" "$1"
}

analyze_url() {
    local url=$1
    local first second

    echo ""
    echo -e "${BLUE}Analysiere: ${url}${NC}"
    echo "-------------------------------------------------------"

    if ! first=$(fetch "${url}") || ! echo "${first}" | grep -q "^HTTP"; then
        echo -e "${RED}Fehler: URL nicht erreichbar${NC}"
        return 1
    fi
    sleep "${CACHE_DEBUG_WAIT}"
    second=$(fetch "${url}")

    local status cache_control x_cache age1 age set_cookie ttfb1 ttfb2
    status=$(echo "${second}" | grep -i "^HTTP" | tail -1 | awk '{print $2}')
    cache_control=$(header_value "${second}" "cache-control")
    x_cache=$(header_value "${second}" "x-cache")
    age1=$(header_value "${first}" "age")
    age=$(header_value "${second}" "age")
    set_cookie=$(echo "${first}" | grep -ci "^set-cookie:" || true)
    ttfb1=$(echo "${first}" | sed -n 's/^TTFB=//p')
    ttfb2=$(echo "${second}" | sed -n 's/^TTFB=//p')

    echo "HTTP Status:    ${status}"
    echo "Cache-Control:  ${cache_control:-(nicht gesetzt)}"
    [[ -n "${x_cache}" ]] && echo "X-Cache:        ${x_cache}"
    [[ -n "${age1}${age}" ]] && echo "Age:            1. Aufruf ${age1:--}, 2. Aufruf ${age:--} (Pause ${CACHE_DEBUG_WAIT} s)"
    awk -v a="${ttfb1}" -v b="${ttfb2}" 'BEGIN { printf "TTFB:           1. Aufruf %.0f ms, 2. Aufruf %.0f ms\n", a * 1000, b * 1000 }'
    [[ "${set_cookie}" -gt 0 ]] && echo "Set-Cookie:     ${set_cookie}x beim 1. Aufruf"

    echo -n "Bewertung:      "
    if [[ "${status}" =~ ^3 ]]; then
        echo -e "${YELLOW}Weiterleitung - Ziel-URL prüfen${NC}"
    elif [[ -n "${x_cache}" ]]; then
        if [[ "${x_cache}" == *HIT* ]]; then
            echo -e "${GREEN}Varnish: 2. Aufruf aus dem Cache${NC}"
        else
            echo -e "${YELLOW}Varnish: auch der 2. Aufruf kam vom Backend (Route ohne _httpCache, Pass-Regel oder Set-Cookie?)${NC}"
        fi
    elif [[ "${cache_control}" == *public* && "${cache_control}" == *s-maxage* ]]; then
        echo -e "${GREEN}Backend liefert cachebar für Reverse Proxy/CDN${NC} (Cache-Status beim Proxy prüfen)"
    elif [[ "${cache_control}" == *private* ]]; then
        if [[ "${age1}" =~ ^[0-9]+$ && "${age}" =~ ^[0-9]+$ ]] \
            && [[ $((age - age1)) -ge "${CACHE_DEBUG_WAIT}" ]]; then
            echo -e "${GREEN}Eingebauter Shopware-Cache: 2. Aufruf aus dem Cache${NC} (Age um $((age - age1)) s gewachsen)"
        elif [[ "${age}" =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Kein Treffer erkennbar: Age nicht um die Pause gewachsen${NC} (zwei MISS? Route mit _httpCache? APP_ENV=prod?)"
        elif awk -v a="${ttfb1}" -v b="${ttfb2}" 'BEGIN { exit !(b * 3 < a) }'; then
            echo -e "${YELLOW}2. Aufruf deutlich schneller, aber ohne Age${NC} (Warmlaufen statt Cache? APP_ENV=prod?)"
        else
            echo -e "${YELLOW}Nicht gecacht oder nicht erkennbar${NC} (Route mit _httpCache? APP_ENV=prod?)"
        fi
    else
        echo -e "${YELLOW}Nicht eindeutig - Header oben prüfen${NC}"
    fi
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

if ! [[ "${CACHE_DEBUG_WAIT}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Fehler: CACHE_DEBUG_WAIT muss eine ganze Zahl ab 1 sein: ${CACHE_DEBUG_WAIT}" >&2
    exit 1
fi

BASE_URL="${1%/}"
shift

if [[ $# -eq 0 ]]; then
    PATHS=("/")
else
    PATHS=("$@")
fi

echo -e "${BLUE}HTTP-Cache Debug${NC}"

failed=0
for path in "${PATHS[@]}"; do
    [[ "${path}" == /* ]] || path="/${path}"
    analyze_url "${BASE_URL}${path}" || failed=1
done

echo ""
echo "Hinweise:"
echo "  - Getestet wird als Gast ohne Cookies. Eingeloggte Kunden und Besucher"
echo "    mit Warenkorb gehen immer am Cache vorbei."
echo "  - Hinter Varnish sieht der Browser für HTML bewusst 'no-store'."

exit "${failed}"
