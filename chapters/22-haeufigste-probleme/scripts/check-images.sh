#!/bin/bash
#
# Problem 4: Unoptimierte Bilder
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Prüft Bildoptimierung: WebP, Größen, Lazy Loading.
#
# Verwendung: ./check-images.sh [SHOP_URL] [SHOP_PATH]
#

set -e

SHOP_URL="${1:-https://localhost}"
SHOP_PATH="${2:-.}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Schwellenwerte
MAX_IMAGE_SIZE_KB=500
LCP_IMAGE_SIZE_KB=100

echo "=== Bildoptimierung Check ==="
echo "URL: ${SHOP_URL}"
echo ""

ISSUES=0

# Check 1: WebP Support
echo -e "${BLUE}1. WebP Support${NC}"
echo -n "   Server liefert WebP... "

WEBP_RESPONSE=$(curl -sI -H "Accept: image/webp" "${SHOP_URL}" 2>/dev/null | grep -i "content-type" || echo "")

# Test mit einem Beispielbild
HTML=$(curl -s "${SHOP_URL}" 2>/dev/null | head -500)
FIRST_IMAGE=$(echo "${HTML}" | grep -oE 'src="[^"]*\.(jpg|jpeg|png|webp)[^"]*"' | head -1 | sed 's/src="//g' | sed 's/"//g')

if [[ -n "${FIRST_IMAGE}" ]]; then
    if [[ "${FIRST_IMAGE}" != http* ]]; then
        FIRST_IMAGE="${SHOP_URL}${FIRST_IMAGE}"
    fi

    # WebP-Version anfragen
    WEBP_CHECK=$(curl -sI -H "Accept: image/webp" "${FIRST_IMAGE}" 2>/dev/null | grep -i "content-type" | grep -i "webp" || echo "")

    if [[ -n "${WEBP_CHECK}" ]]; then
        echo -e "${GREEN}Ja${NC}"
    else
        echo -e "${YELLOW}Nein${NC}"
        echo "   Empfehlung: WebP-Konvertierung aktivieren"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "${YELLOW}Kein Testbild gefunden${NC}"
fi

# Check 2: Bildgrößen prüfen
echo ""
echo -e "${BLUE}2. Bildgrößen${NC}"

IMAGE_URLS=$(echo "${HTML}" | grep -oE 'src="[^"]*\.(jpg|jpeg|png|webp|gif)[^"]*"' | sed 's/src="//g' | sed 's/"//g' | head -10)

LARGE_IMAGES=0
for img_url in ${IMAGE_URLS}; do
    if [[ "${img_url}" != http* ]]; then
        img_url="${SHOP_URL}${img_url}"
    fi

    SIZE_HEADER=$(curl -sI "${img_url}" 2>/dev/null | grep -i "content-length" | awk '{print $2}' | tr -d '\r')

    if [[ -n "${SIZE_HEADER}" ]] && [[ "${SIZE_HEADER}" -gt 0 ]]; then
        SIZE_KB=$((SIZE_HEADER / 1024))
        BASENAME=$(basename "${img_url}" | cut -d'?' -f1 | cut -c1-30)

        if [[ "${SIZE_KB}" -gt "${MAX_IMAGE_SIZE_KB}" ]]; then
            echo -e "   ${RED}${SIZE_KB} KB${NC} - ${BASENAME}... (> ${MAX_IMAGE_SIZE_KB} KB)"
            LARGE_IMAGES=$((LARGE_IMAGES + 1))
        fi
    fi
done

if [[ "${LARGE_IMAGES}" -gt 0 ]]; then
    echo "   ${LARGE_IMAGES} Bild(er) über ${MAX_IMAGE_SIZE_KB} KB"
    ISSUES=$((ISSUES + 1))
else
    echo -e "   ${GREEN}Alle geprüften Bilder < ${MAX_IMAGE_SIZE_KB} KB${NC}"
fi

# Check 3: Lazy Loading
echo ""
echo -e "${BLUE}3. Lazy Loading${NC}"
echo -n "   loading='lazy' verwendet... "

LAZY_COUNT=$(echo "${HTML}" | grep -c 'loading="lazy"' || echo "0")
IMG_COUNT=$(echo "${HTML}" | grep -c '<img' || echo "0")

if [[ "${LAZY_COUNT}" -gt 0 ]]; then
    echo -e "${GREEN}Ja (${LAZY_COUNT} von ${IMG_COUNT} Bildern)${NC}"
else
    echo -e "${YELLOW}Nein${NC}"
    echo "   Empfehlung: loading='lazy' für Below-the-Fold Bilder"
    ISSUES=$((ISSUES + 1))
fi

# Check 4: Width/Height Attribute (CLS)
echo ""
echo -e "${BLUE}4. Width/Height Attribute (CLS)${NC}"
echo -n "   Dimensionen angegeben... "

DIMS_COUNT=$(echo "${HTML}" | grep -E '<img[^>]*(width|height)=' | wc -l || echo "0")

if [[ "${DIMS_COUNT}" -gt 0 ]]; then
    RATIO=$((DIMS_COUNT * 100 / IMG_COUNT))
    if [[ "${RATIO}" -gt 80 ]]; then
        echo -e "${GREEN}${RATIO}% der Bilder${NC}"
    else
        echo -e "${YELLOW}${RATIO}% der Bilder${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "${RED}Nein${NC}"
    echo "   Fehlende Dimensionen verursachen CLS!"
    ISSUES=$((ISSUES + 1))
fi

# Check 5: Lokale Medien-Ordner
echo ""
echo -e "${BLUE}5. Lokale Medien-Analyse${NC}"

if [[ -d "${SHOP_PATH}/public/media" ]]; then
    MEDIA_SIZE=$(du -sh "${SHOP_PATH}/public/media" 2>/dev/null | cut -f1)
    MEDIA_COUNT=$(find "${SHOP_PATH}/public/media" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.gif" \) 2>/dev/null | wc -l)
    WEBP_COUNT=$(find "${SHOP_PATH}/public/media" -type f -name "*.webp" 2>/dev/null | wc -l)

    echo "   Medien-Ordner: ${MEDIA_SIZE}"
    echo "   JPG/PNG/GIF: ${MEDIA_COUNT} Dateien"
    echo "   WebP: ${WEBP_COUNT} Dateien"

    if [[ "${WEBP_COUNT}" -lt "${MEDIA_COUNT}" ]]; then
        echo -e "   ${YELLOW}WebP-Konvertierung unvollständig${NC}"
    fi
else
    echo "   Medien-Ordner nicht gefunden"
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [[ "${ISSUES}" -eq 0 ]]; then
    echo -e "${GREEN}Bildoptimierung OK.${NC}"
    exit 0
else
    echo -e "${RED}${ISSUES} Problem(e) gefunden.${NC}"
    echo ""
    echo "Empfohlene Optimierungen:"
    echo "  1. WebP aktivieren (shopware.media.remote_thumbnails)"
    echo "  2. Bilder komprimieren (Squoosh, ImageOptim)"
    echo "  3. loading='lazy' für Below-the-Fold"
    echo "  4. width/height immer angeben"
    exit 1
fi
