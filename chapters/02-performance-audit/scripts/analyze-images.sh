#!/bin/bash
#
# Bildgrößen-Analyse für Shopware 6
# Kapitel 2: Performance-Audit
#
# Verwendung: ./analyze-images.sh /pfad/zu/media
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MEDIA_PATH="${1:-public/media}"
THRESHOLD_KB="${2:-500}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       BILDGRÖSSEN-ANALYSE                                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Pfad: ${MEDIA_PATH}"
echo "Schwellwert: ${THRESHOLD_KB}KB"
echo ""

if [[ ! -d "${MEDIA_PATH}" ]]; then
    echo -e "${RED}Fehler: Verzeichnis nicht gefunden: ${MEDIA_PATH}${NC}"
    exit 1
fi

# Statistiken sammeln
echo -e "${BLUE}Analysiere...${NC}"
echo ""

# Gesamtanzahl Bilder
TOTAL_IMAGES=$(find "${MEDIA_PATH}" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" \) 2>/dev/null | wc -l)

# Bilder über Schwellwert
LARGE_IMAGES=$(find "${MEDIA_PATH}" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) -size +${THRESHOLD_KB}k 2>/dev/null | wc -l)

# WebP-Bilder
WEBP_IMAGES=$(find "${MEDIA_PATH}" -type f -name "*.webp" 2>/dev/null | wc -l)

# Gesamt-Größe
TOTAL_SIZE=$(find "${MEDIA_PATH}" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)

echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ÜBERSICHT                                                    │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo "Gesamtanzahl Bilder: ${TOTAL_IMAGES}"
echo "Gesamt-Größe: ${TOTAL_SIZE}"
echo ""

# WebP-Status
echo -n "WebP-Bilder: "
if [[ "${WEBP_IMAGES}" -gt 0 ]]; then
    WEBP_PERCENT=$((WEBP_IMAGES * 100 / TOTAL_IMAGES))
    echo -e "${GREEN}${WEBP_IMAGES} (${WEBP_PERCENT}%) ✓${NC}"
else
    echo -e "${YELLOW}0 (WebP-Konvertierung empfohlen)${NC}"
fi

echo ""
echo -n "Bilder > ${THRESHOLD_KB}KB: "
if [[ "${LARGE_IMAGES}" -eq 0 ]]; then
    echo -e "${GREEN}0 ✓${NC}"
else
    LARGE_PERCENT=$((LARGE_IMAGES * 100 / TOTAL_IMAGES))
    echo -e "${RED}${LARGE_IMAGES} (${LARGE_PERCENT}%)${NC}"
fi

# Format-Verteilung
echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ FORMAT-VERTEILUNG                                            │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"
echo ""

JPG_COUNT=$(find "${MEDIA_PATH}" -type f \( -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
PNG_COUNT=$(find "${MEDIA_PATH}" -type f -name "*.png" 2>/dev/null | wc -l)
GIF_COUNT=$(find "${MEDIA_PATH}" -type f -name "*.gif" 2>/dev/null | wc -l)

echo "JPEG: ${JPG_COUNT}"
echo "PNG:  ${PNG_COUNT}"
echo "GIF:  ${GIF_COUNT}"
echo "WebP: ${WEBP_IMAGES}"

# Große Bilder auflisten
if [[ "${LARGE_IMAGES}" -gt 0 ]]; then
    echo ""
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│ GRÖßTE BILDER (TOP 20)                                       │${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    find "${MEDIA_PATH}" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) -size +${THRESHOLD_KB}k -exec ls -lhS {} \; 2>/dev/null | head -20 | awk '{print $5 "\t" $9}'
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       EMPFEHLUNGEN                                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "${LARGE_IMAGES}" -gt 0 ]]; then
    echo -e "${YELLOW}! ${LARGE_IMAGES} Bilder sind größer als ${THRESHOLD_KB}KB${NC}"
    echo "  → Diese Bilder komprimieren oder in WebP konvertieren"
    echo ""
fi

if [[ "${WEBP_IMAGES}" -eq 0 ]]; then
    echo -e "${YELLOW}! Keine WebP-Bilder gefunden${NC}"
    echo "  → WebP-Konvertierung spart 25-34% Dateigröße"
    echo "  → Shopware 6 unterstützt automatische WebP-Generierung"
    echo ""
fi

if [[ "${PNG_COUNT}" -gt "$((TOTAL_IMAGES / 4))" ]]; then
    echo -e "${YELLOW}! Hoher PNG-Anteil (${PNG_COUNT} Bilder)${NC}"
    echo "  → PNG nur für Grafiken mit Transparenz verwenden"
    echo "  → Fotos als JPEG oder WebP speichern"
    echo ""
fi

echo "Fertig."
