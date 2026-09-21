#!/bin/bash
#
# Bildgrössen-Analyse für Shopware 6
# Kapitel 2: Performance-Audit
#
# Zählt Originalbilder nach Format, listet die grössten über einer Schwelle
# und zeigt den WebP-Anteil. Liest nur, ändert nichts.
#
# public/media enthält die hochgeladenen Originale; an den Browser gehen meist
# die Thumbnails aus public/thumbnail. Ein grosses Original ist deshalb erst
# dann ein Problem, wenn es ungekürzt ausgeliefert wird (Network-Panel, Filter
# "Img"). Bildoptimierung: Kapitel 4.
#
# Verwendung:
#   ./analyze-images.sh [media-verzeichnis] [schwelle-kb]
#   ./analyze-images.sh /var/www/shopware/public/media 500
#
# Exit-Codes: 0 Analyse gelaufen, 1 Verzeichnis fehlt, 2 falscher Aufruf
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

show_usage() {
    echo "Usage: $0 [media-verzeichnis] [schwelle-kb]"
    echo ""
    echo "Defaults: public/media, 500 KB"
}

case "${1:-}" in
    -h|--help) show_usage; exit 0 ;;
    -*) echo "Unbekannte Option: $1" >&2; show_usage >&2; exit 2 ;;
esac
if [[ $# -gt 2 ]]; then
    show_usage >&2
    exit 2
fi

MEDIA_PATH="${1:-public/media}"
THRESHOLD_KB="${2:-500}"

if ! [[ "${THRESHOLD_KB}" =~ ^[0-9]+$ ]]; then
    echo "Fehler: Schwelle muss eine ganze Zahl in KB sein: ${THRESHOLD_KB}" >&2
    exit 2
fi
if [[ ! -d "${MEDIA_PATH}" ]]; then
    echo "Fehler: Verzeichnis nicht gefunden: ${MEDIA_PATH}" >&2
    exit 1
fi

# Anzahl Dateien mit einer der Endungen (Gross-/Kleinschreibung egal)
count_ext() {
    local expr=() ext
    for ext in "$@"; do
        [[ ${#expr[@]} -gt 0 ]] && expr+=(-o)
        expr+=(-iname "*.${ext}")
    done
    find "${MEDIA_PATH}" -type f \( "${expr[@]}" \) 2>/dev/null | grep -c . || true
}

JPG=$(count_ext jpg jpeg)
PNG=$(count_ext png)
GIF=$(count_ext gif)
WEBP=$(count_ext webp)
AVIF=$(count_ext avif)
TOTAL=$((JPG + PNG + GIF + WEBP + AVIF))

echo "Pfad:      ${MEDIA_PATH}"
echo "Schwelle:  ${THRESHOLD_KB} KB"
echo ""
echo "Bilder gesamt: ${TOTAL}"
echo "  JPEG: ${JPG}"
echo "  PNG:  ${PNG}"
echo "  GIF:  ${GIF}"
echo "  WebP: ${WEBP}"
echo "  AVIF: ${AVIF}"

if [[ ${TOTAL} -eq 0 ]]; then
    echo ""
    echo "Keine Bilder gefunden (externer Speicher wie S3?)."
    exit 0
fi

# Grösste Dateien über der Schwelle (stat -c läuft mit GNU und BusyBox)
sizes=$(find "${MEDIA_PATH}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \) \
    -size "+${THRESHOLD_KB}k" -exec stat -c '%s %n' {} + 2>/dev/null | sort -rn) || true
LARGE=0
[[ -n "$sizes" ]] && LARGE=$(grep -c . <<< "$sizes")

echo ""
echo "Über ${THRESHOLD_KB} KB: ${LARGE} ($((LARGE * 100 / TOTAL)) %)"
if [[ ${LARGE} -gt 0 ]]; then
    echo "Die 20 grössten (Bytes, Pfad):"
    n=0
    while IFS= read -r line; do
        echo "  ${line}"
        n=$((n + 1))
        [[ $n -ge 20 ]] && break
    done <<< "$sizes"
fi

echo ""
if [[ $((WEBP + AVIF)) -eq 0 ]]; then
    echo "Keine WebP/AVIF-Dateien. Shopware erzeugt ab Werk Thumbnails im Format"
    echo "des Originals; WebP braucht ein Plugin oder eine Konvertierung vor dem Upload."
    echo "WebP ist laut Google-Studie 25-34 % kleiner als JPEG bei gleicher SSIM"
    echo "(developers.google.com/speed/webp/docs/webp_study). Wege: Kapitel 4."
fi
if [[ ${PNG} -gt $((TOTAL / 4)) ]]; then
    echo "PNG-Anteil über 25 %: PNG nur für Grafiken mit Transparenz,"
    echo "Fotos als JPEG, WebP oder AVIF."
fi
