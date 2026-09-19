#!/usr/bin/env bash
#
# check-render-blocking.sh
#
# Problem 6: Render-Blocking CSS.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zaehlt Stylesheets und Skripte im <head>, die das erste Rendern aufhalten,
# und misst ihre uebertragene Groesse.
#
# Zur Messung: gemessen wird die *komprimierte* Groesse, denn die bestimmt die
# Uebertragungszeit. Dafuer braucht es ein GET mit Accept-Encoding; ein
# Content-Length aus einem HEAD-Request ist unzuverlaessig (bei chunked
# Transfer fehlt er ganz).
#
# Verwendung:
#   ./check-render-blocking.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = nichts Auffaelliges
#   1 = render-blockierende Ressourcen gefunden
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-render-blocking.sh [SHOP_URL] [SHOP_PATH]

Sucht im <head> nach Stylesheets und Skripten, die das erste Rendern aufhalten.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Wird nicht ausgewertet; nur der Einheitlichkeit halber.

Umgebungsvariablen:
  CSS_THRESHOLD_KB   Ab dieser komprimierten Groesse gilt ein Stylesheet als
                     gross. Default: 80 (das Standardtheme liegt bei rund 64)
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

# Aufrufkonvention aller Skripte dieses Kapitels: $1 = SHOP_URL, $2 = SHOP_PATH.
# Dieses Skript braucht nur die URL; $2 wird bewusst entgegengenommen und
# nicht ausgewertet, damit run-all-diagnostics.sh alle gleich aufrufen kann.
SHOP_URL="${1:-http://localhost}"
SHOP_URL="${SHOP_URL%/}"
# 80 statt 50: das unveraenderte Standardtheme liefert all.css mit rund
# 64 KB gzip. Mit 50 bekaeme jeder Shop ab Werk einen Fund, und "nichts
# Auffaelliges" waere nie erreichbar.
CSS_THRESHOLD_KB="${CSS_THRESHOLD_KB:-80}"

echo "=== Problem 6: Render-Blocking ==="
echo
echo "Prueft: ${SHOP_URL}"
echo

HTML=$(curl -sS -L "${SHOP_URL}/") || {
    echo "Shop nicht erreichbar: ${SHOP_URL}" >&2
    exit 1
}

HEAD_HTML=$(printf '%s\n' "${HTML}" | tr '\n' ' ' | grep -oE '<head.*</head>' || true)
if [[ -z "${HEAD_HTML}" ]]; then
    echo "Kein <head> gefunden — antwortet die URL ueberhaupt mit HTML?" >&2
    echo "Ohne Host-Header antwortet Shopware mit \"Sales Channel Not Found\"" >&2
    echo "— und zwar als HTTP 200." >&2
    exit 69
fi

absolutise() {
    case "$1" in
        http://*|https://*) printf '%s\n' "$1" ;;
        //*)                printf '%s:%s\n' "${SHOP_URL%%:*}" "$1" ;;
        /*)                 printf '%s%s\n' "${SHOP_URL}" "$1" ;;
        *)                  printf '%s/%s\n' "${SHOP_URL}" "$1" ;;
    esac
}

# Komprimierte Groesse in KB.
size_kb() {
    local bytes
    bytes=$(curl -sS -o /dev/null -L -H 'Accept-Encoding: gzip, br' -w '%{size_download}' "$1" 2>/dev/null || echo 0)
    echo $(( bytes / 1024 ))
}

ISSUES=0

echo "1. Stylesheets im <head>"
# Jeden <link ...>-Tag auf eine eigene Zeile bringen.
LINKS=$(printf '%s\n' "${HEAD_HTML}" | grep -oE '<link[^>]*>' || true)
CSS_TOTAL=0
while IFS= read -r link; do
    [[ -z "${link}" ]] && continue
    printf '%s' "${link}" | grep -q 'rel="stylesheet"' || continue
    href=$(printf '%s' "${link}" | grep -oE 'href="[^"]*"' | head -1 | sed 's/^href="//; s/"$//')
    [[ -z "${href}" ]] && continue
    CSS_TOTAL=$((CSS_TOTAL + 1))
    url=$(absolutise "${href}")
    name="${href##*/}"
    name="${name%%\?*}"
    if printf '%s' "${link}" | grep -qE 'media="print"|onload='; then
        printf '   %-34s nicht blockierend (asynchron geladen)\n' "${name}"
        continue
    fi
    kb=$(size_kb "${url}")
    if [[ "${kb}" -ge "${CSS_THRESHOLD_KB}" ]]; then
        printf '   %-34s blockiert, %s KB komprimiert\n' "${name}" "${kb}"
        printf '   %-34s (Standardtheme liegt bei rund 64 KB)\n' ""
        ISSUES=$((ISSUES + 1))
    else
        printf '   %-34s blockiert, %s KB komprimiert (klein)\n' "${name}" "${kb}"
    fi
done <<< "${LINKS}"
[[ "${CSS_TOTAL}" -eq 0 ]] && echo "   Keine Stylesheets im <head> gefunden."

echo
echo "2. Skripte im <head>"
SCRIPTS=$(printf '%s\n' "${HEAD_HTML}" | grep -oE '<script[^>]*>' || true)
JS_TOTAL=0
JS_BLOCKING=0
while IFS= read -r tag; do
    [[ -z "${tag}" ]] && continue
    printf '%s' "${tag}" | grep -q 'src=' || continue
    JS_TOTAL=$((JS_TOTAL + 1))
    src=$(printf '%s' "${tag}" | grep -oE 'src="[^"]*"' | head -1 | sed 's/^src="//; s/"$//')
    name="${src##*/}"
    name="${name%%\?*}"
    if printf '%s' "${tag}" | grep -qE '[[:space:]](async|defer|type="module")'; then
        printf '   %-34s nicht blockierend\n' "${name}"
    else
        printf '   %-34s BLOCKIERT das Parsen\n' "${name}"
        JS_BLOCKING=$((JS_BLOCKING + 1))
        ISSUES=$((ISSUES + 1))
    fi
done <<< "${SCRIPTS}"
[[ "${JS_TOTAL}" -eq 0 ]] && echo "   Keine externen Skripte im <head> gefunden."

echo
echo "3. Critical CSS"
if printf '%s' "${HEAD_HTML}" | grep -q '<style'; then
    INLINE_BYTES=$(printf '%s' "${HEAD_HTML}" | grep -oE '<style[^>]*>.*</style>' | wc -c)
    echo "   Inline-<style> im <head> vorhanden (${INLINE_BYTES} Byte roh)."
else
    echo "   Kein Inline-<style> im <head>."
    echo "   Mit Critical CSS rendert der Browser den sichtbaren Bereich, bevor"
    echo "   das grosse Stylesheet da ist. In Shopware fuehrt der Weg ueber ein"
    echo "   eigenes Theme/Plugin-Template:"
    echo "     src/Resources/views/storefront/layout/meta.html.twig"
    echo "   mit {% sw_extends '@Storefront/storefront/layout/meta.html.twig' %}"
    echo "   und einem ueberschriebenen Block layout_head_stylesheet."
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Nichts Auffaelliges im <head>."
    exit 0
fi

echo "${ISSUES} Punkt(e) halten das erste Rendern auf."
echo
if [[ "${JS_BLOCKING}" -gt 0 ]]; then
    echo "Skripte ohne async/defer im <head> stoppen den HTML-Parser, bis sie"
    echo "geladen und ausgefuehrt sind. Shopwares eigenes Storefront-JS laedt"
    echo "bereits mit defer; blockierende Skripte stammen meist aus Plugins oder"
    echo "aus von Hand eingefuegten Tracking-Snippets."
    echo
fi
cat <<'EOF'
Fuer grosse Stylesheets: nicht kritisches CSS asynchron nachladen, mit einem
Fallback fuer Besucher ohne JavaScript.

  <link rel="stylesheet" href="…" media="print" onload="this.media='all'">
  <noscript><link rel="stylesheet" href="…"></noscript>

Das media="print"-Muster ist dem rel="preload"-Muster vorzuziehen: es kommt
ohne zweiten Request aus und degradiert sauber.
EOF
exit 1
