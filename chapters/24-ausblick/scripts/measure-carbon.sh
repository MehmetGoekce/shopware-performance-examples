#!/bin/bash
#
# Kapitel 24: CO2-Fußabdruck messen
# Ausblick – Neue Technologien und Trends
#
# Misst den geschätzten CO2-Ausstoß einer Webseite.
# Nutzt die Website Carbon Calculator API.
#

URL="${1:-https://localhost}"

echo "=== CO2-Fußabdruck Analyse ==="
echo ""
echo "URL: ${URL}"
echo ""

# Website Carbon API abfragen
echo "Analysiere..."
RESULT=$(curl -s "https://api.websitecarbon.com/site?url=${URL}" 2>/dev/null)

if [[ -z "${RESULT}" ]]; then
    echo "Fehler: Keine Antwort von der API"
    echo ""
    echo "Alternative: Manuell testen unter"
    echo "→ https://websitecarbon.com/"
    exit 1
fi

# JSON parsen (mit jq wenn verfügbar)
if command -v jq &> /dev/null; then
    GREEN=$(echo "${RESULT}" | jq -r '.green // "unknown"')
    CO2_GRID=$(echo "${RESULT}" | jq -r '.statistics.co2.grid.grams // 0')
    CO2_RENEWABLE=$(echo "${RESULT}" | jq -r '.statistics.co2.renewable.grams // 0')
    BYTES=$(echo "${RESULT}" | jq -r '.bytes // 0')
    CLEANER_THAN=$(echo "${RESULT}" | jq -r '.cleanerThan // 0')

    echo "1. Ergebnisse"
    echo ""
    echo "   Seitengröße: $(echo "scale=2; ${BYTES} / 1024" | bc) KB"
    echo "   CO2 pro Aufruf (Stromnetz): ${CO2_GRID}g"
    echo "   CO2 pro Aufruf (erneuerbar): ${CO2_RENEWABLE}g"
    echo "   Grünes Hosting: ${GREEN}"
    echo "   Sauberer als: ${CLEANER_THAN}% aller Seiten"
    echo ""

    # Hochrechnung
    MONTHLY_VIEWS="${2:-10000}"
    YEARLY_CO2=$(echo "scale=2; ${CO2_GRID} * ${MONTHLY_VIEWS} * 12 / 1000" | bc)

    echo "2. Jährliche Hochrechnung (bei ${MONTHLY_VIEWS} Aufrufen/Monat)"
    echo ""
    echo "   CO2 pro Jahr: ${YEARLY_CO2} kg"
    echo ""

    # Vergleich
    echo "3. Zum Vergleich"
    echo ""
    echo "   1 km Autofahrt: ~120g CO2"
    echo "   1 Stunde Netflix: ~36g CO2"
    echo "   1 Google-Suche: ~0.2g CO2"
    echo ""

    # Bewertung
    if (( $(echo "${CO2_GRID} < 0.2" | bc -l) )); then
        echo "   Bewertung: ✅ Sehr gut"
    elif (( $(echo "${CO2_GRID} < 0.5" | bc -l) )); then
        echo "   Bewertung: ✓ Durchschnittlich"
    else
        echo "   Bewertung: ❌ Verbesserungswürdig"
    fi
else
    echo "jq nicht installiert. Rohe API-Antwort:"
    echo "${RESULT}"
fi

echo ""
echo "=== Optimierungs-Tipps ==="
echo ""
echo "1. Bilder optimieren (WebP/AVIF)"
echo "2. Gzip/Brotli aktivieren"
echo "3. Unnötige Third-Party-Scripts entfernen"
echo "4. HTTP-Cache nutzen"
echo "5. Grünes Hosting wählen"
echo ""
echo "Detaillierte Analyse: https://websitecarbon.com/"
