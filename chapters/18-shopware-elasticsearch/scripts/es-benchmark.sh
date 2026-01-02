#!/bin/bash
#
# Elasticsearch Performance Benchmark
#
# Measures search performance across different query types:
# - Simple match queries
# - Filtered queries
# - Aggregations
# - Complex multi-field searches
#
# Usage:
#   ./es-benchmark.sh
#   ./es-benchmark.sh --iterations 20
#   ./es-benchmark.sh --index sw_product
#
# Requirements:
#   - curl
#   - bc (for math)
#   - jq (for JSON parsing)

set -euo pipefail

# Configuration
ES_URL="${ES_URL:-http://localhost:9200}"
INDEX="${INDEX:-sw_product}"
ITERATIONS="${ITERATIONS:-10}"
SEARCH_TERM="${SEARCH_TERM:-laptop}"

# Parse arguments
for arg in "$@"; do
    case ${arg} in
        --iterations=*)
            ITERATIONS="${arg#*=}"
            ;;
        --index=*)
            INDEX="${arg#*=}"
            ;;
        --term=*)
            SEARCH_TERM="${arg#*=}"
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --iterations=N   Number of iterations per test (default: 10)"
            echo "  --index=NAME     Index to test (default: sw_product)"
            echo "  --term=WORD      Search term to use (default: laptop)"
            echo "  --help           Show this help"
            exit 0
            ;;
    esac
done

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Benchmark function
run_benchmark() {
    local name=$1
    local query=$2
    local total=0
    local times=()
    local min=999999
    local max=0

    echo -n "   Running ${ITERATIONS} iterations..."

    for ((i=1; i<=ITERATIONS; i++)); do
        time=$(curl -s -o /dev/null -w '%{time_total}' \
            -X POST "${ES_URL}/${INDEX}/_search" \
            -H 'Content-Type: application/json' \
            -d "${query}")

        # Convert to milliseconds
        time_ms=$(echo "${time} * 1000" | bc)
        times+=("${time_ms}")
        total=$(echo "${total} + ${time_ms}" | bc)

        # Track min/max
        if (( $(echo "${time_ms} < ${min}" | bc -l) )); then
            min=$time_ms
        fi
        if (( $(echo "${time_ms} > ${max}" | bc -l) )); then
            max=$time_ms
        fi
    done

    avg=$(echo "scale=2; ${total} / ${ITERATIONS}" | bc)

    # Calculate standard deviation
    sum_sq=0
    for t in "${times[@]}"; do
        diff=$(echo "${t} - ${avg}" | bc)
        sq=$(echo "${diff} * ${diff}" | bc)
        sum_sq=$(echo "${sum_sq} + ${sq}" | bc)
    done
    variance=$(echo "scale=4; ${sum_sq} / ${ITERATIONS}" | bc)
    stddev=$(echo "scale=2; sqrt(${variance})" | bc 2>/dev/null || echo "0")

    echo -e "\r   ${name}:"
    printf "     Avg: %8.2fms  Min: %8.2fms  Max: %8.2fms  StdDev: %6.2fms\n" "${avg}" "${min}" "${max}" "${stddev}"

    # Performance rating
    if (( $(echo "${avg} < 50" | bc -l) )); then
        echo -e "     ${GREEN}[EXCELLENT]${NC} Sub-50ms response"
    elif (( $(echo "${avg} < 100" | bc -l) )); then
        echo -e "     ${GREEN}[GOOD]${NC} Sub-100ms response"
    elif (( $(echo "${avg} < 500" | bc -l) )); then
        echo -e "     ${YELLOW}[ACCEPTABLE]${NC} Consider optimization"
    else
        echo -e "     ${RED}[SLOW]${NC} Needs optimization"
    fi
    echo ""
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Performance Benchmark${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "URL:        ${ES_URL}"
echo "Index:      ${INDEX}"
echo "Iterations: ${ITERATIONS}"
echo "Search:     ${SEARCH_TERM}"
echo ""

# Check index exists
DOC_COUNT=$(curl -s "${ES_URL}/_cat/indices/${INDEX}?h=docs.count" 2>/dev/null || echo "0")
if [[ -z "${DOC_COUNT}" ]] || [[ "${DOC_COUNT}" = "0" ]]; then
    echo -e "${RED}Error: Index ${INDEX} not found or empty${NC}"
    exit 1
fi
echo "Documents:  ${DOC_COUNT}"
echo ""

# Warmup
echo -e "${YELLOW}Warming up (3 requests)...${NC}"
for i in 1 2 3; do
    curl -s -o /dev/null "${ES_URL}/${INDEX}/_search?size=1" || true
done
echo ""

echo -e "${YELLOW}Running Benchmarks...${NC}"
echo ""

# Test 1: Simple Match Query
echo -e "${BLUE}Test 1: Simple Match Query${NC}"
run_benchmark "Match Query" '{
    "query": {
        "match": {
            "name": "'"${SEARCH_TERM}"'"
        }
    },
    "size": 20
}'

# Test 2: Multi-Match Query
echo -e "${BLUE}Test 2: Multi-Match Query (3 fields)${NC}"
run_benchmark "Multi-Match" '{
    "query": {
        "multi_match": {
            "query": "'"${SEARCH_TERM}"'",
            "fields": ["name^3", "description", "productNumber"]
        }
    },
    "size": 20
}'

# Test 3: Bool Query with Filter
echo -e "${BLUE}Test 3: Bool Query with Filter${NC}"
run_benchmark "Bool + Filter" '{
    "query": {
        "bool": {
            "must": [
                {"match": {"name": "'"${SEARCH_TERM}"'"}}
            ],
            "filter": [
                {"term": {"active": true}}
           ]]
        }
    },
    "size": 20
}'

# Test 4: Aggregation Only
echo -e "${BLUE}Test 4: Terms Aggregation (no hits)${NC}"
run_benchmark "Aggregation" '{
    "size": 0,
    "aggs": {
        "categories": {
            "terms": {
                "field": "categoryIds",
                "size": 50
            }
        }
    }
}'

# Test 5: Search + Aggregation
echo -e "${BLUE}Test 5: Search + Aggregation Combined${NC}"
run_benchmark "Search + Aggs" '{
    "query": {
        "bool": {
            "must": [
                {"match": {"name": "'"${SEARCH_TERM}"'"}}
            ],
            "filter": [
                {"term": {"active": true}}
           ]]
        }
    },
    "size": 20,
    "aggs": {
        "categories": {
            "terms": {"field": "categoryIds", "size": 50}
        },
        "price_ranges": {
            "range": {
                "field": "price",
                "ranges": [
                    {"to": 50},
                    {"from": 50, "to": 100},
                    {"from": 100, "to": 500},
                    {"from": 500}
               ]]
            }
        }
    }
}'

# Test 6: Wildcard Query (typically slow)
echo -e "${BLUE}Test 6: Wildcard Query (typically slow)${NC}"
run_benchmark "Wildcard" '{
    "query": {
        "wildcard": {
            "name": {
                "value": "*'"${SEARCH_TERM:0:3}"'*"
            }
        }
    },
    "size": 20
}'

# Test 7: Fuzzy Query
echo -e "${BLUE}Test 7: Fuzzy Query (typo tolerance)${NC}"
run_benchmark "Fuzzy" '{
    "query": {
        "fuzzy": {
            "name": {
                "value": "'"${SEARCH_TERM}"'",
                "fuzziness": "AUTO"
            }
        }
    },
    "size": 20
}'

# Test 8: Large Result Set
echo -e "${BLUE}Test 8: Large Result Set (100 items)${NC}"
run_benchmark "100 Results" '{
    "query": {
        "match_all": {}
    },
    "size": 100
}'

# Summary
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Benchmark Complete${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Tips for Optimization:"
echo "  - Wildcard queries are slow; use ngram tokenizer instead"
echo "  - Use filter context for yes/no conditions (faster, cached)"
echo "  - Aggregations on high-cardinality fields need fielddata"
echo "  - Consider doc_values: true for aggregation fields"
echo ""
