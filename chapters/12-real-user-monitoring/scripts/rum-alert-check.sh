#!/bin/bash
#
# RUM Alert Check Script
# Prüft RUM-Metriken und sendet Alerts bei Problemen
#
# Verwendung:
#   ./rum-alert-check.sh
#   ./rum-alert-check.sh --critical-only
#
# Cron-Einrichtung:
#   */15 * * * * /opt/shopware/scripts/rum-alert-check.sh
#
# Umgebungsvariablen:
#   SLACK_WEBHOOK - Slack Incoming Webhook URL
#   ALERT_EMAIL - Email für Alerts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${RUM_LOG_FILE:-/var/log/shopware/rum.log}"
CRITICAL_ONLY="${1:-}"

# Slack Webhook (aus Umgebung oder hardcoded)
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# Schwellenwerte (p75)
declare -A WARNING_THRESHOLDS
declare -A CRITICAL_THRESHOLDS

WARNING_THRESHOLDS[LCP]=2500
CRITICAL_THRESHOLDS[LCP]=4000

WARNING_THRESHOLDS[INP]=200
CRITICAL_THRESHOLDS[INP]=500

WARNING_THRESHOLDS[CLS]=100  # * 1000 für Integer-Vergleich
CRITICAL_THRESHOLDS[CLS]=250

# Mindest-Samples
MIN_SAMPLES=100

# Zeitfenster (1 Stunde)
SECONDS_AGO=3600
CUTOFF_TIME=$(($(date +%s) - SECONDS_AGO))
CUTOFF_MS=$((CUTOFF_TIME * 1000))

# Prüfungen
if [ ! -f "$LOG_FILE" ]; then
    echo "Log-Datei nicht gefunden: $LOG_FILE"
    exit 0  # Kein Fehler, einfach nichts zu prüfen
fi

if ! command -v jq &> /dev/null; then
    echo "FEHLER: jq nicht installiert"
    exit 1
fi

# Funktion: Perzentil berechnen
calculate_p75() {
    local values="$1"
    echo "$values" | sort -n | awk '
        BEGIN { count = 0 }
        { values[count++] = $1 }
        END {
            if (count == 0) { print 0; exit }
            idx = int(count * 0.75)
            if (idx >= count) idx = count - 1
            print values[idx]
        }
    '
}

# Funktion: Alert senden
send_alert() {
    local level="$1"
    local metric="$2"
    local value="$3"
    local threshold="$4"
    local samples="$5"

    local emoji="⚠️"
    local color="warning"
    if [ "$level" == "critical" ]; then
        emoji="🚨"
        color="danger"
    fi

    local message="$emoji *${level^^}* $metric Alert
• Wert (p75): *$value* (Schwelle: $threshold)
• Samples: $samples
• Zeit: $(date '+%Y-%m-%d %H:%M:%S')"

    echo "$message"

    # Slack senden
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H 'Content-type: application/json' \
            -d "{
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"text\": \"$message\",
                    \"mrkdwn_in\": [\"text\"]
                }]
            }" > /dev/null
    fi
}

# Funktion: Metrik prüfen
check_metric() {
    local metric="$1"

    # Werte extrahieren
    local values=$(grep "\"metric\":\"$metric\"" "$LOG_FILE" 2>/dev/null | \
        jq -r "select(.context.timestamp > $CUTOFF_MS) | .context.value" 2>/dev/null | \
        grep -E '^[0-9.]+$')

    if [ -z "$values" ]; then
        return
    fi

    local count=$(echo "$values" | wc -l)

    # Nicht genug Samples
    if [ "$count" -lt "$MIN_SAMPLES" ]; then
        return
    fi

    local p75=$(calculate_p75 "$values")

    # Für CLS: Wert * 1000 für Integer-Vergleich
    local compare_value="$p75"
    if [ "$metric" == "CLS" ]; then
        compare_value=$(echo "$p75 * 1000" | bc | cut -d. -f1)
    fi

    local warning_threshold=${WARNING_THRESHOLDS[$metric]}
    local critical_threshold=${CRITICAL_THRESHOLDS[$metric]}

    # Critical Check
    if [ "$compare_value" -ge "$critical_threshold" ]; then
        send_alert "critical" "$metric" "$p75" "$critical_threshold" "$count"
        return
    fi

    # Warning Check (überspringen wenn --critical-only)
    if [ "$CRITICAL_ONLY" != "--critical-only" ]; then
        if [ "$compare_value" -ge "$warning_threshold" ]; then
            send_alert "warning" "$metric" "$p75" "$warning_threshold" "$count"
        fi
    fi
}

# Hauptlogik
echo "RUM Alert Check: $(date)"
echo "Log: $LOG_FILE"
echo "Zeitfenster: letzte Stunde"
echo ""

for metric in LCP INP CLS; do
    check_metric "$metric"
done

echo "Check abgeschlossen."
