-- Buffer Pool Status und Hit-Rate fuer Shopware
-- Kapitel 8: Datenbank-Optimierung
--
-- Verwendung (Datenbankname ist PFLICHT, sonst ist DATABASE() NULL und die
-- Groessenvergleiche melden stillschweigend Unsinn):
--   mysql shopware < buffer-pool-check.sql
--   mysql -h db -u shopware -p shopware < buffer-pool-check.sql
--
-- NUR FUER MySQL 8.0. Auf MariaDB bricht das Skript ab, weil
-- @@innodb_buffer_pool_instances dort seit 10.6 nicht mehr existiert und
-- performance_schema ab Werk aus ist. Die MariaDB-Fassung steht unten als
-- Kommentar.
--
-- Zielwerte: die 99 % aus vielen Blogposts sind kein dokumentierter Schwellwert.
-- Tideways nennt "schlechter als 90 %" als Problemmarke und 99,9 % als sehr
-- guten Wert; die MySQL-Doku nennt ueberhaupt keinen. Nehmen Sie die Zahlen
-- unten als Erfahrungswerte, nicht als Norm.
--
-- @see https://github.com/MehmetGoekce/shopware-performance-examples

-- ==============================================================================
-- 0. VORAUSSETZUNGEN
-- ==============================================================================

SELECT '=== Voraussetzungen ===' AS '';

-- Diese Abfrage laeuft auf MySQL und MariaDB, damit die Abbruchgruende
-- sichtbar werden, bevor das Skript an einer MySQL-Variablen scheitert.
SELECT
    IF(DATABASE() IS NULL,
       'FEHLER - keine Datenbank gewaehlt. Aufruf: mysql shopware < buffer-pool-check.sql',
       CONCAT('OK - Datenbank: ', DATABASE())) AS 'Datenbank',
    IF(@@performance_schema = 1,
       'OK - performance_schema aktiv',
       'FEHLER - performance_schema aus, die Hit-Rate bleibt leer') AS 'Performance Schema',
    IF(@@version LIKE '%MariaDB%',
       CONCAT('ABBRUCH - ', @@version, ': dieses Skript ist fuer MySQL 8.0. Siehe MariaDB-Fassung am Dateiende.'),
       CONCAT('OK - ', @@version)) AS 'Server';

-- ==============================================================================
-- 1. BUFFER POOL UEBERSICHT
-- ==============================================================================

SELECT '=== Buffer Pool Konfiguration ===' AS '';

SELECT
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS 'Buffer Pool (GB)',
    @@innodb_buffer_pool_instances AS 'Instances',
    ROUND(@@innodb_buffer_pool_size / @@innodb_buffer_pool_instances / 1024 / 1024, 2) AS 'Per Instance (MB)',
    ROUND(@@innodb_redo_log_capacity / 1024 / 1024, 0) AS 'Redo-Log (MB, gemeldet)';

SELECT 'Hinweis: steht innodb_log_file_size in der Konfiguration, ist das echte' AS '';
SELECT 'Redo-Log das Doppelte des gemeldeten Werts. Gegenprobe auf dem Server:' AS '';
SELECT '  du -sh /var/lib/mysql/#innodb_redo' AS '';

-- ==============================================================================
-- 2. BUFFER POOL HIT-RATE
-- ==============================================================================

SELECT '=== Buffer Pool Hit-Rate ===' AS '';

SELECT
    ROUND(hit_rate * 100, 4) AS 'Hit Rate (%)',
    CASE
        WHEN hit_rate IS NULL       THEN 'KEINE DATEN - performance_schema aus?'
        WHEN hit_rate >= 0.999      THEN 'SEHR GUT'
        WHEN hit_rate >= 0.99       THEN 'GUT'
        WHEN hit_rate >= 0.95       THEN 'AKZEPTABEL'
        WHEN hit_rate >= 0.90       THEN 'GRENZWERTIG'
        ELSE 'ZU NIEDRIG - Buffer Pool erhoehen oder Working Set pruefen'
    END AS 'Bewertung'
FROM (
    SELECT 1 - (
        (SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_reads') /
        NULLIF((SELECT variable_value FROM performance_schema.global_status
                WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
    ) AS hit_rate
) AS h;

SELECT 'Die Zaehler gelten seit dem Serverstart. Nach einem Neustart oder' AS '';
SELECT 'nach einem Import sagt die Zahl wenig - erst ein paar Stunden Traffic' AS '';
SELECT 'abwarten (Uptime siehe oben).' AS '';

-- ==============================================================================
-- 3. BUFFER POOL VS DATENBANKGROESSE
-- ==============================================================================

SELECT '=== Datenbankgroesse vs Buffer Pool ===' AS '';

SELECT
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS 'Buffer Pool (GB)',
    ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'Datenbank (GB)',
    CASE
        WHEN DATABASE() IS NULL THEN 'KEIN VERGLEICH - keine Datenbank gewaehlt'
        WHEN @@innodb_buffer_pool_size >= SUM(data_length + index_length) THEN 'OK - Pool fasst die ganze Datenbank'
        ELSE 'Pool kleiner als die Datenbank - das ist erst dann ein Problem, wenn die Hit-Rate darunter leidet'
    END AS 'Status'
FROM information_schema.tables
WHERE table_schema = DATABASE();

-- ==============================================================================
-- 4. DETAILLIERTE STATISTIKEN
-- ==============================================================================

SELECT '=== Detaillierte Statistiken ===' AS '';

SELECT
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_read_requests') AS 'Read Requests',
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_reads') AS 'Disk Reads (Misses)',
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_write_requests') AS 'Write Requests',
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_pages_dirty') AS 'Dirty Pages';

-- ==============================================================================
-- 5. GROESSTE TABELLEN
-- ==============================================================================

SELECT '=== Top 10 groesste Tabellen ===' AS '';
SELECT 'table_rows ist bei InnoDB eine Schaetzung des Optimizers und kann' AS '';
SELECT 'um Faktoren danebenliegen - fuer exakte Zahlen SELECT COUNT(*).' AS '';

SELECT
    table_name AS 'Tabelle',
    table_rows AS 'Zeilen (geschaetzt)',
    ROUND(data_length / 1024 / 1024, 2) AS 'Daten (MB)',
    ROUND(index_length / 1024 / 1024, 2) AS 'Indizes (MB)',
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS 'Total (MB)'
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY (data_length + index_length) DESC
LIMIT 10;

-- ==============================================================================
-- MARIADB-FASSUNG
-- ==============================================================================
-- MariaDB 10.11 kennt @@innodb_buffer_pool_instances nicht mehr (mit 10.6
-- entfernt) und hat performance_schema ab Werk aus. Die Statuswerte stehen
-- dort in information_schema.global_status, das es auf MySQL 8.0 nicht gibt.
-- Es gibt also keine Query, die auf beiden Systemen laeuft.
--
--   SELECT ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS 'Buffer Pool (GB)';
--
--   SELECT ROUND((1 - (
--       (SELECT variable_value FROM information_schema.global_status
--        WHERE variable_name = 'Innodb_buffer_pool_reads') /
--       NULLIF((SELECT variable_value FROM information_schema.global_status
--               WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
--   )) * 100, 4) AS 'Hit Rate (%)';
--
-- Das sys-Schema bringt MariaDB 10.11 dagegen mit - inklusive
-- schema_unused_indexes, schema_redundant_indexes und schema_index_statistics.
-- Die brauchen allerdings performance_schema = ON in der Serverkonfiguration
-- und einen Neustart.
