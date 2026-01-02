#!/bin/bash
#
# Problem 2: HTTP-Cache nicht aktiv diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_URL="${1:-https://localhost}"

echo "=== Problem 2: HTTP-Cache Status ==="
echo ""
echo "Prüfe: ${SHOP_URL}"
echo ""

# Cache-Header abrufen
echo "1. Cache-Header prüfen..."
HEADERS=$(curl -sI "${SHOP_URL}" 2>/dev/null)

# Check Cache-Control
CACHE_CONTROL=$(echo "${HEADERS}" | grep -i "cache-control" | head -1)
if [[ -n "${CACHE_CONTROL}" ]]; then
    echo "   Cache-Control: ${CACHE_CONTROL#*: }"

    if echo "${CACHE_CONTROL}" | grep -qi "no-cache\|no-store\|private"; then
        echo "   ⚠ Cache ist deaktiviert oder private!"
        CACHE_OK=false
    elif echo "${CACHE_CONTROL}" | grep -qi "public\|max-age"; then
        echo "   ✓ Cache ist aktiviert"
        CACHE_OK=true
    else
        echo "   ⚠ Cache-Status unklar"
        CACHE_OK=false
    fi
else
    echo "   ✗ Kein Cache-Control Header gefunden!"
    CACHE_OK=false
fi

# Check X-Shopware-Cache
echo ""
echo "2. Shopware Cache-Header..."
SW_CACHE=$(echo "${HEADERS}" | grep -i "x-sw-cache\|x-shopware" | head -3)
if [[ -n "${SW_CACHE}" ]]; then
    echo "${SW_CACHE}" | while read -r line; do
        echo "   ${line}"
    done
else
    echo "   Keine Shopware Cache-Header gefunden"
fi

# Check Age Header (für CDN/Reverse Proxy)
echo ""
echo "3. Age Header (Cache-Alter)..."
AGE=$(echo "${HEADERS}" | grep -i "^age:" | head -1)
if [[ -n "${AGE}" ]]; then
    echo "   ${AGE}"
    echo "   ✓ Seite wird aus Cache geliefert"
else
    echo "   Kein Age Header - möglicherweise kein Cache-Hit"
fi

# Empfehlungen
echo ""
echo "=== Empfehlung ==="
echo ""

if [[ "${CACHE_OK}" = false ]]; then
    echo "HTTP-Cache aktivieren in config/packages/shopware.yaml:"
    echo ""
    cat << 'EOF'
shopware:
    http_cache:
        enabled: true
        default_ttl: 7200
        invalidation:
            delay: 0
            count: 250
        ignored_url_parameters:
            - 'gclid'
            - 'utm_source'
            - 'utm_medium'
            - 'utm_campaign'
EOF
    echo ""
    echo "Danach: bin/console cache:clear"
    exit 1
else
    echo "HTTP-Cache ist korrekt konfiguriert."
    exit 0
fi
