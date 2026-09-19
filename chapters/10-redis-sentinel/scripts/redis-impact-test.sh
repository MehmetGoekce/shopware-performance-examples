#!/bin/bash
#
# Redis-Impact-Test fuer Shopware.
# Misst die Antwortzeiten der Storefront mit und ohne Redis.
#
# Verwendung:
#   ./redis-impact-test.sh [--help] <url>
#
# WARNUNG: Das Skript stoppt Redis. Nur in Staging/Test verwenden.
#
# Exit-Codes:
#   0 = Messung durchgelaufen
#   1 = Redis liess sich nicht wieder starten (Hinweis lesen!)
#   2 = Voraussetzung fehlt (URL nicht erreichbar, Stop-Befehl fehlgeschlagen)
#   64 = Aufruffehler
#
# Das Skript gibt nur aus, was es gemessen hat. Wie gross der Unterschied
# ausfaellt, haengt am Datenbestand, an der Hardware und daran, welche Pools
# ueberhaupt in Redis liegen — eine allgemeingueltige Faustzahl gibt es nicht.
#
# Gemessen wird sequenziell mit curl, nicht unter Last. Fuer eine Lastaussage
# braucht es ein Lastwerkzeug und eine produktionsnahe Umgebung.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: redis-impact-test.sh [--help] <url>

Misst die Antwortzeit der angegebenen Seite in zwei Phasen: mit laufendem
Redis und mit gestopptem Redis. Danach wird Redis wieder gestartet.

Erwartete Umgebungsvariablen:
  REQUESTS         Optional, Default 20. Sequentielle Requests je Phase.
  CURL_TIMEOUT     Optional, Default 30. Sekunden bis curl abbricht. 30 ist
                   auch Symfonys Default fuer den Redis-Verbindungsaufbau
                   (RedisTrait::$defaultConnectionOptions) — deshalb haengt
                   ein Request ohne eigene Timeouts genau so lange.
  REDIS_STOP_CMD   Optional, Default "systemctl stop redis-server".
                   Bei getrennten Instanzen (Kapitel 10) beide nennen, z. B.
                   "systemctl stop redis-cache redis-session".
  REDIS_START_CMD  Optional, Default "systemctl start redis-server".
  ASSUME_YES       Optional. Auf 1 setzen, um die Rueckfrage zu ueberspringen.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 || "${1}" == -* ]]; then
    echo "Genau eine URL erwartet." >&2
    usage >&2
    exit 64
fi

URL="$1"
REQUESTS="${REQUESTS:-20}"
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"
REDIS_STOP_CMD="${REDIS_STOP_CMD:-systemctl stop redis-server}"
REDIS_START_CMD="${REDIS_START_CMD:-systemctl start redis-server}"

# Eine Phase messen: gibt "<anzahl-fehler> <zeit1> <zeit2> ..." aus.
measure() {
    local errors=0 times=() t
    for (( i = 0; i < REQUESTS; i++ )); do
        # %{time_total} kommt mit Punkt als Trennzeichen, unabhaengig vom Locale.
        if t="$(curl -s -o /dev/null -m "${CURL_TIMEOUT}" -w '%{time_total}' "${URL}" 2>/dev/null)"; then
            times+=("${t}")
        else
            errors=$(( errors + 1 ))
        fi
    done
    printf '%s %s\n' "${errors}" "${times[*]:-}"
}

# min / median / max in Millisekunden. awk statt bc: bc ist nicht ueberall da.
report() {
    local label="$1" errors="$2"
    shift 2
    if [[ $# -eq 0 ]]; then
        echo "${label}: keine erfolgreiche Antwort (${errors} Fehler von ${REQUESTS})"
        return
    fi
    printf '%s\n' "$@" | sort -n | awk -v label="${label}" -v errors="${errors}" -v total="${REQUESTS}" '
        { v[NR] = $1 * 1000 }
        END {
            mid = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
            printf "%s: min %.0f ms | median %.0f ms | max %.0f ms | %d Fehler von %d\n",
                   label, v[1], mid, v[NR], errors, total
        }'
}

echo "==========================================="
echo "=== Redis Impact Test ==="
echo "URL:       ${URL}"
echo "Requests:  ${REQUESTS} je Phase, sequenziell"
echo "Zeitpunkt: $(date)"
echo "==========================================="
echo ""
echo "WARNUNG: Dieser Test stoppt Redis (${REDIS_STOP_CMD})."
echo "         Nur in Test-/Staging-Umgebungen ausfuehren."
echo ""

if [[ "${ASSUME_YES:-}" != "1" ]]; then
    read -r -p "Test starten? (y/N) " reply
    if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
        echo "Abgebrochen."
        exit 0
    fi
fi

if ! curl -s -o /dev/null -m "${CURL_TIMEOUT}" "${URL}"; then
    echo "KRITISCH  ${URL} ist schon vor dem Test nicht erreichbar." >&2
    exit 2
fi

# Warmlauf: der erste Aufruf fuellt den Cache und waere sonst der Ausreisser.
curl -s -o /dev/null -m "${CURL_TIMEOUT}" "${URL}" || true

echo ""
echo "=== Phase 1: mit Redis ==="
read -r -a phase1 <<< "$(measure)"
report "Mit Redis   " "${phase1[@]}"

# Ab hier muss Redis wieder hochkommen, egal wie der Rest ausgeht.
redis_started=0
restart_redis() {
    [[ "${redis_started}" -eq 1 ]] && return 0
    redis_started=1
    echo ""
    echo "=== Starte Redis wieder ==="
    if ! ${REDIS_START_CMD}; then
        echo "FEHLER    Redis laeuft nicht wieder. Von Hand starten:" >&2
        echo "          ${REDIS_START_CMD}" >&2
        return 1
    fi
}
trap 'restart_redis || exit 1' EXIT

echo ""
echo "=== Stoppe Redis ==="
if ! ${REDIS_STOP_CMD}; then
    echo "KRITISCH  Stop-Befehl fehlgeschlagen: ${REDIS_STOP_CMD}" >&2
    exit 2
fi

echo ""
echo "=== Phase 2: ohne Redis ==="
read -r -a phase2 <<< "$(measure)"
report "Ohne Redis  " "${phase2[@]}"

restart_redis || exit 1
trap - EXIT

echo ""
echo "Hinweis: Haengende Requests statt schneller Fehler deuten auf fehlende"
echo "         Client-Timeouts in der DSN hin (&timeout=2&read_timeout=2)."
