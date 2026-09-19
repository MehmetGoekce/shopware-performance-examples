#!/usr/bin/env bash
#
# analyze-cronjobs.sh
#
# Problem 15: Langsame Cronjobs blockieren.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Der haeufigste Fehler in Shopware-Crontabs ist nicht die Uhrzeit, sondern
# die Annahme, "bin/console scheduled-task:run" sei ein Einmal-Befehl.
# Er ist ein Dauerlaeufer: der Prozess schleift und kehrt nicht zurueck.
# Als taeglicher Cronjob gestartet, kommt jeden Tag ein weiterer Prozess dazu,
# der nie endet.
#
# Zwei weitere Klassiker, die dieses Skript sucht:
#   - relative Pfade: Cron startet im Home-Verzeichnis, dort gibt es kein
#     bin/console. Die Zeile scheitert mit "bin/console: not found",
#     und zwar still, wenn niemand die Cron-Mails liest.
#   - fehlende Worker: scheduled-task:run stellt Aufgaben nur in die Queue.
#     Ohne "messenger:consume" arbeitet sie niemand ab.
#
# Verwendung:
#   ./analyze-cronjobs.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = nichts Auffaelliges
#   1 = Auffaelligkeiten gefunden
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: analyze-cronjobs.sh [SHOP_URL] [SHOP_PATH]

Prueft Crontab-Eintraege und Hintergrundprozesse rund um Shopware.

Argumente:
  SHOP_URL    Wird nicht ausgewertet; nur der Einheitlichkeit halber.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Umgebungsvariablen:
  CRONTAB_FILE  Statt der Crontab des aufrufenden Benutzers diese Datei
                auswerten. Nuetzlich fuer Tests und fuer /etc/cron.d/*.
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
# Dieses Skript braucht nur den Pfad; $1 wird bewusst nicht ausgewertet,
# damit run-all-diagnostics.sh alle Skripte gleich aufrufen kann.
SHOP_PATH="${2:-.}"

echo "=== Problem 15: Cronjobs und Hintergrundprozesse ==="
echo

ISSUES=0

echo "1. Crontab-Eintraege"
if [[ -n "${CRONTAB_FILE:-}" ]]; then
    CRON=$(cat "${CRONTAB_FILE}" 2>/dev/null || true)
    echo "   Quelle: ${CRONTAB_FILE}"
else
    CRON=$(crontab -l 2>/dev/null || true)
fi

SHOPWARE_LINES=$(printf '%s\n' "${CRON}" | grep -E 'bin/console' | grep -vE '^[[:space:]]*#' || true)

if [[ -z "${SHOPWARE_LINES}" ]]; then
    echo "   Keine Shopware-Zeilen in der Crontab."
else
    printf '%s\n' "${SHOPWARE_LINES}" | sed 's/^/   /'
    echo
    echo "2. Bewertung der Zeilen"

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        cmd="${line#* * * * * }"

        # Relativer Pfad zu bin/console — aber nur, wenn die Zeile nicht
        # vorher ins Shop-Verzeichnis wechselt. "cd /var/www/shop && php
        # bin/console ..." ist korrekt, auch wenn der Konsolenpfad relativ ist.
        if printf '%s' "${cmd}" | grep -qE '(^|[[:space:]])bin/console' \
           && ! printf '%s' "${cmd}" | grep -qE '(^|[[:space:]])cd[[:space:]]+[^[:space:]]+[[:space:]]*&&'; then
            echo "   Relativer Pfad \"bin/console\":"
            echo "     ${line}"
            echo "     Cron startet im Home-Verzeichnis. Diese Zeile scheitert mit"
            echo "     \"bin/console: not found\". Absoluten Pfad benutzen oder ein"
            echo "     \"cd ${SHOP_PATH} &&\" voranstellen."
            ISSUES=$((ISSUES + 1))
        fi

        # scheduled-task:run ohne Begrenzung?
        if printf '%s' "${cmd}" | grep -q 'scheduled-task:run'; then
            if ! printf '%s' "${cmd}" | grep -qE '\-\-no-wait|--time-limit|-t[[:space:]=]'; then
                echo "   scheduled-task:run ohne --no-wait und ohne --time-limit:"
                echo "     ${line}"
                echo "     Der Prozess endet nie. Bei jedem Cron-Lauf kommt einer dazu."
                ISSUES=$((ISSUES + 1))
            fi
        fi

        # messenger:consume ohne Begrenzung?
        if printf '%s' "${cmd}" | grep -q 'messenger:consume'; then
            if ! printf '%s' "${cmd}" | grep -qE '\-\-time-limit|-t[[:space:]=]'; then
                echo "   messenger:consume ohne --time-limit:"
                echo "     ${line}"
                echo "     Gehoert unter systemd oder supervisor, nicht in die Crontab."
                ISSUES=$((ISSUES + 1))
            fi
        fi
    done <<< "${SHOPWARE_LINES}"
fi

echo
echo "3. Laufende Hintergrundprozesse"
# Auf php-Prozesse einschraenken. Ein blosses "bin/console scheduled-task:run"
# als Muster trifft auch Shells, die diese Zeichenkette nur als Argument tragen
# (etwa ein Editor oder dieses Skript in einer Pipeline).
count_php_processes() {
    pgrep -fc "(^|/)php[0-9.]* .*bin/console $1" 2>/dev/null || true
}
RUNNING_TASKS=$(count_php_processes 'scheduled-task:run')
RUNNING_TASKS="${RUNNING_TASKS:-0}"
RUNNING_WORKERS=$(count_php_processes 'messenger:consume')
RUNNING_WORKERS="${RUNNING_WORKERS:-0}"

echo "   scheduled-task:run:  ${RUNNING_TASKS}"
echo "   messenger:consume:   ${RUNNING_WORKERS}"

if [[ "${RUNNING_TASKS}" -gt 1 ]]; then
    echo "   Mehr als ein Runner. Genau das passiert, wenn er per Cron gestartet"
    echo "   wird: die Prozesse stapeln sich."
    ISSUES=$((ISSUES + 1))
fi
if [[ "${RUNNING_WORKERS}" -eq 0 ]]; then
    echo "   Kein Worker aktiv. Alles, was in die Queue geht — Cache-Invalidierung,"
    echo "   Indizierung, Mails —, bleibt liegen."
    ISSUES=$((ISSUES + 1))
fi

if [[ -f "${SHOP_PATH}/bin/console" ]]; then
    echo
    echo "4. Faellige Scheduled Tasks laut Datenbank"
    if OVERDUE=$(php "${SHOP_PATH}/bin/console" scheduled-task:list 2>/dev/null); then
        printf '%s\n' "${OVERDUE}" | head -25 | sed 's/^/   /'
    else
        echo "   scheduled-task:list nicht verfuegbar — Tabelle scheduled_task"
        echo "   direkt ansehen (Spalten next_execution_time, status)."
    fi
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Nichts Auffaelliges."
    exit 0
fi

cat <<'EOF'
So gehoert es aufgesetzt — als Dienst, nicht als Cronjob:

  # /etc/systemd/system/shopware-scheduler.service
  [Service]
  User=www-data
  WorkingDirectory=/var/www/shop
  ExecStart=/usr/bin/php bin/console scheduled-task:run --time-limit=3600
  Restart=always

  # /etc/systemd/system/shopware-worker@.service
  [Service]
  User=www-data
  WorkingDirectory=/var/www/shop
  ExecStart=/usr/bin/php bin/console messenger:consume async --time-limit=3600 --memory-limit=256M
  Restart=always

Das --time-limit ist kein Umweg, sondern Absicht: der Prozess beendet sich
regelmaessig selbst und wird neu gestartet, damit Speicher nicht endlos
waechst und neuer Code nach einem Deploy wirklich geladen wird.

Wenn es unbedingt Cron sein muss, dann mit --no-wait und absolutem Pfad:

  */5 * * * * cd /var/www/shop && /usr/bin/php bin/console scheduled-task:run --no-wait

Aber Achtung: --no-wait stellt die faelligen Aufgaben nur in die Queue.
Ohne laufenden Worker arbeitet sie trotzdem niemand ab.

Und noch etwas: die Ausfuehrungszeit einzelner Aufgaben verschiebt man NICHT
ueber die Cron-Zeile. Sie ergibt sich aus run_interval und
next_execution_time in der Tabelle scheduled_task.
EOF
exit 1
