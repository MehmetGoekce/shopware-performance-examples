-- Index-Analyse fuer Shopware Datenbank
-- Verwendung: mysql < index-analysis.sql
--
-- Analysiert:
-- - Ungenutzte Indizes
-- - Fehlende Indizes
-- - Index-Selektivitaet

-- ==============================================================================
-- 1. UNGENUTZTE INDIZES (Performance Schema erforderlich)
-- ==============================================================================

SELECT '=== Ungenutzte Indizes ===' AS '';
SELECT '(Kandidaten zum Loeschen - aber vorsichtig!)' AS '';

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
-- 6. SHOPWARE-SPEZIFISCHE INDEX-EMPFEHLUNGEN
-- ==============================================================================

SELECT '=== Empfohlene Indizes pruefen ===' AS '';

-- Pruefe ob wichtige Indizes existieren
SELECT
    'product' AS 'Tabelle',
    'idx_product_active_stock' AS 'Empfohlener Index',
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
    ) THEN 'VORHANDEN' ELSE 'FEHLT' END;

-- ==============================================================================
-- 7. MYSQL 8.0: sys-SCHEMA (moderne Variante zu Abschnitt 1, nur MySQL 8.0)
-- ==============================================================================
-- sys-Schema ist in MySQL 8.0 standardmaessig installiert. MariaDB hat ein
-- abweichendes Pendant - dieser Abschnitt nur auf MySQL 8.0 ausfuehren.

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
