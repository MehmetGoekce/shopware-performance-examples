#!/bin/bash
#
# Redis-Sentinel-Health-Check fuer Shopware.
# Prueft beide ueberwachten Instanzen (Cache und Sessions).
#
# Verwendung:
#   REDIS_AUTH_PASSWORD=... ./redis-monitor.sh [--help]
#
# Fuer Cron (alle 5 Minuten):
#   */5 * * * * . /etc/profile.d/redis-credentials.sh && /opt/redis/redis-monitor.sh >> /var/log/redis/health.log 2>&1
#
# Exit-Codes:
#   0 = alles in Ordnung
#   1 = Warnung (z. B. nur ein Replica, Speicher > 80 %)
#   2 = kritisch (kein Quorum, kein Master, Master nicht erreichbar)
#   64 = Aufruffehler
#
# Das Passwort wird ueber REDISCLI_AUTH uebergeben, nicht ueber "redis-cli -a".
# Mit -a steht es in der Prozessliste und damit fuer jeden lesbar, der `ps`
# ausfuehren darf; ausserdem warnt redis-cli bei jedem Aufruf auf stderr.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: redis-monitor.sh [--help]

Prueft das Redis-Sentinel-Setup aus Kapitel 10:
  - Sentinel-Quorum je ueberwachtem Master
  - erreichbarer Master, Anzahl verbundener Replicas
  - Speicherauslastung, Hit-Rate, abgewiesene Verbindungen

Erwartete Umgebungsvariablen:
  REDIS_AUTH_PASSWORD   Pflicht. Passwort des Benutzers, mit dem geprueft wird.
  REDIS_AUTH_USER       Optional. ACL-Benutzername, z. B. sentinel-watcher.
                        Ohne Angabe meldet sich redis-cli als "default" an —
                        was nicht funktioniert, sobald der default-User per
                        "ACL SETUSER default off" deaktiviert wurde.
  SENTINEL_HOST         Optional, Default 127.0.0.1 (Sentinel laeuft lokal).
  SENTINEL_AUTH_PASSWORD Optional. Nur setzen, wenn die Sentinels selbst ein
                        requirepass haben — das Master-Passwort gehoert NICHT
                        an Sentinel.
  SENTINEL_PORT         Optional, Default 26379.
  MASTER_NAMES          Optional, Default "shopware-cache shopware-session".
  HITRATE_MASTERS       Optional, Default "shopware-cache". Nur fuer diese
                        Master wird die Hit-Rate bewertet — bei einer
                        Session-Instanz ist sie keine sinnvolle Kennzahl.
  MAXMEMORY_<NAME>      Optional. Ersatzwert in Bytes, falls der Monitoring-User
                        CONFIG GET nicht ausfuehren darf. <NAME> ist der
                        Master-Name in Grossbuchstaben, Bindestrich zu
                        Unterstrich, z. B. MAXMEMORY_SHOPWARE_CACHE.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 0 ]]; then
    echo "Unbekanntes Argument: $1" >&2
    usage >&2
    exit 64
fi

if [[ -z "${REDIS_AUTH_PASSWORD:-}" ]]; then
    echo "REDIS_AUTH_PASSWORD muss gesetzt sein (siehe /etc/profile.d/redis-credentials.sh)" >&2
    exit 64
fi

SENTINEL_HOST="${SENTINEL_HOST:-127.0.0.1}"
SENTINEL_PORT="${SENTINEL_PORT:-26379}"
MASTER_NAMES="${MASTER_NAMES:-shopware-cache shopware-session}"
HITRATE_MASTERS="${HITRATE_MASTERS:-shopware-cache}"

# --user nur setzen, wenn ein ACL-Benutzer angegeben ist.
node_user_args=()
if [[ -n "${REDIS_AUTH_USER:-}" ]]; then
    node_user_args=(--user "${REDIS_AUTH_USER}")
fi

# redis-cli liest das Passwort hieraus, ohne es in die Prozessliste zu schreiben.
export REDISCLI_AUTH="${REDIS_AUTH_PASSWORD}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

exit_code=0

# Hoechsten Schweregrad festhalten: kritisch (2) ueberschreibt Warnung (1).
raise() {
    local level="$1"
    [[ "${level}" -gt "${exit_code}" ]] && exit_code="${level}"
    return 0
}

send_alert() {
    local level="$1"
    local message="$2"
    # Hier Mail oder Webhook einhaengen:
    # echo "${message}" | mail -s "[${level}] Redis Alert" ops@example.com
    echo "[${level}] ${message}"
}

# Sentinel bekommt das Master-Passwort NICHT. Sentinel-Instanzen laufen ueblich
# ohne requirepass (abgeschottet per Firewall); schickt man ihnen trotzdem ein
# AUTH, antworten sie mit "Warning: AUTH failed" und jede Pruefung darauf
# schlaegt fehl. Genau dieser Fehler steckte in Symfony bis 7.4.x
# (symfony/symfony#63261). Wer Sentinel ein eigenes Passwort gegeben hat, setzt
# SENTINEL_AUTH_PASSWORD.
sentinel_cli() {
    if [[ -n "${SENTINEL_AUTH_PASSWORD:-}" ]]; then
        REDISCLI_AUTH="${SENTINEL_AUTH_PASSWORD}" \
            redis-cli -h "${SENTINEL_HOST}" -p "${SENTINEL_PORT}" "$@"
    else
        env -u REDISCLI_AUTH redis-cli -h "${SENTINEL_HOST}" -p "${SENTINEL_PORT}" "$@"
    fi
}

echo "==========================================="
echo "=== Redis Sentinel Health Check ==="
echo "Zeitpunkt: $(date)"
echo "==========================================="

for master_name in ${MASTER_NAMES}; do
    echo ""
    echo "############ ${master_name} ############"

    # --- Quorum -------------------------------------------------------------
    # ckquorum liefert bei Erfolg "OK <n> usable Sentinels...". Der genaue
    # Wortlaut nach "OK" hat sich zwischen Redis-Versionen geaendert, deshalb
    # wird nur auf das fuehrende OK geprueft.
    quorum_check="$(sentinel_cli SENTINEL ckquorum "${master_name}" 2>/dev/null || true)"
    if [[ "${quorum_check}" == OK* ]]; then
        echo -e "${GREEN}OK${NC}        Quorum: ${quorum_check}"
    else
        echo -e "${RED}KRITISCH${NC}  Quorum nicht erreichbar: ${quorum_check}"
        send_alert "CRITICAL" "${master_name}: Quorum verloren (${quorum_check})"
        raise 2
        continue
    fi

    # --- Master -------------------------------------------------------------
    # Port mitlesen und auch benutzen: die Session-Instanz laeuft auf 6380.
    master_addr="$(sentinel_cli SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null || true)"
    master_ip="$(printf '%s\n' "${master_addr}" | sed -n 1p)"
    master_port="$(printf '%s\n' "${master_addr}" | sed -n 2p)"

    if [[ -z "${master_ip}" || -z "${master_port}" ]]; then
        echo -e "${RED}KRITISCH${NC}  Kein Master gefunden"
        send_alert "CRITICAL" "${master_name}: kein Master verfuegbar"
        raise 2
        continue
    fi

    echo "          Master: ${master_ip}:${master_port}"

    node() {
        redis-cli -h "${master_ip}" -p "${master_port}" "${node_user_args[@]}" "$@"
    }

    if node PING >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}        Master erreichbar"
    else
        echo -e "${RED}KRITISCH${NC}  Master ${master_ip}:${master_port} nicht erreichbar"
        send_alert "CRITICAL" "${master_name}: Master ${master_ip}:${master_port} nicht erreichbar"
        raise 2
        continue
    fi

    # --- Replicas -----------------------------------------------------------
    # grep -cx: nur Zeilen, die exakt "name" sind. Ohne -x zaehlen kuenftige
    # Felder mit "name" im Namen stillschweigend mit.
    replica_count="$(sentinel_cli SENTINEL replicas "${master_name}" 2>/dev/null | grep -cx 'name' || true)"
    replica_count="${replica_count:-0}"

    if [[ "${replica_count}" -ge 2 ]]; then
        echo -e "${GREEN}OK${NC}        Replicas: ${replica_count}"
    elif [[ "${replica_count}" -eq 1 ]]; then
        echo -e "${YELLOW}WARNUNG${NC}   Nur 1 Replica verbunden (erwartet: 2)"
        send_alert "WARNING" "${master_name}: nur 1 Replica verbunden"
        raise 1
    else
        echo -e "${RED}KRITISCH${NC}  Keine Replicas verbunden"
        send_alert "CRITICAL" "${master_name}: keine Replicas verbunden"
        raise 2
    fi

    # --- Speicher -----------------------------------------------------------
    memory_info="$(node INFO memory 2>/dev/null || true)"
    used_memory="$(printf '%s\n' "${memory_info}" | awk -F: '/^used_memory:/ {print $2}' | tr -d '\r')"
    used_human="$(printf '%s\n' "${memory_info}" | awk -F: '/^used_memory_human:/ {print $2}' | tr -d '\r')"

    # CONFIG GET kann fehlen: der Monitoring-User braucht dafuer +config|get,
    # und wer CONFIG per rename-command umbenannt hat, hat es hier ohnehin nicht.
    # Dann greift der Ersatzwert aus der Umgebung.
    max_memory="$(node CONFIG GET maxmemory 2>/dev/null | sed -n 2p | tr -d '\r' || true)"
    if [[ -z "${max_memory}" ]]; then
        fallback_var="MAXMEMORY_$(printf '%s' "${master_name}" | tr 'a-z-' 'A-Z_')"
        max_memory="${!fallback_var:-}"
        if [[ -n "${max_memory}" ]]; then
            echo "          (maxmemory aus ${fallback_var}, CONFIG GET nicht erlaubt)"
        else
            echo -e "${YELLOW}WARNUNG${NC}   maxmemory unbekannt — CONFIG GET nicht erlaubt und ${fallback_var} nicht gesetzt"
            raise 1
        fi
    fi

    if [[ -n "${max_memory}" && "${max_memory}" -gt 0 && -n "${used_memory}" ]]; then
        usage_percent=$(( used_memory * 100 / max_memory ))
        if [[ "${usage_percent}" -gt 90 ]]; then
            echo -e "${RED}KRITISCH${NC}  Speicher: ${usage_percent}% (${used_human})"
            send_alert "CRITICAL" "${master_name}: Speicher bei ${usage_percent}%"
            raise 2
        elif [[ "${usage_percent}" -gt 80 ]]; then
            echo -e "${YELLOW}WARNUNG${NC}   Speicher: ${usage_percent}% (${used_human})"
            send_alert "WARNING" "${master_name}: Speicher bei ${usage_percent}%"
            raise 1
        else
            echo -e "${GREEN}OK${NC}        Speicher: ${usage_percent}% (${used_human})"
        fi
    else
        echo "          Speicher: ${used_human:-unbekannt} (kein Limit gesetzt oder nicht lesbar)"
    fi

    # --- Evictions ----------------------------------------------------------
    # Fuer die Cache-Instanz mit volatile-lru ist das die wichtigere Zahl:
    # steigende evicted_keys bei gleichzeitig hohem Speicher heisst, dass
    # Tag-Index-Keys ohne TTL den Platz belegen (siehe Kapitel 7.3).
    stats="$(node INFO stats 2>/dev/null || true)"
    evicted="$(printf '%s\n' "${stats}" | awk -F: '/^evicted_keys:/ {print $2}' | tr -d '\r')"
    echo "          Evictions gesamt: ${evicted:-N/A}"

    # --- Hit-Rate -----------------------------------------------------------
    hits="$(printf '%s\n' "${stats}" | awk -F: '/^keyspace_hits:/ {print $2}' | tr -d '\r')"
    misses="$(printf '%s\n' "${stats}" | awk -F: '/^keyspace_misses:/ {print $2}' | tr -d '\r')"

    if [[ " ${HITRATE_MASTERS} " != *" ${master_name} "* ]]; then
        echo "          Hit-Rate: nicht bewertet (keine Cache-Instanz)"
    elif [[ -n "${hits}" && -n "${misses}" && $(( hits + misses )) -gt 0 ]]; then
        hit_rate=$(( hits * 100 / (hits + misses) ))
        if [[ "${hit_rate}" -lt 60 ]]; then
            echo -e "${YELLOW}WARNUNG${NC}   Hit-Rate: ${hit_rate}%"
            send_alert "WARNING" "${master_name}: Hit-Rate nur ${hit_rate}%"
            raise 1
        elif [[ "${hit_rate}" -lt 80 ]]; then
            echo -e "${YELLOW}WARNUNG${NC}   Hit-Rate: ${hit_rate}%"
            raise 1
        else
            echo -e "${GREEN}OK${NC}        Hit-Rate: ${hit_rate}%"
        fi
    else
        echo "          Hit-Rate: N/A (noch keine Statistiken)"
    fi

    # --- Verbindungen -------------------------------------------------------
    connected="$(node INFO clients 2>/dev/null | awk -F: '/^connected_clients:/ {print $2}' | tr -d '\r')"
    rejected="$(printf '%s\n' "${stats}" | awk -F: '/^rejected_connections:/ {print $2}' | tr -d '\r')"

    echo "          Verbundene Clients: ${connected:-N/A}"
    if [[ -n "${rejected}" && "${rejected}" -gt 0 ]]; then
        echo -e "${YELLOW}WARNUNG${NC}   Abgewiesene Verbindungen: ${rejected}"
        send_alert "WARNING" "${master_name}: ${rejected} abgewiesene Verbindungen"
        raise 1
    fi
done

echo ""
echo "==========================================="
case "${exit_code}" in
    0) echo "Ergebnis: OK" ;;
    1) echo "Ergebnis: WARNUNG" ;;
    *) echo "Ergebnis: KRITISCH" ;;
esac
echo "==========================================="

exit "${exit_code}"
