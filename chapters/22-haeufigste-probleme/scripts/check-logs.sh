#!/bin/bash
#
# Problem 17: Große Log-Dateien diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_PATH="${2:-.}"

echo "=== Problem 17: Log-Dateien Größe ==="
echo ""

LOG_DIR="$SHOP_PATH/var/log"

if [ ! -d "$LOG_DIR" ]; then
    echo "⚠ Log-Verzeichnis nicht gefunden: $LOG_DIR"
    exit 1
fi

# Gesamtgröße
echo "1. Gesamtgröße des Log-Verzeichnisses..."
TOTAL_SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
echo "   $LOG_DIR: $TOTAL_SIZE"

# Einzelne Dateien
echo ""
echo "2. Größte Log-Dateien..."
echo ""
du -ah "$LOG_DIR"/*.log 2>/dev/null | sort -rh | head -10 | while read -r size file; do
    echo "   $size  $(basename "$file")"
done

# Warnung bei großen Logs
TOTAL_BYTES=$(du -sb "$LOG_DIR" 2>/dev/null | cut -f1)
if [ "${TOTAL_BYTES:-0}" -gt 1073741824 ]; then
    echo ""
    echo "   ✗ WARNUNG: Log-Verzeichnis > 1 GB!"
    PROBLEM=1
elif [ "${TOTAL_BYTES:-0}" -gt 104857600 ]; then
    echo ""
    echo "   ⚠ Hinweis: Log-Verzeichnis > 100 MB"
    PROBLEM=0
else
    echo ""
    echo "   ✓ Log-Größe im normalen Bereich"
    PROBLEM=0
fi

# Logrotate prüfen
echo ""
echo "3. Logrotate Status..."
if [ -f /etc/logrotate.d/shopware ]; then
    echo "   ✓ Shopware Logrotate-Konfiguration gefunden"
else
    echo "   ⚠ Keine Shopware Logrotate-Konfiguration"
    echo "   → Siehe config/logrotate.conf"
fi

# Empfehlung
echo ""
echo "=== Empfehlung ==="
echo ""
echo "1. Alte Logs bereinigen:"
echo "   find $LOG_DIR -name '*.log' -mtime +7 -delete"
echo ""
echo "2. Logrotate einrichten:"
echo "   sudo cp config/logrotate.conf /etc/logrotate.d/shopware"
echo ""
echo "3. Monolog auf 'error' setzen in Produktion:"
echo "   config/packages/prod/monolog.yaml"

exit ${PROBLEM:-0}
