#!/bin/bash
#
# analyze-bundle.sh — was die Storefront wirklich ausliefert
#
# Shopware kopiert das kompilierte Theme nach public/theme/<prefix>/:
#   css/all.css                   das gesamte Theme-CSS
#   js/<technical-name>/<name>.js Einstieg je Theme/Plugin, lädt auf jeder Seite
#   js/<technical-name>/*.<hash6>.js  Chunks, laden nur bei Bedarf
# Unter public/bundles/storefront/ liegt bis 6.7.10 KEIN Storefront-JavaScript.
# Ab 6.7.11 lädt jede Seite dort zusätzlich das Vite-Laufzeitmodul
# storefront/shopware/shopware.js; ist es vorhanden, zählt es zum Einstieg.
#
# Modus 1 (Standard): Dateien unter public/theme/<prefix>/ vermessen.
# Modus 2 (--stats):  bin/console bundle:dump, dann die Storefront mit
#                     Webpack-Statistik neu bauen und je Compiler einen
#                     webpack-bundle-analyzer-Report schreiben. Der
#                     Production-Build selbst schreibt weder stats.json
#                     noch Source Maps. Webpack schreibt dabei die dist/-
#                     Ordner von Storefront und Plugins neu (wie
#                     bin/build-storefront.sh), public/theme/ bleibt.
#
# Auf dem Shop-Server ausführen (liest SHOPWARE_ROOT); --url muss eine
# Domain des Sales Channels sein.
#
# Usage: analyze-bundle.sh [--url URL | --theme-dir DIR] [--stats]
#                          [--budget-js KB] [--budget-css KB]
#
# Exit-Codes: 0 ok, 1 Budget überschritten, 2 Aufruf- oder Umgebungsfehler
#
# @see ThemeCompiler.php (collectCompiledFiles, copyScriptFilesToTheme)
# @see webpack.config.js der Storefront (devtool: false, stats: 'minimal')

set -euo pipefail

SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
OUT_DIR="${OUT_DIR:-./bundle-report}"
CURL="${CURL:-curl}"
NPX="${NPX:-npx}"
ANALYZER_VERSION="${ANALYZER_VERSION:-4}"

URL=""
THEME_DIR=""
STATS=false
BUDGET_JS=""
BUDGET_CSS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [--url URL | --theme-dir DIR] [--stats] [--budget-js KB] [--budget-css KB]

  --url URL         Theme-Verzeichnis aus dem HTML dieser Seite ermitteln
  --theme-dir DIR   Theme-Verzeichnis direkt angeben (public/theme/<prefix>)
                    Ohne beides: neuestes public/theme/*/css/all.css
  --stats           Zusätzlich bundle:dump + Webpack-Statistik bauen und Reports
                    schreiben (braucht Node.js und npx; schreibt dist/ neu)
  --budget-js KB    Grenze für Einstiegs-JS, gzip, in KB (Exit 1 bei Überschreitung)
  --budget-css KB   Grenze für all.css, gzip, in KB (Exit 1 bei Überschreitung)
  -h, --help        Diese Hilfe

Umgebung: SHOPWARE_ROOT (${SHOPWARE_ROOT}), OUT_DIR (${OUT_DIR})
EOF
}

die() { echo "Fehler: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url) [[ $# -ge 2 ]] || die "--url braucht einen Wert"; URL="$2"; shift 2 ;;
        --theme-dir) [[ $# -ge 2 ]] || die "--theme-dir braucht einen Wert"; THEME_DIR="$2"; shift 2 ;;
        --stats) STATS=true; shift ;;
        --budget-js) [[ $# -ge 2 ]] || die "--budget-js braucht einen Wert"; BUDGET_JS="$2"; shift 2 ;;
        --budget-css) [[ $# -ge 2 ]] || die "--budget-css braucht einen Wert"; BUDGET_CSS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

for b in "$BUDGET_JS" "$BUDGET_CSS"; do
    [[ -z "$b" || "$b" =~ ^[0-9]+$ ]] || die "Budget muss eine ganze Zahl in KB sein: $b"
done

# Bytes → «123.4 KB», ohne bc
kb() { awk -v b="$1" 'BEGIN { printf "%.1f KB", b / 1024 }'; }
gz_bytes() { gzip -9 -c "$1" | wc -c | tr -d ' '; }
file_bytes() { wc -c < "$1" | tr -d ' '; }

# --- Theme-Verzeichnis bestimmen ------------------------------------------
if [[ -n "$URL" ]]; then
    html="$("$CURL" -fsSL "$URL")" || die "Seite nicht erreichbar: $URL"
    prefix="$(printf '%s' "$html" | grep -oE '/theme/[0-9a-f]{32}/css/all\.css' | head -n 1 | cut -d/ -f3 || true)"
    [[ -n "$prefix" ]] || die "Kein /theme/<prefix>/css/all.css im HTML von $URL (Domain des Sales Channels? Sonst antwortet Shopware mit «Sales Channel Not Found»)"
    THEME_DIR="${SHOPWARE_ROOT}/public/theme/${prefix}"
elif [[ -z "$THEME_DIR" ]]; then
    newest="$(ls -t "${SHOPWARE_ROOT}"/public/theme/*/css/all.css 2>/dev/null | head -n 1 || true)"
    [[ -n "$newest" ]] || die "Kein kompiliertes Theme unter ${SHOPWARE_ROOT}/public/theme/ (theme:compile gelaufen?)"
    THEME_DIR="$(dirname "$(dirname "$newest")")"
fi
[[ -f "${THEME_DIR}/css/all.css" ]] || die "Keine css/all.css in ${THEME_DIR}"

echo "Theme-Verzeichnis: ${THEME_DIR}"
echo

# --- CSS ------------------------------------------------------------------
css="${THEME_DIR}/css/all.css"
css_raw="$(file_bytes "$css")"
css_gz="$(gz_bytes "$css")"
echo "CSS (lädt auf jeder Seite)"
printf '  %-12s %-12s %s\n' "$(kb "$css_raw")" "gzip $(kb "$css_gz")" "css/all.css"
echo

# --- JavaScript -----------------------------------------------------------
entry_raw=0; entry_gz=0; chunk_raw=0; chunk_gz=0; chunks=0
echo "JavaScript-Einstieg (lädt auf jeder Seite)"
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    raw="$(file_bytes "$f")"; gz="$(gz_bytes "$f")"
    if [[ "$(basename "$f")" =~ \.[0-9a-f]{6}\.js$ ]]; then
        chunk_raw=$((chunk_raw + raw)); chunk_gz=$((chunk_gz + gz)); chunks=$((chunks + 1))
    else
        entry_raw=$((entry_raw + raw)); entry_gz=$((entry_gz + gz))
        printf '  %-12s %-12s %s\n' "$(kb "$raw")" "gzip $(kb "$gz")" "${f#"${THEME_DIR}/"}"
    fi
done < <(find "${THEME_DIR}/js" -name '*.js' -type f 2>/dev/null | sort)
# Ab 6.7.11: Vite-Laufzeitmodul, lädt auf jeder Seite als <script type="module">
runtime="${SHOPWARE_ROOT}/public/bundles/storefront/storefront/shopware/shopware.js"
if [[ -f "$runtime" ]]; then
    raw="$(file_bytes "$runtime")"; gz="$(gz_bytes "$runtime")"
    entry_raw=$((entry_raw + raw)); entry_gz=$((entry_gz + gz))
    printf '  %-12s %-12s %s\n' "$(kb "$raw")" "gzip $(kb "$gz")" "public/bundles/storefront/storefront/shopware/shopware.js (ab 6.7.11)"
fi
echo
echo "Chunks (laden nur, wenn die Seite das Plugin braucht)"
printf '  %s Dateien, %s, gzip %s\n' "$chunks" "$(kb "$chunk_raw")" "$(kb "$chunk_gz")"
echo "  Welche davon eine Seite lädt, zeigt nur der Browser (DevTools > Netzwerk, Lighthouse)."
echo
echo "Jede Seite mindestens: JS-Einstieg $(kb "$entry_raw") (gzip $(kb "$entry_gz")), CSS $(kb "$css_raw") (gzip $(kb "$css_gz"))"
echo "  Untergrenze: Chunks, die das Layout auf jeder Seite braucht (Header, Footer, Cookie-Banner), kommen dazu."

# --- Budget ---------------------------------------------------------------
rc=0
if [[ -n "$BUDGET_JS" ]] && (( entry_gz > BUDGET_JS * 1024 )); then
    echo "BUDGET: Einstiegs-JS gzip $(kb "$entry_gz") > ${BUDGET_JS} KB" >&2; rc=1
fi
if [[ -n "$BUDGET_CSS" ]] && (( css_gz > BUDGET_CSS * 1024 )); then
    echo "BUDGET: all.css gzip $(kb "$css_gz") > ${BUDGET_CSS} KB" >&2; rc=1
fi

# --- Modus 2: Webpack-Statistik -------------------------------------------
if [[ "$STATS" == true ]]; then
    app="${SHOPWARE_ROOT}/vendor/shopware/storefront/Resources/app/storefront"
    [[ -f "${app}/webpack.config.js" ]] || die "Storefront-App nicht gefunden: ${app}"
    command -v node >/dev/null || die "node fehlt (für --stats nötig)"
    mkdir -p "$OUT_DIR"
    out="$(cd "$OUT_DIR" && pwd)"
    echo
    echo "bin/console bundle:dump, dann Storefront mit Webpack-Statistik bauen (Production-Modus) ..."
    # Wie bin/build-storefront.sh: ohne bundle:dump fehlen seither aktivierte Plugins
    "${SHOPWARE_ROOT}/bin/console" bundle:dump > "${out}/bundle-dump.log" 2>&1 \
        || die "bundle:dump fehlgeschlagen, siehe ${out}/bundle-dump.log"
    # --stats=normal überstimmt stats: 'minimal' aus der Config; ohne das
    # enthält stats.json weder Assets noch Module.
    (cd "$app" && PROJECT_ROOT="$SHOPWARE_ROOT" NODE_ENV=production \
        "$NPX" webpack --config webpack.config.js --stats=normal --json="${out}/stats.json" > "${out}/webpack.log" 2>&1) \
        || die "Webpack-Build fehlgeschlagen, siehe ${out}/webpack.log"
    # Mit Theme- oder Plugin-JS ist stats.json ein Multi-Compiler-Ergebnis:
    # je Compiler ein eigener outputPath. webpack-bundle-analyzer kennt nur
    # ein Bundle-Verzeichnis, also je Compiler eine eigene Datei.
    node -e '
        const fs = require("fs");
        const [file, dir] = process.argv.slice(1);
        const s = JSON.parse(fs.readFileSync(file, "utf8"));
        const list = (s.children && s.children.length) ? s.children : [s];
        for (const c of list) {
            fs.writeFileSync(`${dir}/stats-${c.name}.json`, JSON.stringify(c));
            console.log(`${c.name}\t${c.outputPath}`);
        }' "${out}/stats.json" "$out" > "${out}/compilers.tsv"
    while IFS=$'\t' read -r name path; do
        "$NPX" --yes "webpack-bundle-analyzer@${ANALYZER_VERSION}" "${out}/stats-${name}.json" "$path" \
            -m static -r "${out}/report-${name}.html" --no-open > "${out}/analyzer-${name}.log" 2>&1 \
            || die "webpack-bundle-analyzer fehlgeschlagen, siehe ${out}/analyzer-${name}.log"
        echo "  Report: ${out}/report-${name}.html"
    done < "${out}/compilers.tsv"
    echo "  Im Report: stat = Quelltext der Module, parsed = ausgeliefert, gzip = übertragen."
fi

exit "$rc"
