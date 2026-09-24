#!/bin/bash
#
# Kapitel 24: Performance-Metriken sammeln
# Ausblick – Neue Technologien und Trends
#
# Sammelt Lighthouse-Metriken über die PageSpeed Insights API über Zeit.
# Speichert Daten als JSON für detect-anomalies.py.
#
# Usage: PSI_API_KEY=<key> ./collect-metrics.sh <url> [output.json] [intervall-s] [dauer-s]
#
# API-Key: Ohne Key antwortete die API am 2026-09-24 mit HTTP 429
# (Tageskontingent 0 für anonyme Aufrufe). Key anlegen:
# https://developers.google.com/speed/docs/insights/v5/get-started
#
# Exit-Codes: 0 = mindestens eine Messung gespeichert,
#             1 = Aufruffehler, jq fehlt oder keine einzige Messung gespeichert
#

set -euo pipefail

USAGE="Usage: PSI_API_KEY=<key> $0 <url> [output.json] [intervall-s] [dauer-s]"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "${USAGE}"
    exit 0
fi

if [[ -z "${1:-}" ]]; then
    echo "${USAGE}" >&2
    echo "Die URL muss öffentlich erreichbar sein, die API ruft sie von aussen ab." >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Fehler: jq fehlt (apt install jq)" >&2
    exit 1
fi

URL="$1"
OUTPUT="${2:-metrics.json}"
INTERVAL="${3:-3600}"  # Default: 1 Stunde
DURATION="${4:-604800}"  # Default: 7 Tage

echo "=== Performance-Metrik-Sammlung ==="
echo ""
echo "URL: ${URL}"
echo "Output: ${OUTPUT}"
echo "Intervall: ${INTERVAL}s"
echo "Dauer: ${DURATION}s"
if [[ -z "${PSI_API_KEY:-}" ]]; then
    echo "Hinweis: PSI_API_KEY nicht gesetzt, anonyme Aufrufe scheitern meist mit HTTP 429"
fi
echo ""

# Initialisiere JSON-Array wenn Datei nicht existiert
if [[ ! -f "${OUTPUT}" ]]; then
    echo "[]" > "${OUTPUT}"
fi

START_TIME=$(date +%s)
SAVED=0

collect_metrics() {
    local timestamp
    timestamp=$(date -Iseconds)

    local api
    api="https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=$(jq -rn --arg u "${URL}" '$u|@uri')&strategy=mobile"
    if [[ -n "${PSI_API_KEY:-}" ]]; then
        api="${api}&key=${PSI_API_KEY}"
    fi

    local response
    response=$(curl -s --max-time 120 "${api}" 2>/dev/null)

    if [[ -z "${response}" ]]; then
        echo "[${timestamp}] Fehler: Keine API-Antwort" >&2
        return 1
    fi

    # Fehlerantwort (z. B. 429) ergäbe sonst eine Zeile mit lauter null
    local api_error
    api_error=$(echo "${response}" | jq -r 'if .error then "\(.error.code): \(.error.message)" elif .lighthouseResult == null then "Antwort ohne lighthouseResult" else empty end' 2>/dev/null) \
        || api_error="Antwort ist kein JSON"
    if [[ -n "${api_error}" ]]; then
        echo "[${timestamp}] API-Fehler ${api_error}" >&2
        return 1
    fi

    local metrics
    metrics=$(echo "${response}" | jq -c '{
        timestamp: "'"${timestamp}"'",
        TTFB: .lighthouseResult.audits["server-response-time"].numericValue,
        FCP: .lighthouseResult.audits["first-contentful-paint"].numericValue,
        LCP: .lighthouseResult.audits["largest-contentful-paint"].numericValue,
        CLS: .lighthouseResult.audits["cumulative-layout-shift"].numericValue,
        TBT: .lighthouseResult.audits["total-blocking-time"].numericValue,
        SI: .lighthouseResult.audits["speed-index"].numericValue,
        score: .lighthouseResult.categories.performance.score
    }' 2>/dev/null)

    if [[ -z "${metrics}" ]]; then
        echo "[${timestamp}] Fehler: Konnte Metriken nicht parsen" >&2
        return 1
    fi

    # An JSON-Array anhängen
    local temp
    temp=$(mktemp)
    jq ". += [${metrics}]" "${OUTPUT}" > "${temp}" && mv "${temp}" "${OUTPUT}"
    echo "[${timestamp}] Metriken gespeichert"
    SAVED=$((SAVED + 1))
    return 0
}

echo "Starte Sammlung... (Ctrl+C zum Beenden)"
echo ""

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [[ ${ELAPSED} -ge ${DURATION} ]]; then
        echo ""
        echo "Sammlung abgeschlossen nach ${DURATION}s"
        break
    fi

    # Eine gescheiterte Messung bricht die Sammlung nicht ab
    collect_metrics || true

    echo "Nächste Messung in ${INTERVAL}s..."
    sleep "${INTERVAL}"
done

# Zusammenfassung
COUNT=$(jq '. | length' "${OUTPUT}")
echo ""
echo "=== Zusammenfassung ==="
echo "Neu gespeichert: ${SAVED}"
echo "Datenpunkte in der Datei: ${COUNT}"
echo "Gespeichert in: ${OUTPUT}"

if [[ ${SAVED} -eq 0 ]]; then
    echo "Fehler: keine einzige Messung gespeichert (siehe Meldungen oben)" >&2
    exit 1
fi

echo ""
echo "Nächster Schritt:"
echo "  python scripts/detect-anomalies.py --input ${OUTPUT}"
