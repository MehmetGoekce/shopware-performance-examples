#!/usr/bin/env bash
#
# generate-report.sh
#
# Schreibt die Ausgabe aller Diagnose-Skripte als Markdown-Report nach stdout.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Verwendung:
#   ./generate-report.sh [SHOP_URL] [SHOP_PATH] > performance-report.md
#
# Exit-Codes:
#   0 = alle Pruefungen unauffaellig
#   1 = mindestens eine Pruefung hat etwas gefunden
#   64 = Aufruffehler

set -uo pipefail

usage() {
    cat <<'USAGE'
Usage: generate-report.sh [SHOP_URL] [SHOP_PATH]

Fuehrt alle Diagnose-Skripte dieses Kapitels aus und schreibt das Ergebnis
als Markdown nach stdout.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis
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

SHOP_URL="${1:-http://localhost}"
SHOP_PATH="${2:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FINDINGS=0
CHECKED=0
declare -a FOUND_LIST=()

echo "# Shopware 6: Performance-Diagnose"
echo
echo "| | |"
echo "|---|---|"
echo "| Erstellt | $(date '+%Y-%m-%d %H:%M:%S %Z') |"
echo "| Shop-URL | ${SHOP_URL} |"
echo "| Shop-Pfad | ${SHOP_PATH} |"
echo "| Host | $(hostname) |"
echo
echo "Die Ausgaben stammen unveraendert aus den Diagnose-Skripten in"
echo "\`chapters/22-haeufigste-probleme/scripts/\`. Jede Ueberschrift verweist auf"
echo "den zugehoerigen Abschnitt in Kapitel 22."
echo
echo "---"
echo

run_check() {
    local name="$1" script="$2" number="$3" output status

    echo "## Problem ${number}: ${name}"
    echo

    if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
        echo "Skript \`${script}\` nicht gefunden."
        echo
        echo "---"
        echo
        return
    fi

    output=$(bash "${SCRIPT_DIR}/${script}" "${SHOP_URL}" "${SHOP_PATH}" 2>&1)
    status=$?
    CHECKED=$((CHECKED + 1))

    case "${status}" in
        0) echo "**Ergebnis:** unauffaellig" ;;
        1) echo "**Ergebnis:** etwas gefunden"
           FINDINGS=$((FINDINGS + 1))
           FOUND_LIST+=("Problem ${number}: ${name}") ;;
        *) echo "**Ergebnis:** Skript nicht ausfuehrbar (Exit ${status})" ;;
    esac

    echo
    echo '```'
    # Die Einzelskripte faerben ihre Ausgabe mit ANSI-Sequenzen. In einer
    # Markdown-Datei sind das Steuerzeichen, kein Text.
    printf '%s\n' "${output}" | sed -E $'s/\x1b\\[[0-9;]*m//g'
    echo '```'
    echo
    echo "---"
    echo
}

run_check "Langsame DB-Queries"        "diagnose-slow-queries.sh"  1
run_check "HTTP-Cache"                 "check-http-cache.sh"       2
run_check "JavaScript-Bundles"         "analyze-bundles.sh"        3
run_check "Bilder"                     "check-images.sh"           4
run_check "Preconnects"                "audit-preconnects.sh"      5
run_check "Render-Blocking"            "check-render-blocking.sh"  6
run_check "N+1-Queries"                "detect-n1-queries.sh"      7
run_check "Session-Lock"               "test-session-lock.sh"      8
run_check "Warenkorb-Berechnung"       "profile-cart.sh"           9
run_check "Plugins"                    "audit-plugins.sh"         10
run_check "Elasticsearch"              "check-elasticsearch.sh"   11
run_check "OPcache"                    "check-opcache.sh"         12
run_check "Debug-Modus"                "check-debug-mode.sh"      13
run_check "Kompression"                "check-compression.sh"     14
run_check "Cronjobs und Worker"        "analyze-cronjobs.sh"      15
run_check "Themes"                     "audit-themes.sh"          16
run_check "Log-Dateien"                "check-logs.sh"            17
run_check "CDN"                        "check-cdn.sh"             18
run_check "Synchrone API-Calls"        "detect-sync-calls.sh"     19
run_check "Browser-Cache-Header"       "check-cache-headers.sh"   20

echo "## Zusammenfassung"
echo
echo "${FINDINGS} von ${CHECKED} Pruefungen haben etwas gefunden."
echo

if [[ "${FINDINGS}" -gt 0 ]]; then
    for item in "${FOUND_LIST[@]}"; do
        echo "- ${item}"
    done
    echo
fi

cat <<'EOF'
Bewusst ohne Punktzahl und ohne Rangfolge: die Pruefungen sind weder gleich
gewichtet noch unabhaengig voneinander. Ein abgeschalteter HTTP-Cache wiegt
schwerer als ein fehlender Preconnect, und in einer Prozentzahl zaehlten beide
gleich viel.

Ebenso ohne pauschale Erwartungswerte wie "HTTP-Cache aktivieren spart 50 %
TTFB". Solche Zahlen haengen an Hardware, Datenmenge, Plugins und Trafficmuster;
was sie in Ihrem Shop wirklich bringen, zeigt nur eine Messung vorher und
nachher an derselben URL:

    for i in $(seq 20); do
        curl -s -o /dev/null -w '%{time_starttransfer}\n' https://ihr-shop.example/
    done | sort -n | awk '{v[NR]=$1} END {print "Median:", v[int((NR+1)/2)]}'

Die Erklaerungen zu jedem Punkt stehen in Kapitel 22 des Buchs
"Shop-Performance in 30 Tagen".

Professionelles Audit: https://memotech.ch/performance-check
EOF

[[ "${FINDINGS}" -gt 0 ]] && exit 1
exit 0
