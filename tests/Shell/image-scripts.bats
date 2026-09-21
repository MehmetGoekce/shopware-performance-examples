#!/usr/bin/env bats
#
# Tests für chapters/04-image-optimization/scripts/optimize-images.sh
#
# ImageMagick, pngquant und cwebp sind durch Stubs ersetzt (MAGICK,
# PNGQUANT, CWEBP). Der Stub für ImageMagick schreibt seine Argumente
# nach magick.log, kopiert 600 Byte der Eingabe (MAGICK_BYTES) und
# scheitert bei leeren Dateien – wie convert bei einem leeren JPEG.
# Mit echten Werkzeugen (Ubuntu 24.04: ImageMagick 6.9, pngquant, cwebp)
# von Hand geprüft: Drehung, sRGB, keine Metadaten, JPEG progressiv,
# PNG nicht interlaced.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../chapters/04-image-optimization/scripts/optimize-images.sh"
    TMP="$(mktemp -d)"
    SRC="$TMP/src"
    DST="$TMP/out"
    mkdir -p "$SRC/sub" "$TMP/bin"

    cat > "$TMP/bin/magick" <<'EOF'
#!/usr/bin/env bash
in="$1"; out="${!#}"
echo "$*" >> "$(dirname "$0")/magick.log"
[[ -s "$in" ]] || { echo "insufficient image data" >&2; exit 1; }
if [[ -n "${MAGICK_BYTES:-}" ]]; then head -c "$MAGICK_BYTES" /dev/zero > "$out"; else head -c 600 "$in" > "$out"; fi
EOF
    cat > "$TMP/bin/pngquant" <<'EOF'
#!/usr/bin/env bash
# PNGQUANT_EXIT steuert das Ergebnis; 0 schreibt eine kleinere Datei
out=""; prev=""
for a in "$@"; do [[ "$prev" == "--output" ]] && out="$a"; prev="$a"; done
rc="${PNGQUANT_EXIT:-0}"
[[ "$rc" -eq 0 ]] && head -c 100 "${!#}" > "$out"
exit "$rc"
EOF
    cat > "$TMP/bin/cwebp" <<'EOF'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
echo "$*" >> "$(dirname "$0")/cwebp.log"
echo webp > "$out"
EOF
    chmod +x "$TMP/bin/"*
    export MAGICK="$TMP/bin/magick" PNGQUANT="$TMP/bin/pngquant" CWEBP="$TMP/bin/cwebp"
    echo icc > "$TMP/sRGB.icc"
    export SRGB_ICC="$TMP/sRGB.icc"
    LOG="$TMP/bin/magick.log"

    head -c 2000 /dev/urandom > "$SRC/a.jpg"
    head -c 2000 /dev/urandom > "$SRC/sub/b.png"
    head -c 2000 /dev/urandom > "$SRC/mit leer
zeichen.JPEG"
}

teardown() {
    rm -rf "$TMP"
}

@test "--help zeigt Usage und endet mit 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: optimize-images.sh"* ]]
}

@test "ohne QUELLE und ZIEL: Usage und Exit 1" {
    run bash "$SCRIPT" "$SRC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ZIEL in QUELLE wird abgelehnt und hinterlässt keinen Ordner" {
    run bash "$SCRIPT" "$SRC" "$SRC/out"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ZIEL darf nicht in QUELLE liegen"* ]]
    [ ! -e "$SRC/out" ]
}

@test "verarbeitet alle Dateien, auch mit Leerzeichen und Zeilenumbruch im Namen" {
    run bash "$SCRIPT" "$SRC" "$DST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verarbeitet: 3, uebersprungen: 0, fehlgeschlagen: 0"* ]]
    [ -f "$DST/a.jpg" ]
    [ -f "$DST/sub/b.png" ]
    [ -f "$DST/mit leer
zeichen.JPEG" ]
}

@test "Originale bleiben unverändert" {
    before="$(cat "$SRC/a.jpg" "$SRC/sub/b.png" | cksum)"
    run bash "$SCRIPT" "$SRC" "$DST"
    [ "$(cat "$SRC/a.jpg" "$SRC/sub/b.png" | cksum)" = "$before" ]
}

@test "leere Datei: Fehler gemeldet, Exit 2, die anderen laufen weiter" {
    : > "$SRC/leer.jpg"
    run bash "$SCRIPT" "$SRC" "$DST"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FEHLER: leer.jpg"* ]]
    [[ "$output" == *"Verarbeitet: 3, uebersprungen: 0, fehlgeschlagen: 1"* ]]
    [ ! -e "$DST/leer.jpg" ]
}

@test "zweiter Lauf überspringt alles und komprimiert nichts doppelt" {
    bash "$SCRIPT" "$SRC" "$DST"
    before="$(cksum < "$DST/a.jpg")"
    run bash "$SCRIPT" "$SRC" "$DST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verarbeitet: 0, uebersprungen: 3"* ]]
    [ "$(cksum < "$DST/a.jpg")" = "$before" ]
}

@test "--dry-run schreibt nichts und legt ZIEL nicht an" {
    run bash "$SCRIPT" --dry-run "$SRC" "$DST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verarbeitet: 3"* ]]
    [ ! -e "$DST" ]
    [ ! -e "$LOG" ]
}

@test "JPEG: drehen, nach sRGB, Metadaten weg, verkleinern, q80 progressiv" {
    run bash "$SCRIPT" "$SRC" "$DST"
    line="$(grep -F "$SRC/a.jpg" "$LOG")"
    [[ "$line" == *"-auto-orient -profile $SRGB_ICC -strip -resize 2000x2000> -quality 80 -interlace Plane $DST/a.jpg" ]]
}

@test "PNG: nicht interlaced, ohne JPEG-Qualität" {
    run bash "$SCRIPT" "$SRC" "$DST"
    line="$(grep -F "$SRC/sub/b.png" "$LOG")"
    [[ "$line" == *"-strip -resize 2000x2000> -interlace none $DST/sub/b.png" ]]
    [[ "$line" != *"Plane"* ]]
    [[ "$line" != *"-quality"* ]]
}

@test "ohne sRGB-Profil: Exit 1, nichts verarbeitet" {
    SRGB_ICC="$TMP/fehlt.icc" run bash "$SCRIPT" "$SRC" "$DST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sRGB-Profil fehlt"* ]]
    [ ! -e "$LOG" ]
}

@test "grössere Ausgabe wird als grösser gemeldet" {
    rm "$SRC/sub/b.png" "$SRC/mit leer
zeichen.JPEG"
    MAGICK_BYTES=3000 run bash "$SCRIPT" "$SRC" "$DST"
    [[ "$output" == *"a.jpg: 1 KB -> 2 KB (50% groesser)"* ]]
    [[ "$output" == *"Gesamt: 1 KB -> 2 KB (50% groesser)"* ]]
}

@test "summiert die Ersparnis (600 statt 2000 Byte je JPEG)" {
    rm "$SRC/sub/b.png"
    run bash "$SCRIPT" "$SRC" "$DST"
    [[ "$output" == *"Gesamt: 3 KB -> 1 KB (70% kleiner)"* ]]
}

@test "pngquant Exit 99 (Qualität nicht erreichbar) ist kein Fehler" {
    PNGQUANT_EXIT=99 run bash "$SCRIPT" "$SRC" "$DST"
    [ "$status" -eq 0 ]
    [ "$(wc -c < "$DST/sub/b.png")" -eq 600 ]
}

@test "pngquant Exit 1 ist ein Fehler" {
    PNGQUANT_EXIT=1 run bash "$SCRIPT" "$SRC" "$DST"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FEHLER: sub/b.png"* ]]
}

@test "--webp: foo.jpg und foo.png überschreiben sich nicht" {
    head -c 2000 /dev/urandom > "$SRC/sub/b.jpg"
    run bash "$SCRIPT" --webp "$SRC" "$DST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WebP uebersprungen"* ]]
    [ -f "$DST/sub/b.webp" ]
    [ -f "$DST/a.webp" ]
}

@test "--webp: WebP aus dem Original, nicht aus dem JPEG q80" {
    run bash "$SCRIPT" --webp "$SRC" "$DST"
    [ "$status" -eq 0 ]
    grep -qF -- "$SRC/a.jpg -auto-orient -profile $SRGB_ICC -strip -resize 2000x2000> $DST/a.jpg.src.png" "$LOG"
    grep -qF -- "-q 80 $DST/a.jpg.src.png -o $DST/a.webp" "$TMP/bin/cwebp.log"
    [ ! -e "$DST/a.jpg.src.png" ]
}
