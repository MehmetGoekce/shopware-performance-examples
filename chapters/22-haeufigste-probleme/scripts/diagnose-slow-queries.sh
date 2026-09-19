#!/usr/bin/env bash
#
# diagnose-slow-queries.sh
#
# Problem 1: Langsame Datenbankabfragen.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Warum dieses Skript nicht das Slow Query Log einschaltet:
#
#   "SET GLOBAL slow_query_log = 'ON'" braucht SUPER bzw.
#   SYSTEM_VARIABLES_ADMIN. Ein Shopware-Datenbankbenutzer hat das nicht —
#   selbst mit GRANT ALL PRIVILEGES ON shopware.* endet der Befehl mit
#   ERROR 1227. Auf Managed-MySQL (RDS, Cloud SQL, Shared Hosting) ist es
#   grundsaetzlich nicht erlaubt; dort geht es nur ueber die Parametergruppe
#   des Anbieters. Und selbst wenn es klappt, wirkt eine Aenderung von
#   long_query_time nicht fuer bestehende Verbindungen — PHP-FPM mit warmen
#   Verbindungen protokolliert also erst nach einem Reload.
#
#   performance_schema liefert dieselbe Information ohne Sonderrechte und
#   ohne Neustart. Deshalb wertet dieses Skript sie aus.
#
# Warum es keine Index-Liste zum Abtippen gibt:
#
#   Blind gesetzte Indizes auf Shopware-Kerntabellen sind den Migrationen
#   unbekannt, werden bei Updates nicht gepflegt und kosten bei jedem Import
#   Schreibzeit. Ausserdem stimmen die ueblichen Vorschlaege oft nicht:
#   product hat keine Spalte "name" (die liegt in product_translation), eine
#   Tabelle "session" existiert nicht, und customer.email hat bereits einen
#   Index (idx.email). "CREATE INDEX IF NOT EXISTS" kennt MySQL 8.0 ohnehin
#   nicht — das ist ein Syntaxfehler.
#
#   Dieses Skript zeigt stattdessen, welche Abfragen im laufenden Betrieb
#   ohne Index arbeiten. Danach setzt man gezielt einen — per Migration im
#   eigenen Plugin.
#
# Verwendung:
#   ./diagnose-slow-queries.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = nichts Auffaelliges
#   1 = auffaellige Abfragen gefunden
#   64 = Aufruffehler
#   69 = mysql-Client fehlt

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: diagnose-slow-queries.sh [SHOP_URL] [SHOP_PATH]

Wertet performance_schema aus: die teuersten Abfragen, die ohne Index
arbeitenden Abfragen und den Status des Slow Query Logs.

Argumente:
  SHOP_URL    Wird nicht ausgewertet; nur der Einheitlichkeit halber.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Umgebungsvariablen:
  TOP              Wie viele Abfragen gezeigt werden. Default: 10
  ROWS_THRESHOLD   Ab so vielen im Schnitt gelesenen Zeilen gilt eine Abfrage
                   ohne Index als auffaellig. Default: 100
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

# Aufrufkonvention aller Skripte dieses Kapitels: $1 = SHOP_URL, $2 = SHOP_PATH.
# Dieses Skript braucht nur den Pfad; $1 wird bewusst nicht ausgewertet,
# damit run-all-diagnostics.sh alle Skripte gleich aufrufen kann.
SHOP_PATH="${2:-.}"
TOP="${TOP:-10}"
ROWS_THRESHOLD="${ROWS_THRESHOLD:-100}"

if ! command -v mysql >/dev/null 2>&1; then
    echo "mysql-Client wird benoetigt." >&2
    exit 69
fi

DB_URL=""
for f in "${SHOP_PATH}/.env" "${SHOP_PATH}/.env.local"; do
    [[ -f "$f" ]] || continue
    line=$(grep -E '^DATABASE_URL=' "$f" | tail -1 || true)
    [[ -n "${line}" ]] && DB_URL="${line#DATABASE_URL=}"
done
DB_URL="${DB_URL%\"}"; DB_URL="${DB_URL#\"}"

if [[ -z "${DB_URL}" ]]; then
    echo "Keine DATABASE_URL in ${SHOP_PATH}/.env gefunden." >&2
    exit 1
fi

# Der Benutzerteil wird am LETZTEN @ abgetrennt: ein "@" im Passwort ist
# in der DSN prozentkodiert, manche Installationen schreiben es aber roh.
DB_REST="${DB_URL#*://}"
DB_CRED="${DB_REST%@*}"
DB_HOSTPART="${DB_REST##*@}"
DB_USER="${DB_CRED%%:*}"
DB_PASS="${DB_CRED#*:}"

# Prozentkodierung aufloesen — Passwoerter mit @ : / # stehen in der DSN
# als %40 %3A %2F %23.
urldecode() { printf '%b' "${1//%/\\x}"; }
DB_USER=$(urldecode "${DB_USER}")
DB_PASS=$(urldecode "${DB_PASS}")

DB_HOSTPORT="${DB_HOSTPART%%/*}"
DB_NAME="${DB_HOSTPART#*/}"; DB_NAME="${DB_NAME%%\?*}"
DB_HOST="${DB_HOSTPORT%%:*}"
DB_PORT="${DB_HOSTPORT#*:}"
[[ "${DB_PORT}" == "${DB_HOST}" ]] && DB_PORT=3306

q() {
    MYSQL_PWD="${DB_PASS}" mysql --default-character-set=utf8mb4 \
        -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -N -B -e "$1" 2>/dev/null
}

echo "=== Problem 1: Langsame Datenbankabfragen ==="
echo
echo "Datenbank: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo

# Verbindung einmal mit sichtbarer Fehlermeldung pruefen. Sonst sieht ein
# Zugangsfehler genauso aus wie "performance_schema nicht aktiv".
if ! MYSQL_PWD="${DB_PASS}" mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" \
        -N -B -e "SELECT 1" > /dev/null; then
    echo "Keine Verbindung zur Datenbank (Meldung oben)." >&2
    exit 69
fi

ISSUES=0

echo "1. Slow Query Log"
SLOW_ON=$(q "SELECT @@global.slow_query_log;")
SLOW_FILE=$(q "SELECT @@global.slow_query_log_file;")
LONG_TIME=$(q "SELECT @@global.long_query_time;")
echo "   slow_query_log:      ${SLOW_ON:-unbekannt}"
echo "   slow_query_log_file: ${SLOW_FILE:-unbekannt}"
echo "   long_query_time:     ${LONG_TIME:-unbekannt}"
if [[ "${SLOW_ON}" == "0" ]]; then
    echo "   Ausgeschaltet. Einschalten gehoert in die my.cnf bzw. in die"
    echo "   Parametergruppe des Hosters, nicht in einen Laufzeitbefehl:"
    echo "     slow_query_log = 1"
    echo "     long_query_time = 1"
    echo "     log_queries_not_using_indexes = 1"
    echo "   Die Auswertung unten funktioniert auch ohne."
fi

echo
echo "2. performance_schema"
PS_ON=$(q "SELECT @@performance_schema;")
if [[ "${PS_ON}" != "1" ]]; then
    echo "   Nicht aktiv. Ohne sie bleibt nur das Slow Query Log."
    echo "   Einschalten in der my.cnf: performance_schema = ON (Neustart noetig)."
    exit 1
fi
echo "   aktiv"

echo
echo "3. Die teuersten Abfragen (Gesamtzeit seit dem letzten Neustart)"
printf '   %10s %8s %10s  %s\n' "GESAMT_MS" "AUFRUFE" "SCHNITT_MS" "ABFRAGE"
TOP_QUERIES=$(q "
SELECT ROUND(SUM_TIMER_WAIT/1000000000),
       COUNT_STAR,
       ROUND(AVG_TIMER_WAIT/1000000000, 1),
       REPLACE(LEFT(DIGEST_TEXT, 90), '\n', ' ')
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = '${DB_NAME}'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT ${TOP};")
if [[ -z "${TOP_QUERIES}" ]]; then
    echo "   Noch keine Daten — der Shop hatte seit dem Neustart kaum Verkehr."
else
    while IFS=$'\t' read -r total calls avg text; do
        printf '   %10s %8s %10s  %s\n' "${total}" "${calls}" "${avg}" "${text}"
    done <<< "${TOP_QUERIES}"
fi

echo
echo "4. Abfragen ohne Index"
NO_INDEX=$(q "
SELECT COUNT_STAR,
       SUM_NO_INDEX_USED,
       ROUND(SUM_ROWS_EXAMINED/GREATEST(COUNT_STAR,1)),
       REPLACE(LEFT(DIGEST_TEXT, 80), '\n', ' ')
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = '${DB_NAME}'
  AND SUM_NO_INDEX_USED > 0
  AND SUM_ROWS_EXAMINED/GREATEST(COUNT_STAR,1) >= ${ROWS_THRESHOLD}
ORDER BY SUM_NO_INDEX_USED DESC
LIMIT ${TOP};")
echo "   (nur Abfragen, die im Schnitt mindestens ${ROWS_THRESHOLD} Zeilen lesen —"
echo "   ein Tabellenscan ueber eine Tabelle mit fuenf Zeilen ist kein Problem,"
echo "   und Shopware macht davon im Normalbetrieb einige.)"
if [[ -z "${NO_INDEX}" ]]; then
    echo "   Keine."
else
    printf '   %8s %10s %12s  %s\n' "AUFRUFE" "OHNE_INDEX" "ZEILEN/LAUF" "ABFRAGE"
    while IFS=$'\t' read -r calls noidx rows text; do
        printf '   %8s %10s %12s  %s\n' "${calls}" "${noidx}" "${rows}" "${text}"
    done <<< "${NO_INDEX}"
    ISSUES=$((ISSUES + 1))
fi

echo
echo "5. Groesste Tabellen"
q "
SELECT TABLE_NAME,
       ROUND((DATA_LENGTH + INDEX_LENGTH)/1024/1024) AS mb,
       TABLE_ROWS
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '${DB_NAME}'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 5;" | while IFS=$'\t' read -r name mb rows; do
    printf '   %-40s %6s MB  ca. %s Zeilen\n' "${name}" "${mb}" "${rows}"
done

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Keine Abfragen ohne Index. Wenn der Shop trotzdem langsam ist, liegt"
    echo "es nicht an fehlenden Indizes — Abschnitt 3 zeigt, wo die Zeit hingeht."
    exit 0
fi

cat <<'EOF'
Es gibt Abfragen, die ohne Index arbeiten.

Bevor ein Index gesetzt wird:

  1. Die Abfrage aus Abschnitt 4 mit EXPLAIN ansehen. "type: ALL" und
     "key: NULL" heisst voller Tabellenscan.

  2. Pruefen, ob ein Index ueberhaupt helfen KANN. Bei einem LIKE mit
     fuehrendem Platzhalter zum Beispiel nicht:

       EXPLAIN SELECT * FROM product_translation WHERE name LIKE '%shirt%';

     Der Optimizer zieht einen B-Tree hier nicht einmal in Betracht —
     possible_keys bleibt NULL, auch wenn der Index existiert. Fuer
     Volltextsuche ist Elasticsearch der richtige Weg, ersatzweise ein
     FULLTEXT-Index mit MATCH ... AGAINST. Die Storefront-Suche laeuft
     ohnehin nicht ueber product_translation.name, sondern ueber
     product_search_keyword.

  3. Pruefen, ob es den Index schon gibt:

       SHOW INDEX FROM <tabelle>;

  4. Wenn er wirklich fehlt: NICHT von Hand anlegen, sondern als Migration
     im eigenen Plugin. Von Hand gesetzte Indizes auf Kerntabellen kennt
     Shopware nicht — sie ueberleben Updates unbemerkt und kosten bei jedem
     Produktimport Schreibzeit.

     Und: MySQL 8.0 kennt kein "CREATE INDEX IF NOT EXISTS". Das ist ein
     Syntaxfehler, kein stiller No-Op.
EOF
exit 1
