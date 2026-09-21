#!/bin/bash
#
# extract-critical-css.sh — Critical CSS einer Seite als Twig-Include schreiben
#
# Nutzt `critical` ab Version 9 (Node.js >= 22.13). Die CLI hat sich mit
# v9 geändert: --base und --output gibt es nicht mehr (Abbruch mit
# «Unknown option»), die Ausgabe heisst -o/--out. Mit --inline liefert
# critical in jeder Version das komplette HTML, nicht das CSS — deshalb
# hier ohne --inline.
#
# Engine «render» (Standard) misst im echten Browser (Playwright) und
# liefert nur das CSS über dem Fold. Engine «static» kommt ohne Browser
# aus, liefert aber das CSS aller Elemente der Seite (eine Obermenge).
#
# Ergebnis: <views-dir>/critical/critical.css.twig, eingebunden von
# PerformanceTheme/src/Resources/views/storefront/layout/meta.html.twig.
#
# Usage: extract-critical-css.sh URL [--views-dir DIR] [--width PX] [--height PX] [--engine render|static]
#
# Exit-Codes: 0 ok, 1 Extraktion fehlgeschlagen, 2 Aufruf- oder Umgebungsfehler
#
# @see https://github.com/addyosmani/critical

set -euo pipefail

NPX="${NPX:-npx}"
NODE="${NODE:-node}"
CRITICAL_VERSION="${CRITICAL_VERSION:-9}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-latest}"

URL=""
VIEWS_DIR="./PerformanceTheme/src/Resources/views/storefront"
WIDTH=1300
HEIGHT=900
ENGINE="render"

usage() {
    cat <<EOF
Usage: $(basename "$0") URL [--views-dir DIR] [--width PX] [--height PX] [--engine render|static]

  URL               Seite, deren Above-the-fold-CSS extrahiert wird
  --views-dir DIR   Ziel: <DIR>/critical/critical.css.twig
                    (Standard: ${VIEWS_DIR})
  --width PX        Viewport-Breite (Standard: ${WIDTH})
  --height PX       Viewport-Höhe (Standard: ${HEIGHT})
  --engine NAME     render (Browser, Standard) oder static (ohne Browser, Obermenge)
  -h, --help        Diese Hilfe

Für --engine render einmalig: npx playwright install chromium
EOF
}

die() { echo "Fehler: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --views-dir) [[ $# -ge 2 ]] || die "--views-dir braucht einen Wert"; VIEWS_DIR="$2"; shift 2 ;;
        --width) [[ $# -ge 2 ]] || die "--width braucht einen Wert"; WIDTH="$2"; shift 2 ;;
        --height) [[ $# -ge 2 ]] || die "--height braucht einen Wert"; HEIGHT="$2"; shift 2 ;;
        --engine) [[ $# -ge 2 ]] || die "--engine braucht einen Wert"; ENGINE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *) [[ -z "$URL" ]] || die "Nur eine URL erlaubt"; URL="$1"; shift ;;
    esac
done

[[ -n "$URL" ]] || { usage >&2; exit 2; }
[[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]] || die "--width/--height müssen ganze Zahlen sein"
[[ "$ENGINE" == render || "$ENGINE" == static ]] || die "--engine muss render oder static sein"
[[ -d "$VIEWS_DIR" ]] || die "Views-Verzeichnis fehlt: $VIEWS_DIR"

# critical 9 verlangt Node.js >= 22.13
node_version="$("$NODE" -p 'process.versions.node' 2>/dev/null)" || die "node fehlt"
IFS=. read -r major minor _ <<< "$node_version"
if (( major < 22 || (major == 22 && minor < 13) )); then
    die "critical ${CRITICAL_VERSION} braucht Node.js >= 22.13, gefunden: ${node_version}"
fi

packages=(-p "critical@${CRITICAL_VERSION}")
[[ "$ENGINE" == render ]] && packages+=(-p "playwright@${PLAYWRIGHT_VERSION}")

target_dir="${VIEWS_DIR}/critical"
target="${target_dir}/critical.css.twig"
mkdir -p "$target_dir"
tmp_css="$(mktemp)"
trap 'rm -f "$tmp_css" "${target}.part"' EXIT

echo "Extrahiere Critical CSS: ${URL} (${WIDTH}x${HEIGHT}, Engine ${ENGINE}) ..."
if ! "$NPX" --yes "${packages[@]}" critical "$URL" -e "$ENGINE" -w "$WIDTH" -h "$HEIGHT" -o "$tmp_css"; then
    echo "Extraktion fehlgeschlagen. Für --engine render: npx playwright install chromium" >&2
    exit 1
fi
[[ -s "$tmp_css" ]] || { echo "critical hat eine leere Datei geliefert" >&2; exit 1; }

# verbatim: Twig soll im CSS nie nach {{ oder {% suchen
{
    echo "{# Erzeugt von extract-critical-css.sh aus ${URL} (${WIDTH}x${HEIGHT}, ${ENGINE}) — nicht von Hand pflegen #}"
    echo "{% verbatim %}"
    cat "$tmp_css"
    echo
    echo "{% endverbatim %}"
} > "${target}.part"
mv "${target}.part" "$target"

raw="$(wc -c < "$tmp_css" | tr -d ' ')"
gz="$(gzip -9 -c "$tmp_css" | wc -c | tr -d ' ')"
awk -v r="$raw" -v g="$gz" 'BEGIN { printf "Critical CSS: %.1f KB, gzip %.1f KB\n", r / 1024, g / 1024 }'
echo "Geschrieben: ${target}"
echo "Danach: theme:compile nicht nötig, aber cache:clear; Schalter «criticalCss» in der Theme-Konfiguration einschalten."
