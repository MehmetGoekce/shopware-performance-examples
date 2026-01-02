#!/bin/bash
#
# Kapitel 24: Performance-Metriken sammeln
# Ausblick – Neue Technologien und Trends
#
# Sammelt Performance-Metriken über Zeit für ML-Analyse.
# Speichert Daten als JSON für detect-anomalies.py.
#

URL="${1:-https://localhost}"
OUTPUT="${2:-metrics.json}"
INTERVAL="${3:-3600}"  # Default: 1 Stunde
DURATION="${4:-604800}"  # Default: 7 Tage

echo "=== Performance-Metrik-Sammlung ==="
echo ""
echo "URL: $URL"
echo "Output: $OUTPUT"
echo "Intervall: ${INTERVAL}s"
echo "Dauer: ${DURATION}s"
echo ""

# Initialisiere JSON-Array wenn Datei nicht existiert
if [ ! -f "$OUTPUT" ]; then
    echo "[]" > "$OUTPUT"
fi

START_TIME=$(date +%s)

collect_metrics() {
    local timestamp
    timestamp=$(date -Iseconds)

    # PageSpeed API abfragen (kein API-Key nötig für Basis-Daten)
    local response
    response=$(curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=$URL&strategy=mobile" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "[$timestamp] Fehler: Keine API-Antwort"
        return 1
    fi

    # Metriken extrahieren mit jq
    if command -v jq &> /dev/null; then
        local metrics
        metrics=$(echo "$response" | jq -c '{
            timestamp: "'"$timestamp"'",
            TTFB: .lighthouseResult.audits["server-response-time"].numericValue,
            FCP: .lighthouseResult.audits["first-contentful-paint"].numericValue,
            LCP: .lighthouseResult.audits["largest-contentful-paint"].numericValue,
            CLS: .lighthouseResult.audits["cumulative-layout-shift"].numericValue,
            TBT: .lighthouseResult.audits["total-blocking-time"].numericValue,
            SI: .lighthouseResult.audits["speed-index"].numericValue,
            score: .lighthouseResult.categories.performance.score
        }' 2>/dev/null)

        if [ -n "$metrics" ] && [ "$metrics" != "null" ]; then
            # An JSON-Array anhängen
            local temp
            temp=$(mktemp)
            jq ". += [$metrics]" "$OUTPUT" > "$temp" && mv "$temp" "$OUTPUT"
            echo "[$timestamp] Metriken gespeichert"
            return 0
        fi
    fi

    echo "[$timestamp] Fehler: Konnte Metriken nicht parsen"
    return 1
}

echo "Starte Sammlung... (Ctrl+C zum Beenden)"
echo ""

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $DURATION ]; then
        echo ""
        echo "Sammlung abgeschlossen nach ${DURATION}s"
        break
    fi

    collect_metrics

    echo "Nächste Messung in ${INTERVAL}s..."
    sleep $INTERVAL
done

# Zusammenfassung
if command -v jq &> /dev/null; then
    COUNT=$(jq '. | length' "$OUTPUT")
    echo ""
    echo "=== Zusammenfassung ==="
    echo "Gesammelte Datenpunkte: $COUNT"
    echo "Gespeichert in: $OUTPUT"
    echo ""
    echo "Nächster Schritt:"
    echo "  python detect-anomalies.py --input $OUTPUT"
fi
