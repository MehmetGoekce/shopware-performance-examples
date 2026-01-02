#!/bin/bash
#
# Slow Query Analyse fuer Shopware
# Verwendung: ./slow-query-analyze.sh [slow_log_path]
#
# Voraussetzungen:
#   - Slow Query Log aktiviert
#   - percona-toolkit installiert (optional, empfohlen)
#     sudo apt install percona-toolkit

SLOW_LOG="${1:-/var/log/mysql/slow.log}"

echo "=========================================="
echo "Slow Query Analyse"
echo "=========================================="
echo "Log-Datei: ${SLOW_LOG}"
echo "Zeit: $(date)"
echo ""

# ==============================================================================
# 1. SLOW QUERY LOG STATUS
# ==============================================================================

echo "=== 1. Slow Query Log Status ==="

SLOW_ENABLED=$(mysql -N -e "SELECT @@slow_query_log" 2>/dev/null)
LONG_QUERY_TIME=$(mysql -N -e "SELECT @@long_query_time" 2>/dev/null)
LOG_FILE=$(mysql -N -e "SELECT @@slow_query_log_file" 2>/dev/null)

echo "Slow Query Log: ${SLOW_ENABLED}"
echo "Schwellwert: ${LONG_QUERY_TIME}s"
echo "Log-Datei: ${LOG_FILE}"

if [[ "${SLOW_ENABLED}" != "1" ]] && [[ "${SLOW_ENABLED}" != "ON" ]]; then
    echo ""
    echo "WARNUNG: Slow Query Log ist nicht aktiviert!"
    echo "Aktivieren mit:"
    echo "  SET GLOBAL slow_query_log = 'ON';"
    echo "  SET GLOBAL long_query_time = 1;"
    echo "  SET GLOBAL log_queries_not_using_indexes = 'ON';"
    echo ""
fi
echo ""

# ==============================================================================
# 2. LOG-DATEI PRUEFEN
# ==============================================================================

echo "=== 2. Log-Datei pruefen ==="

if [[ -f "${SLOW_LOG}" ]]; then
    LOG_SIZE=$(du -h "${SLOW_LOG}" | cut -f1)
    LOG_LINES=$(wc -l < "${SLOW_LOG}")
    QUERY_COUNT=$(grep -c "^# Time:" "${SLOW_LOG}" 2>/dev/null || echo "0")

    echo "Dateigroesse: ${LOG_SIZE}"
    echo "Zeilen: ${LOG_LINES}"
    echo "Queries (ca.): ${QUERY_COUNT}"
else
    echo "Log-Datei nicht gefunden: ${SLOW_LOG}"
    echo "Verwenden Sie den korrekten Pfad als Argument."
    exit 1
fi
echo ""

# ==============================================================================
# 3. ANALYSE MIT MYSQLDUMPSLOW (eingebaut)
# ==============================================================================

echo "=== 3. Top 10 langsamste Queries (mysqldumpslow) ==="

if command -v mysqldumpslow &> /dev/null; then
    mysqldumpslow -s t -t 10 "${SLOW_LOG}" 2>/dev/null | head -50
else
    echo "mysqldumpslow nicht gefunden."
fi
echo ""

# ==============================================================================
# 4. ANALYSE MIT PT-QUERY-DIGEST (Percona, empfohlen)
# ==============================================================================

echo "=== 4. Detaillierte Analyse (pt-query-digest) ==="

if command -v pt-query-digest &> /dev/null; then
    echo "pt-query-digest gefunden. Generiere Report..."

    REPORT_FILE="/tmp/slow_query_report_$(date +%Y%m%d_%H%M%S).txt"

    pt-query-digest "${SLOW_LOG}" --limit 10 > "${REPORT_FILE}" 2>/dev/null

    if [[ -f "${REPORT_FILE}" ]]; then
        echo "Report gespeichert: ${REPORT_FILE}"
        echo ""
        echo "Top 5 Queries aus dem Report:"
        echo ""
        head -100 "${REPORT_FILE}"
    fi
else
    echo "pt-query-digest nicht installiert."
    echo "Installation: sudo apt install percona-toolkit"
    echo ""
    echo "Alternative: Manuelle Analyse der Log-Datei"
fi
echo ""

# ==============================================================================
# 5. HAEUFIGE SLOW QUERY PATTERNS
# ==============================================================================

echo "=== 5. Haeufige Problemmuster ==="

echo "SELECT * Queries:"
grep -c "SELECT \*" "${SLOW_LOG}" 2>/dev/null || echo "0"

echo ""
echo "Queries ohne Index (filesort):"
grep -c "filesort" "${SLOW_LOG}" 2>/dev/null || echo "0"

echo ""
echo "Full Table Scans:"
grep -c "Full scan" "${SLOW_LOG}" 2>/dev/null || echo "0"

echo ""
echo "LIKE mit Wildcard am Anfang:"
grep -c "LIKE '%'" "${SLOW_LOG}" 2>/dev/null || echo "0"
echo ""

# ==============================================================================
# 6. SHOPWARE-SPEZIFISCHE QUERIES
# ==============================================================================

echo "=== 6. Shopware-spezifische Patterns ==="

echo "product Tabelle betroffen:"
grep -c "FROM.*product" "${SLOW_LOG}" 2>/dev/null || echo "0"

echo "order Tabelle betroffen:"
grep -c "FROM.*\`order\`" "${SLOW_LOG}" 2>/dev/null || echo "0"

echo "customer Tabelle betroffen:"
grep -c "FROM.*customer" "${SLOW_LOG}" 2>/dev/null || echo "0"
echo ""

# ==============================================================================
# 7. EMPFEHLUNGEN
# ==============================================================================

echo "=== 7. Naechste Schritte ==="
echo "1. Analysieren Sie die Top 5 langsamsten Queries"
echo "2. Pruefen Sie fehlende Indizes mit: EXPLAIN [query]"
echo "3. Erstellen Sie ggf. neue Indizes"
echo "4. Optimieren Sie SELECT * zu spezifischen Spalten"
echo "5. Pruefen Sie DAL-Nutzung in Shopware-Plugins"
echo ""

echo "=========================================="
echo "Analyse abgeschlossen"
echo "=========================================="
