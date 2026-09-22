#!/usr/bin/env bash
#
# Lighthouse-Mobil-Test mit mehreren Laeufen und Median
# Kapitel 19: Mobile Performance
#
# Lighthouse emuliert ab Werk ein Mobilgeraet (412 x 823, DPR 1,75) und
# drosselt simuliert (Lantern: RTT 150 ms, 1,6 Mbit/s, CPU 4x) – dieselbe
# Einstellung wie PageSpeed Insights. Das Skript aendert daran nichts.
# --preset=perf wuerde auf echte DevTools-Drosselung umschalten; die Werte
# waeren dann nicht mehr mit PSI vergleichbar.
#
# Einzelne Laeufe streuen. Das Skript misst mehrmals und nennt den Median
# und die Spanne.
#
# INP misst Lighthouse bei einem Seitenaufruf nicht (nur im Timespan-Modus
# mit Interaktion). INP kommt aus Felddaten: CrUX/PageSpeed Insights oder
# eigenem RUM (Kapitel 12).
#
# Verwendung:
#   ./lighthouse-mobile.sh https://shop.example.com/
#   ./lighthouse-mobile.sh https://shop.example.com/ --runs=5 --output=./reports
#
# Voraussetzungen: Node.js, Lighthouse (npm install -g lighthouse), jq, Chrome/Chromium
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

LIGHTHOUSE="${LIGHTHOUSE:-lighthouse}"
CHROME_FLAGS="${CHROME_FLAGS:---headless=new}"
URL=""
RUNS=5
OUTPUT_DIR="./reports"

usage() {
    echo "Usage: $0 <url> [--runs=N] [--output=DIR]"
    echo ""
    echo "  --runs=N        Anzahl Laeufe (Vorgabe: 5)"
    echo "  --output=DIR    Ordner fuer die JSON-Reports (Vorgabe: ./reports)"
    echo "  --help          Diese Hilfe"
}

for arg in "$@"; do
    case "${arg}" in
        --runs=*) RUNS="${arg#*=}" ;;
        --output=*) OUTPUT_DIR="${arg#*=}" ;;
        --help|-h) usage; exit 0 ;;
        -*) echo "Unbekannte Option: ${arg}" >&2; usage >&2; exit 1 ;;
        *) URL="${arg}" ;;
    esac
done

if [[ -z "${URL}" ]]; then
    echo "Fehler: URL fehlt" >&2
    usage >&2
    exit 1
fi

if ! [[ "${RUNS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Fehler: --runs muss eine positive Zahl sein" >&2
    exit 1
fi

for cmd in "${LIGHTHOUSE}" jq; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
        echo "Fehler: ${cmd} nicht gefunden" >&2
        exit 1
    fi
done

mkdir -p "${OUTPUT_DIR}"

# Median einer Zahlenliste (eine Zahl pro Zeile)
median() {
    sort -n | awk '{ v[NR] = $1 } END { if (NR % 2) print v[(NR + 1) / 2]; else print (v[NR / 2] + v[NR / 2 + 1]) / 2 }'
}

# Kleinster und groesster Wert
range() {
    sort -n | awk 'NR == 1 { min = $1 } { max = $1 } END { print min " - " max }'
}

SCORES=""
LCPS=""
TBTS=""
CLSS=""

echo "Lighthouse mobil: ${URL} (${RUNS} Laeufe)"
echo ""
printf '%-6s %6s %9s %9s %7s\n' "Lauf" "Score" "LCP (ms)" "TBT (ms)" "CLS"

for ((i = 1; i <= RUNS; i++)); do
    report="${OUTPUT_DIR}/mobile-${i}.json"
    "${LIGHTHOUSE}" "${URL}" \
        --only-categories=performance \
        --output=json \
        --output-path="${report}" \
        --chrome-flags="${CHROME_FLAGS}" \
        --quiet

    score=$(jq -r '(.categories.performance.score * 100) | round' "${report}")
    lcp=$(jq -r '.audits["largest-contentful-paint"].numericValue | round' "${report}")
    tbt=$(jq -r '.audits["total-blocking-time"].numericValue | round' "${report}")
    cls=$(jq -r '.audits["cumulative-layout-shift"].numericValue * 1000 | round / 1000' "${report}")

    printf '%-6s %6s %9s %9s %7s\n' "${i}" "${score}" "${lcp}" "${tbt}" "${cls}"
    SCORES+="${score}"$'\n'
    LCPS+="${lcp}"$'\n'
    TBTS+="${tbt}"$'\n'
    CLSS+="${cls}"$'\n'
done

echo ""
echo "Median (Spanne):"
echo "  Score: $(printf '%s' "${SCORES}" | median) ($(printf '%s' "${SCORES}" | range))"
echo "  LCP:   $(printf '%s' "${LCPS}" | median) ms ($(printf '%s' "${LCPS}" | range))"
echo "  TBT:   $(printf '%s' "${TBTS}" | median) ms ($(printf '%s' "${TBTS}" | range))"
echo "  CLS:   $(printf '%s' "${CLSS}" | median) ($(printf '%s' "${CLSS}" | range))"
echo "  INP:   nicht gemessen (nur Felddaten: CrUX/PageSpeed Insights, RUM aus Kapitel 12)"
echo ""
echo "Reports: ${OUTPUT_DIR}/mobile-1.json ... mobile-${RUNS}.json"
