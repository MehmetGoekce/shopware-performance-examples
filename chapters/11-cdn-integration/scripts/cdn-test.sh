#!/bin/bash
#
# Prueft die CDN-Konfiguration eines Shopware-Shops
# Kapitel 11: CDN-Integration
#
# Usage:
#   ./cdn-test.sh <shop-url> [--verbose]
#   ./cdn-test.sh --help
#
# Exit-Codes:
#   0  alles bestanden oder nur Warnungen
#   1  mindestens ein Fehler
#   2  falsche Aufrufparameter
#
# Geprueft werden: HTTP-Status, Cache-Control, CDN-Status-Header, Langzeit-Cache
# und Kompression statischer Assets, CORS fuer Fonts sowie der Bypass fuer den
# Checkout.
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

usage() {
    cat <<'USAGE'
Usage: cdn-test.sh <shop-url> [--verbose]

  <shop-url>   Basis-URL des Shops, z.B. https://shop.example.com
  --verbose    Vollstaendige Response-Header ausgeben
  --help       Diese Hilfe

Exit-Codes: 0 = ok/Warnungen, 1 = Fehler gefunden, 2 = Aufruffehler
USAGE
}

check_pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; PASS=$((PASS + 1)); }
check_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; WARN=$((WARN + 1)); }
check_fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; FAIL=$((FAIL + 1)); }

# Header holen. curl darf fehlschlagen, ohne das Skript zu beenden.
get_headers() {
    curl -sS -D - -o /dev/null -H "Accept-Encoding: gzip, deflate, br" "$1" 2>/dev/null || true
}

# Gibt den Wert eines Headers zurueck, oder nichts. Wichtig: die Funktion muss
# mit 0 enden, sonst beendet `set -e` das Skript, sobald ein Header fehlt.
header_value() {
    printf '%s\n' "$1" | grep -i "^$2:" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//' || true
}

# Loest "." und ".." in einem Pfad auf. Als Subshell, damit das geaenderte IFS
# lokal bleibt.
normalize_path() (
    IFS='/'
    out=''
    for seg in $1; do
        case "${seg}" in
            ''|.) continue ;;
            ..)   out="${out%/*}" ;;
            *)    out="${out}/${seg}" ;;
        esac
    done
    printf '%s' "${out:-/}"
)

# Macht aus einer (auch relativen) URL eine absolute.
#   $1 = Referenz
#   $2 = Basis-URL, gegen die relative Referenzen aufgeloest werden
#        (Default: Shop-Root)
#
# Wichtig fuer Fonts: in der Theme-CSS stehen Pfade wie
# "../../<hash>/assets/font/Inter-Regular-Roman.woff2" — relativ zur CSS-Datei,
# nicht zum Shop-Root. Wer sie einfach an die Shop-URL haengt, testet eine
# Adresse, die es nicht gibt, und meldet faelschlich fehlendes CORS.
absolute_url() {
    local ref="$1" base="${2:-${SHOP_URL}/}" origin path query dir

    case "${ref}" in
        http*) printf '%s' "${ref}"; return ;;
    esac

    query=''
    case "${ref}" in
        *\?*) query="?${ref#*\?}"; ref="${ref%%\?*}" ;;
    esac

    base="${base%%\?*}"
    origin=$(printf '%s' "${base}" | sed -E 's#^(https?://[^/]+).*#\1#')

    case "${ref}" in
        /*) path="${ref}" ;;
        *)
            dir="${base#"${origin}"}"
            dir="${dir%/*}"
            path="${dir}/${ref}"
            ;;
    esac

    printf '%s%s%s' "${origin}" "$(normalize_path "${path}")" "${query}"
}

test_homepage() {
    echo "=== 1. Startseite ==="

    local headers status cache_control cf_status
    headers=$(get_headers "${SHOP_URL}/")

    [ "${VERBOSE}" = "--verbose" ] && printf '%s\n\n' "${headers}"

    status=$(printf '%s\n' "${headers}" | head -1 | grep -oE '[0-9]{3}' | head -1 || true)
    if [ "${status:-000}" = "200" ]; then
        check_pass "HTTP-Status: ${status}"
    else
        check_fail "HTTP-Status: ${status:-keine Antwort} (erwartet 200)"
    fi

    cache_control=$(header_value "${headers}" "cache-control")
    if [ -z "${cache_control}" ]; then
        check_warn "Kein Cache-Control-Header"
    elif printf '%s' "${cache_control}" | grep -qi 's-maxage'; then
        check_pass "Cache-Control: ${cache_control}"
    else
        # Ohne Reverse Proxy sendet Shopware bewusst no-cache, private.
        check_warn "Cache-Control: ${cache_control} (CDN cached kein HTML; Reverse Proxy aktiv?)"
    fi

    cf_status=$(header_value "${headers}" "cf-cache-status")
    if [ -n "${cf_status}" ]; then
        case "${cf_status}" in
            HIT) check_pass "cf-cache-status: HIT" ;;
            MISS|EXPIRED|REVALIDATED) check_warn "cf-cache-status: ${cf_status}" ;;
            BYPASS|DYNAMIC) check_warn "cf-cache-status: ${cf_status} (HTML wird nicht gecacht)" ;;
            *) echo "  cf-cache-status: ${cf_status}" ;;
        esac
    elif [ -n "$(header_value "${headers}" "cdn-cache")" ]; then
        echo "  Bunny CDN: $(header_value "${headers}" "cdn-cache")"
    else
        check_warn "Kein CDN-Status-Header gefunden"
    fi

    echo ""
}

test_static_assets() {
    echo "=== 2. Statische Assets ==="

    local css_url headers cache_control max_age encoding
    css_url=$(curl -sS "${SHOP_URL}/" 2>/dev/null | grep -oE 'href="[^"]+\.css[^"]*"' | head -1 | sed 's/href="//;s/"$//' || true)

    if [ -z "${css_url}" ]; then
        check_warn "Keine CSS-Datei auf der Startseite gefunden"
        echo ""
        return
    fi

    css_url=$(absolute_url "${css_url}")
    echo "Test-URL: ${css_url}"

    headers=$(get_headers "${css_url}")
    [ "${VERBOSE}" = "--verbose" ] && printf '%s\n\n' "${headers}"

    if [ "$(printf '%s\n' "${headers}" | grep -ci '^cache-control:' || true)" -gt 1 ]; then
        check_fail "Zwei Cache-Control-Header (expires UND add_header gesetzt?)"
    fi

    cache_control=$(header_value "${headers}" "cache-control")
    max_age=$(printf '%s' "${cache_control}" | grep -oE 'max-age=[0-9]+' | head -1 | cut -d= -f2 || true)

    if [ -z "${max_age}" ]; then
        check_fail "max-age nicht gesetzt"
    elif [ "${max_age}" -ge 31536000 ]; then
        check_pass "max-age: ${max_age} (ein Jahr)"
    elif [ "${max_age}" -ge 86400 ]; then
        check_warn "max-age: ${max_age} (nur $((max_age / 86400)) Tage)"
    else
        check_fail "max-age: ${max_age} (zu kurz fuer versionierte Assets)"
    fi

    if printf '%s' "${cache_control}" | grep -qi 'immutable'; then
        check_pass "immutable gesetzt"
    else
        check_warn "immutable fehlt (bei versionierten Assets empfohlen)"
    fi

    encoding=$(header_value "${headers}" "content-encoding")
    if [ -n "${encoding}" ]; then
        check_pass "Kompression: ${encoding}"
    else
        check_warn "Keine Kompression (gzip/br)"
    fi

    echo ""
}

test_fonts() {
    echo "=== 3. Fonts (CORS) ==="

    local font_url css_url cors
    font_url=$(curl -sS "${SHOP_URL}/" 2>/dev/null | grep -oE 'href="[^"]+\.woff2[^"]*"' | head -1 | sed 's/href="//;s/"$//' || true)

    if [ -z "${font_url}" ]; then
        css_url=$(curl -sS "${SHOP_URL}/" 2>/dev/null | grep -oE 'href="[^"]+\.css[^"]*"' | head -1 | sed 's/href="//;s/"$//' || true)
        if [ -n "${css_url}" ]; then
            css_url=$(absolute_url "${css_url}")
            font_url=$(curl -sS "${css_url}" 2>/dev/null | grep -oE 'url\([^)]+\.woff2[^)]*\)' | head -1 | sed 's/url(//;s/)$//;s/"//g;s/'\''//g' || true)
        fi
    fi

    if [ -z "${font_url}" ]; then
        check_warn "Keine woff2-Datei gefunden"
        echo ""
        return
    fi

    # Relative Font-Pfade gegen die CSS-Datei aufloesen, nicht gegen den Shop-Root.
    font_url=$(absolute_url "${font_url}" "${css_url:-${SHOP_URL}/}")
    echo "Test-URL: ${font_url}"

    cors=$(curl -sS -D - -o /dev/null -H "Origin: ${SHOP_URL}" "${font_url}" 2>/dev/null | grep -i '^access-control-allow-origin:' | head -1 | tr -d '\r' || true)

    if [ -n "${cors}" ]; then
        check_pass "${cors}"
    else
        check_fail "Kein Access-Control-Allow-Origin (Fonts von der CDN-Domain werden blockiert)"
    fi

    echo ""
}

test_bypass() {
    echo "=== 4. Bypass-Bereiche ==="

    local path headers status cache_control
    for path in /checkout/cart /account/login; do
        headers=$(get_headers "${SHOP_URL}${path}")
        status=$(printf '%s\n' "${headers}" | head -1 | grep -oE '[0-9]{3}' | head -1 || true)

        if [ "${status:-000}" = "404" ]; then
            check_fail "${path}: HTTP 404 - fehlt try_files/fastcgi_pass in der nginx-Location?"
            continue
        fi

        cache_control=$(header_value "${headers}" "cache-control")
        if printf '%s' "${cache_control}" | grep -qiE 'private|no-store|no-cache'; then
            check_pass "${path}: nicht cachebar (${cache_control})"
        else
            check_fail "${path}: cachebar (${cache_control:-kein Header})"
        fi
    done

    echo ""
}

summary() {
    echo "==========================================="
    echo "=== Zusammenfassung ==="
    echo "==========================================="
    echo ""
    printf "${GREEN}Bestanden: %s${NC}\n" "${PASS}"
    printf "${YELLOW}Warnungen: %s${NC}\n" "${WARN}"
    printf "${RED}Fehler:    %s${NC}\n" "${FAIL}"
    echo ""

    if [ "${FAIL}" -gt 0 ]; then
        printf "${RED}CDN-Konfiguration hat Fehler.${NC}\n"
        return 1
    fi

    if [ "${WARN}" -gt 0 ]; then
        printf "${YELLOW}CDN laeuft, mit Optimierungspotenzial.${NC}\n"
        return 0
    fi

    printf "${GREEN}CDN-Konfiguration ist in Ordnung.${NC}\n"
    return 0
}

# ============================================================================
# Hauptlauf
# ============================================================================

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
    VERBOSE="${2:-}"

    echo "=== CDN-Test ==="
    echo ""
    echo "Shop: ${SHOP_URL}"
    echo ""

    test_homepage
    test_static_assets
    test_fonts
    test_bypass
    summary
}

# Nur ausfuehren, wenn das Skript direkt aufgerufen wird - so koennen die
# Hilfsfunktionen in Tests eingebunden werden (siehe tests/Shell/cdn-scripts.bats).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
