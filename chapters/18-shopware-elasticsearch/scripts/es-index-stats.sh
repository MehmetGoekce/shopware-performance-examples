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
#

set -euo pipefail

# Configuration
ES_URL="${ES_URL:-http://localhost:9200}"
INDEX_PREFIX="${INDEX_PREFIX:-sw_}"
INDEX="${1:-}"
DETAILED="${DETAILED:-false}"

# Parse arguments
for arg in "$@"; do
    case $arg in
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
            ;;
        *)
            if [ -z "$INDEX" ]; then
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
if [ -n "$INDEX" ]; then
    TARGET="$INDEX"
else
    TARGET="${INDEX_PREFIX}*"
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Index Statistics${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "URL:     $ES_URL"
echo "Target:  $TARGET"
echo ""

# Basic index info
echo -e "${YELLOW}1. Index Overview${NC}"
echo "-------------------------------------------"
printf "%-35s %12s %12s %8s\n" "Index" "Docs" "Size" "Shards"
echo "-------------------------------------------"
curl -s "$ES_URL/_cat/indices/$TARGET?h=index,docs.count,store.size,pri&s=index" 2>/dev/null | while read -r index docs size shards; do
    printf "%-35s %12s %12s %8s\n" "$index" "$docs" "$size" "$shards"
done
echo ""

# Segment info
echo -e "${YELLOW}2. Segment Statistics${NC}"
echo "-------------------------------------------"
printf "%-35s %8s %12s %12s\n" "Index" "Segments" "Memory" "Merges"
echo "-------------------------------------------"

curl -s "$ES_URL/$TARGET/_stats/segments,merge" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.segments.count)|\(.value.primaries.segments.memory_in_bytes)|\(.value.primaries.merges.total)"
' | while IFS='|' read -r index segments memory merges; do
    memory_mb=$((memory / 1024 / 1024))
    printf "%-35s %8s %10sMB %12s\n" "$index" "$segments" "$memory_mb" "$merges"
done
echo ""

# Recommendations based on segments
echo -e "${YELLOW}   Recommendations:${NC}"
HIGH_SEGMENT_COUNT=$(curl -s "$ES_URL/$TARGET/_stats/segments" 2>/dev/null | jq '[.indices | to_entries[] | select(.value.primaries.segments.count > 10)] | length')
if [ "$HIGH_SEGMENT_COUNT" -gt 0 ]; then
    echo -e "   ${YELLOW}! $HIGH_SEGMENT_COUNT indices have >10 segments. Consider force merge:${NC}"
    echo "     curl -X POST '$ES_URL/$TARGET/_forcemerge?max_num_segments=1'"
else
    echo -e "   ${GREEN}All indices have optimal segment counts${NC}"
fi
echo ""

# Document count by type
echo -e "${YELLOW}3. Document Distribution${NC}"
echo "-------------------------------------------"
TOTAL_DOCS=0
curl -s "$ES_URL/$TARGET/_stats/docs" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.docs.count)"
' | while IFS='|' read -r index docs; do
    entity=$(echo "$index" | sed "s/${INDEX_PREFIX}//" | cut -d'_' -f1)
    printf "   %-20s %12s documents\n" "$entity" "$docs"
done
echo ""

# Field mappings (if detailed)
if [ "$DETAILED" = "true" ]; then
    echo -e "${YELLOW}4. Field Mappings${NC}"
    echo "-------------------------------------------"

    curl -s "$ES_URL/$TARGET/_mapping" 2>/dev/null | jq -r '
        to_entries[] |
        .key as $index |
        .value.mappings.properties // {} |
        to_entries[] |
        "\($index)|\(.key)|\(.value.type // "object")"
    ' | sort | while IFS='|' read -r index field type; do
        printf "   %-30s %-25s %s\n" "$index" "$field" "$type"
    done
    echo ""
fi

# Search performance
echo -e "${YELLOW}4. Search Performance${NC}"
echo "-------------------------------------------"
SEARCH_STATS=$(curl -s "$ES_URL/$TARGET/_stats/search" 2>/dev/null)

echo "$SEARCH_STATS" | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.search.query_total)|\(.value.primaries.search.query_time_in_millis)|\(.value.primaries.search.fetch_total)"
' | while IFS='|' read -r index queries query_time fetches; do
    if [ "$queries" -gt 0 ]; then
        avg_query=$((query_time / queries))
        printf "   %-30s %10s queries, %5sms avg\n" "$index" "$queries" "$avg_query"
    fi
done
echo ""

# Indexing stats
echo -e "${YELLOW}5. Indexing Statistics${NC}"
echo "-------------------------------------------"
curl -s "$ES_URL/$TARGET/_stats/indexing" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.indexing.index_total)|\(.value.primaries.indexing.index_time_in_millis)"
' | while IFS='|' read -r index indexed time; do
    if [ "$indexed" -gt 0 ]; then
        avg_index=$((time / indexed))
        printf "   %-30s %10s indexed, %5sms avg\n" "$index" "$indexed" "$avg_index"
    fi
done
echo ""

# Cache usage
echo -e "${YELLOW}6. Cache Usage${NC}"
echo "-------------------------------------------"
curl -s "$ES_URL/$TARGET/_stats/query_cache,fielddata,request_cache" 2>/dev/null | jq -r '
    .indices | to_entries[] |
    "\(.key)|\(.value.primaries.query_cache.memory_size_in_bytes // 0)|\(.value.primaries.fielddata.memory_size_in_bytes // 0)|\(.value.primaries.request_cache.memory_size_in_bytes // 0)"
' | while IFS='|' read -r index query_cache fielddata request_cache; do
    qc_mb=$((query_cache / 1024 / 1024))
    fd_mb=$((fielddata / 1024 / 1024))
    rc_mb=$((request_cache / 1024 / 1024))
    if [ $((qc_mb + fd_mb + rc_mb)) -gt 0 ]; then
        printf "   %-25s Query: %4sMB  Field: %4sMB  Request: %4sMB\n" "$index" "$qc_mb" "$fd_mb" "$rc_mb"
    fi
done
echo ""

# Summary
echo -e "${BLUE}============================================${NC}"
TOTAL_SIZE=$(curl -s "$ES_URL/_cat/indices/$TARGET?h=store.size&bytes=b" 2>/dev/null | awk '{sum+=$1} END {print sum}')
TOTAL_DOCS=$(curl -s "$ES_URL/_cat/indices/$TARGET?h=docs.count" 2>/dev/null | awk '{sum+=$1} END {print sum}')
TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))

echo "Total Documents: $TOTAL_DOCS"
echo "Total Size:      ${TOTAL_SIZE_MB} MB"
echo ""
