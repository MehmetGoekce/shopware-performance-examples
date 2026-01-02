#!/bin/bash
#
# Cache-Hit-Rate aus Redis auslesen
# Verwendung: ./cache-hit-rate.sh [redis-host] [redis-port]
#
# Zielwerte:
#   - E-Commerce optimal: >95%
#   - Guter Wert: 80-95%
#   - Minimum akzeptabel: >70%

REDIS_HOST="${1:-localhost}"
REDIS_PORT="${2:-6379}"

echo "=== Redis Cache Statistics ==="
echo "Host: ${REDIS_HOST}:${REDIS_PORT}"
echo ""

# Redis INFO abrufen
INFO=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO stats 2>/dev/null)

if [[ $? -ne 0 ]]; then
    echo "FEHLER: Kann nicht zu Redis verbinden"
    echo "Pruefen Sie:"
    echo "  1. Redis laeuft: sudo systemctl status redis-server"
    echo "  2. Host/Port korrekt: redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} ping"
    exit 1
fi

# Hits und Misses extrahieren
HITS=$(echo "${INFO}" | grep "keyspace_hits:" | cut -d: -f2 | tr -d '\r')
MISSES=$(echo "${INFO}" | grep "keyspace_misses:" | cut -d: -f2 | tr -d '\r')

if [[ -z "${HITS}" ]] || [[ -z "${MISSES}" ]]; then
    echo "Keine Cache-Statistiken gefunden"
    exit 1
fi

# Hit-Rate berechnen
TOTAL=$((HITS + MISSES))

if [[ ${TOTAL} -eq 0 ]]; then
    echo "Noch keine Cache-Operationen (kein Traffic)"
    exit 0
fi

# Bash Integer-Division, dann Dezimal berechnen
HIT_RATE_INT=$((HITS * 100 / TOTAL))
HIT_RATE_DECIMAL=$((HITS * 10000 / TOTAL % 100))

echo "Cache Hits:     ${HITS}"
echo "Cache Misses:   ${MISSES}"
echo "Total Requests: ${TOTAL}"
echo ""
printf "Hit-Rate:       %d.%02d%%\n" ${HIT_RATE_INT} ${HIT_RATE_DECIMAL}

# Bewertung
echo ""
echo "=== Bewertung ==="

if [[ ${HIT_RATE_INT} -ge 95 ]]; then
    echo "EXCELLENT - Optimale Cache-Nutzung"
elif [[ ${HIT_RATE_INT} -ge 80 ]]; then
    echo "GUT - Cache arbeitet effektiv"
elif [[ ${HIT_RATE_INT} -ge 70 ]]; then
    echo "OK - Verbesserungspotential vorhanden"
else
    echo "WARNUNG - Cache-Effizienz zu niedrig"
    echo ""
    echo "Moegliche Ursachen:"
    echo "  - Zu kurze TTLs"
    echo "  - Zu aggressive Cache-Invalidierung"
    echo "  - Viele eingeloggte User (kein HTTP-Cache)"
    echo "  - Cache-Warmup nach Deployment fehlt"
fi

# Weitere nuetzliche Stats
echo ""
echo "=== Weitere Redis-Metriken ==="

MEMORY=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO memory 2>/dev/null | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
KEYS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" DBSIZE 2>/dev/null | awk '{print $2}')
UPTIME=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO server 2>/dev/null | grep "uptime_in_days:" | cut -d: -f2 | tr -d '\r')

echo "Speicherverbrauch: ${MEMORY}"
echo "Anzahl Keys:       ${KEYS}"
echo "Uptime:            ${UPTIME} Tage"
