-- Buffer Pool Status und Hit-Rate fuer Shopware
-- Verwendung: mysql < buffer-pool-check.sql
--
-- Zielwerte:
--   - Hit-Rate: >99%
--   - Buffer Pool >= Datenbankgroesse

-- ==============================================================================
-- 1. BUFFER POOL UEBERSICHT
-- ==============================================================================

SELECT '=== Buffer Pool Konfiguration ===' AS '';

SELECT
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS 'Buffer Pool (GB)',
    @@innodb_buffer_pool_instances AS 'Instances',
    ROUND(@@innodb_buffer_pool_size / @@innodb_buffer_pool_instances / 1024 / 1024, 2) AS 'Per Instance (MB)';

-- ==============================================================================
-- 2. BUFFER POOL HIT-RATE (WICHTIGSTE METRIK)
-- ==============================================================================

SELECT '=== Buffer Pool Hit-Rate ===' AS '';

SELECT
    ROUND((1 - (
        (SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_reads') /
        NULLIF((SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
    )) * 100, 4) AS 'Hit Rate (%)',
    CASE
        WHEN (1 - (
            (SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_reads') /
            NULLIF((SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
        )) >= 0.999 THEN 'EXCELLENT'
        WHEN (1 - (
            (SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_reads') /
            NULLIF((SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
        )) >= 0.99 THEN 'GUT'
        WHEN (1 - (
            (SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_reads') /
            NULLIF((SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
        )) >= 0.95 THEN 'AKZEPTABEL'
        ELSE 'WARNUNG - Buffer Pool erhoehen!'
    END AS 'Bewertung';

-- ==============================================================================
-- 3. BUFFER POOL VS DATENBANKGROESSE
-- ==============================================================================

SELECT '=== Datenbankgroesse vs Buffer Pool ===' AS '';

SELECT
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS 'Buffer Pool (GB)',
    ROUND(
        (SELECT SUM(data_length + index_length)
         FROM information_schema.tables
         WHERE table_schema = DATABASE()) / 1024 / 1024 / 1024, 2
    ) AS 'Datenbank (GB)',
    CASE
        WHEN @@innodb_buffer_pool_size >= (
            SELECT SUM(data_length + index_length)
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
        ) THEN 'OK - Buffer Pool >= DB'
        ELSE 'WARNUNG - Buffer Pool kleiner als DB!'
    END AS 'Status';

-- ==============================================================================
-- 4. BUFFER POOL DETAILLIERTE STATISTIKEN
-- ==============================================================================

SELECT '=== Detaillierte Statistiken ===' AS '';

SELECT
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests') AS 'Read Requests',
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') AS 'Disk Reads (Misses)',
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_write_requests') AS 'Write Requests',
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_pages_dirty') AS 'Dirty Pages';

-- ==============================================================================
-- 5. TOP 10 GROESSTE TABELLEN
-- ==============================================================================

SELECT '=== Top 10 groesste Tabellen ===' AS '';

SELECT
    table_name AS 'Tabelle',
    ROUND(data_length / 1024 / 1024, 2) AS 'Daten (MB)',
    ROUND(index_length / 1024 / 1024, 2) AS 'Index (MB)',
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS 'Total (MB)',
    table_rows AS 'Zeilen'
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY (data_length + index_length) DESC
LIMIT 10;
