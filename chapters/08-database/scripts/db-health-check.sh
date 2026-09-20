#!/bin/bash
# Datenbank-Gesundheitscheck fuer Shopware
# Kapitel 8: Datenbank-Optimierung
#
# Prueft Verbindung, Buffer Pool, Verbindungsauslastung, Slow-Query-Log,
# Fragmentierung und die wichtigsten Konfigurationswerte.
#
# Verwendung:
#   ./db-health-check.sh                 # Datenbank "shopware"
#   ./db-health-check.sh meineshopdb
#
# Zugangsdaten kommen aus ~/.my.cnf oder aus der Umgebungsvariablen MYSQL:
#   MYSQL="mysql -h db -u shopware -pgeheim" ./db-health-check.sh shopware
#
# MySQL im Container:
#   MYSQL="docker exec -i db mysql -uroot -proot" ./db-health-check.sh
#
# NUR FUER MySQL 8.0. Auf MariaDB stehen die Statuswerte in
# information_schema.global_status statt in performance_schema.global_status,
# und performance_schema ist ab Werk aus. Das Skript sagt das und bricht ab.
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MYSQL="${MYSQL:-mysql}"
DB_NAME="shopware"

show_usage() {
    echo "Usage: $0 [datenbank]"
    echo ""
    echo "Argumente:"
    echo "  datenbank  Name der Shopware-Datenbank (Default: shopware)"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  MYSQL      Befehl fuer den MySQL-Client (Default: mysql)"
}

status_ok()   { printf "%b[OK]%b %s\n"   "$GREEN"  "$NC" "$1"; }
status_warn() { printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$1"; }
status_fail() { printf "%b[FAIL]%b %s\n" "$RED"    "$NC" "$1"; }

# Einzelwert aus MySQL holen (ohne Spaltenueberschrift)
query_value() {
    $MYSQL -N -B -e "$1" 2>/dev/null
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unbekannte Option: $1" >&2
            show_usage >&2
            exit 1
            ;;
        *)
            DB_NAME="$1"
            shift
            ;;
    esac
done

echo "=========================================="
echo "Datenbank-Gesundheitscheck: ${DB_NAME}"
echo "=========================================="
echo "Zeit: $(date)"
echo ""

# ==============================================================================
# 1. VERBINDUNG UND VORAUSSETZUNGEN
# ==============================================================================

echo "=== 1. Verbindung ==="

if $MYSQL -e "SELECT 1" > /dev/null 2>&1; then
    status_ok "MySQL erreichbar"
else
    status_fail "MySQL nicht erreichbar"
    exit 1
fi

SERVER_VERSION=$(query_value "SELECT @@version")
echo "Server: ${SERVER_VERSION}"

if [[ "$SERVER_VERSION" == *MariaDB* ]]; then
    status_fail "MariaDB erkannt - dieses Skript liest performance_schema.global_status, das es dort nicht gibt."
    echo "Auf MariaDB stattdessen information_schema.global_status verwenden (siehe buffer-pool-check.sql)."
    exit 2
fi

if [[ "$(query_value "SELECT @@performance_schema")" != "1" ]]; then
    status_fail "performance_schema ist aus - Buffer-Pool- und Index-Auswertung bleiben leer."
    echo "In der Serverkonfiguration 'performance_schema = ON' setzen, dann neu starten."
    exit 2
fi

if [[ -z "$(query_value "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${DB_NAME}'")" ]]; then
    status_fail "Datenbank '${DB_NAME}' existiert nicht"
    exit 2
fi

UPTIME=$(query_value "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime'")
echo "Uptime: ${UPTIME}s"
if [[ "${UPTIME}" -lt 3600 ]]; then
    status_warn "Server laeuft seit weniger als einer Stunde - alle Zaehler unten sind noch wenig aussagekraeftig"
fi
echo ""

# ==============================================================================
# 2. BUFFER POOL
# ==============================================================================

echo "=== 2. Buffer Pool ==="

BUFFER_SIZE=$(query_value "SELECT ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2)")
echo "Buffer Pool Groesse: ${BUFFER_SIZE} GB"

# Hit-Rate in Promille, damit die Auswertung ohne bc auskommt
HIT_RATE_PM=$(query_value "
SELECT ROUND((1 - (
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') /
    NULLIF((SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
)) * 1000, 0)")

if [[ -z "${HIT_RATE_PM}" ]] || [[ "${HIT_RATE_PM}" = "NULL" ]]; then
    status_warn "Hit-Rate nicht berechenbar - noch keine Lesezugriffe seit dem Serverstart"
else
    printf "Hit-Rate: %s.%s%%\n" "$((HIT_RATE_PM / 10))" "$((HIT_RATE_PM % 10))"
    # Schwellen sind Erfahrungswerte. Tideways nennt "schlechter als 90 %" als
    # Problemmarke; einen dokumentierten Zielwert gibt es in der MySQL-Doku nicht.
    if [[ "${HIT_RATE_PM}" -ge 999 ]]; then
        status_ok "Buffer Pool Hit-Rate sehr gut"
    elif [[ "${HIT_RATE_PM}" -ge 990 ]]; then
        status_ok "Buffer Pool Hit-Rate gut"
    elif [[ "${HIT_RATE_PM}" -ge 900 ]]; then
        status_warn "Buffer Pool Hit-Rate grenzwertig"
    else
        status_fail "Buffer Pool Hit-Rate zu niedrig - Buffer Pool erhoehen oder Working Set pruefen"
    fi
fi
echo ""

# ==============================================================================
# 3. VERBINDUNGEN
# ==============================================================================

echo "=== 3. Verbindungen ==="

MAX_CONN=$(query_value "SELECT @@max_connections")
CURRENT_CONN=$(query_value "SELECT COUNT(*) FROM information_schema.processlist")
CONN_PERCENT=$((CURRENT_CONN * 100 / MAX_CONN))

echo "Aktive Verbindungen: ${CURRENT_CONN} / ${MAX_CONN} (${CONN_PERCENT}%)"

if [[ ${CONN_PERCENT} -lt 70 ]]; then
    status_ok "Verbindungen im normalen Bereich"
elif [[ ${CONN_PERCENT} -lt 90 ]]; then
    status_warn "Verbindungen werden knapp"
else
    status_fail "Verbindungen kritisch hoch!"
fi
echo ""

# ==============================================================================
# 4. SLOW QUERIES
# ==============================================================================

echo "=== 4. Slow Queries ==="

SLOW_LOG=$(query_value "SELECT @@slow_query_log")
if [[ "${SLOW_LOG}" = "1" ]]; then
    status_ok "Slow Query Log aktiviert"

    echo "Slow Queries seit Start: $(query_value "
        SELECT VARIABLE_VALUE FROM performance_schema.global_status
        WHERE VARIABLE_NAME = 'Slow_queries'")"
    echo "Schwellwert: $(query_value "SELECT @@long_query_time")s"

    if [[ "$(query_value "SELECT @@log_queries_not_using_indexes")" = "1" ]]; then
        status_warn "log_queries_not_using_indexes ist an - das Log enthaelt auch Queries, die in Mikrosekunden fertig sind"
        echo "Fuer eine belastbare Slow-Query-Auswertung voruebergehend ausschalten:"
        echo "  SET GLOBAL log_queries_not_using_indexes = 0;"
    fi
else
    status_warn "Slow Query Log NICHT aktiviert"
    echo "Empfehlung: SET GLOBAL slow_query_log = 1;"
fi
echo ""

# ==============================================================================
# 5. TABELLEN-FRAGMENTIERUNG
# ==============================================================================

echo "=== 5. Tabellen-Fragmentierung ==="

# data_free gehoert in den Nenner. Ohne das liefert die Formel Werte ueber
# 100 %, sobald eine kleine Tabelle ein freies Extent von 4 MB haelt.
$MYSQL -e "
SELECT
    table_name AS 'Tabelle',
    ROUND(data_free / 1024 / 1024, 2) AS 'Fragmentiert (MB)',
    ROUND(data_free / (data_length + index_length + data_free) * 100, 2) AS 'Fragmentierung (%)'
FROM information_schema.tables
WHERE table_schema = '${DB_NAME}'
AND data_free > 10 * 1024 * 1024
ORDER BY data_free DESC
LIMIT 5;" 2>/dev/null

FRAG_COUNT=$(query_value "
SELECT COUNT(*)
FROM information_schema.tables
WHERE table_schema = '${DB_NAME}'
AND data_free > 100 * 1024 * 1024")

if [[ "${FRAG_COUNT}" -eq 0 ]]; then
    status_ok "Keine stark fragmentierten Tabellen"
else
    status_warn "${FRAG_COUNT} Tabellen mit >100MB Fragmentierung"
    echo "Empfehlung: OPTIMIZE TABLE <tabelle>;"
    echo "Auf InnoDB laeuft das als Online-DDL - gemessen an einer Tabelle mit"
    echo "770.000 Zeilen: 11,8 s Laufzeit, parallele Schreibzugriffe wurden um"
    echo "hoechstens 59 ms verzoegert. Exklusiv gesperrt wird nur kurz am Ende."
fi
echo ""

# ==============================================================================
# 6. DATENBANKGROESSE
# ==============================================================================

echo "=== 6. Datenbankgroesse ==="

$MYSQL -e "
SELECT
    ROUND(SUM(data_length) / 1024 / 1024 / 1024, 2) AS 'Daten (GB)',
    ROUND(SUM(index_length) / 1024 / 1024 / 1024, 2) AS 'Indizes (GB)',
    ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'Total (GB)'
FROM information_schema.tables
WHERE table_schema = '${DB_NAME}';" 2>/dev/null
echo ""

# ==============================================================================
# 7. WICHTIGE VARIABLEN
# ==============================================================================

echo "=== 7. Konfiguration ==="

$MYSQL -e "
SELECT 'innodb_buffer_pool_size' AS Variable,
       CONCAT(ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2), ' GB') AS Wert
UNION ALL
SELECT 'innodb_buffer_pool_instances', @@innodb_buffer_pool_instances
UNION ALL
SELECT 'innodb_redo_log_capacity',
       CONCAT(ROUND(@@innodb_redo_log_capacity / 1024 / 1024, 0), ' MB')
UNION ALL
SELECT 'group_concat_max_len', @@group_concat_max_len
UNION ALL
SELECT 'max_connections', @@max_connections
UNION ALL
SELECT 'tmp_table_size',
       CONCAT(ROUND(@@tmp_table_size / 1024 / 1024, 0), ' MB')
UNION ALL
SELECT 'table_open_cache', @@table_open_cache;" 2>/dev/null

# innodb_log_file_size ist seit 8.0.30 abgekuendigt, wirkt aber weiter: MySQL
# rechnet daraus innodb_redo_log_capacity = Wert x innodb_log_files_in_group
# (ab Werk 2), waehrend SHOW VARIABLES den Vorgabewert weitermeldet. Steht die
# Direktive noch in der Konfiguration, ist das echte Redo-Log doppelt so gross
# wie oben angezeigt.
LOG_FILE_SIZE=$(query_value "SELECT @@innodb_log_file_size")
REDO_DEFAULT=$(query_value "SELECT @@innodb_redo_log_capacity")
if [[ "${REDO_DEFAULT}" = "104857600" ]] && [[ "${LOG_FILE_SIZE}" != "50331648" ]]; then
    status_warn "innodb_log_file_size ist gesetzt (${LOG_FILE_SIZE} Bytes), innodb_redo_log_capacity meldet den Vorgabewert."
    echo "Das echte Redo-Log ist innodb_log_file_size x innodb_log_files_in_group."
    echo "Gegenprobe auf dem Server: du -sh /var/lib/mysql/#innodb_redo"
    echo "Besser: innodb_log_file_size entfernen und innodb_redo_log_capacity setzen."
fi
echo ""

echo "=========================================="
echo "Gesundheitscheck abgeschlossen"
echo "=========================================="
