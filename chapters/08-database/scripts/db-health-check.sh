#!/bin/bash
#
# Datenbank-Gesundheitscheck fuer Shopware
# Verwendung: ./db-health-check.sh [database_name]
#
# Prueft:
# - Buffer Pool Status
# - Verbindungen
# - Slow Queries
# - Tabellen-Fragmentierung
# - Wichtige Variablen

DB_NAME="${1:-shopware}"

echo "=========================================="
echo "Datenbank-Gesundheitscheck: ${DB_NAME}"
echo "=========================================="
echo "Zeit: $(date)"
echo ""

# Funktion fuer Status-Ausgabe
status_ok() { echo -e "\e[32m[OK]\e[0m $1"; }
status_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
status_fail() { echo -e "\e[31m[FAIL]\e[0m $1"; }

# ==============================================================================
# 1. VERBINDUNGSTEST
# ==============================================================================

echo "=== 1. Verbindung ==="

if mysql -e "SELECT 1" > /dev/null 2>&1; then
    status_ok "MySQL erreichbar"
else
    status_fail "MySQL nicht erreichbar"
    exit 1
fi
echo ""

# ==============================================================================
# 2. BUFFER POOL
# ==============================================================================

echo "=== 2. Buffer Pool ==="

BUFFER_SIZE=$(mysql -N -e "SELECT ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2)")
echo "Buffer Pool Groesse: ${BUFFER_SIZE} GB"

HIT_RATE=$(mysql -N -e "
SELECT ROUND((1 - (
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') /
    NULLIF((SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
)) * 100, 2)")

echo "Hit-Rate: ${HIT_RATE}%"

if (( $(echo "${HIT_RATE} >= 99" | bc -l) )); then
    status_ok "Buffer Pool Hit-Rate optimal"
elif (( $(echo "${HIT_RATE} >= 95" | bc -l) )); then
    status_warn "Buffer Pool Hit-Rate akzeptabel"
else
    status_fail "Buffer Pool Hit-Rate zu niedrig - Buffer Pool erhoehen!"
fi
echo ""

# ==============================================================================
# 3. VERBINDUNGEN
# ==============================================================================

echo "=== 3. Verbindungen ==="

MAX_CONN=$(mysql -N -e "SELECT @@max_connections")
CURRENT_CONN=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.processlist")
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

SLOW_LOG=$(mysql -N -e "SELECT @@slow_query_log")
if [[ "${SLOW_LOG}" = "1" ]] || [[ "${SLOW_LOG}" = "ON" ]]; then
    status_ok "Slow Query Log aktiviert"

    SLOW_COUNT=$(mysql -N -e "SHOW GLOBAL STATUS LIKE 'Slow_queries'" | awk '{print $2}')
    echo "Slow Queries seit Start: ${SLOW_COUNT}"

    LONG_QUERY_TIME=$(mysql -N -e "SELECT @@long_query_time")
    echo "Schwellwert: ${LONG_QUERY_TIME}s"
else
    status_warn "Slow Query Log NICHT aktiviert"
    echo "Empfehlung: SET GLOBAL slow_query_log = 'ON'"
fi
echo ""

# ==============================================================================
# 5. TABELLEN-FRAGMENTIERUNG
# ==============================================================================

echo "=== 5. Tabellen-Fragmentierung ==="

mysql -e "
SELECT
    table_name AS 'Tabelle',
    ROUND(data_free / 1024 / 1024, 2) AS 'Fragmentiert (MB)',
    ROUND(data_free / (data_length + index_length + data_free) * 100, 2) AS 'Fragmentierung (%)'
FROM information_schema.tables
WHERE table_schema = '${DB_NAME}'
AND data_free > 10 * 1024 * 1024
ORDER BY data_free DESC
LIMIT 5;" 2>/dev/null

FRAG_COUNT=$(mysql -N -e "
SELECT COUNT(*)
FROM information_schema.tables
WHERE table_schema = '${DB_NAME}'
AND data_free > 100 * 1024 * 1024")

if [[ "${FRAG_COUNT}" -eq 0 ]]; then
    status_ok "Keine stark fragmentierten Tabellen"
else
    status_warn "${FRAG_COUNT} Tabellen mit >100MB Fragmentierung"
    echo "Empfehlung: OPTIMIZE TABLE [tabelle];"
fi
echo ""

# ==============================================================================
# 6. DATENBANKGROESSE
# ==============================================================================

echo "=== 6. Datenbankgroesse ==="

mysql -e "
SELECT
    ROUND(SUM(data_length) / 1024 / 1024 / 1024, 2) AS 'Daten (GB)',
    ROUND(SUM(index_length) / 1024 / 1024 / 1024, 2) AS 'Indizes (GB)',
    ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'Total (GB)'
FROM information_schema.tables
WHERE table_schema = '${DB_NAME}';"
echo ""

# ==============================================================================
# 7. WICHTIGE VARIABLEN
# ==============================================================================

echo "=== 7. Konfiguration ==="

mysql -e "
SELECT 'innodb_buffer_pool_size' AS Variable,
       CONCAT(ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2), ' GB') AS Wert
UNION ALL
SELECT 'innodb_log_file_size',
       CONCAT(ROUND(@@innodb_log_file_size / 1024 / 1024, 0), ' MB')
UNION ALL
SELECT 'max_connections',
       @@max_connections
UNION ALL
SELECT 'tmp_table_size',
       CONCAT(ROUND(@@tmp_table_size / 1024 / 1024, 0), ' MB')
UNION ALL
SELECT 'table_open_cache',
       @@table_open_cache;"
echo ""

# ==============================================================================
# ZUSAMMENFASSUNG
# ==============================================================================

echo "=========================================="
echo "Gesundheitscheck abgeschlossen"
echo "=========================================="
