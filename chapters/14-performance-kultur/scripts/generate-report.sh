#!/bin/bash
#
# Performance Report Generator
#
# Baut einen Markdown-Report aus den RUM-Logs von Kapitel 12:
# Perzentile aus `bin/console rum:report`, Error Budget aus error-budget.php.
# Abschnitte, die kein Werkzeug liefert (Top-Issues, Erfolge), bleiben als
# Platzhalter fuer den Champion stehen - der Report erfindet keine Zahlen.
#
# Usage: ./generate-report.sh [weekly|monthly]
#
# Umgebung:
#   SHOPWARE_DIR   Shopware-Verzeichnis (Vorgabe: /var/www/html)
#   OUTPUT_DIR     Zielordner (Vorgabe: ../reports neben diesem Skript)
#   SLACK_WEBHOOK  optional: Kurzfassung an einen Slack-Webhook schicken
#   CONSOLE, PHP, CURL  Befehle (Vorgabe: $SHOPWARE_DIR/bin/console, php, curl)
#
# Voraussetzung: Plugin RumMonitoring (Kapitel 12) ist installiert.
# Ausfuehren als Benutzer des Webservers (liest var/log/rum-*.log).
#
# Exit-Codes: 0 = Report geschrieben, 1 = Aufruffehler, 2 = Werkzeug gescheitert

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_TYPE="${1:-weekly}"
SHOPWARE_DIR="${SHOPWARE_DIR:-/var/www/html}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/../reports}"
CONSOLE="${CONSOLE:-${SHOPWARE_DIR}/bin/console}"
PHP="${PHP:-php}"
CURL="${CURL:-curl}"
TIMESTAMP=$(date +%Y%m%d)

case "${REPORT_TYPE}" in
    -h|--help)
        echo "Usage: $0 [weekly|monthly]"
        exit 0
        ;;
    weekly)
        DAYS=7
        PERIOD="Letzte 7 Tage"
        ;;
    monthly)
        DAYS=30
        PERIOD="Letzte 30 Tage"
        ;;
    *)
        echo "Unbekannter Report-Typ: ${REPORT_TYPE}" >&2
        echo "Usage: $0 [weekly|monthly]" >&2
        exit 1
        ;;
esac

HOURS=$((DAYS * 24))
mkdir -p "${OUTPUT_DIR}"
REPORT_FILE="${OUTPUT_DIR}/performance-report-${REPORT_TYPE}-${TIMESTAMP}.md"

# Erst in Variablen lesen, dann schreiben: ein gescheitertes Werkzeug
# hinterlaesst keinen halben Report
if ! CWV=$("${CONSOLE}" rum:report --hours="${HOURS}" 2>&1); then
    echo "rum:report gescheitert:" >&2
    echo "${CWV}" >&2
    exit 2
fi

if ! BY_ROUTE=$("${CONSOLE}" rum:report --hours="${HOURS}" --by=route 2>&1); then
    echo "rum:report --by=route gescheitert:" >&2
    echo "${BY_ROUTE}" >&2
    exit 2
fi

# error-budget.php: 0 = ok, 1 = SLO verletzt, 3 = zu wenig Daten, 2 = Fehler
BUDGET_RC=0
BUDGET=$("${PHP}" "${SCRIPT_DIR}/error-budget.php" "${SHOPWARE_DIR}" 2>&1) || BUDGET_RC=$?

case "${BUDGET_RC}" in
    0) BUDGET_NOTE="Kein SLO verletzt." ;;
    1) BUDGET_NOTE="**Mindestens ein SLO ist verletzt (p75 nicht mehr gut):** Stufe rot laut Error-Budget-Policy." ;;
    3) BUDGET_NOTE="Zu wenig Seitenaufrufe fuer eine Bewertung." ;;
    *)
        echo "error-budget.php gescheitert (Exit ${BUDGET_RC}):" >&2
        echo "${BUDGET}" >&2
        exit 2
        ;;
esac

OVERALL=$(grep '^Gesamt: ' <<< "${BUDGET}" | head -n 1 || true)

cat > "${REPORT_FILE}.part" << EOF
# Performance Report

**Zeitraum**: ${PERIOD}
**Erstellt**: $(date '+%Y-%m-%d %H:%M')
**Typ**: ${REPORT_TYPE}

## Core Web Vitals (Feld-Daten, ${PERIOD})

\`\`\`text
${CWV}
\`\`\`

## Je Seitentyp

\`\`\`text
${BY_ROUTE}
\`\`\`

## Error Budget (28 Tage)

\`\`\`text
${BUDGET}
\`\`\`

${BUDGET_NOTE}

## Top Performance Issues

<!-- vom Champion ausfuellen: Seite, Metrik, Ursache, Ticket -->

## Erfolge diese Periode

<!-- vom Champion ausfuellen: gemergte Performance-PRs mit Vorher/Nachher aus rum:report -->

## Naechste Schritte

<!-- vom Champion ausfuellen -->
EOF
mv "${REPORT_FILE}.part" "${REPORT_FILE}"

echo "Report erstellt: ${REPORT_FILE}"

if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
    SUMMARY="Performance Report (${REPORT_TYPE}): Error Budget ${OVERALL#Gesamt: }"
    if ! "${CURL}" -sS -f -X POST "${SLACK_WEBHOOK}" \
        -H 'Content-type: application/json' \
        -d "{\"text\": \"${SUMMARY}\"}" > /dev/null; then
        echo "Slack-Versand gescheitert, Report liegt trotzdem unter ${REPORT_FILE}" >&2
        exit 2
    fi
    echo "Slack-Nachricht gesendet."
fi
