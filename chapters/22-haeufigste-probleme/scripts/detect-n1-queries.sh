#!/bin/bash
#
# Problem 7: N+1 Query Problem
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Erkennt N+1 Query Patterns in Shopware durch Log-Analyse.
#
# Verwendung: ./detect-n1-queries.sh [SHOP_URL] [SHOP_PATH]
#

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: detect-n1-queries.sh [SHOP_URL] [SHOP_PATH]

Sucht nach Hinweisen auf N+1-Abfragen: im Log, im Slow Query Log und
in den Plugins unter custom/plugins.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis
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

# >>> dotenv_get (wortgleich in allen Skripten dieses Kapitels, siehe BATS)
# Liest eine Variable so, wie Symfonys Dotenv::bootEnv() sie fuer die CLI
# (bin/console) ermittelt. Setzt DOTENV_VALUE und DOTENV_SOURCE; beide leer,
# wenn die Variable nirgends steht. Reihenfolge (symfony/dotenv 7.2-7.4):
#   1. Umgebung dieses Aufrufs — schlaegt jede Datei.
#   2. .env.local.php (composer dump-env) — ersetzt ALLE .env-Dateien,
#      ausser die Umgebung setzt ein anderes APP_ENV als die Datei.
#   3. .env, .env.local, .env.<APP_ENV>, .env.<APP_ENV>.local; die spaetere
#      Datei gewinnt, auch fuer APP_ENV selbst. Die Dateiwahl folgt dem
#      APP_ENV nach .env/.env.local (ohne Angabe: dev); bei APP_ENV=test
#      entfaellt .env.local. Ohne .env, .env.dist und .env.local.php liest
#      Shopware gar keine Datei.
# Die Umgebung des Webservers (FPM env[], Apache SetEnv, nginx fastcgi_param)
# sieht diese Funktion nicht; sie schlaegt im Web ebenfalls jede Datei.
dotenv_get() {
    local name="$1" root="${SHOP_PATH:-.}" f env_name line php_env
    DOTENV_VALUE="" DOTENV_SOURCE=""
    if line=$(printenv "$name"); then
        DOTENV_VALUE="$line" DOTENV_SOURCE="Umgebung"
        return 0
    fi
    if [[ -f "$root/.env.local.php" ]]; then
        php_env=$(dotenv_php_value "$root/.env.local.php" APP_ENV)
        if ! env_name=$(printenv APP_ENV) || [[ -z "$php_env" || "$env_name" == "$php_env" ]]; then
            if grep -qE "^[[:space:]]*'${name}'[[:space:]]*=>" "$root/.env.local.php"; then
                DOTENV_VALUE=$(dotenv_php_value "$root/.env.local.php" "$name")
                DOTENV_SOURCE=".env.local.php"
            fi
            return 0
        fi
    fi
    [[ -f "$root/.env" || -f "$root/.env.dist" ]] || return 0
    f="$root/.env"; [[ -f "$f" ]] || f="$root/.env.dist"
    env_name=$(printenv APP_ENV) || env_name=$(dotenv_file_value "$f" APP_ENV)
    local files=("$f")
    if [[ "${env_name:-dev}" != "test" && -f "$root/.env.local" ]]; then
        files+=("$root/.env.local")
        printenv APP_ENV >/dev/null || env_name=$(dotenv_file_value "$root/.env.local" APP_ENV "$env_name")
    fi
    env_name="${env_name:-dev}"
    if [[ "$env_name" != "local" ]]; then
        files+=("$root/.env.$env_name" "$root/.env.$env_name.local")
    fi
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        if grep -qE "^[[:space:]]*(export[[:space:]]+)?${name}=" "$f"; then
            DOTENV_VALUE=$(dotenv_file_value "$f" "$name")
            DOTENV_SOURCE="${f##*/}"
        fi
    done
}
# Letzte Zuweisung NAME=... einer .env-Datei; "export " davor erlaubt.
# Entfernt umschliessende Anfuehrungszeichen und einen Kommentar hinter
# einem Wert ohne Anfuehrungszeichen. ${VAR}-Verweise bleiben unaufgeloest.
# $3 = Rueckgabe, wenn die Datei die Variable nicht setzt.
dotenv_file_value() {
    local line v
    line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$1" | tail -n 1) || { printf '%s' "${3:-}"; return 0; }
    v="${line#*=}"
    case "$v" in
        \"*\"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*\'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *) v="${v%%[[:space:]]#*}"; v="${v%"${v##*[![:space:]]}"}" ;;
    esac
    printf '%s' "$v"
}
# Wert aus .env.local.php (var_export-Format von composer dump-env).
dotenv_php_value() {
    grep -E "^[[:space:]]*'$2'[[:space:]]*=>" "$1" | tail -n 1 \
        | sed -E "s/^[^=]*=>[[:space:]]*'(.*)',?[[:space:]]*$/\1/; s/\\\\'/'/g; s/\\\\\\\\/\\\\/g" || true
}
# <<< dotenv_get

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Schwellenwerte
N1_THRESHOLD=10  # Gleiche Query > 10x = N+1
TOTAL_QUERY_THRESHOLD=100  # > 100 Queries pro Request = Problem

echo "=== N+1 Query Detection ==="
echo "Shop: ${SHOP_PATH}"
echo ""

# DATABASE_URL lesen, damit der Slow-Log-Pfad bei MySQL erfragt werden kann.
# DATABASE_URL wie bin/console sie sieht: Umgebung, .env.local.php, sonst
# .env-Dateien in Symfonys Reihenfolge (spaetere gewinnt).
dotenv_get DATABASE_URL
DB_URL="${DOTENV_VALUE}"

if [[ -n "${DB_URL}" ]]; then
    DB_REST="${DB_URL#*://}"
    DB_CRED="${DB_REST%@*}"
    DB_HOSTPART="${DB_REST##*@}"
    DB_USER="${DB_CRED%%:*}"
    DB_PASS="${DB_CRED#*:}"
    urldecode() { printf '%b' "${1//%/\\x}"; }
    DB_USER=$(urldecode "${DB_USER}")
    DB_PASS=$(urldecode "${DB_PASS}")
    DB_HOSTPORT="${DB_HOSTPART%%/*}"
    DB_HOST="${DB_HOSTPORT%%:*}"
    DB_PORT="${DB_HOSTPORT#*:}"
    [[ "${DB_PORT}" == "${DB_HOST}" ]] && DB_PORT=3306
fi

ISSUES=0

# Methode 1: Doctrine Query Log analysieren
echo -e "${BLUE}1. Doctrine Query Log Analyse${NC}"

LOG_FILE="${SHOP_PATH}/var/log/dev.log"
# Shopware 6.6 haengt einen Hash an das Cache-Verzeichnis: var/cache/dev_h<hash>.
PROFILER_DIR=""
for d in "${SHOP_PATH}"/var/cache/dev*/profiler; do
    [[ -d "$d" ]] && PROFILER_DIR="$d" && break
done

if [[ -f "${LOG_FILE}" ]]; then
    echo "   Analysiere: ${LOG_FILE}"

    # Suche nach wiederholten SELECT Statements
    REPEATED_QUERIES=$(grep -o 'SELECT.*FROM [a-z_]*' "${LOG_FILE}" 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 || true)

    if [[ -n "${REPEATED_QUERIES}" ]]; then
        echo ""
        echo "   Häufigste Queries (Top 10):"
        echo "${REPEATED_QUERIES}" | while read -r count query; do
            if [[ "${count}" -gt "${N1_THRESHOLD}" ]]; then
                TABLE=$(echo "${query}" | grep -oE 'FROM [a-z_]+' | awk '{print $2}')
                echo -e "   ${RED}${count} x${NC} ${TABLE}"
            else
                TABLE=$(echo "${query}" | grep -oE 'FROM [a-z_]+' | awk '{print $2}')
                echo -e "   ${GREEN}${count} x${NC} ${TABLE}"
            fi
        done
    else
        echo "   Keine Query-Patterns gefunden"
    fi
else
    echo -e "   ${YELLOW}dev.log nicht gefunden (APP_ENV=prod?)${NC}"
fi

# Methode 2: MySQL Slow Query Log
echo ""
echo -e "${BLUE}2. MySQL Slow Query Log${NC}"

# Den Pfad nennt MySQL selbst. "/var/log/mysql/slow.log" ist NICHT der
# Standardwert — ab Werk schreibt MySQL nach <hostname>-slow.log im
# Datenverzeichnis.
SLOW_LOG=""
if command -v mysql > /dev/null 2>&1 && [[ -n "${DB_URL:-}" ]]; then
    SLOW_LOG=$(MYSQL_PWD="${DB_PASS:-}" mysql -h"${DB_HOST:-127.0.0.1}" \
        -P"${DB_PORT:-3306}" -u"${DB_USER:-root}" -N -B \
        -e "SELECT @@global.slow_query_log_file;" 2>/dev/null || true)
fi
if [[ -n "${SLOW_LOG}" && -f "${SLOW_LOG}" ]]; then
    echo "   Analysiere: ${SLOW_LOG}"

    # Letzte 1000 Zeilen analysieren
    SLOW_PATTERNS=$(tail -1000 "${SLOW_LOG}" 2>/dev/null | \
        grep -o 'SELECT.*FROM `[^`]*`' | \
        sort | uniq -c | sort -rn | head -5 || true)

    if [[ -n "${SLOW_PATTERNS}" ]]; then
        echo ""
        echo "   Wiederholte langsame Queries:"
        echo "${SLOW_PATTERNS}"
    fi
else
    if [[ -n "${SLOW_LOG}" ]]; then
        echo -e "   ${YELLOW}Slow Query Log laut MySQL: ${SLOW_LOG} — nicht lesbar${NC}"
    else
        echo -e "   ${YELLOW}Slow Query Log nicht gefunden${NC}"
    fi
    echo "   SET GLOBAL braucht SUPER/SYSTEM_VARIABLES_ADMIN und ist auf"
    echo "   Managed-MySQL nicht erlaubt. Das Log gehoert in die my.cnf."
    echo "   Ohne Sonderrechte geht es auch so:"
    echo "     SELECT COUNT_STAR, SUM_NO_INDEX_USED, DIGEST_TEXT"
    echo "     FROM performance_schema.events_statements_summary_by_digest"
    echo "     ORDER BY COUNT_STAR DESC LIMIT 20;"
fi

# Methode 3: Code-Analyse auf typische N+1 Patterns
echo ""
echo -e "${BLUE}3. Code-Analyse (typische N+1 Patterns)${NC}"

if [[ -d "${SHOP_PATH}/custom/plugins" ]]; then
    echo "   Suche in custom/plugins..."

    # Die Aufrufe stehen selten auf derselben Zeile wie das foreach.
    # Deshalb mit Kontext suchen: ein Repository-Aufruf innerhalb von fuenf
    # Zeilen nach einem foreach ist der Verdachtsfall.
    LOOP_QUERIES=$(grep -rn -A5 --include='*.php' 'foreach' \
        "${SHOP_PATH}/custom/plugins" 2>/dev/null \
        | grep -cE '(repository|Repository)->(search|searchIds)\(' || true)

    GET_ENTITY=$(grep -rn -A5 --include='*.php' 'foreach' \
        "${SHOP_PATH}/custom/plugins" 2>/dev/null \
        | grep -E -e '->(getEntity|get)\(' \
        | grep -vcE 'getEntities|getData' || true)

    # Criteria ohne addAssociation im selben File — das ist schwaecher als
    # die beiden oberen und geht deshalb nicht in die Bewertung ein.
    MISSING_ASSOC=0
    while IFS= read -r file; do
        if ! grep -q 'addAssociation' "${file}" 2>/dev/null; then
            MISSING_ASSOC=$((MISSING_ASSOC + 1))
        fi
    done < <(grep -rl --include='*.php' 'new Criteria(' \
        "${SHOP_PATH}/custom/plugins" 2>/dev/null || true)

    echo ""
    echo "   Verdachtsfaelle aus der Code-Suche:"
    echo "   - Repository-Aufrufe nahe einem foreach: ${LOOP_QUERIES}"
    echo "   - getEntity()/get() nahe einem foreach:   ${GET_ENTITY}"
    echo "   - Dateien mit Criteria ohne Association:  ${MISSING_ASSOC}  (nur Hinweis)"

    if [[ "${LOOP_QUERIES}" -gt 0 ]] || [[ "${GET_ENTITY}" -gt 5 ]]; then
        ISSUES=$((ISSUES + 1))
        echo ""
        echo -e "   ${YELLOW}Verdaechtige Stellen — von Hand ansehen:${NC}"
        echo ""
        grep -rn -A5 --include='*.php' 'foreach' "${SHOP_PATH}/custom/plugins" 2>/dev/null \
            | grep -E '(repository|Repository)->(search|searchIds)\(' | head -3 || true
    fi
else
    echo "   custom/plugins nicht gefunden"
fi

# Methode 4: Profiler-Daten (wenn verfügbar)
echo ""
echo -e "${BLUE}4. Symfony Profiler Analyse${NC}"

if [[ -d "${PROFILER_DIR}" ]]; then
    # Letzte Profile-Datei finden
    LATEST_PROFILE=$(ls -t "${PROFILER_DIR}" 2>/dev/null | head -1 || true)

    if [[ -n "${LATEST_PROFILE}" ]]; then
        echo "   Letztes Profil: ${LATEST_PROFILE}"

        # Query-Count aus Index extrahieren (falls verfügbar)
        INDEX_FILE="${PROFILER_DIR}/${LATEST_PROFILE}/index.csv"
        if [[ -f "${INDEX_FILE}" ]]; then
            echo "   Profiler-Index gefunden"
        fi
    fi
else
    echo -e "   ${YELLOW}Profiler nicht aktiv (APP_ENV=prod?)${NC}"
fi

# Zusammenfassung
echo ""
echo "=== Zusammenfassung ==="

if [[ "${ISSUES}" -eq 0 ]]; then
    echo -e "${GREEN}Keine offensichtlichen N+1 Probleme erkannt.${NC}"
    echo
    echo "Das ist eine Textsuche im eigenen Plugin-Code, kein Beweis. Ein"
    echo "N+1 zeigt sich daran, dass die Zahl der Abfragen mit der Zahl der"
    echo "Datensaetze waechst. Dafuer dieselbe Seite einmal mit einem und"
    echo "einmal mit zwanzig Produkten abrufen und dazwischen vergleichen:"
    echo "  SELECT SUM(COUNT_STAR) FROM performance_schema."
    echo "  events_statements_summary_by_digest WHERE SCHEMA_NAME = 'shopware';"
    echo "(vorher mit TRUNCATE TABLE performance_schema."
    echo "events_statements_summary_by_digest zuruecksetzen)."
    echo ""
    echo "Hinweis: Für detaillierte Analyse:"
    echo "  1. APP_ENV=dev setzen"
    echo "  2. Symfony Profiler nutzen (Doctrine Tab)"
    echo "  3. Blackfire.io für Production-Profiling"
    exit 0
else
    echo -e "${RED}Potentielle N+1 Query Probleme gefunden.${NC}"
    echo ""
    echo "Lösungen:"
    echo ""
    echo "  1. Associations vorab laden:"
    echo '     $criteria->addAssociation("manufacturer");'
    echo '     $criteria->addAssociation("media");'
    echo ""
    echo "  2. Batch-Loading statt einzelner Abfragen in der Schleife:"
    echo '     $criteria = new Criteria($productIds);'
    echo '     $products = $productRepository->search($criteria, $context);'
    echo ""
    echo "  3. In der Storefront nicht selbst suchen, sondern die Criteria"
    echo "     erweitern, die Shopware ohnehin baut:"
    echo '     ProductListingCriteriaEvent bzw. ProductPageCriteriaEvent'
    exit 1
fi
