#!/bin/bash
#
# Cache Warming Script - Fallstudie 1: Enterprise-Telekommunikation
# Kapitel 23: Reale Fallstudien aus 26 Jahren
#
# Wärmt HTTP-Cache für die wichtigsten Seiten vor.
# Reduziert TTFB für erste Besucher signifikant.
#

SHOP_URL="${1:-https://localhost}"
CONCURRENCY="${2:-5}"
LOG_FILE="${3:-/var/log/cache-warming.log}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

warm_url() {
    local url="$1"
    local response

    response=$(curl -s -o /dev/null -w "%{http_code}:%{time_total}" \
        -H "X-Cache-Warming: true" \
        "$url" 2>/dev/null)

    local status="${response%%:*}"
    local time="${response##*:}"

    if [ "$status" = "200" ]; then
        log "OK $url (${time}s)"
        return 0
    else
        log "FAIL $url (HTTP $status)"
        return 1
    fi
}

# Hauptseiten
log "=== Cache Warming Start ==="
log "Shop: $SHOP_URL"
log "Concurrency: $CONCURRENCY"

URLS=(
    "/"
    "/navigation"
    # Top-Kategorien (aus Sitemap oder Config anpassen)
    "/smartphones/"
    "/tablets/"
    "/zubehoer/"
    "/tarife/"
    # Wichtige Landingpages
    "/angebote/"
    "/neuheiten/"
)

# Kategorien aus Sitemap extrahieren (optional)
if command -v xmllint &> /dev/null; then
    log "Extrahiere URLs aus Sitemap..."
    SITEMAP_URLS=$(curl -s "$SHOP_URL/sitemap.xml" 2>/dev/null | \
        xmllint --xpath "//*[local-name()='loc']/text()" - 2>/dev/null | \
        head -50)

    for url in $SITEMAP_URLS; do
        URLS+=("${url#$SHOP_URL}")
    done
fi

# Paralleles Warming
log "Wärme ${#URLS[@]} URLs..."

SUCCESS=0
FAILED=0

for url in "${URLS[@]}"; do
    if warm_url "$SHOP_URL$url"; then
        ((SUCCESS++))
    else
        ((FAILED++))
    fi
done

log "=== Cache Warming Ende ==="
log "Erfolgreich: $SUCCESS"
log "Fehlgeschlagen: $FAILED"

# Exit-Code für Monitoring
if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
