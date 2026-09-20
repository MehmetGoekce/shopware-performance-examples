#!/bin/bash
#
# Elasticsearch Index Statistics
#
# Displays detailed statistics for Shopware indices including:
# - Document counts
# - Index sizes
# - Segment counts
# - Field mappings
#
# Usage:
#   ./es-index-stats.sh
#   ./es-index-stats.sh sw_product
#   ./es-index-stats.sh --detailed
#   ./es-index-stats.sh sw_product --detailed
#
# Environment:
#   ES_URL         Default http://localhost:9200
#   INDEX_PREFIX   Default sw   (ohne Unterstrich — Shopware haengt ihn an)
#   DETAILED       true schaltet die Feld-Mappings zu (wie --detailed)
#
# Exit codes:
#   0  Kennzahlen ausgegeben
#   1  Cluster nicht erreichbar oder Ziel existiert nicht
#   2  Falscher Aufruf
#

set -euo pipefail

# Configuration
ES_URL="${ES_URL:-http://localhost:9200}"
# OHNE Unterstrich — Shopware haengt ihn selbst an
# (ElasticsearchHelper::getIndexName). Ein Prefix 'sw_' erzeugt sw__product.
INDEX_PREFIX="${INDEX_PREFIX:-sw}"
INDEX="${INDEX:-}"
DETAILED="${DETAILED:-false}"

# Parse arguments
for arg in "$@"; do
    case ${arg} in
        --detailed)
            DETAILED=true
            ;;
        --help)
            echo "Usage: $0 [index-name] [options]"
            echo ""
            echo "Arguments:"
            echo "  index-name    Specific index to analyze (default: all sw_* indices)"
            echo ""
            echo "Options:"
            echo "  --detailed    Show detailed field mappings"
            echo "  --help        Show this help"
            exit 0
            ;;
        -*)
            echo "Unbekannte Option: ${arg}" >&2
            exit 2
            ;;
        *)
            if [[ -z "${INDEX}" ]]; then
                INDEX=$arg
            fi
            ;;
    esac
done

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Target indices
if [[ -n "${INDEX}" ]]; then
    TARGET="${INDEX}"
else
    TARGET="${INDEX_PREFIX}_*"
fi

# Erst pruefen, dann rechnen. Ohne diese beiden Zeilen stirbt das Skript bei
# einem nicht existierenden Ziel mitten im zweiten Abschnitt mit dem rohen
# `jq: error … null (null) has no keys` und einem Exit-Code, den es nirgends
# dokumentiert. es-benchmark.sh macht es an dieser Stelle richtig.
if ! curl -sf --connect-timeout 5 -o /dev/null "${ES_URL}/_cluster/health"; then
    echo "Cluster unter ${ES_URL} nicht erreichbar." >&2
    exit 1
fi
# -f ist hier wesentlich: Bei einem konkreten, nicht existierenden Index
# antwortet _cat mit 404 UND einem Fehlerrumpf — ohne -f waere die Ausgabe
# nicht leer und der Check liefe durch. Ein Platzhalter, der nichts trifft,
# antwortet dagegen mit 200 und leerem Rumpf.
if ! curl -sf "${ES_URL}/_cat/indices/${TARGET}?h=index" 2>/dev/null | grep -q .; then
    echo "Kein Index passt auf '${TARGET}'." >&2
    exit 1
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Index Statistics${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "URL:     ${ES_URL}"
echo "Target:  ${TARGET}"
echo ""

# Basic index info
echo -e "${YELLOW}1. Index Overview${NC}"
echo "-------------------------------------------"
# «Docs» ist hier die Zahl der LUCENE-Dokumente. Shopware indexiert
# verschachtelte Felder, deshalb liegt sie deutlich ueber der Zahl der
# Entitaeten (gemessen: 234 Lucene-Dokumente bei 14 Produkten). Ausserdem
# haengt der Wert am Refresh und steht direkt nach dem Indexieren noch auf 0.
# Die Zahl der Produkte steht weiter unten, aus _count.
printf "%-35s %12s %12s %8s\n" "Index" "Lucene-Docs" "Size" "Shards"
echo "-------------------------------------------"
curl -s "${ES_URL}/_cat/indices/${TARGET}?h=index,docs.count,store.size,pri&s=index" 2>/dev/null | while read -r index docs size shards; do
    printf "%-35s %12s %12s %8s\n" "${index}" "${docs}" "${size}" "${shards}"
done
echo ""

# Segment info
echo -e "${YELLOW}2. Segment Statistics${NC}"
echo "-------------------------------------------"
printf "%-35s %8s %12s %12s\n" "Index" "Segments" "Memory" "Merges"
echo "-------------------------------------------"

curl -s "${ES_URL}/${TARGET}/_stats/segments,merge" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.segments.count)|\(.value.primaries.segments.memory_in_bytes)|\(.value.primaries.merges.total)"
' | while IFS='|' read -r index segments memory merges; do
    memory_mb=$((memory / 1024 / 1024))
    printf "%-35s %8s %10sMB %12s\n" "${index}" "${segments}" "${memory_mb}" "${merges}"
done
echo ""

# Recommendations based on segments
echo -e "${YELLOW}   Recommendations:${NC}"
HIGH_SEGMENT_COUNT=$(curl -s "${ES_URL}/${TARGET}/_stats/segments" 2>/dev/null | jq '[.indices | to_entries[] | select(.value.primaries.segments.count > 10)] | length')
if [[ "${HIGH_SEGMENT_COUNT}" -gt 0 ]]; then
    echo -e "   ${YELLOW}! ${HIGH_SEGMENT_COUNT} indices have >10 segments. Consider force merge:${NC}"
    echo "     curl -X POST '${ES_URL}/${TARGET}/_forcemerge?max_num_segments=1'"
else
    echo -e "   ${GREEN}All indices have optimal segment counts${NC}"
fi
echo ""

# Document count by type
echo -e "${YELLOW}3. Document Distribution${NC}"
echo "-------------------------------------------"
TOTAL_DOCS=0
curl -s "${ES_URL}/${TARGET}/_stats/docs" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.docs.count)"
' | while IFS='|' read -r index docs; do
    entity=$(echo "${index}" | sed "s/^${INDEX_PREFIX}_//" | rev | cut -d'_' -f2- | rev)
    printf "   %-20s %12s Lucene-Docs\n" "${entity}" "${docs}"
done
echo ""
# Die tatsaechliche Entitaetenzahl hinter den Aliassen — das ist die Zahl,
# die ein Leser erwartet, wenn er «Dokumente» liest.
echo "   Entitaeten (aus _count ueber den Alias):"
while read -r alias; do
    [[ -z "${alias}" ]] && continue
    cnt=$(curl -s "${ES_URL}/${alias}/_count" | jq -r '.count // "n/a"')
    printf "   %-20s %12s\n" "${alias}" "${cnt}"
done < <(curl -s "${ES_URL}/_cat/aliases/${TARGET}?h=alias" | tr -d ' ' | sort -u)
echo ""

# Field mappings (if detailed)
if [[ "${DETAILED}" = "true" ]]; then
    echo -e "${YELLOW}4. Field Mappings${NC}"
    echo "-------------------------------------------"

    curl -s "${ES_URL}/${TARGET}/_mapping" 2>/dev/null | jq -r '
        to_entries[] |
        .key as $index |
        .value.mappings.properties // {} |
        to_entries[] |
        "\($index)|\(.key)|\(.value.type // "object")"
    ' | sort | while IFS='|' read -r index field type; do
        printf "   %-30s %-25s %s\n" "${index}" "${field}" "${type}"
    done
    echo ""
fi

# Search performance
echo -e "${YELLOW}5. Search Performance${NC}"
echo "-------------------------------------------"
SEARCH_STATS=$(curl -s "${ES_URL}/${TARGET}/_stats/search" 2>/dev/null)

echo "${SEARCH_STATS}" | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.search.query_total)|\(.value.primaries.search.query_time_in_millis)|\(.value.primaries.search.fetch_total)"
' | while IFS='|' read -r index queries query_time fetches; do
    if [[ "${queries}" -gt 0 ]]; then
        avg_query=$((query_time / queries))
        printf "   %-30s %10s queries, %5sms avg\n" "${index}" "${queries}" "${avg_query}"
    fi
done
echo ""

# Indexing stats
echo -e "${YELLOW}5. Indexing Statistics${NC}"
echo "-------------------------------------------"
curl -s "${ES_URL}/${TARGET}/_stats/indexing" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.indexing.index_total)|\(.value.primaries.indexing.index_time_in_millis)"
' | while IFS='|' read -r index indexed time; do
    if [[ "${indexed}" -gt 0 ]]; then
        avg_index=$((time / indexed))
        printf "   %-30s %10s indexed, %5sms avg\n" "${index}" "${indexed}" "${avg_index}"
    fi
done
echo ""

# Cache usage
echo -e "${YELLOW}6. Cache Usage${NC}"
echo "-------------------------------------------"
curl -s "${ES_URL}/${TARGET}/_stats/query_cache,fielddata,request_cache" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.query_cache.memory_size_in_bytes // 0)|\(.value.primaries.fielddata.memory_size_in_bytes // 0)|\(.value.primaries.request_cache.memory_size_in_bytes // 0)"
' | while IFS='|' read -r index query_cache fielddata request_cache; do
    qc_mb=$((query_cache / 1024 / 1024))
    fd_mb=$((fielddata / 1024 / 1024))
    rc_mb=$((request_cache / 1024 / 1024))
    if [[ $((qc_mb + fd_mb + rc_mb)) -gt 0 ]]; then
        printf "   %-25s Query: %4sMB  Field: %4sMB  Request: %4sMB\n" "${index}" "${qc_mb}" "${fd_mb}" "${rc_mb}"
    fi
done
echo ""

# Summary
echo -e "${BLUE}============================================${NC}"
TOTAL_SIZE=$(curl -s "${ES_URL}/_cat/indices/${TARGET}?h=store.size&bytes=b" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
TOTAL_LUCENE=$(curl -s "${ES_URL}/_cat/indices/${TARGET}?h=docs.count" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
# Ganzzahldivision meldete fuer 105 kB "0 MB". Und die Zahl aus docs.count
# heisst Lucene-Dokumente, nicht Dokumente — genau die Verwechslung, gegen die
# dieses Skript weiter oben anschreibt. Die Entitaetszahl liefert _count.
TOTAL_SIZE_MB=$(awk -v b="${TOTAL_SIZE}" 'BEGIN { printf "%.1f", b / 1024 / 1024 }')
ENTITIES=$(curl -s "${ES_URL}/${INDEX_PREFIX}_product/_count" 2>/dev/null | jq -r '.count // "n/a"')

echo "Total Lucene-Docs: ${TOTAL_LUCENE}   (inkl. nested — nicht die Entitaetszahl)"
echo "Produkte (_count): ${ENTITIES}"
echo "Total Size:        ${TOTAL_SIZE_MB} MB"
echo ""
