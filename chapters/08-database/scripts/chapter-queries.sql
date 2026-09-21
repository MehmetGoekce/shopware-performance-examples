-- Die SQL-Abfragen aus Kapitel 8, so wie sie im Buch stehen
-- Kapitel 8: Datenbank-Optimierung
--
-- Das Buch zeigt diese Abfragen als Kurzformen. Die ausfuehrlichen Fassungen mit
-- Bewertung und Voraussetzungs-Pruefung stehen in buffer-pool-check.sql,
-- index-analysis.sql und db-health-check.sh; diese Datei ist die Quelle der
-- Buch-Snippets und wird vom Snippet-Gate gegen das Kapitel gehalten.
--
-- Verwendung (Datenbankname ist PFLICHT: alle Abfragen lesen ihn aus DATABASE(),
-- ohne gewaehlte Datenbank ist DATABASE() NULL und die Abfragen liefern NULL oder
-- keine Zeile - ohne Fehlermeldung):
--   mysql shopware < chapter-queries.sql
--
-- Ziel ist MySQL 8.0: Die ganze Datei ist gegen 8.0.42 mit einer Shopware-
-- 6.6.10.6-Datenbank gelaufen. Auf MariaDB 10.11.19 mit performance_schema = ON
-- laufen die beiden Hit-Rate-Abschnitte ebenfalls; der Rest ist dort nicht
-- gegen eine Shopware-Datenbank geprueft.
--
-- Die OPTIMIZE-TABLE-Zeilen am Ende sind mit # auskommentiert: Das Buch zeigt
-- sie als Befehl, aber wer diese Datei als Ganzes einspielt, soll keine Tabelle
-- neu schreiben. OPTIMIZE baut die Tabelle vollstaendig neu (I/O, Platz fuer die
-- Kopie) - einzeln und im Wartungsfenster ausfuehren.
--
-- @see https://github.com/MehmetGoekce/shopware-performance-examples

-- ==============================================================================
-- 8.2 Buffer Pool richtig dimensionieren - Nutzung und Hit-Rate (MySQL 8.0)
-- ==============================================================================

-- Aktuelle Buffer Pool Nutzung
SELECT
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS 'Buffer Pool (GB)',
    ROUND(
        (SELECT SUM(data_length + index_length)
         FROM information_schema.tables
         WHERE table_schema = DATABASE()) / 1024 / 1024 / 1024, 2
    ) AS 'Database size (GB)';

-- Buffer Pool Hit Rate, MySQL 8.0
SELECT
    ROUND(
        (1 - (
            (SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_reads') /
            NULLIF((SELECT variable_value FROM performance_schema.global_status
             WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
        )) * 100, 4
    ) AS 'Hit Rate (%)';

-- ==============================================================================
-- 8.2 Hit-Rate, portable Fassung (MySQL 8.0 und MariaDB 10.11 mit performance_schema = ON)
-- ==============================================================================

-- Läuft auf MySQL 8.0 und auf MariaDB 10.11 mit performance_schema = ON
SELECT ROUND((1 - (
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') /
    NULLIF((SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
)) * 100, 4) AS 'Hit Rate (%)';

-- ==============================================================================
-- 8.4 Bestehende Indizes analysieren - Groesse, nicht Nutzung
-- ==============================================================================

-- Alle Indizes einer Tabelle anzeigen
SHOW INDEX FROM product;

-- Index-GRÖSSE prüfen (nicht die Nutzung - die kommt im nächsten Abschnitt)
SELECT
    table_name,
    index_name,
    stat_value AS pages,
    ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS 'Size (MB)'
FROM mysql.innodb_index_stats
WHERE database_name = DATABASE()
AND stat_name = 'size'
ORDER BY stat_value DESC
LIMIT 20;

-- ==============================================================================
-- 8.4 Ungenutzte Indizes finden (performance_schema)
-- ==============================================================================

-- Erst die Laufzeit prüfen - ohne sie ist das Ergebnis unten wertlos
SHOW GLOBAL STATUS LIKE 'Uptime';

-- MySQL Performance Schema: Index-Statistiken
SELECT
    object_schema,
    object_name,
    index_name,
    count_read,
    count_write
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = DATABASE()
AND index_name IS NOT NULL
AND index_name != 'PRIMARY'
AND count_read = 0
ORDER BY object_name;

-- ==============================================================================
-- 8.4 sys-Schema - ungenutzte und redundante Indizes, Full-Table-Scans
-- ==============================================================================

-- Nie genutzte Indizes (Kandidaten zum Entfernen) — ersetzt die rohe
-- table_io_waits_summary_by_index_usage-Query aus 8.4
SELECT * FROM sys.schema_unused_indexes
WHERE object_schema = DATABASE();

-- Redundante/doppelte Indizes (typisch nach Plugin-Updates)
SELECT * FROM sys.schema_redundant_indexes
WHERE table_schema = DATABASE();

-- Full-Table-Scans aufspüren
SELECT * FROM sys.statements_with_full_table_scans
WHERE db = DATABASE() ORDER BY no_index_used_count DESC LIMIT 20;

-- ==============================================================================
-- 8.8 Fragmentierung pruefen
-- ==============================================================================

-- Fragmentierung prüfen
SELECT
    table_name,
    ROUND(data_free / 1024 / 1024, 2) AS 'Fragmented (MB)',
    ROUND(data_free / (data_length + index_length + data_free) * 100, 2) AS 'Fragmentation (%)'
FROM information_schema.tables
WHERE table_schema = DATABASE()
AND data_free > 0
ORDER BY data_free DESC;

-- Tabellen optimieren (Online-DDL, aber I/O-intensiv)
# OPTIMIZE TABLE product;
# OPTIMIZE TABLE `order`;
# OPTIMIZE TABLE order_line_item;
