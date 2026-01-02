#!/bin/bash
# Cache Debug Script
# Kapitel 6: HTTP-Caching
#
# Analysiert HTTP-Cache-Header einer URL
#
# Verwendung:
#   ./cache-debug.sh https://ihr-shop.ch
#   ./cache-debug.sh https://ihr-shop.ch /kategorie /produkt/test
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Funktionen
# ============================================================

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  HTTP-Cache Debug Tool${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

analyze_url() {
    local url=$1
    echo ""
    echo -e "${YELLOW}🔍 Analysiere: ${url}${NC}"
    echo "───────────────────────────────────────────────────────"

    # HTTP-Header abrufen
    headers=$(curl -sI -H "Accept-Encoding: gzip" "${url}" 2>/dev/null)

    if [[ -z "${headers}" ]]; then
        echo -e "${RED}❌ Fehler: URL nicht erreichbar${NC}"
        return 1
    fi

    # Status Code
    status=$(echo "${headers}" | grep -i "^HTTP" | head -1 | awk '{print $2}')
    echo -e "HTTP Status: ${status}"

    # Cache-Control Header
    cache_control=$(echo "${headers}" | grep -i "^cache-control:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${cache_control}" ]]; then
        echo -e "${GREEN}Cache-Control:${NC}${cache_control}"

        # max-age extrahieren
        if [[ "${cache_control}" =~ max-age=([0-9]+) ]]; then
            max_age="${BASH_REMATCH[1]}"
            hours=$((max_age / 3600))
            mins=$(((max_age % 3600) / 60))
            echo -e "  └─ TTL: ${max_age}s (${hours}h ${mins}m)"
        fi

        # stale-while-revalidate
        if [[ "${cache_control}" =~ stale-while-revalidate=([0-9]+) ]]; then
            swr="${BASH_REMATCH[1]}"
            echo -e "  └─ SWR: ${swr}s"
        fi

        # public/private
        if [[ "${cache_control}" =~ "public" ]]; then
            echo -e "  └─ Scope: ${GREEN}public${NC} (cacheable)"
        elif [[ "${cache_control}" =~ "private" ]]; then
            echo -e "  └─ Scope: ${YELLOW}private${NC} (nur Browser-Cache)"
        fi

        # no-cache/no-store
        if [[ "${cache_control}" =~ "no-store" ]]; then
            echo -e "  └─ ${RED}no-store${NC} (nicht gecacht!)"
        elif [[ "${cache_control}" =~ "no-cache" ]]; then
            echo -e "  └─ ${YELLOW}no-cache${NC} (Revalidierung erforderlich)"
        fi
    else
        echo -e "${RED}Cache-Control: nicht gesetzt!${NC}"
    fi

    # X-Cache Header (Varnish/CDN)
    x_cache=$(echo "${headers}" | grep -i "^x-cache:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${x_cache}" ]]; then
        if [[ "${x_cache}" =~ "HIT" ]]; then
            echo -e "${GREEN}X-Cache:${NC}${x_cache} ✅"
        else
            echo -e "${YELLOW}X-Cache:${NC}${x_cache}"
        fi
    fi

    # X-Cache-Hits (Varnish)
    x_cache_hits=$(echo "${headers}" | grep -i "^x-cache-hits:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${x_cache_hits}" ]]; then
        echo -e "X-Cache-Hits:${x_cache_hits}"
    fi

    # Age Header
    age=$(echo "${headers}" | grep -i "^age:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${age}" ]]; then
        echo -e "Age:${age}s (Zeit im Cache)"
    fi

    # ETag
    etag=$(echo "${headers}" | grep -i "^etag:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${etag}" ]]; then
        echo -e "ETag: vorhanden ✅"
    fi

    # Shopware-spezifische Header
    sw_cache_id=$(echo "${headers}" | grep -i "^x-shopware-cache-id:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${sw_cache_id}" ]]; then
        echo -e "Shopware-Cache-ID: vorhanden"
    fi

    # Vary Header
    vary=$(echo "${headers}" | grep -i "^vary:" | cut -d: -f2- | tr -d '\r')
    if [[ -n "${vary}" ]]; then
        echo -e "Vary:${vary}"
    fi

    # Set-Cookie (verhindert Caching!)
    set_cookie=$(echo "${headers}" | grep -i "^set-cookie:")
    if [[ -n "${set_cookie}" ]]; then
        echo -e "${RED}⚠️  Set-Cookie Header gefunden - verhindert Caching!${NC}"
    fi

    echo ""
}

print_summary() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Legende${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Cache-Control Direktiven:"
    echo "  public        = Darf von jedem Cache gespeichert werden"
    echo "  private       = Nur Browser-Cache, kein CDN/Proxy"
    echo "  max-age       = Gültigkeitsdauer in Sekunden"
    echo "  s-maxage      = Gültigkeitsdauer für Shared Caches"
    echo "  no-cache      = Muss revalidiert werden"
    echo "  no-store      = Wirklich nicht cachen"
    echo "  stale-while-revalidate = Stale Content während Refresh"
    echo ""
    echo "X-Cache Werte:"
    echo "  HIT           = Aus Cache geliefert"
    echo "  MISS          = Vom Backend geholt"
    echo ""
    echo "Ziel-Werte:"
    echo "  TTFB          = < 100ms (mit Cache)"
    echo "  Cache-Hit-Rate = > 80% (Ziel), > 95% (exzellent)"
    echo ""
}

# ============================================================
# Main
# ============================================================

if [[ $# -lt 1 ]]; then
    echo "Verwendung: $0 <base-url> [pfade...]"
    echo ""
    echo "Beispiele:"
    echo "  $0 https://ihr-shop.ch"
    echo "  $0 https://ihr-shop.ch / /kategorie /produkt/test"
    exit 1
fi

BASE_URL="${1%/}"  # Trailing slash entfernen
shift

print_header

# Wenn keine Pfade angegeben, Standard-Pfade testen
if [[ $# -eq 0 ]]; then
    PATHS=("/" "/navigation" "/search")
else
    PATHS=("$@")
fi

for path in "${PATHS[@]}"; do
    if [[ "${path}" == /* ]]; then
        analyze_url "${BASE_URL}${path}"
    else
        analyze_url "${BASE_URL}/${path}"
    fi
done

print_summary

echo -e "${GREEN}✅ Analyse abgeschlossen${NC}"
