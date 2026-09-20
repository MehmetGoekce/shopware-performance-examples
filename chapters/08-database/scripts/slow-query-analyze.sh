#!/bin/bash
# Slow-Query-Analyse fuer Shopware
# Kapitel 8: Datenbank-Optimierung
#
# Liest das Slow-Query-Log, prueft die Logeinstellungen und fasst zusammen,
# was mysqldumpslow bzw. pt-query-digest daraus machen.
#
# Verwendung:
#   ./slow-query-analyze.sh                          # /var/log/mysql/slow.log
#   ./slow-query-analyze.sh /pfad/zum/slow.log
#
# Zugangsdaten kommen aus ~/.my.cnf oder aus der Umgebungsvariablen MYSQL:
#   MYSQL="mysql -h db -u root -pgeheim" ./slow-query-analyze.sh
#
# mysqldumpslow -t N stirbt mit Exit 255, sobald N groesser ist als die Zahl
# der verschiedenen Query-Muster im Log ("Died at /usr/bin/mysqldumpslow line
# 163"). Es gibt vorher alles aus, was es gefunden hat - interaktiv faellt das
# kaum auf, in einem Cron-Job bricht der Rest weg. Dieses Skript faengt das ab.
#
# Warum hier keine grep-Heuristiken auf "filesort" oder "Full scan" stehen:
# beides steht so nirgends im Slow-Log. "filesort" ist eine EXPLAIN-Ausgabe.
# Und "Full_scan: Yes" ist ein MARIADB-Feld, das log_slow_verbosity=query_plan
# erzeugt - MySQL 8.0 schreibt es auch mit log_slow_extra = ON nicht. Dort
# heissen die Zusatzfelder Read_rnd_next, Sort_scan_count, Created_tmp_tables
# und so weiter. Gegen ein echtes Log gemessen liefern die alten greps
# zuverlaessig 0 und wiegen den Leser in Sicherheit; die Auswertung unten
# arbeitet deshalb je Engine mit den Feldern, die es dort wirklich gibt.
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MYSQL="${MYSQL:-mysql}"
SLOW_LOG="/var/log/mysql/slow.log"

show_usage() {
    echo "Usage: $0 [slow-log-pfad]"
    echo ""
    echo "Argumente:"
    echo "  slow-log-pfad  Slow-Query-Log (Default: /var/log/mysql/slow.log)"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  MYSQL          Befehl fuer den MySQL-Client (Default: mysql)"
}

status_ok()   { printf "%b[OK]%b %s\n"   "$GREEN"  "$NC" "$1"; }
status_warn() { printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$1"; }
status_fail() { printf "%b[FAIL]%b %s\n" "$RED"    "$NC" "$1"; }

query_value() {
    $MYSQL -N -B -e "$1" 2>/dev/null
}

# Zaehlt Treffer, ohne dass ein leeres Ergebnis den Exit-Code verfaelscht.
# "grep -c muster datei || echo 0" gibt bei null Treffern ZWEI Nullen aus:
# grep schreibt selbst schon 0 und beendet sich mit 1, dann feuert auch das
# Fallback-echo. Deshalb hier mit einem expliziten if.
count_matches() {
    local pattern="$1" file="$2" n
    if n=$(grep -c -e "$pattern" "$file"); then
        echo "$n"
    else
        echo 0
    fi
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
            SLOW_LOG="$1"
            shift
            ;;
    esac
done

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

if $MYSQL -e "SELECT 1" > /dev/null 2>&1; then
    SLOW_ENABLED=$(query_value "SELECT @@slow_query_log")
    echo "Slow Query Log: ${SLOW_ENABLED}"
    echo "Schwellwert: $(query_value "SELECT @@long_query_time")s"
    echo "Log-Datei laut Server: $(query_value "SELECT @@slow_query_log_file")"

    if [[ "${SLOW_ENABLED}" != "1" ]]; then
        status_warn "Slow Query Log ist nicht aktiviert"
        echo "Aktivieren mit:"
        echo "  SET GLOBAL slow_query_log = 1;"
        echo "  SET GLOBAL long_query_time = 1;"
    fi

    # log_queries_not_using_indexes ignoriert long_query_time und schreibt jede
    # Query ohne Index-Zugriff ins Log - auch die, die in 0,1 ms fertig ist.
    # Gemessen: mit long_query_time = 10 landeten 40 von 40 trivialen Queries
    # im Log. Fuer die Auswertung unten ist das Gift.
    if [[ "$(query_value "SELECT @@log_queries_not_using_indexes")" = "1" ]]; then
        status_warn "log_queries_not_using_indexes ist an - das Log enthaelt auch Queries im Mikrosekundenbereich"
        echo "Fuer eine belastbare Auswertung voruebergehend ausschalten:"
        echo "  SET GLOBAL log_queries_not_using_indexes = 0;"
    fi

    if [[ "$(query_value "SELECT @@log_slow_extra")" = "1" ]]; then
        status_ok "log_slow_extra ist an - das Log enthaelt Read_rnd_next, Sort_scan_count und Created_tmp_tables"
    else
        echo "Hinweis: log_slow_extra ist aus (Standard). Ohne die Option stehen"
        echo "im Log nur Query_time, Lock_time, Rows_sent und Rows_examined:"
        echo "  SET GLOBAL log_slow_extra = 1;"
        echo "Auf MariaDB heisst die passende Option log_slow_verbosity=query_plan"
        echo "und liefert stattdessen Full_scan, Full_join und Tmp_table."
    fi
else
    status_warn "MySQL nicht erreichbar - werte nur die Datei aus"
fi
echo ""

# ==============================================================================
# 2. LOG-DATEI PRUEFEN
# ==============================================================================

echo "=== 2. Log-Datei pruefen ==="

if [[ ! -f "${SLOW_LOG}" ]]; then
    status_fail "Log-Datei nicht gefunden: ${SLOW_LOG}"
    echo "Pfad als Argument uebergeben oder aus dem Server auslesen:"
    echo "  mysql -N -B -e \"SELECT @@slow_query_log_file\""
    exit 1
fi

if [[ ! -r "${SLOW_LOG}" ]]; then
    status_fail "Log-Datei nicht lesbar: ${SLOW_LOG}"
    echo "Das Log gehoert ueblicherweise mysql:adm - mit sudo aufrufen."
    exit 1
fi

echo "Dateigroesse: $(du -h "${SLOW_LOG}" | cut -f1)"
echo "Zeilen: $(wc -l < "${SLOW_LOG}")"
QUERY_COUNT=$(count_matches "^# Query_time" "${SLOW_LOG}")
echo "Protokollierte Queries: ${QUERY_COUNT}"

if [[ "${QUERY_COUNT}" -eq 0 ]]; then
    status_warn "Keine Queries im Log - nichts auszuwerten"
    exit 0
fi
echo ""

# ==============================================================================
# 3. ANALYSE MIT MYSQLDUMPSLOW
# ==============================================================================

echo "=== 3. Top 10 nach Gesamtzeit (mysqldumpslow) ==="

# Die Ausgabe hat kein "#" am Zeilenanfang und nennt neben Count/Time/Lock auch
# Rows und user@host. Literale sind zu N bzw. S normalisiert, damit gleiche
# Queries mit anderen Werten zusammenfallen.
if command -v mysqldumpslow > /dev/null 2>&1; then
    # Ohne -t laeuft mysqldumpslow nicht in den Slice-Fehler; die Begrenzung
    # uebernimmt awk anhand der "Count:"-Bloecke.
    if ! mysqldumpslow -s t "${SLOW_LOG}" | awk '/^Count:/ { n++ } n <= 10'; then
        status_warn "mysqldumpslow ist mit einem Fehler ausgestiegen - Ausgabe oben ist unvollstaendig"
    fi
else
    echo "mysqldumpslow nicht gefunden (Paket mysql-client bzw. mariadb-client)."
fi
echo ""

# ==============================================================================
# 4. ANALYSE MIT PT-QUERY-DIGEST
# ==============================================================================

echo "=== 4. Detaillierte Analyse (pt-query-digest) ==="

if command -v pt-query-digest > /dev/null 2>&1; then
    REPORT_FILE="${TMPDIR:-/tmp}/slow_query_report_$(date +%Y%m%d_%H%M%S).txt"
    if pt-query-digest "${SLOW_LOG}" --limit 10 > "${REPORT_FILE}"; then
        echo "Report gespeichert: ${REPORT_FILE}"
        echo ""
        head -60 "${REPORT_FILE}"
    else
        status_warn "pt-query-digest ist mit einem Fehler ausgestiegen (Teilausgabe in ${REPORT_FILE})"
    fi
    echo ""
    # --since kennt nur: N[shmd], "YYYY-MM-DD [HH:MM:SS]", "YYMMDD [HH:MM:SS]"
    # oder einen von MySQL auswertbaren Ausdruck. Umgangssprachliches wie
    # "1 week ago" ist KEIN gueltiges Format.
    echo "Nur die letzte Woche auswerten:"
    echo "  pt-query-digest ${SLOW_LOG} --since 7d"
else
    echo "pt-query-digest nicht installiert."
    echo "Installation: sudo apt install percona-toolkit"
fi
echo ""

# ==============================================================================
# 5. MUSTER IM LOG
# ==============================================================================

echo "=== 5. Muster im Log ==="
echo "(gezaehlt wird, was wirklich im Slow-Log steht - siehe Kopfkommentar)"
echo ""

printf "%-44s %s\n" "SELECT * Queries:" "$(count_matches "SELECT \*" "${SLOW_LOG}")"
printf "%-44s %s\n" "LIKE mit fuehrender Wildcard:" "$(count_matches "LIKE '%" "${SLOW_LOG}")"
# grep -c mit zwei Mustern geht nicht; "ohne WHERE" heisst: SELECT-Zeile, in der
# kein WHERE vorkommt. Das alte Muster "^SELECT [^;]*FROM [^;]*;$" zaehlte jede
# einzeilige SELECT-Zeile, weil [^;]* die WHERE-Klausel mitfrisst.
printf "%-44s %s\n" "Queries ohne WHERE:" "$(grep -e '^SELECT' "${SLOW_LOG}" | grep -vic 'where' || true)"

# Zusatzfelder erkennen wir am Log selbst, nicht an der Serverkonfiguration -
# das Log kann aelter sein als die aktuelle Einstellung.
if [[ "$(count_matches "Read_rnd_next:" "${SLOW_LOG}")" -gt 0 ]]; then
    # MySQL 8.0 mit log_slow_extra = ON
    printf "%-44s %s\n" "Sequentielle Tabellen-Reads (Read_rnd_next>0):" \
        "$(count_matches "Read_rnd_next: [1-9]" "${SLOW_LOG}")"
    printf "%-44s %s\n" "Sortierung ohne Index (Sort_scan_count>0):" \
        "$(count_matches "Sort_scan_count: [1-9]" "${SLOW_LOG}")"
    printf "%-44s %s\n" "Temp-Tabellen auf Platte:" \
        "$(count_matches "Created_tmp_disk_tables: [1-9]" "${SLOW_LOG}")"
elif [[ "$(count_matches "Full_scan:" "${SLOW_LOG}")" -gt 0 ]]; then
    # MariaDB mit log_slow_verbosity = query_plan
    printf "%-44s %s\n" "Full Table Scans (Full_scan: Yes):" "$(count_matches "Full_scan: Yes" "${SLOW_LOG}")"
    printf "%-44s %s\n" "Joins ohne Index (Full_join: Yes):" "$(count_matches "Full_join: Yes" "${SLOW_LOG}")"
    printf "%-44s %s\n" "Temporaere Tabellen (Tmp_table: Yes):" "$(count_matches "Tmp_table: Yes" "${SLOW_LOG}")"
else
    echo "Keine Zusatzfelder im Log - Scans und Sortierungen sind daraus nicht"
    echo "ablesbar. MySQL: SET GLOBAL log_slow_extra = 1;"
    echo "MariaDB:        SET GLOBAL log_slow_verbosity = 'query_plan';"
fi

echo ""
echo "Zeilen gelesen vs. geliefert - der zuverlaessigste Indikator fuer einen"
echo "fehlenden Index. Top 5 nach Rows_examined:"
grep -e "^# Query_time" "${SLOW_LOG}" \
    | sed -e 's/.*Rows_sent: \([0-9]*\).*Rows_examined: \([0-9]*\).*/\2 gelesen, \1 geliefert/' \
    | sort -rn | head -5 || true
echo ""

# ==============================================================================
# 6. SHOPWARE-TABELLEN
# ==============================================================================

echo "=== 6. Betroffene Shopware-Tabellen ==="

for table in product product_translation category "\`order\`" order_line_item customer; do
    label="${table//\`/}"
    printf "%-44s %s\n" "${label}:" "$(count_matches "FROM ${table}" "${SLOW_LOG}")"
done
echo ""

# ==============================================================================
# 7. NAECHSTE SCHRITTE
# ==============================================================================

echo "=== 7. Naechste Schritte ==="
echo "1. Die Top-Queries aus Abschnitt 3/4 einzeln mit EXPLAIN pruefen"
echo "2. Rows_examined >> Rows_sent heisst: es fehlt ein Index"
echo "3. Index anlegen, dann mit ANALYZE TABLE die Statistiken auffrischen"
echo "4. SELECT * durch die tatsaechlich benoetigten Spalten ersetzen"
echo "5. Bei DAL-Queries: Associations und addFields in den Plugins pruefen"
echo ""

echo "=========================================="
echo "Analyse abgeschlossen"
echo "=========================================="
