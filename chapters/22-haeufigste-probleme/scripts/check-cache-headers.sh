#!/bin/bash
#
# Problem 20: Fehlende Browser-Caching-Header diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_URL="${1:-https://localhost}"

echo "=== Problem 20: Browser-Cache-Header ==="
echo ""
echo "Prüfe: ${SHOP_URL}"
echo ""

PROBLEMS=0

# CSS prüfen
echo "1. CSS-Dateien..."
CSS_URL="${SHOP_URL}/bundles/storefront/assets/css/base.css"
CSS_HEADERS=$(curl -sI "${CSS_URL}" 2>/dev/null)
CSS_CACHE=$(echo "${CSS_HEADERS}" | grep -i "cache-control\|expires" | head -2)

if [[ -n "${CSS_CACHE}" ]]; then
    echo "${CSS_CACHE}" | while read -r line; do echo "   ${line}"; done
    echo "   ✓ Cache-Header vorhanden"
else
    echo "   ✗ Keine Cache-Header für CSS!"
    PROBLEMS=$((PROBLEMS + 1))
fi

# JavaScript prüfen
echo ""
echo "2. JavaScript-Dateien..."
JS_URL="${SHOP_URL}/bundles/storefront/assets/js/storefront.js"
JS_HEADERS=$(curl -sI "${JS_URL}" 2>/dev/null)
JS_CACHE=$(echo "${JS_HEADERS}" | grep -i "cache-control\|expires" | head -2)

if [[ -n "${JS_CACHE}" ]]; then
    echo "${JS_CACHE}" | while read -r line; do echo "   ${line}"; done
    echo "   ✓ Cache-Header vorhanden"
else
    echo "   ✗ Keine Cache-Header für JS!"
    PROBLEMS=$((PROBLEMS + 1))
fi

# Bilder prüfen
echo ""
echo "3. Bilder..."
IMG_URL="${SHOP_URL}/media/image/shopware-logo.png"
IMG_HEADERS=$(curl -sI "${IMG_URL}" 2>/dev/null)
IMG_CACHE=$(echo "${IMG_HEADERS}" | grep -i "cache-control\|expires" | head -2)

if [[ -n "${IMG_CACHE}" ]]; then
    echo "${IMG_CACHE}" | while read -r line; do echo "   ${line}"; done
    echo "   ✓ Cache-Header vorhanden"
else
    echo "   ⚠ Keine Cache-Header für Bilder gefunden"
fi

# Fonts prüfen
echo ""
echo "4. Fonts..."
FONT_URL="${SHOP_URL}/bundles/storefront/assets/fonts/Inter-Regular.woff2"
FONT_HEADERS=$(curl -sI "${FONT_URL}" 2>/dev/null)
FONT_CACHE=$(echo "${FONT_HEADERS}" | grep -i "cache-control\|expires" | head -2)

if [[ -n "${FONT_CACHE}" ]]; then
    echo "${FONT_CACHE}" | while read -r line; do echo "   ${line}"; done
    echo "   ✓ Cache-Header vorhanden"
else
    echo "   ⚠ Fonts-URL möglicherweise anders"
fi

# Immutable prüfen
echo ""
echo "5. Immutable-Flag (best practice)..."
IMMUTABLE=$(curl -sI "${CSS_URL}" 2>/dev/null | grep -i "immutable")
if [[ -n "${IMMUTABLE}" ]]; then
    echo "   ✓ immutable-Flag gesetzt"
else
    echo "   ⚠ immutable-Flag nicht gesetzt"
    echo "     (Shopware nutzt Hash-basierte Dateinamen)"
fi

# Empfehlung
echo ""
echo "=== Empfehlung ==="
echo ""

if [[ ${PROBLEMS} -gt 0 ]]; then
    echo "Browser-Caching aktivieren:"
    echo ""
    echo "Für Apache (.htaccess):"
    echo "  → Siehe config/apache-compression.conf"
    echo ""
    echo "Für Nginx:"
    cat << 'EOF'
location ~* \.(css|js|woff|woff2|ttf|otf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}

location ~* \.(jpg|jpeg|png|gif|webp|svg|ico)$ {
    expires 1y;
    add_header Cache-Control "public";
}
EOF
    exit 1
else
    echo "Browser-Caching ist korrekt konfiguriert."
    exit 0
fi
