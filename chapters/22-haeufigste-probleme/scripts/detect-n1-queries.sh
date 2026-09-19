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

ISSUES=0

# Methode 1: Doctrine Query Log analysieren
echo -e "${BLUE}1. Doctrine Query Log Analyse${NC}"

LOG_FILE="${SHOP_PATH}/var/log/dev.log"
PROFILER_DIR="${SHOP_PATH}/var/cache/dev/profiler"

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

SLOW_LOG="/var/log/mysql/slow.log"
if [[ -f "${SLOW_LOG}" ]]; then
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
    echo -e "   ${YELLOW}Slow Query Log nicht gefunden${NC}"
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

    # Pattern 1: Loop mit einzelnen Repository-Calls
    LOOP_QUERIES=$(grep -rn 'foreach.*\$.*repository->search' "${SHOP_PATH}/custom/plugins" 2>/dev/null | wc -l || true)

    # Pattern 2: getEntity() in Loop
    GET_ENTITY=$(grep -rn 'foreach.*getEntity\|foreach.*get(' "${SHOP_PATH}/custom/plugins" 2>/dev/null | \
        grep -v 'getEntities\|getData' | wc -l || true)

    # Pattern 3: Fehlende Associations
    MISSING_ASSOC=$(grep -rn 'Criteria()' "${SHOP_PATH}/custom/plugins" 2>/dev/null | \
        grep -v 'addAssociation' | wc -l || true)

    echo ""
    echo "   Potentielle N+1 Patterns:"
    echo "   - Repository-Calls in Loops: ${LOOP_QUERIES}"
    echo "   - getEntity() in Loops: ${GET_ENTITY}"
    echo "   - Criteria ohne Association: ${MISSING_ASSOC}"

    if [[ "${LOOP_QUERIES}" -gt 0 ]] || [[ "${GET_ENTITY}" -gt 5 ]]; then
        ISSUES=$((ISSUES + 1))
        echo ""
        echo -e "   ${YELLOW}Verdächtige Stellen gefunden${NC}"

        # Beispiele zeigen
        echo ""
        echo "   Beispiele:"
        grep -rn 'foreach.*\$.*repository->search' "${SHOP_PATH}/custom/plugins" 2>/dev/null | head -3
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
