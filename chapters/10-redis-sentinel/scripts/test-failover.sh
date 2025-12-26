#!/bin/bash
#
# Redis Sentinel Failover Test
# Testet automatisches Failover und misst die Zeit
#
# Verwendung: ./test-failover.sh [sentinel_port]
#
# Voraussetzungen:
#   - Redis Sentinel muss laufen
#   - Mindestens 2 Replicas muessen verbunden sein

SENTINEL_PORT="${1:-26379}"
SENTINEL_CLI="redis-cli -p $SENTINEL_PORT"
MASTER_NAME="shopware-master"

echo "=== Redis Sentinel Failover Test ==="
echo ""
echo "Sentinel Port: $SENTINEL_PORT"
echo "Master Name:   $MASTER_NAME"
echo ""

# === Vorab-Pruefungen ===

# Sentinel erreichbar?
if ! $SENTINEL_CLI PING > /dev/null 2>&1; then
    echo "FEHLER: Sentinel auf Port $SENTINEL_PORT nicht erreichbar!"
    exit 1
fi

# Quorum pruefen
QUORUM_CHECK=$($SENTINEL_CLI SENTINEL ckquorum $MASTER_NAME 2>&1)
if [[ $QUORUM_CHECK != *"OK"* ]]; then
    echo "FEHLER: Sentinel Quorum nicht erreicht!"
    echo "$QUORUM_CHECK"
    exit 1
fi
echo "Sentinel Quorum: OK"

# Aktuellen Master ermitteln
MASTER_INFO=$($SENTINEL_CLI SENTINEL get-master-addr-by-name $MASTER_NAME)
MASTER_IP=$(echo $MASTER_INFO | awk '{print $1}')
MASTER_PORT=$(echo $MASTER_INFO | awk '{print $2}')

echo "Aktueller Master: $MASTER_IP:$MASTER_PORT"

# Replicas zaehlen
REPLICA_COUNT=$($SENTINEL_CLI SENTINEL replicas $MASTER_NAME | grep -c "name")
echo "Verbundene Replicas: $REPLICA_COUNT"

if [ "$REPLICA_COUNT" -lt 1 ]; then
    echo "FEHLER: Mindestens 1 Replica erforderlich fuer Failover!"
    exit 1
fi

echo ""
echo "=== Starte Failover Test ==="
echo ""

# Startzeit merken
START_TIME=$(date +%s%3N)

# Manuelles Failover ausloesen
echo "Loese manuelles Failover aus..."
$SENTINEL_CLI SENTINEL failover $MASTER_NAME

# Auf neuen Master warten (max 30 Sekunden)
echo "Warte auf Failover..."
for i in {1..30}; do
    sleep 1

    NEW_MASTER_INFO=$($SENTINEL_CLI SENTINEL get-master-addr-by-name $MASTER_NAME)
    NEW_MASTER_IP=$(echo $NEW_MASTER_INFO | awk '{print $1}')

    if [ "$NEW_MASTER_IP" != "$MASTER_IP" ]; then
        END_TIME=$(date +%s%3N)
        FAILOVER_TIME=$((END_TIME - START_TIME))

        echo ""
        echo "==========================================="
        echo "=== FAILOVER ERFOLGREICH ==="
        echo "==========================================="
        echo ""
        echo "Alter Master: $MASTER_IP:$MASTER_PORT"
        echo "Neuer Master: $NEW_MASTER_IP:$NEW_MASTER_PORT"
        echo ""
        echo "Failover-Zeit: ${FAILOVER_TIME}ms"
        echo ""

        # Status nach Failover
        echo "=== Cluster-Status nach Failover ==="
        echo ""
        echo "Master:"
        $SENTINEL_CLI SENTINEL master $MASTER_NAME | grep -E "(ip|port|flags|num-slaves)"
        echo ""
        echo "Replicas:"
        $SENTINEL_CLI SENTINEL replicas $MASTER_NAME | grep -E "(ip|port|flags)" | head -10

        exit 0
    fi

    echo "  Warte... ($i/30 Sekunden)"
done

echo ""
echo "FEHLER: Failover nicht innerhalb von 30 Sekunden abgeschlossen!"
echo ""
echo "Sentinel-Logs pruefen:"
echo "  tail -50 /var/log/redis/sentinel.log"
exit 1
