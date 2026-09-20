-- Index-Analyse fuer Shopware Datenbank
-- Kapitel 8: Datenbank-Optimierung
--
-- Verwendung (Datenbankname ist PFLICHT - ohne ihn ist DATABASE() NULL, die
-- ersten Abschnitte liefern stillschweigend nichts und Abschnitt 4 bricht mit
-- "ERROR 1046 No database selected" ab):
--   mysql shopware < index-analysis.sql
--
-- Analysiert:
-- - Ungenutzte Indizes
-- - Index-Groessen
-- - Index-Selektivitaet
-- - Tabellen ohne Primaerschluessel
--
-- @see https://github.com/MehmetGoekce/shopware-performance-examples

-- ==============================================================================
-- 0. VORAUSSETZUNGEN
-- ==============================================================================

SELECT '=== Voraussetzungen ===' AS '';

SELECT
    IF(DATABASE() IS NULL,
       'FEHLER - keine Datenbank gewaehlt. Aufruf: mysql shopware < index-analysis.sql',
       CONCAT('OK - Datenbank: ', DATABASE())) AS 'Datenbank',
    IF(@@performance_schema = 1,
       'OK - performance_schema aktiv',
       'FEHLER - performance_schema aus. Abschnitt 1, 2 und 7 bleiben leer.') AS 'Performance Schema';

-- Die Zaehler des Performance Schema werden bei JEDEM Serverstart auf null
-- gesetzt. Kurz nach einem Neustart meldet Abschnitt 1 praktisch jeden Index
-- als ungenutzt - gemessen: elf Sekunden nach einem Neustart stand dort der
-- Primaerschluessel einer Tabelle mit 770.000 Zeilen.
SELECT
    CONCAT(ROUND(VARIABLE_VALUE / 3600, 1), ' h') AS 'Uptime',
    IF(VARIABLE_VALUE < 86400,
       'ZU KURZ - Abschnitt 1 und 2 erst nach mindestens einem vollen Tag Traffic auswerten',
       'OK - Zaehler haben genug Laufzeit gesehen') AS 'Aussagekraft'
FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime';

-- ==============================================================================
-- 1. UNGENUTZTE INDIZES (Performance Schema erforderlich)
-- ==============================================================================

SELECT '=== Ungenutzte Indizes ===' AS '';
SELECT '(Kandidaten zum Loeschen - erst nach Uptime-Pruefung oben!)' AS '';
SELECT '(PRIMARY ist ausgenommen - ein Primaerschluessel wird nie geloescht)' AS '';

SELECT
    object_schema AS 'Schema',
    object_name AS 'Tabelle',
    index_name AS 'Index',
    count_read AS 'Reads',
    count_write AS 'Writes'
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = DATABASE()
AND index_name IS NOT NULL
AND index_name != 'PRIMARY'
AND count_read = 0
ORDER BY object_name, index_name
LIMIT 20;

-- ==============================================================================
-- 2. AM MEISTEN GENUTZTE INDIZES
-- ==============================================================================

SELECT '=== Top 10 meistgenutzte Indizes ===' AS '';

SELECT
    object_name AS 'Tabelle',
    index_name AS 'Index',
    count_read AS 'Reads',
    count_write AS 'Writes',
    ROUND(count_read / NULLIF(count_write, 0), 2) AS 'Read/Write Ratio'
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = DATABASE()
AND index_name IS NOT NULL
AND count_read > 0
ORDER BY count_read DESC
LIMIT 10;

-- ==============================================================================
-- 3. INDEX-GROESSEN
-- ==============================================================================

SELECT '=== Groesste Indizes ===' AS '';

SELECT
    table_name AS 'Tabelle',
    index_name AS 'Index',
    ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS 'Groesse (MB)'
FROM mysql.innodb_index_stats
WHERE database_name = DATABASE()
AND stat_name = 'size'
ORDER BY stat_value DESC
LIMIT 15;

-- ==============================================================================
-- 4. INDEX-SELEKTIVITAET (Wie effektiv ist der Index?)
-- ==============================================================================

SELECT '=== Index-Selektivitaet fuer wichtige Tabellen ===' AS '';
SELECT '(Hoeher = besser, >0.1 empfohlen fuer Index)' AS '';

-- product Tabelle
SELECT
    'product' AS 'Tabelle',
    'product_number' AS 'Spalte',
    ROUND(COUNT(DISTINCT product_number) / COUNT(*), 4) AS 'Selektivitaet'
FROM product
UNION ALL
SELECT
    'product',
    'active',
    ROUND(COUNT(DISTINCT active) / COUNT(*), 4)
FROM product
UNION ALL
SELECT
    'product',
    'created_at',
    ROUND(COUNT(DISTINCT created_at) / COUNT(*), 4)
FROM product;

-- ==============================================================================
-- 5. TABELLEN OHNE PRIMAERSCHLUESSEL (Problematisch!)
-- ==============================================================================

SELECT '=== Tabellen ohne Primaerschluessel ===' AS '';

SELECT
    t.table_name AS 'Tabelle'
FROM information_schema.tables t
LEFT JOIN information_schema.table_constraints tc
    ON t.table_schema = tc.table_schema
    AND t.table_name = tc.table_name
    AND tc.constraint_type = 'PRIMARY KEY'
WHERE t.table_schema = DATABASE()
AND t.table_type = 'BASE TABLE'
AND tc.constraint_name IS NULL
ORDER BY t.table_name;

-- ==============================================================================
-- 6. EIGENE INDIZES - UND WAS SHOPWARE SCHON MITBRINGT
-- ==============================================================================
-- Vor jedem neuen Index nachsehen, was auf der Tabelle bereits liegt. Zwei
-- Beispiele aus dem Shopware-Standardschema:
--
-- * order hat bereits idx.state_index (state_id). Ein zusaetzlicher
--   Composite (state_id, created_at) macht den vorhandenen Index zu einem
--   redundanten Praefix - genau das, was schema_redundant_indexes in
--   Abschnitt 7 spaeter anmahnt.
-- * order hat bereits idx.order_date_currency_id (order_date, currency_id),
--   und Shopware filtert Bestellungen ueber order_date bzw. order_date_time.
--   Ein Index auf created_at hilft nur eigenen Reports, nicht dem Shop.
--
-- Die Abfrage unten zeigt deshalb erst die vorhandenen Indizes der beiden
-- Tabellen, dann den Status der eigenen Kandidaten.

SELECT '=== Vorhandene Indizes auf product und order ===' AS '';

SELECT
    table_name AS 'Tabelle',
    index_name AS 'Index',
    GROUP_CONCAT(column_name ORDER BY seq_in_index) AS 'Spalten'
FROM information_schema.statistics
WHERE table_schema = DATABASE()
AND table_name IN ('product', 'order')
GROUP BY table_name, index_name
ORDER BY table_name, index_name;

SELECT '=== Eigene Index-Kandidaten pruefen ===' AS '';

SELECT
    'product' AS 'Tabelle',
    'idx_product_active_stock' AS 'Eigener Index',
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE()
        AND table_name = 'product'
        AND index_name = 'idx_product_active_stock'
    ) THEN 'VORHANDEN' ELSE 'FEHLT' END AS 'Status'
UNION ALL
SELECT
    'order',
    'idx_order_state_created',
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE()
        AND table_name = 'order'
        AND index_name = 'idx_order_state_created'
    ) THEN 'VORHANDEN (macht idx.state_index redundant - siehe oben)'
      ELSE 'FEHLT (vor dem Anlegen idx.state_index oben pruefen)' END;

-- ==============================================================================
-- 7. sys-SCHEMA (moderne Variante zu Abschnitt 1)
-- ==============================================================================
-- Das sys-Schema ist in MySQL 8.0 standardmaessig installiert - und in
-- MariaDB 10.11 ebenfalls, samt schema_unused_indexes, schema_redundant_indexes
-- und schema_index_statistics. Auf MariaDB muss dafuer allerdings
-- performance_schema = ON in der Serverkonfiguration stehen (ab Werk aus),
-- sonst bleiben die Views leer.
--
-- schema_unused_indexes ist sicherer als die Rohabfrage aus Abschnitt 1: die
-- View blendet PRIMARY und UNIQUE aus und kann deshalb keinen
-- Primaerschluessel zum Loeschen vorschlagen.
--
-- statements_with_full_table_scans gibt es nur auf MySQL.

SELECT '=== Nie genutzte Indizes (sys-Schema) ===' AS '';

SELECT * FROM sys.schema_unused_indexes
WHERE object_schema = DATABASE();

SELECT '=== Redundante Indizes (sys-Schema) ===' AS '';

SELECT * FROM sys.schema_redundant_indexes
WHERE table_schema = DATABASE();

SELECT '=== Statements mit Full-Table-Scan (Top 20) ===' AS '';

SELECT query, db, exec_count, no_index_used_count
FROM sys.statements_with_full_table_scans
WHERE db = DATABASE()
ORDER BY no_index_used_count DESC
LIMIT 20;

-- Invisible-Index-Pattern (Index risikofrei testen statt droppen):
--   ALTER TABLE product ALTER INDEX idx_xy INVISIBLE;  -- soft-deaktivieren
--   ALTER TABLE product ALTER INDEX idx_xy VISIBLE;    -- sofort zurueck
-- Beobachtung ueber Slow-Log + sys.statements_with_full_table_scans.
-- Primaerschluessel koennen nicht invisible werden.
--
-- MariaDB 10.6+ kennt dasselbe Konzept mit anderem Keyword (IGNORED statt INVISIBLE):
--   ALTER TABLE product ALTER INDEX idx_xy IGNORED;      -- soft-deaktivieren
--   ALTER TABLE product ALTER INDEX idx_xy NOT IGNORED;  -- sofort zurueck
-- Quelle: mariadb.com/kb/en/ignored-indexes/ (Feature seit MariaDB 10.6).
