#!/bin/bash
# Cache Debug Script
# Kapitel 6: HTTP-Caching
#
# Ruft jede URL zweimal ohne Cookies ab (mit kurzer Pause dazwischen) und zeigt,
# ob die zweite Antwort aus dem Cache kommt. Erkennt drei Fälle:
#   1. Varnish mit config/varnish.vcl  -> Header "X-Cache: HIT/MISS"
#   2. Anderer Reverse Proxy / CDN     -> "Cache-Control: public, s-maxage=..." vom Backend
#   3. Eingebauter Shopware-Cache      -> Browser sieht immer "no-cache, private".
#      Treffer: Age wächst zwischen den Aufrufen um mindestens die Pause UND
#      Date bleibt gleich. Nur eine gespeicherte Kopie wiederholt ihr Date.
#      Gibt Symfony X-Symfony-Cache aus (dev oder framework.http_cache.trace_level),
#      entscheidet der Header: "fresh" beim 2. Aufruf ist ein Treffer (ebenso
#      stale-while-revalidate und stale-if-error: eine veraltete gespeicherte Kopie).
#      Age allein reicht nicht:
#        - Symfony setzt beim Speichern Age = Sekunden seit Date, und Shopware
#          erzeugt die Response vor dem Twig-Rendern. Ein MISS trägt so Age 1
#          über eine Sekundengrenze und mehr bei langsamem Rendern.
#        - Mit ESI trägt die Seite das Age des ältesten Fragments (Symfony
#          ResponseCacheStrategy), Date bleibt das der neu gerenderten Seite.
#          Shopware 6.7 lädt Header und Footer immer per ESI (6.6 nur mit
#          CACHE_REWORK): Dort trägt jede Seite ein Age, bei abgeschaltetem
#          Cache 0 oder 1, und am nie gecachten Warenkorb wächst es mit.
#      Wächst Age, Date aber auch, ist es nicht entscheidbar: ESI-Fragment oder
#      ein Webserver davor, der Date neu setzt (nginx proxy_pass ohne
#      "proxy_pass_header Date;", Apache mit mod_php). Bleibt Date gleich, ohne
#      dass Age um die Pause wächst, ebenso (andere Cache-Schicht, neu
#      gespeichertes Fragment). Die TTFB wird nur angezeigt: Direkt nach
#      cache:clear ist auch ohne Treffer der 1. Aufruf viel langsamer.
#
# Umgebungsvariablen:
#   CACHE_DEBUG_WAIT  Pause zwischen den Aufrufen in ganzen Sekunden (Default und
#                     Minimum: 2). Bei einem Treffer wächst Age um mindestens
#                     diesen Wert.
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
    echo "  CACHE_DEBUG_WAIT  Pause zwischen den Aufrufen in ganzen Sekunden (Default und Minimum: 2)"
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
    if ! second=$(fetch "${url}") || ! echo "${second}" | grep -q "^HTTP"; then
        echo -e "${RED}Fehler: 2. Aufruf gescheitert, nicht bewertbar${NC}"
        return 1
    fi

    local status cache_control x_cache age1 age date1 date2 trace set_cookie ttfb1 ttfb2
    status=$(echo "${second}" | grep -i "^HTTP" | tail -1 | awk '{print $2}')
    cache_control=$(header_value "${second}" "cache-control")
    x_cache=$(header_value "${second}" "x-cache")
    age1=$(header_value "${first}" "age")
    age=$(header_value "${second}" "age")
    date1=$(header_value "${first}" "date")
    date2=$(header_value "${second}" "date")
    trace=$(header_value "${second}" "x-symfony-cache")
    set_cookie=$(echo "${first}" | grep -ci "^set-cookie:" || true)
    ttfb1=$(echo "${first}" | sed -n 's/^TTFB=//p')
    ttfb2=$(echo "${second}" | sed -n 's/^TTFB=//p')

    echo "HTTP Status:    ${status}"
    echo "Cache-Control:  ${cache_control:-(nicht gesetzt)}"
    [[ -n "${x_cache}" ]] && echo "X-Cache:        ${x_cache}"
    [[ -n "${age1}${age}" ]] && echo "Age:            1. Aufruf ${age1:--}, 2. Aufruf ${age:--} (Pause ${CACHE_DEBUG_WAIT} s)"
    [[ -n "${date1}${date2}" ]] && echo "Date:           1. Aufruf ${date1:--}, 2. Aufruf ${date2:--}"
    [[ -n "${trace}" ]] && echo "X-Symfony-Cache: ${trace} (2. Aufruf)"
    awk -v a="${ttfb1}" -v b="${ttfb2}" 'BEGIN { printf "TTFB:           1. Aufruf %.0f ms, 2. Aufruf %.0f ms\n", a * 1000, b * 1000 }'
    [[ "${set_cookie}" -gt 0 ]] && echo "Set-Cookie:     ${set_cookie}x beim 1. Aufruf"

    echo -n "Bewertung:      "
    if [[ "${status}" =~ ^3 ]]; then
        echo -e "${YELLOW}Weiterleitung - Ziel-URL prüfen${NC}"
    elif [[ ! "${status}" =~ ^2 ]]; then
        echo -e "${YELLOW}Fehlerseite (HTTP ${status}) - nicht bewertbar, eine Kategorie- oder Produktseite angeben${NC}"
    elif [[ -n "${x_cache}" ]]; then
        if [[ "${x_cache}" == *HIT* ]]; then
            echo -e "${GREEN}Varnish: 2. Aufruf aus dem Cache${NC}"
        else
            echo -e "${YELLOW}Varnish: auch der 2. Aufruf kam vom Backend (Route ohne _httpCache, Pass-Regel oder Set-Cookie?)${NC}"
        fi
    elif [[ "${cache_control}" == *public* && "${cache_control}" == *s-maxage* ]]; then
        echo -e "${GREEN}Backend liefert cachebar für Reverse Proxy/CDN${NC} (Cache-Status beim Proxy prüfen)"
    elif [[ "${cache_control}" == *no-store* ]]; then
        echo -e "${YELLOW}Seite bewusst nicht cachebar (no-store)${NC} (Checkout, Kundenkonto): eine Kategorie- oder Produktseite prüfen"
    elif [[ "${cache_control}" == *private* ]]; then
        local aged=0 main_trace="" trace_hit=0 token
        if [[ "${age1}" =~ ^[0-9]+$ && "${age}" =~ ^[0-9]+$ ]] \
            && [[ $((age - age1)) -ge "${CACHE_DEBUG_WAIT}" ]]; then
            aged=1
        fi
        # Der Trace nennt zuerst die Hauptanfrage ("fresh" im Format short,
        # "GET /: fresh; GET /_esi/...: ..." im Format full). "fresh" zählt, dazu
        # die beiden Fälle, in denen Symfony eine veraltete Kopie ausliefert;
        # "valid" heisst: das Backend hat die Seite neu gerendert.
        if [[ -n "${trace}" ]]; then
            main_trace="${trace%%;*}"
            main_trace="${main_trace##*: }"
            for token in ${main_trace//[\/,]/ }; do
                case "${token}" in
                    fresh|stale-while-revalidate|stale-if-error) trace_hit=1 ;;
                esac
            done
        fi
        if [[ -n "${trace}" && "${trace_hit}" -eq 1 ]]; then
            echo -e "${GREEN}Eingebauter Shopware-Cache: 2. Aufruf aus dem Cache${NC} (X-Symfony-Cache: ${main_trace})"
        elif [[ -n "${trace}" ]]; then
            echo -e "${YELLOW}Kein Treffer: X-Symfony-Cache meldet \"${main_trace}\"${NC}"
            echo "                \"miss\" ohne \"store\": Route ohne _httpCache oder Cache aus."
            echo "                \"miss/store\" auch beim 2. Aufruf: der Eintrag überlebt nicht (APP_ENV=dev?)."
        elif [[ "${aged}" -eq 1 && -n "${date1}" && "${date1}" == "${date2}" ]]; then
            echo -e "${GREEN}Eingebauter Shopware-Cache: 2. Aufruf aus dem Cache${NC} (Age um $((age - age1)) s gewachsen, Date unverändert)"
        elif [[ "${aged}" -eq 1 ]]; then
            if [[ -z "${date1}" || -z "${date2}" ]]; then
                echo -e "${YELLOW}Nicht entscheidbar: Age wächst um die Pause, aber ohne Date-Header${NC}"
            else
                echo -e "${YELLOW}Nicht entscheidbar: Age wächst um die Pause, Date aber auch${NC}"
            fi
            echo "                Entweder bindet die neu gerenderte Seite ein gecachtes ESI-Fragment ein (ab 6.7"
            echo "                Header und Footer, auch am nie gecachten Warenkorb), oder der Webserver davor setzt"
            echo "                Date neu (nginx proxy_pass ohne \"proxy_pass_header Date;\", Apache mit mod_php)."
            echo "                Eindeutig: framework.http_cache.trace_level: short setzen (Kapitel 6.8)."
        elif [[ "${age1}" =~ ^[0-9]+$ && "${age}" =~ ^[0-9]+$ && -n "${date1}" && "${date1}" == "${date2}" ]]; then
            echo -e "${YELLOW}Nicht entscheidbar: Date gleich, Age aber nicht um die Pause gewachsen${NC}"
            echo "                Eine gespeicherte Kopie, aber eine andere Cache-Schicht schreibt Age nicht fort"
            echo "                (nginx proxy_cache), oder das älteste ESI-Fragment wurde neu gespeichert."
            echo "                Eindeutig: framework.http_cache.trace_level: short setzen (Kapitel 6.8)."
        elif [[ "${age1}" =~ ^[0-9]+$ && "${age}" =~ ^[0-9]+$ && "${age}" -lt "${age1}" ]]; then
            echo -e "${YELLOW}Kein Treffer erkennbar: Age gesunken${NC} (1. Aufruf aus dem Cache und Eintrag danach"
            echo "                abgelaufen oder invalidiert, oder zwei MISS, ab 6.7 auch bei abgeschaltetem Cache)"
        elif [[ "${age}" =~ ^[0-9]+$ && ! "${age1}" =~ ^[0-9]+$ ]] || [[ "${age1}" =~ ^[0-9]+$ && ! "${age}" =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Nicht entscheidbar: Age nur bei einem Aufruf${NC} (erneut prüfen)"
        elif [[ "${age}" =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Kein Treffer erkennbar: Age nicht um die Pause gewachsen${NC} (zwei MISS? Route mit _httpCache? APP_ENV=prod?)"
            echo "                Ab 6.7 trägt jede Seite ein Age (ESI), auch wenn der Cache abgeschaltet ist."
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

if ! [[ "${CACHE_DEBUG_WAIT}" =~ ^([2-9]|[1-9][0-9]+)$ ]]; then
    echo "Fehler: CACHE_DEBUG_WAIT muss eine ganze Zahl ab 2 sein: ${CACHE_DEBUG_WAIT}" >&2
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
