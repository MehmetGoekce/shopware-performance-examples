#!/bin/bash
# Shopware Database Query Analyzer
# Kapitel 8: Datenbank-Optimierung

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Defaults
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-root}"
MYSQL_DB="${MYSQL_DB:-shopware}"
SLOW_THRESHOLD="${SLOW_THRESHOLD:-1}"

echo -e "${GREEN}=== Shopware Query Analyzer ===${NC}"
echo ""

# MySQL connection
MYSQL_CMD="mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASS $MYSQL_DB"

echo -e "${YELLOW}1. Slow Query Summary (> ${SLOW_THRESHOLD}s)${NC}"
echo ""
$MYSQL_CMD -e "
SELECT
    LEFT(sql_text, 80) AS query_preview,
    COUNT(*) AS exec_count,
    ROUND(AVG(timer_wait/1000000000000), 3) AS avg_time_sec,
    ROUND(MAX(timer_wait/1000000000000), 3) AS max_time_sec
FROM performance_schema.events_statements_history_long
WHERE timer_wait > ${SLOW_THRESHOLD}000000000000
GROUP BY LEFT(sql_text, 80)
ORDER BY avg_time_sec DESC
LIMIT 10;
" 2>/dev/null || echo "Performance Schema not available"

echo ""
echo -e "${YELLOW}2. Tables Without Indexes (potential issues)${NC}"
echo ""
$MYSQL_CMD -e "
SELECT
    t.TABLE_NAME,
    t.TABLE_ROWS,
    ROUND(t.DATA_LENGTH / 1024 / 1024, 2) AS data_mb
FROM information_schema.TABLES t
LEFT JOIN information_schema.STATISTICS s
    ON t.TABLE_NAME = s.TABLE_NAME AND t.TABLE_SCHEMA = s.TABLE_SCHEMA
WHERE t.TABLE_SCHEMA = '$MYSQL_DB'
    AND t.TABLE_ROWS > 1000
    AND s.INDEX_NAME IS NULL
ORDER BY t.TABLE_ROWS DESC
LIMIT 10;
" 2>/dev/null

echo ""
echo -e "${YELLOW}3. Largest Tables${NC}"
echo ""
$MYSQL_CMD -e "
SELECT
    TABLE_NAME,
    TABLE_ROWS AS rows_approx,
    ROUND(DATA_LENGTH / 1024 / 1024, 2) AS data_mb,
    ROUND(INDEX_LENGTH / 1024 / 1024, 2) AS index_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '$MYSQL_DB'
ORDER BY DATA_LENGTH DESC
LIMIT 10;
"

echo ""
echo -e "${YELLOW}4. Index Usage Statistics${NC}"
echo ""
$MYSQL_CMD -e "
SELECT
    object_name AS table_name,
    index_name,
    count_read,
    count_write,
    CASE
        WHEN count_read = 0 AND count_write > 0 THEN 'WRITE-ONLY (consider removing)'
        WHEN count_read = 0 AND count_write = 0 THEN 'UNUSED (consider removing)'
        ELSE 'ACTIVE'
    END AS status
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = '$MYSQL_DB'
    AND index_name IS NOT NULL
    AND index_name != 'PRIMARY'
ORDER BY count_read ASC
LIMIT 20;
" 2>/dev/null || echo "Performance Schema not available"

echo ""
echo -e "${GREEN}=== Analysis Complete ===${NC}"
