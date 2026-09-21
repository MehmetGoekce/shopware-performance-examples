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
# Nachbearbeitung, beide im Testshop gemessen:
#  - URLs: critical übernimmt die Font-URLs aus all.css relativ
#    (../../<theme-id>/assets/...) und zusätzlich absolut mit dem Host,
#    gegen den extrahiert wurde. Inline im <style> zeigen die relativen
#    auf HTTP 404, die absoluten auf den Extraktions-Host (Staging!).
#    Beide werden zu /theme/... umgeschrieben.
#  - Schalter: Vor dem Lauf muss «criticalCss» aus sein; sonst enthält die
#    Seite das alte Critical CSS, und critical sammelt es mit ein. Das
#    Skript bricht dann ab (Erkennung über data-critical-css).
#  - Media Queries: critical 9 minifiziert mit lightningcss ohne
#    Browserziele und schreibt (min-width: 576px) als (width>=576px).
#    Safari/iOS < 16.4 und Chrome < 104 verwerfen das. lightningcss mit
#    den Zielen der Storefront (.browserslistrc, 6.6) schreibt es zurück.
#
# Läuft auf einem Rechner mit Node.js >= 22.13 (Dockware hat Node 20).
# Ergebnis: <views-dir>/critical/critical.css.twig — Standard ist das
# Theme im Companion-Checkout; danach auf den Server kopieren und dort
# bin/console cache:clear. Eingebunden von
# PerformanceTheme/src/Resources/views/storefront/layout/meta.html.twig.
#
# Usage: extract-critical-css.sh URL [--views-dir DIR] [--width PX] [--height PX] [--engine render|static]
#
# Exit-Codes: 0 ok, 1 Extraktion fehlgeschlagen, 2 Aufruf- oder Umgebungsfehler
#
# @see https://github.com/addyosmani/critical

set -euo pipefail

NPX="${NPX:-npx}"
CURL="${CURL:-curl}"
NODE="${NODE:-node}"
CRITICAL_VERSION="${CRITICAL_VERSION:-9}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-latest}"
LIGHTNINGCSS_VERSION="${LIGHTNINGCSS_VERSION:-1}"
# Browserziele der Storefront 6.6 (.browserslistrc: Safari/iOS >= 12, Chrome/Firefox >= 60)
CSS_TARGETS="${CSS_TARGETS:-safari 12, ios_saf 12, chrome 60, firefox 60}"

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

Läuft dort, wo Node.js >= 22.13 installiert ist (Dockware hat Node 20):
im Companion-Checkout erzeugen, dann die Datei ins Theme auf dem Server
kopieren und dort bin/console cache:clear.
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

# Enthält die Seite schon Critical CSS (Schalter «criticalCss» an), sammelt
# critical es mit ein: Das Ergebnis wächst mit jedem Lauf (gemessen: doppelt).
# Erst lesen, dann prüfen: `curl | grep -q` meldet unter pipefail einen Fehler,
# sobald grep früh beendet und curl SIGPIPE bekommt — die Prüfung schlüge nie an.
page_html="$("$CURL" -fsSL "$URL" 2>/dev/null || true)"
if [[ "$page_html" == *data-critical-css* ]]; then
    die "Die Seite enthält schon Critical CSS. Schalter «criticalCss» in der Theme-Konfiguration erst ausschalten (cache:clear), dann neu erzeugen."
fi

packages=(-p "critical@${CRITICAL_VERSION}")
[[ "$ENGINE" == render ]] && packages+=(-p "playwright@${PLAYWRIGHT_VERSION}")

target_dir="${VIEWS_DIR}/critical"
target="${target_dir}/critical.css.twig"
mkdir -p "$target_dir"
tmp_css="$(mktemp)"
tmp_urls="$(mktemp)"
tmp_final="$(mktemp)"
trap 'rm -f "$tmp_css" "$tmp_urls" "$tmp_final" "${target}.part"' EXIT


echo "Extrahiere Critical CSS: ${URL} (${WIDTH}x${HEIGHT}, Engine ${ENGINE}) ..."
if ! "$NPX" --yes "${packages[@]}" critical "$URL" -e "$ENGINE" -w "$WIDTH" -h "$HEIGHT" -o "$tmp_css"; then
    echo "Extraktion fehlgeschlagen. Für --engine render: npx playwright install chromium" >&2
    exit 1
fi
[[ -s "$tmp_css" ]] || { echo "critical hat eine leere Datei geliefert" >&2; exit 1; }

# URLs: ../../<theme-id>/... und <extraktions-host>/... → /theme/... bzw. /...
origin="$(printf '%s' "$URL" | grep -oE '^https?://[^/]+' || true)"
# Ein Origin enthält nur Schema, Host und Port; zu maskieren ist nur der Punkt
# (BusyBox-sed kennt keine Klammerausdrücke wie [][...]).
origin_re="${origin//./\\.}"
sed -E -e "s#url\((['\"]?)\.\./\.\./#url(\1/theme/#g" \
       -e "s#url\((['\"]?)${origin_re}/#url(\1/#g" "$tmp_css" > "$tmp_urls"

# Media Queries für die Browserziele der Storefront zurückschreiben
if ! "$NPX" --yes "lightningcss-cli@${LIGHTNINGCSS_VERSION}" --minify --targets "$CSS_TARGETS" -o "$tmp_final" "$tmp_urls"; then
    echo "lightningcss fehlgeschlagen" >&2
    exit 1
fi

# verbatim: Twig soll im CSS nie nach {{ oder {% suchen
{
    echo "{# Erzeugt von extract-critical-css.sh aus ${URL} (${WIDTH}x${HEIGHT}, ${ENGINE}) — nicht von Hand pflegen #}"
    echo "{% verbatim %}"
    cat "$tmp_final"
    echo
    echo "{% endverbatim %}"
} > "${target}.part"
mv "${target}.part" "$target"

raw="$(wc -c < "$tmp_final" | tr -d ' ')"
gz="$(gzip -9 -c "$tmp_final" | wc -c | tr -d ' ')"
awk -v r="$raw" -v g="$gz" 'BEGIN { printf "Critical CSS: %.1f KB, gzip %.1f KB\n", r / 1024, g / 1024 }'
echo "Geschrieben: ${target}"
echo "Danach: Datei ins Theme auf dem Server kopieren, dort cache:clear (theme:compile nicht nötig);"
echo "Schalter «criticalCss» in der Theme-Konfiguration einschalten."
