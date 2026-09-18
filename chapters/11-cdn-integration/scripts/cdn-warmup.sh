#!/bin/bash
#
# Waermt den CDN-Cache nach einem Deployment
# Kapitel 11: CDN-Integration
#
# Usage:
#   ./cdn-warmup.sh <shop-url> [--critical|--sitemap|--all]
#   ./cdn-warmup.sh --help
#
# Exit-Codes:
#   0  alle angefragten URLs haben mit 200 geantwortet
#   1  mindestens eine URL hat nicht mit 200 geantwortet
#   2  falsche Aufrufparameter
#
# WICHTIG — was ein Warmup leisten kann und was nicht:
# Der Aufruf landet immer am PoP, der dem ausfuehrenden Rechner am naechsten
# liegt. Ein CI-Runner in Frankfurt waermt Frankfurt, nicht Singapur. Wer
# mehrere Regionen waermen will, braucht Runner in diesen Regionen.
#
# Shopwares /sitemap.xml ist ein sitemapindex und verlinkt gzip-komprimierte
# Teil-Sitemaps (.xml.gz). Ein Warmup, das nur die <loc>-Eintraege der
# Index-Datei abruft, waermt also Archive statt Seiten. Dieses Skript loest den
# Index auf und entpackt die Teil-Sitemaps.
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONCURRENCY=5
USER_AGENT="CDN-Warmup/2.0"
MAX_SITEMAP_URLS=500

OK_COUNT=0
ERR_COUNT=0

usage() {
    cat <<'USAGE'
Usage: cdn-warmup.sh <shop-url> [--critical|--sitemap|--all]

  <shop-url>    Basis-URL des Shops, z.B. https://shop.example.com
  --critical    Nur Startseite, Suche, Kategorie-Einstieg
  --sitemap     URLs aus der Sitemap (loest den sitemapindex und .xml.gz auf)
  --all         Beides (Default)
  --help        Diese Hilfe

Exit-Codes: 0 = alles 200, 1 = mindestens ein Fehler, 2 = Aufruffehler
USAGE
}

# Ruft eine URL ab und zaehlt das Ergebnis. Nie abbrechen, nur zaehlen.
warm_url() {
    local url="$1" status
    status=$(curl -sS -o /dev/null -w '%{http_code}' -A "${USER_AGENT}" "${url}" 2>/dev/null || printf '000')

    if [ "${status}" = "200" ]; then
        OK_COUNT=$((OK_COUNT + 1))
        printf "  ${GREEN}200${NC} %s\n" "${url}"
    else
        ERR_COUNT=$((ERR_COUNT + 1))
        printf "  ${RED}%s${NC} %s\n" "${status}" "${url}"
    fi
}

warm_critical() {
    echo "=== Kritische Seiten ==="

    local path
    for path in "/" "/search?search=a" "/sitemap.xml"; do
        warm_url "${SHOP_URL}${path}"
    done

    echo ""
}

# Zieht alle <loc>-Werte aus einem XML-Dokument auf stdin.
extract_locs() {
    grep -oE '<loc>[^<]+</loc>' | sed -e 's#<loc>##' -e 's#</loc>##'
}

warm_sitemap() {
    echo "=== Sitemap ==="

    local index children child body urls count
    index=$(curl -sS -A "${USER_AGENT}" "${SHOP_URL}/sitemap.xml" 2>/dev/null || true)

    if [ -z "${index}" ]; then
        printf "${YELLOW}Keine Sitemap unter %s/sitemap.xml${NC}\n\n" "${SHOP_URL}"
        return
    fi

    urls=''

    if printf '%s' "${index}" | grep -q '<sitemapindex'; then
        children=$(printf '%s' "${index}" | extract_locs || true)
        echo "  sitemapindex mit $(printf '%s\n' "${children}" | grep -c . || true) Teil-Sitemaps"

        for child in ${children}; do
            # Teil-Sitemaps sind gzip-komprimiert; unkomprimierte trotzdem zulassen.
            case "${child}" in
                *.gz) body=$(curl -sS -A "${USER_AGENT}" "${child}" 2>/dev/null | gunzip -c 2>/dev/null || true) ;;
                *)    body=$(curl -sS -A "${USER_AGENT}" "${child}" 2>/dev/null || true) ;;
            esac

            urls="${urls}$(printf '%s' "${body}" | extract_locs || true)
"
        done
    else
        urls=$(printf '%s' "${index}" | extract_locs || true)
    fi

    urls=$(printf '%s\n' "${urls}" | grep -E '^https?://' | sort -u | head -n "${MAX_SITEMAP_URLS}" || true)
    count=$(printf '%s\n' "${urls}" | grep -c . || true)

    if [ "${count}" -eq 0 ]; then
        printf "${YELLOW}Keine Seiten-URLs in der Sitemap gefunden${NC}\n\n"
        return
    fi

    echo "  ${count} URLs (max. ${MAX_SITEMAP_URLS}), ${CONCURRENCY} parallel"

    # xargs ruft /bin/sh auf — hier ist POSIX Pflicht, kein [[ ]].
    printf '%s\n' "${urls}" | xargs -P "${CONCURRENCY}" -I {} sh -c '
        status=$(curl -sS -o /dev/null -w "%{http_code}" -A "$1" "$2" 2>/dev/null || echo 000)
        if [ "$status" = "200" ]; then
            echo "  200 $2"
        else
            echo "  $status $2"
        fi
    ' _ "${USER_AGENT}" {} | tee /dev/stderr | grep -cE '^  200 ' >/tmp/.cdn_warmup_ok 2>/dev/null || true

    local ok
    ok=$(cat /tmp/.cdn_warmup_ok 2>/dev/null || echo 0)
    rm -f /tmp/.cdn_warmup_ok
    OK_COUNT=$((OK_COUNT + ok))
    ERR_COUNT=$((ERR_COUNT + count - ok))

    echo ""
}

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
        return 0
    fi

    if [ $# -lt 1 ] || [ -z "${1}" ]; then
        usage >&2
        return 2
    fi

    SHOP_URL="${1%/}"
    MODE="${2:---all}"

    case "${MODE}" in
        --critical|--sitemap|--all) ;;
        *) printf 'Unbekannter Modus: %s\n\n' "${MODE}" >&2; usage >&2; return 2 ;;
    esac

    echo "=== CDN-Warmup ==="
    echo ""
    echo "Shop: ${SHOP_URL}"
    echo "Modus: ${MODE}"
    echo ""

    case "${MODE}" in
        --critical) warm_critical ;;
        --sitemap)  warm_sitemap ;;
        --all)      warm_critical; warm_sitemap ;;
    esac

    echo "Erfolgreich: ${OK_COUNT}"
    echo "Fehler:      ${ERR_COUNT}"

    [ "${ERR_COUNT}" -eq 0 ]
}

# Nur ausfuehren, wenn das Skript direkt aufgerufen wird.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
