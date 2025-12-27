#!/bin/bash
#
# Problem 14: Fehlende Gzip-Kompression diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_URL="${1:-https://localhost}"

echo "=== Problem 14: Gzip-Kompression ==="
echo ""
echo "Prüfe: $SHOP_URL"
echo ""

# Gzip-Header prüfen
echo "1. Kompression für HTML..."
HTML_HEADERS=$(curl -sI -H "Accept-Encoding: gzip, deflate, br" "$SHOP_URL" 2>/dev/null)
HTML_ENCODING=$(echo "$HTML_HEADERS" | grep -i "content-encoding" | head -1)

if [ -n "$HTML_ENCODING" ]; then
    echo "   ✓ $HTML_ENCODING"
else
    echo "   ✗ Keine Kompression für HTML!"
fi

# CSS prüfen
echo ""
echo "2. Kompression für CSS..."
CSS_URL="$SHOP_URL/bundles/storefront/assets/css/base.css"
CSS_HEADERS=$(curl -sI -H "Accept-Encoding: gzip, deflate, br" "$CSS_URL" 2>/dev/null)
CSS_ENCODING=$(echo "$CSS_HEADERS" | grep -i "content-encoding" | head -1)

if [ -n "$CSS_ENCODING" ]; then
    echo "   ✓ $CSS_ENCODING"
else
    echo "   ⚠ Keine Kompression für CSS gefunden"
fi

# JS prüfen
echo ""
echo "3. Kompression für JavaScript..."
JS_URL="$SHOP_URL/bundles/storefront/assets/js/storefront.js"
JS_HEADERS=$(curl -sI -H "Accept-Encoding: gzip, deflate, br" "$JS_URL" 2>/dev/null)
JS_ENCODING=$(echo "$JS_HEADERS" | grep -i "content-encoding" | head -1)

if [ -n "$JS_ENCODING" ]; then
    echo "   ✓ $JS_ENCODING"
else
    echo "   ⚠ Keine Kompression für JS gefunden"
fi

# Größenvergleich
echo ""
echo "4. Größenvergleich (mit/ohne Kompression)..."

# Mit Kompression
SIZE_COMPRESSED=$(curl -s -H "Accept-Encoding: gzip" -w "%{size_download}" -o /dev/null "$SHOP_URL" 2>/dev/null)
# Ohne Kompression
SIZE_UNCOMPRESSED=$(curl -s -H "Accept-Encoding: identity" -w "%{size_download}" -o /dev/null "$SHOP_URL" 2>/dev/null)

if [ "$SIZE_COMPRESSED" -gt 0 ] && [ "$SIZE_UNCOMPRESSED" -gt 0 ]; then
    SAVINGS=$((100 - (SIZE_COMPRESSED * 100 / SIZE_UNCOMPRESSED)))
    echo "   Komprimiert:   $(numfmt --to=iec $SIZE_COMPRESSED 2>/dev/null || echo "${SIZE_COMPRESSED} bytes")"
    echo "   Unkomprimiert: $(numfmt --to=iec $SIZE_UNCOMPRESSED 2>/dev/null || echo "${SIZE_UNCOMPRESSED} bytes")"
    echo "   Ersparnis:     ${SAVINGS}%"
fi

# Brotli-Support prüfen
echo ""
echo "5. Brotli-Support (br)..."
BR_ENCODING=$(echo "$HTML_HEADERS" | grep -i "content-encoding" | grep -i "br")
if [ -n "$BR_ENCODING" ]; then
    echo "   ✓ Brotli wird unterstützt (beste Kompression)"
else
    echo "   ⚠ Brotli nicht aktiv (empfohlen für moderne Browser)"
fi

# Empfehlungen
echo ""
echo "=== Empfehlung ==="
echo ""

if [ -z "$HTML_ENCODING" ]; then
    echo "Kompression aktivieren:"
    echo ""
    echo "--- Nginx ---"
    cat << 'EOF'
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css text/xml text/javascript
           application/javascript application/json application/xml
           image/svg+xml;
EOF
    echo ""
    echo "--- Apache (.htaccess) ---"
    cat << 'EOF'
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/css
    AddOutputFilterByType DEFLATE text/javascript application/javascript
    AddOutputFilterByType DEFLATE application/json image/svg+xml
</IfModule>
EOF
    exit 1
else
    echo "Kompression ist aktiviert."
    exit 0
fi
