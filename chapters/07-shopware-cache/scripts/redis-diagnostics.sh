#!/bin/bash
#
# Redis Diagnostik-Script fuer Shopware
# Verwendung: ./redis-diagnostics.sh [redis-host] [redis-port]
#
# Prueft haeufige Probleme und gibt Loesungsvorschlaege

REDIS_HOST="${1:-localhost}"
REDIS_PORT="${2:-6379}"

echo "=========================================="
echo "Redis Diagnostik fuer Shopware"
echo "=========================================="
echo "Host: ${REDIS_HOST}:${REDIS_PORT}"
echo "Zeit: $(date)"
echo ""

# Funktion fuer Status-Ausgabe
status_ok() { echo -e "\e[32m[OK]\e[0m $1"; }
status_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
status_fail() { echo -e "\e[31m[FAIL]\e[0m $1"; }

# 1. Verbindungstest
echo "=== 1. Verbindung ==="
if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" ping > /dev/null 2>&1; then
    status_ok "Redis erreichbar"
else
    status_fail "Redis nicht erreichbar"
    echo ""
    echo "Loesungen:"
    echo "  1. Redis starten: sudo systemctl start redis-server"
    echo "  2. Port pruefen: netstat -tlnp | grep 6379"
    echo "  3. Firewall: sudo ufw allow 6379/tcp"
    exit 1
fi
echo ""

# 2. Speicher-Check
echo "=== 2. Speicher ==="
MEMORY_INFO=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO memory)
USED_MEMORY=$(echo "${MEMORY_INFO}" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
MAX_MEMORY=$(echo "${MEMORY_INFO}" | grep "maxmemory_human:" | cut -d: -f2 | tr -d '\r')
EVICTION=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" CONFIG GET maxmemory-policy | tail -1)

echo "Verwendet: ${USED_MEMORY}"
echo "Maximum:   ${MAX_MEMORY}"
echo "Eviction:  ${EVICTION}"

if [[ "${MAX_MEMORY}" = "0B" ]]; then
    status_warn "Kein Speicher-Limit gesetzt (kann RAM fuellen!)"
    echo "  Empfehlung: maxmemory 2gb in redis.conf"
else
    status_ok "Speicher-Limit konfiguriert"
fi

if [[ "${EVICTION}" = "noeviction" ]]; then
    status_warn "Eviction-Policy ist 'noeviction' - Fehler bei vollem Speicher"
    echo "  Empfehlung: maxmemory-policy allkeys-lru"
elif [[ "${EVICTION}" = "allkeys-lru" ]] || [[ "${EVICTION}" = "volatile-lru" ]]; then
    status_ok "Eviction-Policy korrekt: ${EVICTION}"
fi
echo ""

# 3. Persistenz-Check
echo "=== 3. Persistenz ==="
PERSISTENCE=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" CONFIG GET save | tail -1)
AOF=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" CONFIG GET appendonly | tail -1)

if [[ -z "${PERSISTENCE}" ]] || [[ "${PERSISTENCE}" = "" ]]; then
    status_ok "RDB Persistenz deaktiviert (empfohlen fuer Cache)"
else
    status_warn "RDB Persistenz aktiv: ${PERSISTENCE}"
    echo "  Fuer reinen Cache: save \"\" in redis.conf"
fi

if [[ "${AOF}" = "no" ]]; then
    status_ok "AOF deaktiviert (empfohlen fuer Cache)"
else
    status_warn "AOF aktiv - verlangsamt Schreiboperationen"
fi
echo ""

# 4. Shopware-spezifische Keys
echo "=== 4. Shopware Cache-Keys ==="
SHOPWARE_KEYS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" KEYS "shopware*" 2>/dev/null | wc -l)
SESSION_KEYS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" KEYS "sf_s*" 2>/dev/null | wc -l)

echo "Shopware Cache-Keys: ${SHOPWARE_KEYS}"
echo "Session-Keys:        ${SESSION_KEYS}"

if [[ "${SHOPWARE_KEYS}" -eq 0 ]]; then
    status_warn "Keine Shopware-Keys gefunden"
    echo "  Moegliche Ursachen:"
    echo "  - Shopware nutzt Filesystem-Cache (framework.yaml pruefen)"
    echo "  - REDIS_URL in .env nicht gesetzt"
    echo "  - Cache wurde gerade geleert"
else
    status_ok "Shopware nutzt Redis als Cache-Backend"
fi
echo ""

# 5. Performance-Metriken
echo "=== 5. Performance ==="
STATS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO stats)
HITS=$(echo "${STATS}" | grep "keyspace_hits:" | cut -d: -f2 | tr -d '\r')
MISSES=$(echo "${STATS}" | grep "keyspace_misses:" | cut -d: -f2 | tr -d '\r')
TOTAL=$((HITS + MISSES))

if [[ ${TOTAL} -gt 0 ]]; then
    HIT_RATE=$((HITS * 100 / TOTAL))
    echo "Cache-Hit-Rate: ${HIT_RATE}%"

    if [[ ${HIT_RATE} -ge 90 ]]; then
        status_ok "Ausgezeichnete Hit-Rate"
    elif [[ ${HIT_RATE} -ge 70 ]]; then
        status_warn "Hit-Rate koennte besser sein"
    else
        status_fail "Niedrige Hit-Rate - Cache-Effizienz pruefen"
    fi
else
    echo "Noch keine Cache-Statistiken (kein Traffic)"
fi

# Latenz-Check
LATENCY=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --latency -c 10 2>&1 | grep "avg" | awk '{print $3}')
if [[ -n "${LATENCY}" ]]; then
    echo "Durchschnittliche Latenz: ${LATENCY}ms"
    # Latenz ist in ms, als Integer vergleichen
    LATENCY_INT=${LATENCY%.*}
    if [[ "${LATENCY_INT:-0}" -le 1 ]]; then
        status_ok "Latenz im optimalen Bereich"
    else
        status_warn "Latenz erhoet - Netzwerk oder Last pruefen"
    fi
fi
echo ""

# 6. Grosse Keys finden
echo "=== 6. Grosse Keys (potentielle Probleme) ==="
redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --bigkeys 2>/dev/null | grep -A1 "Biggest" | head -10
echo ""

# 7. Client-Verbindungen
echo "=== 7. Clients ==="
CLIENTS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO clients)
CONNECTED=$(echo "${CLIENTS}" | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
BLOCKED=$(echo "${CLIENTS}" | grep "blocked_clients:" | cut -d: -f2 | tr -d '\r')

echo "Verbundene Clients: ${CONNECTED}"
echo "Blockierte Clients: ${BLOCKED}"

if [[ "${BLOCKED:-0}" -gt 0 ]]; then
    status_warn "Es gibt blockierte Clients - potentielles Locking-Problem"
fi
echo ""

# Zusammenfassung
echo "=========================================="
echo "Diagnose abgeschlossen"
echo "=========================================="
