#!/bin/bash
#
# RUM Statistik-Auswertung
# Analysiert RUM-Logs und berechnet Perzentile
#
# Verwendung:
#   ./rum-stats.sh /var/log/shopware/rum.log 1h
#   ./rum-stats.sh /var/log/shopware/rum.log 24h
#   ./rum-stats.sh /var/log/shopware/rum.log 7d
#
# Voraussetzungen:
#   - jq (für JSON-Parsing)
#   - bc (für Berechnungen)

set -e

LOG_FILE="${1:-/var/log/shopware/rum.log}"
TIME_WINDOW="${2:-1h}"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Schwellenwerte
declare -A THRESHOLDS_GOOD
declare -A THRESHOLDS_POOR
THRESHOLDS_GOOD[LCP]=2500
THRESHOLDS_POOR[LCP]=4000
THRESHOLDS_GOOD[INP]=200
THRESHOLDS_POOR[INP]=500
THRESHOLDS_GOOD[CLS]=0.1
THRESHOLDS_POOR[CLS]=0.25
THRESHOLDS_GOOD[FCP]=1800
THRESHOLDS_POOR[FCP]=3000
THRESHOLDS_GOOD[TTFB]=800
THRESHOLDS_POOR[TTFB]=1800

usage() {
    echo "Verwendung: $0 <log-file> <time-window>"
    echo ""
    echo "Time windows: 1h, 6h, 24h, 7d, 30d"
    exit 1
}

# Prüfungen
if [[ ! -f "${LOG_FILE}" ]]; then
    echo "FEHLER: Log-Datei nicht gefunden: ${LOG_FILE}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "FEHLER: jq nicht installiert"
    echo "        sudo apt install jq"
    exit 1
fi

# Zeitfenster in Sekunden umrechnen
case "${TIME_WINDOW}" in
    1h)  SECONDS_AGO=3600 ;;
    6h)  SECONDS_AGO=21600 ;;
    24h) SECONDS_AGO=86400 ;;
    7d)  SECONDS_AGO=604800 ;;
    30d) SECONDS_AGO=2592000 ;;
    *)   usage ;;
esac

CUTOFF_TIME=$(($(date +%s) - SECONDS_AGO))
CUTOFF_MS=$((CUTOFF_TIME * 1000))

echo "=== RUM Statistiken (letzte ${TIME_WINDOW}) ==="
echo "Log-Datei: ${LOG_FILE}"
echo "Zeitpunkt: $(date)"
echo ""

# Funktion zur Berechnung von Perzentilen
calculate_percentile() {
    local values="$1"
    local percentile="$2"

    echo "${values}" | sort -n | awk -v p="${percentile}" '
        BEGIN { count = 0 }
        { values[count++] = $1 }
        END {
            if (count == 0) { print 0; exit }
            idx = int(count * p / 100)
            if (idx >= count) idx = count - 1
            print values[idx]
        }
    '
}

# Funktion zur Auswertung einer Metrik
analyze_metric() {
    local metric="$1"

    # Werte extrahieren (nur innerhalb Zeitfenster)
    local values
    values=$(grep "\"metric\":\"${metric}\"" "${LOG_FILE}" 2>/dev/null | \
        jq -r "select(.context.timestamp > ${CUTOFF_MS}) | .context.value" 2>/dev/null | \
        grep -E '^[0-9.]+$')

    if [[ -z "${values}" ]]; then
        echo "  Keine Daten"
        return
    fi

    local count p50 p75 p90 p99
    count=$(echo "${values}" | wc -l)
    p50=$(calculate_percentile "${values}" 50)
    p75=$(calculate_percentile "${values}" 75)
    p90=$(calculate_percentile "${values}" 90)
    p99=$(calculate_percentile "${values}" 99)

    # Rating berechnen
    local good_threshold=${THRESHOLDS_GOOD[${metric}]}
    local poor_threshold=${THRESHOLDS_POOR[${metric}]}

    local rating_color=${GREEN}
    local rating_text="GOOD"

    if (( $(echo "${p75} > ${poor_threshold}" | bc -l) )); then
        rating_color=${RED}
        rating_text="POOR"
    elif (( $(echo "${p75} > ${good_threshold}" | bc -l) )); then
        rating_color=${YELLOW}
        rating_text="NEEDS IMPROVEMENT"
    fi

    # Good Rate berechnen
    local good_count good_rate
    good_count=$(echo "${values}" | awk -v t="${good_threshold}" '$1 <= t' | wc -l)
    good_rate=$(echo "scale=1; ${good_count} * 100 / ${count}" | bc)

    # Ausgabe
    echo "  Samples: ${count}"
    echo "  p50: ${p50}"
    echo "  p75: ${p75}"
    echo "  p90: ${p90}"
    echo "  p99: ${p99}"
    echo -e "  Rating: ${rating_color}${rating_text}${NC} (${good_rate}% unter ${good_threshold})"
}

# Alle Metriken analysieren
for metric in LCP INP CLS FCP TTFB; do
    echo "${metric}:"
    analyze_metric "${metric}"
    echo ""
done

# Zusammenfassung nach Seiten-Typ
echo "=== Nach Seiten-Typ ==="
for page_type in home product category checkout; do
    count=$(grep "\"page_type\":\"${page_type}\"" "${LOG_FILE}" 2>/dev/null | wc -l)
    if [[ "${count}" -gt 0 ]]; then
        echo "  ${page_type}: ${count} Samples"
    fi
done
echo ""

# Zusammenfassung nach Gerät
echo "=== Nach Gerät ==="
for device in mobile desktop tablet; do
    count=$(grep "\"device_type\":\"${device}\"" "${LOG_FILE}" 2>/dev/null | wc -l)
    if [[ "${count}" -gt 0 ]]; then
        echo "  ${device}: ${count} Samples"
    fi
done
echo ""

# Top 5 langsamste Seiten
echo "=== Top 5 langsamste Seiten (LCP) ==="
grep "\"metric\":\"LCP\"" "${LOG_FILE}" 2>/dev/null | \
    jq -r '.context | "\(.value)\t\(.page)"' 2>/dev/null | \
    sort -rn | head -5 | \
    awk '{printf "  %.0fms\t%s\n", $1, $2}'
