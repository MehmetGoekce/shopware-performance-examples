#!/bin/bash
#
# PHP-FPM pm.max_children Kalkulator
# Berechnet die optimale Anzahl Worker fuer Ihren Server
#
# Verwendung:
#   1. Werte unten anpassen
#   2. ./calculate-max-children.sh ausfuehren
#   3. Empfehlung in shopware-fpm.conf uebernehmen
#
# Quelle: https://tideways.com/profiler/blog/an-introduction-to-php-fpm-tuning

# =============================================================================
# KONFIGURATION - ANPASSEN!
# =============================================================================

# Server-RAM in MB (z.B. 16384 fuer 16 GB)
TOTAL_RAM_MB=16384

# Reserve fuer Betriebssystem (empfohlen: 1-2 GB)
OS_RESERVE_MB=2048

# RAM fuer andere Services (MySQL, Redis, Nginx, Elasticsearch, etc.)
# Grobe Schaetzung:
#   MySQL: 2-8 GB (je nach Buffer Pool)
#   Redis: 0.5-2 GB
#   Elasticsearch: 2-4 GB
#   Nginx: 0.1 GB
OTHER_SERVICES_MB=4096

# Sicherheitspuffer (20% empfohlen)
BUFFER_PERCENT=20

# Durchschnittlicher RAM pro Worker in MB
# Ermitteln Sie diesen Wert mit ./php-fpm-memory.sh
# Typische Werte fuer Shopware: 80-150 MB
AVG_WORKER_MB=128

# =============================================================================
# BERECHNUNG (nicht aendern)
# =============================================================================

AVAILABLE_RAM=$((TOTAL_RAM_MB - OS_RESERVE_MB - OTHER_SERVICES_MB))
BUFFER=$((AVAILABLE_RAM * BUFFER_PERCENT / 100))
PHP_RAM=$((AVAILABLE_RAM - BUFFER))
MAX_CHILDREN=$((PHP_RAM / AVG_WORKER_MB))

# Mindestens 8 Worker
if [[ ${MAX_CHILDREN} -lt 8 ]]; then
    MAX_CHILDREN=8
fi

# Abgeleitete Werte
START_SERVERS=$((MAX_CHILDREN / 4))
MIN_SPARE=$((MAX_CHILDREN / 4))
MAX_SPARE=$((MAX_CHILDREN * 3 / 4))

# =============================================================================
# AUSGABE
# =============================================================================

echo "=== PHP-FPM Kalkulation ==="
echo ""
echo "Eingabewerte:"
echo "  Gesamt-RAM:        ${TOTAL_RAM_MB} MB"
echo "  OS-Reserve:        ${OS_RESERVE_MB} MB"
echo "  Andere Services:   ${OTHER_SERVICES_MB} MB"
echo "  Worker-RAM:        ${AVG_WORKER_MB} MB"
echo "  Sicherheitspuffer: ${BUFFER_PERCENT}%"
echo ""
echo "Berechnung:"
echo "  Verfuegbar:        ${AVAILABLE_RAM} MB"
echo "  Minus Buffer:      ${BUFFER} MB"
echo "  Fuer PHP-FPM:      ${PHP_RAM} MB"
echo ""
echo "=== EMPFOHLENE WERTE ==="
echo ""
echo "pm = dynamic"
echo "pm.max_children = ${MAX_CHILDREN}"
echo "pm.start_servers = ${START_SERVERS}"
echo "pm.min_spare_servers = ${MIN_SPARE}"
echo "pm.max_spare_servers = ${MAX_SPARE}"
echo ""
echo "=== Zum Kopieren in shopware-fpm.conf ==="
cat << EOF

pm = dynamic
pm.max_children = ${MAX_CHILDREN}
pm.start_servers = ${START_SERVERS}
pm.min_spare_servers = ${MIN_SPARE}
pm.max_spare_servers = ${MAX_SPARE}

EOF

echo ""
echo "WARNUNG: Diese Berechnung ist eine Schaetzung!"
echo "         Ueberwachen Sie den Server nach der Anwendung."
echo "         'max children reached' darf NIE auftreten."
