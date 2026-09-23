#!/bin/bash
#
# Kapitel 24: CO2-Fussabdruck je Seitenaufruf schaetzen
# Ausblick – Neue Technologien und Trends
#
# Fragt die Website Carbon API (Modell SWDM v4) mit der uebertragenen
# Seitengroesse ab. Der Endpoint /site (URL rein, Messung dort) ist seit dem
# 14.07.2025 nicht mehr oeffentlich (HTTP 401); oeffentlich ist /data mit
# Bytes und Green-Hosting-Flag. Die Bytes messen Sie selbst, am einfachsten
# mit Lighthouse (Audit "total-byte-weight", alle Ressourcen der Seite):
#
#   lighthouse https://shop.example.com --output=json --output-path=lh.json
#   ./measure-carbon.sh lh.json
#
# SWDM v4 rechnet linear in Bytes: Die Zahl ist eine Modellschaetzung, keine
# Messung, und sie sinkt genau so stark wie die uebertragenen Bytes.
#
# Exit-Codes: 0 Ergebnis ausgegeben, 1 Aufruffehler, 2 Werkzeug oder API
# gescheitert.
#
# @see https://www.websitecarbon.com/introducing-the-website-carbon-rating-system/
# @see https://sustainablewebdesign.org/estimating-digital-emissions/

set -euo pipefail

API="${CARBON_API:-https://api.websitecarbon.com}"
GREEN=0
VIEWS=10000

usage() {
    cat <<'EOF'
Usage: measure-carbon.sh [--green] [--views N] <bytes | lighthouse-report.json>

  bytes                  uebertragene Bytes je Seitenaufruf (alle Ressourcen)
  lighthouse-report.json Bytes aus dem Audit "total-byte-weight"
  --green                Hosting mit erneuerbarer Energie (Green Web Foundation)
  --views N              Seitenaufrufe pro Monat fuer die Hochrechnung (Vorgabe 10000)
EOF
}

INPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --green) GREEN=1; shift ;;
        --views)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "Fehler: --views braucht eine ganze Zahl" >&2; exit 1; }
            VIEWS="$2"; shift 2 ;;
        -*) echo "Fehler: unbekannte Option $1" >&2; usage >&2; exit 1 ;;
        *)
            [[ -z "$INPUT" ]] || { echo "Fehler: nur eine Eingabe erlaubt" >&2; exit 1; }
            INPUT="$1"; shift ;;
    esac
done

[[ -n "$INPUT" ]] || { usage >&2; exit 1; }

for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Fehler: $tool fehlt" >&2; exit 2; }
done

if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
    BYTES="$INPUT"
    SOURCE="Eingabe"
elif [[ -f "$INPUT" ]]; then
    BYTES=$(jq -r '.audits["total-byte-weight"].numericValue // empty | floor' "$INPUT" 2>/dev/null) || BYTES=""
    [[ "$BYTES" =~ ^[0-9]+$ ]] || { echo "Fehler: $INPUT ist kein Lighthouse-Report mit total-byte-weight" >&2; exit 1; }
    SOURCE="Lighthouse, $(jq -r '.finalDisplayedUrl // .finalUrl // "URL unbekannt"' "$INPUT")"
else
    echo "Fehler: $INPUT ist weder eine Zahl noch eine Datei" >&2
    exit 1
fi

[[ "$BYTES" -gt 0 ]] || { echo "Fehler: 0 Bytes ergibt keine Schaetzung" >&2; exit 1; }

# -f: ein HTTP-Fehler (401, 429, 5xx) ist ein Fehler, keine Antwort
if ! RESULT=$(curl -fsS --max-time 30 "${API}/data?bytes=${BYTES}&green=${GREEN}" 2>&1); then
    echo "Fehler: Website Carbon API nicht erreichbar: $RESULT" >&2
    exit 2
fi

GRAMS=$(jq -r '.gco2e // empty' <<<"$RESULT" 2>/dev/null) || GRAMS=""
RATING=$(jq -r '.rating // empty' <<<"$RESULT" 2>/dev/null) || RATING=""
if [[ -z "$GRAMS" || -z "$RATING" ]]; then
    echo "Fehler: unerwartete Antwort der API: ${RESULT:0:200}" >&2
    exit 2
fi

# Hochrechnung in kg pro Jahr: g × Aufrufe/Monat × 12 / 1000
YEARLY_KG=$(jq -n --argjson g "$GRAMS" --argjson v "$VIEWS" '$g * $v * 12 / 1000 * 10 | round / 10')
KB=$(jq -n --argjson b "$BYTES" '$b / 1024 | round')
GRAMS_ROUNDED=$(jq -n --argjson g "$GRAMS" '$g * 1000 | round / 1000')

echo "=== CO2-Schaetzung je Seitenaufruf (Website Carbon, SWDM v4) ==="
echo ""
echo "Seitengroesse:    ${KB} KB uebertragen (${SOURCE})"
echo "Green Hosting:    $([[ "$GREEN" -eq 1 ]] && echo ja || echo nein)"
echo "CO2e je Aufruf:   ${GRAMS_ROUNDED} g"
echo "Rating:           ${RATING}   (A+ bis F; F ab 0,36 g = ueber dem globalen Mittel)"
echo ""
echo "Hochrechnung bei ${VIEWS} Aufrufen/Monat: ${YEARLY_KG} kg CO2e pro Jahr"
echo ""
echo "Modellschaetzung, keine Messung: SWDM v4 rechnet linear in Bytes."
echo "Weniger Bytes (Kapitel 4 Bilder, Kapitel 5 CSS/JS) senken den Wert im selben Verhaeltnis."
