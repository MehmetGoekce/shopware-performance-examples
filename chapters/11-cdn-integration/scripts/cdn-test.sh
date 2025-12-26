#!/bin/bash
#
# CDN Configuration Test Script
# Prüft CDN-Setup und Cache-Header
#
# Verwendung:
#   ./cdn-test.sh https://shop.de
#   ./cdn-test.sh https://shop.de --verbose
#
# Prüft:
#   - Cache-Control Header
#   - CDN-Status Header (Cloudflare/Bunny)
#   - CORS Header für Fonts
#   - Compression
#   - TTL-Konfiguration

set -e

SHOP_URL="${1:-}"
VERBOSE="${2:-}"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Verwendung: $0 <shop-url> [--verbose]"
    exit 1
}

if [ -z "$SHOP_URL" ]; then
    usage
fi

SHOP_URL="${SHOP_URL%/}"

echo "=== CDN Configuration Test ==="
echo ""
echo "Shop: $SHOP_URL"
echo ""

PASS=0
WARN=0
FAIL=0

# ============================================================================
# Helper Functions
# ============================================================================

check_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS++))
}

check_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN++))
}

check_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL++))
}

get_headers() {
    curl -sI -H "Accept-Encoding: gzip, deflate, br" "$1" 2>/dev/null
}

# ============================================================================
# Test: Homepage
# ============================================================================

test_homepage() {
    echo "=== 1. Homepage ==="

    headers=$(get_headers "$SHOP_URL/")

    if [ "$VERBOSE" == "--verbose" ]; then
        echo "$headers"
        echo ""
    fi

    # HTTP Status
    status=$(echo "$headers" | head -1 | grep -oE "[0-9]{3}")
    if [ "$status" == "200" ]; then
        check_pass "HTTP Status: $status"
    else
        check_fail "HTTP Status: $status (erwartet: 200)"
    fi

    # Cache-Control
    cache_control=$(echo "$headers" | grep -i "^cache-control:" | head -1)
    if [ -n "$cache_control" ]; then
        if echo "$cache_control" | grep -qi "public"; then
            check_pass "Cache-Control: public gesetzt"
        else
            check_warn "Cache-Control: private (CDN cached nicht)"
        fi
    else
        check_warn "Cache-Control Header fehlt"
    fi

    # CDN Status
    cf_status=$(echo "$headers" | grep -i "^cf-cache-status:" | head -1)
    bunny_status=$(echo "$headers" | grep -i "^cdn-cache:" | head -1)

    if [ -n "$cf_status" ]; then
        status_value=$(echo "$cf_status" | cut -d: -f2 | tr -d ' ')
        if [ "$status_value" == "HIT" ]; then
            check_pass "Cloudflare: HIT (aus Cache)"
        elif [ "$status_value" == "MISS" ]; then
            check_warn "Cloudflare: MISS (nicht im Cache)"
        elif [ "$status_value" == "BYPASS" ]; then
            check_warn "Cloudflare: BYPASS (Caching deaktiviert)"
        else
            echo "  Cloudflare Status: $status_value"
        fi
    elif [ -n "$bunny_status" ]; then
        echo "  Bunny CDN Status: $bunny_status"
    else
        check_warn "Kein CDN-Status Header gefunden"
    fi

    echo ""
}

# ============================================================================
# Test: Statische Assets
# ============================================================================

test_static_assets() {
    echo "=== 2. Statische Assets ==="

    # CSS-Datei finden
    css_url=$(curl -s "$SHOP_URL/" | grep -oE 'href="[^"]+\.css[^"]*"' | head -1 | sed 's/href="//;s/"//')

    if [ -n "$css_url" ]; then
        # Relative URL zu absoluter machen
        if [[ "$css_url" == /* ]]; then
            css_url="${SHOP_URL}${css_url}"
        elif [[ "$css_url" != http* ]]; then
            css_url="${SHOP_URL}/${css_url}"
        fi

        echo "Test-URL: $css_url"

        headers=$(get_headers "$css_url")

        if [ "$VERBOSE" == "--verbose" ]; then
            echo "$headers"
            echo ""
        fi

        # Cache-Control mit max-age
        cache_control=$(echo "$headers" | grep -i "^cache-control:" | head -1)
        if echo "$cache_control" | grep -qE "max-age=[0-9]+"; then
            max_age=$(echo "$cache_control" | grep -oE "max-age=[0-9]+" | cut -d= -f2)
            if [ "$max_age" -ge 31536000 ]; then
                check_pass "max-age: $max_age (1 Jahr+)"
            elif [ "$max_age" -ge 86400 ]; then
                check_warn "max-age: $max_age (nur $(($max_age/86400)) Tage)"
            else
                check_fail "max-age: $max_age (zu kurz!)"
            fi
        else
            check_fail "max-age nicht gesetzt"
        fi

        # immutable Flag
        if echo "$cache_control" | grep -qi "immutable"; then
            check_pass "immutable Flag gesetzt"
        else
            check_warn "immutable Flag fehlt (empfohlen für versionierte Assets)"
        fi

        # Compression
        content_encoding=$(echo "$headers" | grep -i "^content-encoding:" | head -1)
        if [ -n "$content_encoding" ]; then
            check_pass "Komprimierung: $content_encoding"
        else
            check_warn "Keine Komprimierung (gzip/br)"
        fi
    else
        check_warn "Keine CSS-Datei gefunden zum Testen"
    fi

    echo ""
}

# ============================================================================
# Test: Bilder
# ============================================================================

test_images() {
    echo "=== 3. Bilder ==="

    # Bild-URL finden
    img_url=$(curl -s "$SHOP_URL/" | grep -oE 'src="[^"]+\.(jpg|png|webp)[^"]*"' | head -1 | sed 's/src="//;s/"//')

    if [ -n "$img_url" ]; then
        if [[ "$img_url" == /* ]]; then
            img_url="${SHOP_URL}${img_url}"
        elif [[ "$img_url" != http* ]]; then
            img_url="${SHOP_URL}/${img_url}"
        fi

        echo "Test-URL: $img_url"

        headers=$(get_headers "$img_url")

        # Cache-Control
        cache_control=$(echo "$headers" | grep -i "^cache-control:" | head -1)
        if echo "$cache_control" | grep -qE "max-age=[0-9]+"; then
            max_age=$(echo "$cache_control" | grep -oE "max-age=[0-9]+" | cut -d= -f2)
            if [ "$max_age" -ge 31536000 ]; then
                check_pass "Bild-Cache: $max_age Sekunden"
            else
                check_warn "Bild-Cache nur $max_age Sekunden"
            fi
        else
            check_fail "Bild max-age nicht gesetzt"
        fi

        # Content-Type
        content_type=$(echo "$headers" | grep -i "^content-type:" | head -1)
        if echo "$content_type" | grep -qi "webp"; then
            check_pass "WebP Format"
        else
            echo "  Format: $content_type"
        fi
    else
        check_warn "Keine Bilder gefunden zum Testen"
    fi

    echo ""
}

# ============================================================================
# Test: Fonts (CORS)
# ============================================================================

test_fonts() {
    echo "=== 4. Fonts (CORS) ==="

    # Font-URL finden
    font_url=$(curl -s "$SHOP_URL/" | grep -oE 'href="[^"]+\.woff2[^"]*"' | head -1 | sed 's/href="//;s/"//')

    if [ -z "$font_url" ]; then
        # Versuche aus CSS zu extrahieren
        css_url=$(curl -s "$SHOP_URL/" | grep -oE 'href="[^"]+\.css[^"]*"' | head -1 | sed 's/href="//;s/"//')
        if [ -n "$css_url" ]; then
            if [[ "$css_url" == /* ]]; then
                css_url="${SHOP_URL}${css_url}"
            fi
            font_url=$(curl -s "$css_url" | grep -oE 'url\([^)]+\.woff2[^)]*\)' | head -1 | sed 's/url(//;s/)//;s/"//g;s/'\''//g')
        fi
    fi

    if [ -n "$font_url" ]; then
        if [[ "$font_url" == /* ]]; then
            font_url="${SHOP_URL}${font_url}"
        elif [[ "$font_url" != http* ]]; then
            font_url="${SHOP_URL}/${font_url}"
        fi

        echo "Test-URL: $font_url"

        # Mit Origin-Header testen (CORS)
        headers=$(curl -sI -H "Origin: ${SHOP_URL}" "$font_url" 2>/dev/null)

        # Access-Control-Allow-Origin
        cors=$(echo "$headers" | grep -i "^access-control-allow-origin:" | head -1)
        if [ -n "$cors" ]; then
            check_pass "CORS Header: $cors"
        else
            check_fail "CORS Header fehlt (Fonts werden blockiert!)"
        fi
    else
        check_warn "Keine Font-Datei gefunden zum Testen"
    fi

    echo ""
}

# ============================================================================
# Test: Bypass-Bereiche
# ============================================================================

test_bypass() {
    echo "=== 5. Bypass-Bereiche ==="

    # Checkout sollte nicht gecached werden
    checkout_url="${SHOP_URL}/checkout/cart"

    headers=$(get_headers "$checkout_url")

    cache_control=$(echo "$headers" | grep -i "^cache-control:" | head -1)
    if echo "$cache_control" | grep -qiE "(private|no-store|no-cache)"; then
        check_pass "Checkout: Nicht gecached"
    else
        check_fail "Checkout: Könnte gecached werden! (Sicherheitsrisiko)"
    fi

    # CDN Bypass?
    cf_status=$(echo "$headers" | grep -i "^cf-cache-status:" | head -1)
    if echo "$cf_status" | grep -qi "BYPASS\|DYNAMIC"; then
        check_pass "CDN: Bypass für Checkout"
    fi

    echo ""
}

# ============================================================================
# Zusammenfassung
# ============================================================================

echo "==========================================="
echo "=== Zusammenfassung ==="
echo "==========================================="
echo ""
echo -e "${GREEN}Bestanden: $PASS${NC}"
echo -e "${YELLOW}Warnungen: $WARN${NC}"
echo -e "${RED}Fehler:    $FAIL${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}CDN-Konfiguration hat kritische Probleme!${NC}"
    exit 1
elif [ $WARN -gt 0 ]; then
    echo -e "${YELLOW}CDN funktioniert, aber mit Optimierungspotential.${NC}"
    exit 0
else
    echo -e "${GREEN}CDN-Konfiguration ist optimal!${NC}"
    exit 0
fi

# ============================================================================
# Tests ausführen
# ============================================================================

test_homepage
test_static_assets
test_images
test_fonts
test_bypass
