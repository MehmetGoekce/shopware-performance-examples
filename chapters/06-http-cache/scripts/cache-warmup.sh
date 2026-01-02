#!/bin/bash
# Cache Warmup Script
# Kapitel 6: HTTP-Caching
#
# Wärmt den HTTP-Cache auf indem wichtige Seiten gecrawlt werden.
#
# Verwendung:
#   ./cache-warmup.sh https://ihr-shop.ch
#   ./cache-warmup.sh https://ihr-shop.ch --sitemap
#   ./cache-warmup.sh https://ihr-shop.ch --parallel 4
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -e

# Konfiguration
PARALLEL=2
USE_SITEMAP=false
DELAY=0.1

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Funktionen
# ============================================================

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Cache Warmup Tool${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

warmup_url() {
    local url=$1
    local start
    start=$(date +%s%N)

    # Request mit gzip, User-Agent setzen
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept-Encoding: gzip" \
        -H "User-Agent: CacheWarmup/1.0" \
        "$url" 2>/dev/null)

    local end
    end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [ "$status" == "200" ]; then
        echo -e "${GREEN}✓${NC} ${url} (${duration}ms)"
    else
        echo -e "${YELLOW}⚠${NC} ${url} (HTTP ${status})"
    fi
}

warmup_from_sitemap() {
    local base_url=$1
    local sitemap_url="${base_url}/sitemap.xml"

    echo ""
    echo -e "${BLUE}📋 Lade Sitemap: ${sitemap_url}${NC}"

    # Sitemap laden und URLs extrahieren
    urls=$(curl -s "$sitemap_url" 2>/dev/null | grep -oP '(?<=<loc>)[^<]+' | head -100)

    if [ -z "$urls" ]; then
        echo -e "${YELLOW}⚠ Keine URLs in Sitemap gefunden, verwende Standard-URLs${NC}"
        warmup_standard "$base_url"
        return
    fi

    url_count=$(echo "$urls" | wc -l)
    echo -e "Gefunden: ${url_count} URLs"
    echo ""

    # URLs parallel aufwärmen
    echo "$urls" | xargs -P "$PARALLEL" -I {} bash -c 'warmup_url "$@"' _ {}
}

warmup_standard() {
    local base_url=$1

    echo ""
    echo -e "${BLUE}📋 Wärme Standard-Seiten auf...${NC}"
    echo ""

    # Wichtigste Seiten zuerst
    local urls=(
        "/"
        "/navigation"
        "/search"
    )

    for url in "${urls[@]}"; do
        warmup_url "${base_url}${url}"
        sleep "$DELAY"
    done

    # Versuche häufige Kategorie-Pfade
    echo ""
    echo -e "${BLUE}📋 Teste häufige Kategorien...${NC}"
    echo ""

    local category_paths=(
        "/kategorie"
        "/products"
        "/shop"
        "/collection"
    )

    for path in "${category_paths[@]}"; do
        status=$(curl -s -o /dev/null -w "%{http_code}" "${base_url}${path}" 2>/dev/null)
        if [ "$status" == "200" ]; then
            warmup_url "${base_url}${path}"
        fi
    done
}

print_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Cache Warmup abgeschlossen${NC}"
    echo ""
    echo "Nächste Schritte:"
    echo "  1. Cache-Status prüfen: ./cache-debug.sh ${BASE_URL}"
    echo "  2. Hit-Rate messen: ./cache-hit-rate.sh"
    echo ""
}

show_usage() {
    echo "Verwendung: $0 <base-url> [optionen]"
    echo ""
    echo "Optionen:"
    echo "  --sitemap       URLs aus sitemap.xml laden"
    echo "  --parallel N    Anzahl paralleler Requests (Standard: 2)"
    echo "  --delay N       Verzögerung zwischen Requests in Sekunden (Standard: 0.1)"
    echo ""
    echo "Beispiele:"
    echo "  $0 https://ihr-shop.ch"
    echo "  $0 https://ihr-shop.ch --sitemap"
    echo "  $0 https://ihr-shop.ch --sitemap --parallel 4"
}

# ============================================================
# Argument Parsing
# ============================================================

if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

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
        --delay)
            DELAY="$2"
            shift 2
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Export für xargs
export -f warmup_url
export GREEN YELLOW NC

# ============================================================
# Main
# ============================================================

print_header

echo ""
echo "Base URL: ${BASE_URL}"
echo "Parallel: ${PARALLEL}"
echo "Sitemap:  ${USE_SITEMAP}"
echo ""

# Shopware CLI Warmup wenn verfügbar
if [ -f "bin/console" ]; then
    echo -e "${BLUE}🚀 Starte Shopware HTTP-Cache Warmup...${NC}"
    bin/console http:cache:warm:up --no-debug 2>/dev/null || true
    echo ""
fi

if [ "$USE_SITEMAP" = true ]; then
    warmup_from_sitemap "$BASE_URL"
else
    warmup_standard "$BASE_URL"
fi

print_summary
