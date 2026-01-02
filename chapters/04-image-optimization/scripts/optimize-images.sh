#!/bin/bash
#
# Bildoptimierungs-Skript
# Kapitel 4: Bildoptimierung
#
# Optimiert JPEG/PNG-Bilder und erstellt WebP-Versionen
#
# Voraussetzungen:
#   - ImageMagick: sudo apt install imagemagick
#   - WebP: sudo apt install webp
#   - pngquant: sudo apt install pngquant
#
# Verwendung:
#   ./optimize-images.sh /pfad/zu/bildern
#   ./optimize-images.sh /pfad/zu/bildern --dry-run
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -e

# Konfiguration
MAX_WIDTH=2000
MAX_HEIGHT=2000
JPEG_QUALITY=80
WEBP_QUALITY=80
PNG_QUALITY="65-80"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Argumente parsen
INPUT_DIR="${1:-.}"
DRY_RUN=false

if [[ "$2" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN - Keine Änderungen werden durchgeführt${NC}\n"
fi

# Prüfen ob Tools installiert sind
check_dependencies() {
    local missing=()

    command -v convert >/dev/null 2>&1 || missing+=("imagemagick")
    command -v cwebp >/dev/null 2>&1 || missing+=("webp")
    command -v pngquant >/dev/null 2>&1 || missing+=("pngquant")

    if [[ ${#missing[@]} -ne 0 ]]; then
        echo -e "${RED}Fehlende Abhängigkeiten:${NC}"
        echo "sudo apt install ${missing[*]}"
        exit 1
    fi
}

# Statistiken
TOTAL_BEFORE=0
TOTAL_AFTER=0
FILES_PROCESSED=0

# Dateigröße in Bytes
get_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null
}

# Menschenlesbare Größe
human_size() {
    local bytes=$1
    if [[ ${bytes} -ge 1048576 ]]; then
        echo "$(echo "scale=2; ${bytes}/1048576" | bc) MB"
    elif [[ ${bytes} -ge 1024 ]]; then
        echo "$(echo "scale=2; ${bytes}/1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# JPEG optimieren
optimize_jpeg() {
    local file="$1"
    local before
    before=$(get_size "${file}")

    echo -e "${BLUE}JPEG:${NC} ${file}"
    echo -n "  Vorher: $(human_size ${before})"

    if [[ "${DRY_RUN}" = false ]]; then
        # Resize wenn größer als MAX
        convert "${file}" \
            -resize "${MAX_WIDTH}x${MAX_HEIGHT}>" \
            -quality ${JPEG_QUALITY} \
            -strip \
            -interlace Plane \
            "${file}"

        local after
        after=$(get_size "${file}")
        local saved=$((before - after))
        local percent=$((saved * 100 / before))

        echo -e " → Nachher: $(human_size ${after}) ${GREEN}(-${percent}%)${NC}"

        TOTAL_BEFORE=$((TOTAL_BEFORE + before))
        TOTAL_AFTER=$((TOTAL_AFTER + after))
    else
        echo " → [DRY RUN]"
    fi

    FILES_PROCESSED=$((FILES_PROCESSED + 1))
}

# PNG optimieren
optimize_png() {
    local file="$1"
    local before
    before=$(get_size "${file}")

    echo -e "${BLUE}PNG:${NC} ${file}"
    echo -n "  Vorher: $(human_size ${before})"

    if [[ "${DRY_RUN}" = false ]]; then
        # Resize wenn größer als MAX
        convert "${file}" \
            -resize "${MAX_WIDTH}x${MAX_HEIGHT}>" \
            "${file}"

        # PNG-spezifische Optimierung
        pngquant --quality=${PNG_QUALITY} --strip --ext .png --force "${file}" 2>/dev/null || true

        local after
        after=$(get_size "${file}")
        local saved=$((before - after))
        local percent=$((saved * 100 / before))

        echo -e " → Nachher: $(human_size ${after}) ${GREEN}(-${percent}%)${NC}"

        TOTAL_BEFORE=$((TOTAL_BEFORE + before))
        TOTAL_AFTER=$((TOTAL_AFTER + after))
    else
        echo " → [DRY RUN]"
    fi

    FILES_PROCESSED=$((FILES_PROCESSED + 1))
}

# WebP erstellen
create_webp() {
    local file="$1"
    local webp_file="${file%.*}.webp"

    if [[ -f "${webp_file}" ]]; then
        echo -e "  ${YELLOW}WebP existiert bereits${NC}"
        return
    fi

    if [[ "${DRY_RUN}" = false ]]; then
        cwebp -q ${WEBP_QUALITY} "${file}" -o "${webp_file}" 2>/dev/null

        local original webp_size
        original=$(get_size "${file}")
        webp_size=$(get_size "${webp_file}")
        local saved=$((original - webp_size))
        local percent=$((saved * 100 / original))

        echo -e "  ${GREEN}WebP erstellt:${NC} $(human_size ${webp_size}) ${GREEN}(-${percent}% vs Original)${NC}"
    else
        echo -e "  ${YELLOW}WebP würde erstellt: ${webp_file}${NC}"
    fi
}

# Hauptlogik
main() {
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         BILDOPTIMIERUNG - Kapitel 4                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Verzeichnis: ${INPUT_DIR}"
    echo "Max. Größe: ${MAX_WIDTH}×${MAX_HEIGHT}"
    echo "JPEG-Qualität: ${JPEG_QUALITY}%"
    echo "WebP-Qualität: ${WEBP_QUALITY}%"
    echo ""

    check_dependencies

    # Alle Bilder finden und verarbeiten
    find "${INPUT_DIR}" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) | while read -r file; do
        optimize_jpeg "${file}"
        create_webp "${file}"
        echo ""
    done

    find "${INPUT_DIR}" -type f -iname "*.png" | while read -r file; do
        optimize_png "${file}"
        create_webp "${file}"
        echo ""
    done

    # Zusammenfassung
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   ZUSAMMENFASSUNG                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Dateien verarbeitet: ${FILES_PROCESSED}"

    if [[ "${DRY_RUN}" = false ]] && [[ ${TOTAL_BEFORE} -gt 0 ]]; then
        local total_saved=$((TOTAL_BEFORE - TOTAL_AFTER))
        local total_percent=$((total_saved * 100 / TOTAL_BEFORE))

        echo "Vorher gesamt: $(human_size ${TOTAL_BEFORE})"
        echo "Nachher gesamt: $(human_size ${TOTAL_AFTER})"
        echo -e "${GREEN}Eingespart: $(human_size ${total_saved}) (-${total_percent}%)${NC}"
    fi

    echo ""
    echo -e "${GREEN}Fertig!${NC}"
}

main
