#!/bin/bash
#
# Problem 15: Langsame Cronjobs blockieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Analysiert Cronjob-Scheduling und identifiziert Performance-Probleme.
#
# Verwendung: ./analyze-cronjobs.sh [SHOP_PATH]
#

set -e

SHOP_PATH="${1:-.}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Peak-Traffic Zeiten (zu vermeiden)
PEAK_START=9
PEAK_END=18

echo "=== Cronjob Analyse ==="
echo "Shop: $SHOP_PATH"
echo ""

ISSUES=0

# Check 1: System Crontab
echo -e "${BLUE}1. System Crontab${NC}"

CRONTAB_ENTRIES=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "")

if [ -n "$CRONTAB_ENTRIES" ]; then
    echo "   Gefundene Cronjobs:"
    echo ""

    echo "$CRONTAB_ENTRIES" | while read -r line; do
        # Extrahiere Stunde (zweites Feld bei Standard-Cron)
        HOUR=$(echo "$line" | awk '{print $2}')

        # Prüfe ob numerisch und in Peak-Zeit
        if [[ "$HOUR" =~ ^[0-9]+$ ]]; then
            if [ "$HOUR" -ge "$PEAK_START" ] && [ "$HOUR" -le "$PEAK_END" ]; then
                echo -e "   ${YELLOW}⚠ Peak-Zeit:${NC} $line"
                ISSUES=$((ISSUES + 1))
            else
                echo -e "   ${GREEN}✓${NC} $line"
            fi
        elif [ "$HOUR" = "*" ]; then
            echo -e "   ${YELLOW}⚠ Läuft stündlich:${NC} $line"
        else
            echo "   $line"
        fi
    done
else
    echo "   Keine Cronjobs in crontab gefunden"
fi

# Check 2: Shopware Scheduled Tasks
echo ""
echo -e "${BLUE}2. Shopware Scheduled Tasks${NC}"

if [ -f "$SHOP_PATH/bin/console" ]; then
    # Liste scheduled tasks
    TASKS=$(php "$SHOP_PATH/bin/console" scheduled-task:list 2>/dev/null || echo "")

    if [ -n "$TASKS" ]; then
        echo "   Aktive Tasks:"
        echo "$TASKS" | head -20

        # Zähle überfällige Tasks
        OVERDUE=$(echo "$TASKS" | grep -c "overdue" 2>/dev/null || echo "0")

        if [ "$OVERDUE" -gt 0 ]; then
            echo ""
            echo -e "   ${RED}$OVERDUE überfällige Task(s)!${NC}"
            ISSUES=$((ISSUES + 1))
        fi
    else
        echo "   Konnte Tasks nicht auflisten"
    fi
else
    echo "   Shopware Console nicht verfügbar"
fi

# Check 3: Message Queue Worker
echo ""
echo -e "${BLUE}3. Message Queue Status${NC}"

# Prüfe ob Worker laufen
WORKER_COUNT=$(pgrep -f "messenger:consume" 2>/dev/null | wc -l || echo "0")
echo "   Aktive Worker-Prozesse: $WORKER_COUNT"

if [ "$WORKER_COUNT" -eq 0 ]; then
    echo -e "   ${YELLOW}Keine Worker aktiv!${NC}"
    echo "   Empfehlung: Supervisor für messenger:consume einrichten"
    ISSUES=$((ISSUES + 1))
fi

# Queue-Größe prüfen (wenn Redis)
if command -v redis-cli &> /dev/null; then
    QUEUE_SIZE=$(redis-cli LLEN messenger_messages 2>/dev/null || echo "?")
    if [ "$QUEUE_SIZE" != "?" ]; then
        echo "   Queue-Größe: $QUEUE_SIZE"

        if [ "$QUEUE_SIZE" -gt 1000 ]; then
            echo -e "   ${RED}Queue zu voll (> 1000)!${NC}"
            ISSUES=$((ISSUES + 1))
        fi
    fi
fi

# Check 4: Supervisor-Konfiguration
echo ""
echo -e "${BLUE}4. Supervisor Konfiguration${NC}"

SUPERVISOR_CONF="/etc/supervisor/conf.d"

if [ -d "$SUPERVISOR_CONF" ]; then
    SHOPWARE_SUPERVISOR=$(ls "$SUPERVISOR_CONF"/*shopware* 2>/dev/null | head -1 || echo "")

    if [ -n "$SHOPWARE_SUPERVISOR" ]; then
        echo -e "   ${GREEN}Supervisor-Konfiguration gefunden${NC}"
        echo "   Datei: $SHOPWARE_SUPERVISOR"

        # Worker-Anzahl
        NUMPROCS=$(grep "numprocs" "$SHOPWARE_SUPERVISOR" 2>/dev/null | head -1)
        echo "   $NUMPROCS"
    else
        echo -e "   ${YELLOW}Keine Shopware Supervisor-Konfiguration${NC}"
    fi
else
    echo "   Supervisor nicht installiert"
fi

# Check 5: Indexer-Jobs
echo ""
echo -e "${BLUE}5. Indexer Status${NC}"

if [ -f "$SHOP_PATH/bin/console" ]; then
    # Indexer-Liste
    INDEXERS=$(php "$SHOP_PATH/bin/console" dal:refresh:index --list 2>/dev/null | grep -E "^\s*-" || echo "")

    if [ -n "$INDEXERS" ]; then
        INDEX_COUNT=$(echo "$INDEXERS" | wc -l)
        echo "   Registrierte Indexer: $INDEX_COUNT"

        # Prüfe letzte Indexierung
        if [ -f "$SHOP_PATH/var/log/prod.log" ]; then
            LAST_INDEX=$(grep "Indexing" "$SHOP_PATH/var/log/prod.log" 2>/dev/null | tail -1)
            if [ -n "$LAST_INDEX" ]; then
                echo "   Letzte Indexierung: $(echo "$LAST_INDEX" | cut -d' ' -f1-2)"
            fi
        fi
    fi
fi

# Check 6: Cleanup-Jobs
echo ""
echo -e "${BLUE}6. Cleanup-Jobs${NC}"

# Prüfe ob Cleanup konfiguriert ist
echo -n "   Cart Cleanup... "
if crontab -l 2>/dev/null | grep -q "cart:cleanup"; then
    echo -e "${GREEN}konfiguriert${NC}"
else
    echo -e "${YELLOW}nicht gefunden${NC}"
    echo "   Empfehlung: bin/console cart:cleanup regelmäßig ausführen"
fi

echo -n "   Log Rotation... "
if [ -f "/etc/logrotate.d/shopware" ] || [ -f "$SHOP_PATH/logrotate.conf" ]; then
    echo -e "${GREEN}konfiguriert${NC}"
else
    echo -e "${YELLOW}nicht gefunden${NC}"
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}Cronjob-Konfiguration OK.${NC}"
    exit 0
else
    echo -e "${YELLOW}$ISSUES Problem(e) gefunden.${NC}"
    echo ""
    echo "Empfohlene Optimierungen:"
    echo ""
    echo "  1. Cronjobs in Low-Traffic-Zeiten verschieben:"
    echo "     0 3 * * * /var/www/shop/bin/console scheduled-task:run"
    echo ""
    echo "  2. Message Queue Worker einrichten:"
    echo "     supervisor mit messenger:consume konfigurieren"
    echo ""
    echo "  3. Regelmäßige Cleanups:"
    echo "     0 4 * * * bin/console cart:cleanup"
    echo "     0 5 * * 0 bin/console dal:refresh:index"
    exit 1
fi
