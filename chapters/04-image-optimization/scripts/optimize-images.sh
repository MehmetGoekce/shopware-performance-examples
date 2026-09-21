#!/usr/bin/env bash
#
# Bilder vor dem Upload optimieren
# Kapitel 4: Bildoptimierung
#
# Liest JPEG/PNG aus QUELLE und schreibt verkleinerte, neu komprimierte
# Fassungen nach ZIEL (gleiche Unterordner). Die Originale bleiben
# unangetastet; eine Datei, die im ZIEL schon liegt, wird uebersprungen –
# ein zweiter Lauf komprimiert also nichts doppelt.
#
# Was passiert:
#   - auf hoechstens 2000 x 2000 px verkleinern (nie vergroessern)
#   - EXIF-Ausrichtung anwenden
#   - nach sRGB umrechnen, dann alle Metadaten entfernen (EXIF, IPTC,
#     XMP, ICC). Ein Profil zu behalten hilft nicht: Shopware erzeugt
#     die Thumbnails mit GD, und GD verwirft es – ein Adobe-RGB-Bild
#     kaeme im srcset mit verschobenen Farben an.
#   - JPEG mit Qualitaet 80, progressiv
#   - PNG mit pngquant (verlustbehaftet, 65-80), falls installiert
#   - mit --webp zusaetzlich eine WebP-Fassung (cwebp -q 80), aus dem
#     Original erzeugt, nicht aus dem schon komprimierten JPEG
#
# Shopware erzeugt Thumbnails im Format des hochgeladenen Originals:
# ein WebP-Original ergibt WebP-Thumbnails (Kapitel 4).
#
# Voraussetzungen (Ubuntu/Debian, bash 4 oder neuer):
#   sudo apt install imagemagick pngquant webp colord-data
#   (colord-data liefert das sRGB-Profil; anderes Profil per SRGB_ICC=…)
#
# Verwendung:
#   ./optimize-images.sh [--dry-run] [--webp] QUELLE ZIEL
#
# Exit-Codes: 0 = ok, 1 = Aufruf/Werkzeug fehlt, 2 = einzelne Dateien fehlgeschlagen
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

MAX_SIZE=2000
JPEG_QUALITY=80
WEBP_QUALITY=80
PNG_QUALITY="65-80"

# Werkzeuge per Umgebung ueberschreibbar (Tests)
MAGICK="${MAGICK:-}"
PNGQUANT="${PNGQUANT:-pngquant}"
CWEBP="${CWEBP:-cwebp}"
SRGB_ICC="${SRGB_ICC:-/usr/share/color/icc/colord/sRGB.icc}"

usage() {
    cat <<'EOF'
Usage: optimize-images.sh [--dry-run] [--webp] QUELLE ZIEL

Optimiert JPEG/PNG aus QUELLE nach ZIEL, ohne die Originale zu aendern.

  --dry-run   nur anzeigen, was passieren wuerde
  --webp      zusaetzlich eine WebP-Fassung je Bild erzeugen
  -h, --help  diese Hilfe
EOF
}

DRY_RUN=false
WEBP=false
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --webp) WEBP=true ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unbekannte Option: $1" >&2; usage >&2; exit 1 ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done

if [[ ${#ARGS[@]} -ne 2 ]]; then
    usage >&2
    exit 1
fi

SRC="${ARGS[0]%/}"
DST="${ARGS[1]%/}"

if [[ ! -d "$SRC" ]]; then
    echo "Quelle ist kein Verzeichnis: $SRC" >&2
    exit 1
fi

# Absoluter Pfad, auch fuer ein noch nicht vorhandenes ZIEL (ohne es
# anzulegen; realpath -m fehlt unter BusyBox und macOS)
abs_path() {
    local dir="$1" rest=""
    while [[ ! -d "$dir" ]]; do
        rest="/$(basename "$dir")$rest"
        dir="$(dirname "$dir")"
    done
    echo "$(cd "$dir" && pwd -P)$rest"
}
SRC_ABS="$(abs_path "$SRC")"
DST_ABS="$(abs_path "$DST")"
case "$DST_ABS/" in
    "$SRC_ABS/"*)
        echo "ZIEL darf nicht in QUELLE liegen (sonst werden Originale ueberschrieben)." >&2
        exit 1 ;;
esac

# ImageMagick 7 heisst magick, 6 (Ubuntu 22.04/24.04) convert
if [[ -z "$MAGICK" ]]; then
    if command -v magick >/dev/null 2>&1; then
        MAGICK=magick
    elif command -v convert >/dev/null 2>&1; then
        MAGICK=convert
    else
        echo "ImageMagick fehlt: sudo apt install imagemagick" >&2
        exit 1
    fi
fi

if [[ ! -r "$SRGB_ICC" ]]; then
    echo "sRGB-Profil fehlt ($SRGB_ICC): sudo apt install colord-data" >&2
    exit 1
fi

HAVE_PNGQUANT=true
command -v "$PNGQUANT" >/dev/null 2>&1 || HAVE_PNGQUANT=false
if [[ "$WEBP" == true ]] && ! command -v "$CWEBP" >/dev/null 2>&1; then
    echo "cwebp fehlt: sudo apt install webp" >&2
    exit 1
fi

size_of() {
    stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}

processed=0
skipped=0
failed=0
bytes_before=0
bytes_after=0

optimize_one() {
    local in="$1" out="$2" ext="$3"
    # drehen, nach sRGB umrechnen, Metadaten weg, verkleinern
    local prep=(-auto-orient -profile "$SRGB_ICC" -strip -resize "${MAX_SIZE}x${MAX_SIZE}>")
    # progressiv nur fuer JPEG: -interlace Plane macht aus PNG Adam7, 30-45 % groesser
    local enc=(-interlace none)
    [[ "$ext" == "jpg" ]] && enc=(-quality "$JPEG_QUALITY" -interlace Plane)

    "$MAGICK" "$in" "${prep[@]}" "${enc[@]}" "$out" || return 1

    if [[ "$ext" == "png" && "$HAVE_PNGQUANT" == true ]]; then
        # Exit 99: Qualitaet unter 65 noetig – Datei bleibt ohne Quantisierung
        local rc=0
        "$PNGQUANT" --quality="$PNG_QUALITY" --skip-if-larger --force --output "$out.q" "$out" || rc=$?
        if [[ $rc -eq 0 && -f "$out.q" ]]; then
            mv "$out.q" "$out"
        else
            rm -f "$out.q"
            [[ $rc -eq 98 || $rc -eq 99 ]] || return 1
        fi
    fi

    if [[ "$WEBP" == true ]]; then
        # foo.jpg und foo.png ergaeben dieselbe foo.webp – nicht ueberschreiben
        if [[ -e "${out%.*}.webp" ]]; then
            echo "WebP uebersprungen (${out%.*}.webp gibt es schon): $in" >&2
        else
            # verlustfrei zwischenspeichern, damit nicht JPEG q80 -> WebP q80
            local rc=0
            "$MAGICK" "$in" "${prep[@]}" "$out.src.png" || rc=$?
            [[ $rc -eq 0 ]] && { "$CWEBP" -quiet -q "$WEBP_QUALITY" "$out.src.png" -o "${out%.*}.webp" || rc=$?; }
            rm -f "$out.src.png"
            [[ $rc -eq 0 ]] || return 1
        fi
    fi
}

while IFS= read -r -d '' in; do
    rel="${in#"$SRC"/}"
    out="$DST/$rel"
    ext="${in##*.}"
    ext="${ext,,}"
    [[ "$ext" == "jpeg" ]] && ext="jpg"

    if [[ -e "$out" ]]; then
        echo "uebersprungen (schon im Ziel): $rel"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "wuerde optimieren: $rel"
        processed=$((processed + 1))
        continue
    fi

    mkdir -p "$(dirname "$out")"
    before=$(size_of "$in")

    if optimize_one "$in" "$out" "$ext"; then
        after=$(size_of "$out")
        bytes_before=$((bytes_before + before))
        bytes_after=$((bytes_after + after))
        processed=$((processed + 1))
        if [[ $before -gt 0 && $after -le $before ]]; then
            echo "$rel: $((before / 1024)) KB -> $((after / 1024)) KB ($(( (before - after) * 100 / before ))% kleiner)"
        elif [[ $before -gt 0 ]]; then
            echo "$rel: $((before / 1024)) KB -> $((after / 1024)) KB ($(( (after - before) * 100 / before ))% groesser)"
        else
            echo "$rel: leere Datei"
        fi
    else
        echo "FEHLER: $rel" >&2
        rm -f "$out"
        failed=$((failed + 1))
    fi
done < <(find "$SRC" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 | sort -z)

echo
echo "Verarbeitet: $processed, uebersprungen: $skipped, fehlgeschlagen: $failed"
if [[ "$DRY_RUN" == false && $bytes_before -gt 0 && $bytes_after -le $bytes_before ]]; then
    echo "Gesamt: $((bytes_before / 1024)) KB -> $((bytes_after / 1024)) KB ($(( (bytes_before - bytes_after) * 100 / bytes_before ))% kleiner)"
elif [[ "$DRY_RUN" == false && $bytes_before -gt 0 ]]; then
    echo "Gesamt: $((bytes_before / 1024)) KB -> $((bytes_after / 1024)) KB ($(( (bytes_after - bytes_before) * 100 / bytes_before ))% groesser)"
fi
if [[ "$HAVE_PNGQUANT" == false ]]; then
    echo "Hinweis: pngquant nicht gefunden – PNG nur neu komprimiert, nicht quantisiert."
fi

[[ $failed -eq 0 ]] || exit 2
