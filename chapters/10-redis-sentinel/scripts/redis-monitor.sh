#!/bin/bash
#
# Redis Sentinel Health Check & Monitoring
# Prueft Sentinel-Cluster und Redis-Metriken
#
# Verwendung: REDIS_AUTH_PASSWORD muss in der Env gesetzt sein.
#   Beispiel: source /etc/profile.d/redis-credentials.sh && ./redis-monitor.sh
#
# Fuer Cron (alle 5 Minuten) mit env-File:
#   */5 * * * * . /etc/profile.d/redis-credentials.sh && /opt/redis/redis-monitor.sh >> /var/log/redis/health.log 2>&1

# Fail fast wenn das Passwort nicht in der Env steht — niemals leer als Default.
: "${REDIS_AUTH_PASSWORD:?REDIS_AUTH_PASSWORD muss gesetzt sein (siehe /etc/profile.d/redis-credentials.sh)}"

SENTINEL_PORT=26379
MASTER_NAME="shopware-master"

REDIS_CLI="redis-cli -a ${REDIS_AUTH_PASSWORD}"
SENTINEL_CLI="redis-cli -p ${SENTINEL_PORT}"

# Farben fuer Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Alert-Funktionen (anpassen!)
send_alert() {
    local level="$1"
    local message="$2"

    # Email (wenn mail installiert)
    # echo "${message}" | mail -s "[${level}] Redis Alert" ops@example.com

    # Slack Webhook (anpassen!)
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"text\":\"[${level}] ${message}\"}" \
    #   https://hooks.slack.com/services/YOUR/WEBHOOK

    echo "[${level}] ${message}"
}

echo "==========================================="
echo "=== Redis Sentinel Health Check ==="
echo "==========================================="
echo "Zeitpunkt: $(date)"
echo ""

# =============================================================================
# 1. Sentinel Quorum
# =============================================================================

echo "=== 1. Sentinel Quorum ==="

QUORUM_CHECK=$(${SENTINEL_CLI} SENTINEL ckquorum ${MASTER_NAME} 2>&1)
if [[ ${QUORUM_CHECK} == *"OK"* ]]; then
    echo -e "${GREEN}OK${NC} Sentinel Quorum erreichbar"
else
    echo -e "${RED}KRITISCH${NC} Sentinel Quorum NICHT erreichbar!"
    send_alert "CRITICAL" "Redis Sentinel Quorum verloren: ${QUORUM_CHECK}"
fi

# =============================================================================
# 2. Master Status
# =============================================================================

echo ""
echo "=== 2. Master Status ==="

MASTER_INFO=$(${SENTINEL_CLI} SENTINEL get-master-addr-by-name ${MASTER_NAME} 2>/dev/null)
MASTER_IP=$(echo "${MASTER_INFO}" | awk '{print $1}')
MASTER_PORT=$(echo "${MASTER_INFO}" | awk '{print $2}')

if [[ -z "${MASTER_IP}" ]]; then
    echo -e "${RED}KRITISCH${NC} Kein Master gefunden!"
    send_alert "CRITICAL" "Redis Master nicht verfuegbar"
    exit 1
fi

echo "Master: ${MASTER_IP}:${MASTER_PORT}"

# Master erreichbar?
if ${REDIS_CLI} -h ${MASTER_IP} PING > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC} Master erreichbar"
else
    echo -e "${RED}KRITISCH${NC} Master nicht erreichbar!"
    send_alert "CRITICAL" "Redis Master ${MASTER_IP} nicht erreichbar"
fi

# =============================================================================
# 3. Replica Status
# =============================================================================

echo ""
echo "=== 3. Replica Status ==="

REPLICA_COUNT=$(${SENTINEL_CLI} SENTINEL replicas ${MASTER_NAME} 2>/dev/null | grep -c "name")

if [[ "${REPLICA_COUNT}" -ge 2 ]]; then
    echo -e "${GREEN}OK${NC} ${REPLICA_COUNT} Replicas verbunden"
elif [[ "${REPLICA_COUNT}" -eq 1 ]]; then
    echo -e "${YELLOW}WARNUNG${NC} Nur ${REPLICA_COUNT} Replica verbunden (erwartet: 2)"
    send_alert "WARNING" "Redis: Nur 1 Replica verbunden"
else
    echo -e "${RED}KRITISCH${NC} Keine Replicas verbunden!"
    send_alert "CRITICAL" "Redis: Keine Replicas verbunden"
fi

# =============================================================================
# 4. Memory Status
# =============================================================================

echo ""
echo "=== 4. Memory Status ==="

MEMORY_INFO=$(${REDIS_CLI} -h ${MASTER_IP} INFO memory 2>/dev/null)
USED_MEMORY=$(echo "${MEMORY_INFO}" | grep "used_memory:" | cut -d: -f2 | tr -d '\r')
USED_MEMORY_HUMAN=$(echo "${MEMORY_INFO}" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
MAX_MEMORY=$(${REDIS_CLI} -h ${MASTER_IP} CONFIG GET maxmemory 2>/dev/null | tail -1)

if [[ -n "${MAX_MEMORY}" ]] && [[ "${MAX_MEMORY}" -gt 0 ]]; then
    USAGE_PERCENT=$((USED_MEMORY * 100 / MAX_MEMORY))

    if [[ ${USAGE_PERCENT} -gt 90 ]]; then
        echo -e "${RED}KRITISCH${NC} Memory: ${USAGE_PERCENT}% (${USED_MEMORY_HUMAN})"
        send_alert "CRITICAL" "Redis Memory bei ${USAGE_PERCENT}%"
    elif [[ ${USAGE_PERCENT} -gt 80 ]]; then
        echo -e "${YELLOW}WARNUNG${NC} Memory: ${USAGE_PERCENT}% (${USED_MEMORY_HUMAN})"
        send_alert "WARNING" "Redis Memory bei ${USAGE_PERCENT}%"
    else
        echo -e "${GREEN}OK${NC} Memory: ${USAGE_PERCENT}% (${USED_MEMORY_HUMAN})"
    fi
else
    echo "Memory: ${USED_MEMORY_HUMAN} (kein Limit gesetzt)"
fi

# =============================================================================
# 5. Hit Rate
# =============================================================================

echo ""
echo "=== 5. Cache Hit Rate ==="

STATS=$(${REDIS_CLI} -h ${MASTER_IP} INFO stats 2>/dev/null)
HITS=$(echo "${STATS}" | grep "keyspace_hits:" | cut -d: -f2 | tr -d '\r')
MISSES=$(echo "${STATS}" | grep "keyspace_misses:" | cut -d: -f2 | tr -d '\r')

if [[ -n "${HITS}" ]] && [[ -n "${MISSES}" ]] && [[ $((HITS + MISSES)) -gt 0 ]]; then
    HIT_RATE=$((HITS * 100 / (HITS + MISSES)))

    if [[ ${HIT_RATE} -lt 60 ]]; then
        echo -e "${RED}KRITISCH${NC} Hit Rate: ${HIT_RATE}%"
        send_alert "WARNING" "Redis Hit Rate nur ${HIT_RATE}%"
    elif [[ ${HIT_RATE} -lt 80 ]]; then
        echo -e "${YELLOW}WARNUNG${NC} Hit Rate: ${HIT_RATE}%"
    else
        echo -e "${GREEN}OK${NC} Hit Rate: ${HIT_RATE}%"
    fi
else
    echo "Hit Rate: N/A (keine Statistiken)"
fi

# =============================================================================
# 6. Verbindungen
# =============================================================================

echo ""
echo "=== 6. Verbindungen ==="

CLIENTS=$(${REDIS_CLI} -h ${MASTER_IP} INFO clients 2>/dev/null)
CONNECTED=$(echo "${CLIENTS}" | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
REJECTED=$(${REDIS_CLI} -h ${MASTER_IP} INFO stats 2>/dev/null | grep "rejected_connections:" | cut -d: -f2 | tr -d '\r')

echo "Verbundene Clients: ${CONNECTED}"

if [[ -n "${REJECTED}" ]] && [[ "${REJECTED}" -gt 0 ]]; then
    echo -e "${YELLOW}WARNUNG${NC} Abgewiesene Verbindungen: ${REJECTED}"
    send_alert "WARNING" "Redis: ${REJECTED} abgewiesene Verbindungen"
else
    echo -e "${GREEN}OK${NC} Keine abgewiesenen Verbindungen"
fi

# =============================================================================
# Zusammenfassung
# =============================================================================

echo ""
echo "==========================================="
echo "=== Zusammenfassung ==="
echo "==========================================="
echo "Master:    ${MASTER_IP}:${MASTER_PORT}"
echo "Replicas:  ${REPLICA_COUNT}"
echo "Memory:    ${USAGE_PERCENT:-N/A}%"
echo "Hit Rate:  ${HIT_RATE:-N/A}%"
echo "Clients:   ${CONNECTED:-N/A}"
echo "==========================================="
