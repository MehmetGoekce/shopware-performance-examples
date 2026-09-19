#!/bin/bash
#
# Sentinel-Failover-Test fuer Shopware.
# Loest ein manuelles Failover aus und misst, wie lange Sentinel braucht.
# Prueft standardmaessig beide ueberwachten Instanzen (Cache und Sessions).
#
# Verwendung:
#   ./test-failover.sh [--help] [<master-name> ...]
#
# WARNUNG: Nur in Staging/Test. Das Skript schaltet den Master wirklich um.
#
# Exit-Codes:
#   0 = Failover abgeschlossen (fuer jeden geprueften Master)
#   1 = Failover nicht innerhalb der Wartezeit abgeschlossen
#   2 = Voraussetzung fehlt (Sentinel nicht erreichbar, kein Quorum, kein Replica)
#   64 = Aufruffehler
#
# Nach einem Failover laesst Sentinel "2 * failover-timeout" verstreichen, bevor
# er denselben Master AUTOMATISCH erneut umschaltet. Ein weiteres manuelles
# SENTINEL failover geht sofort — das umgeht die Sperre. Wer also direkt nach
# diesem Test den harten Ausfall nachstellt, sieht ein Cluster, das minutenlang
# nichts tut: das ist die Sperrfrist, kein Defekt. Das Skript rechnet sie aus.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: test-failover.sh [--help] [<master-name> ...]

Loest je Master ein manuelles Failover aus und misst die Zeit bis zum neuen
Master. Ohne Argument werden die Master aus MASTER_NAMES getestet.

Erwartete Umgebungsvariablen:
  SENTINEL_HOST          Optional, Default 127.0.0.1.
  SENTINEL_PORT          Optional, Default 26379.
  SENTINEL_AUTH_PASSWORD Optional. Nur setzen, wenn die Sentinels selbst ein
                         requirepass haben — das Master-Passwort gehoert NICHT
                         an Sentinel (siehe redis-monitor.sh).
  MASTER_NAMES           Optional, Default "shopware-cache shopware-session".
  WAIT_SECONDS           Optional, Default 30. Wartezeit je Master.

Das Skript braucht kein Master-Passwort: es spricht ausschliesslich mit
Sentinel.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

for arg in "$@"; do
    if [[ "${arg}" == -* ]]; then
        echo "Unbekanntes Argument: ${arg}" >&2
        usage >&2
        exit 64
    fi
done

SENTINEL_HOST="${SENTINEL_HOST:-127.0.0.1}"
SENTINEL_PORT="${SENTINEL_PORT:-26379}"
WAIT_SECONDS="${WAIT_SECONDS:-30}"

if [[ $# -gt 0 ]]; then
    masters=("$@")
else
    # shellcheck disable=SC2206  # Wortaufteilung ist hier gewollt.
    masters=(${MASTER_NAMES:-shopware-cache shopware-session})
fi

# Sentinel bekommt das Master-Passwort NICHT: ein unerwartetes AUTH beantwortet
# er mit "Warning: AUTH failed", und jede Pruefung darauf schlaegt fehl.
sentinel_cli() {
    if [[ -n "${SENTINEL_AUTH_PASSWORD:-}" ]]; then
        REDISCLI_AUTH="${SENTINEL_AUTH_PASSWORD}" \
            redis-cli -h "${SENTINEL_HOST}" -p "${SENTINEL_PORT}" "$@"
    else
        env -u REDISCLI_AUTH redis-cli -h "${SENTINEL_HOST}" -p "${SENTINEL_PORT}" "$@"
    fi
}

# Ein Feld aus "SENTINEL master <name>" lesen (Antwort ist eine flache Liste
# aus abwechselnd Feldname und Wert).
master_field() {
    local name="$1" field="$2"
    sentinel_cli SENTINEL master "${name}" 2>/dev/null \
        | tr -d '\r' \
        | awk -v f="${field}" 'p == 1 { print; exit } $0 == f { p = 1 }'
}

echo "==========================================="
echo "=== Redis Sentinel Failover Test ==="
echo "Sentinel:  ${SENTINEL_HOST}:${SENTINEL_PORT}"
echo "Zeitpunkt: $(date)"
echo "==========================================="

if ! sentinel_cli PING >/dev/null 2>&1; then
    echo "KRITISCH  Sentinel ${SENTINEL_HOST}:${SENTINEL_PORT} nicht erreichbar" >&2
    exit 2
fi

exit_code=0

for master_name in "${masters[@]}"; do
    echo ""
    echo "############ ${master_name} ############"

    # ckquorum liefert bei Erfolg "OK <n> usable Sentinels...". Der Wortlaut
    # dahinter hat sich zwischen Redis-Versionen geaendert (7.4: "Quorum and
    # failover authorization can be reached"), deshalb nur das fuehrende OK.
    quorum_check="$(sentinel_cli SENTINEL ckquorum "${master_name}" 2>&1 || true)"
    if [[ "${quorum_check}" != OK* ]]; then
        echo "KRITISCH  Quorum nicht erreicht: ${quorum_check}" >&2
        exit_code=2
        continue
    fi
    echo "OK        Quorum: ${quorum_check}"

    old_addr="$(sentinel_cli SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null | tr -d '\r')"
    old_ip="$(printf '%s\n' "${old_addr}" | sed -n 1p)"
    old_port="$(printf '%s\n' "${old_addr}" | sed -n 2p)"

    if [[ -z "${old_ip}" || -z "${old_port}" ]]; then
        echo "KRITISCH  Kein Master gefunden" >&2
        exit_code=2
        continue
    fi
    echo "          Master vorher: ${old_ip}:${old_port}"

    # grep -cx: nur Zeilen, die exakt "name" sind.
    replica_count="$(sentinel_cli SENTINEL replicas "${master_name}" 2>/dev/null | tr -d '\r' | grep -cx 'name' || true)"
    replica_count="${replica_count:-0}"
    echo "          Verbundene Replicas: ${replica_count}"

    if [[ "${replica_count}" -lt 1 ]]; then
        echo "KRITISCH  Mindestens 1 Replica noetig, sonst hat Sentinel kein Ziel" >&2
        exit_code=2
        continue
    fi

    failover_timeout="$(master_field "${master_name}" failover-timeout)"
    failover_timeout="${failover_timeout:-180000}"
    lockout=$(( 2 * failover_timeout / 1000 ))

    start_ms="$(date +%s%3N)"
    failover_reply="$(sentinel_cli SENTINEL failover "${master_name}" 2>&1 || true)"
    if [[ "${failover_reply}" != OK* ]]; then
        echo "KRITISCH  Sentinel lehnt das Failover ab: ${failover_reply}" >&2
        exit_code=2
        continue
    fi

    promoted=0
    for (( i = 1; i <= WAIT_SECONDS; i++ )); do
        sleep 1
        new_addr="$(sentinel_cli SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null | tr -d '\r')"
        new_ip="$(printf '%s\n' "${new_addr}" | sed -n 1p)"
        new_port="$(printf '%s\n' "${new_addr}" | sed -n 2p)"

        if [[ -n "${new_ip}" && "${new_ip}:${new_port}" != "${old_ip}:${old_port}" ]]; then
            end_ms="$(date +%s%3N)"
            echo "OK        Master nachher: ${new_ip}:${new_port}"
            echo "          Failover-Zeit: $(( end_ms - start_ms )) ms"
            promoted=1
            break
        fi
    done

    if [[ "${promoted}" -eq 0 ]]; then
        echo "FEHLER    Failover nicht innerhalb von ${WAIT_SECONDS} s abgeschlossen." >&2
        echo "          Sentinel-Log pruefen: journalctl -u redis-sentinel -n 50" >&2
        echo "          Haeufigste Ursache: CONFIG oder SLAVEOF wurden per rename-command" >&2
        echo "          umbenannt, ohne Sentinel das per SENTINEL rename-command" >&2
        echo "          mitzuteilen — dann bleibt er in failover-state-wait-promotion." >&2
        [[ "${exit_code}" -lt 1 ]] && exit_code=1
        continue
    fi

    echo ""
    echo "          Sperrfrist: einen AUTOMATISCHEN Failover von ${master_name} startet"
    echo "          Sentinel erst wieder in ${lockout} s (2 * failover-timeout). Ein harter"
    echo "          Ausfalltest davor sieht aus wie ein Defekt, ist aber nur die Wartezeit."
    echo "          Ein weiteres manuelles Failover geht sofort — es umgeht die Sperre."
done

exit "${exit_code}"
