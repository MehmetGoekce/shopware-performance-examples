#!/bin/bash
# Shopware Performance Benchmark Script
# Kapitel 2: Performance-Audit

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Defaults
BASE_URL="${BASE_URL:-http://localhost:8000}"
ITERATIONS="${ITERATIONS:-10}"
ENDPOINT="${ENDPOINT:-/}"
CONCURRENCY="${CONCURRENCY:-1}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --url URL         Base URL (default: $BASE_URL)"
    echo "  --endpoint PATH   Endpoint to test (default: $ENDPOINT)"
    echo "  --iterations N    Number of requests (default: $ITERATIONS)"
    echo "  --concurrency N   Concurrent requests (default: $CONCURRENCY)"
    echo "  --help            Show this help"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url) BASE_URL="$2"; shift 2 ;;
        --endpoint) ENDPOINT="$2"; shift 2 ;;
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

URL="${BASE_URL}${ENDPOINT}"

echo -e "${GREEN}=== Shopware Performance Benchmark ===${NC}"
echo ""
echo "URL:         $URL"
echo "Iterations:  $ITERATIONS"
echo "Concurrency: $CONCURRENCY"
echo ""

# Check if ab (Apache Bench) is available
if command -v ab &> /dev/null; then
    echo -e "${YELLOW}Running Apache Bench...${NC}"
    ab -n "$ITERATIONS" -c "$CONCURRENCY" -g /tmp/benchmark.tsv "$URL" 2>/dev/null | grep -E "(Requests per second|Time per request|Transfer rate|Failed requests)"
    echo ""
fi

# Check if curl is available
if command -v curl &> /dev/null; then
    echo -e "${YELLOW}Running curl timing test...${NC}"
    echo ""

    # Timing variables
    total_time=0
    total_ttfb=0
    min_time=999999
    max_time=0

    for i in $(seq 1 "$ITERATIONS"); do
        # curl timing
        result=$(curl -s -o /dev/null -w "%{time_total},%{time_starttransfer}" "$URL")
        time_total=$(echo "$result" | cut -d',' -f1)
        time_ttfb=$(echo "$result" | cut -d',' -f2)

        # Convert to milliseconds
        time_ms=$(echo "$time_total * 1000" | bc)
        ttfb_ms=$(echo "$time_ttfb * 1000" | bc)

        total_time=$(echo "$total_time + $time_ms" | bc)
        total_ttfb=$(echo "$total_ttfb + $ttfb_ms" | bc)

        # Min/Max
        if (( $(echo "$time_ms < $min_time" | bc -l) )); then
            min_time=$time_ms
        fi
        if (( $(echo "$time_ms > $max_time" | bc -l) )); then
            max_time=$time_ms
        fi

        printf "  Request %2d: %.0fms (TTFB: %.0fms)\n" "$i" "$time_ms" "$ttfb_ms"
    done

    avg_time=$(echo "scale=0; $total_time / $ITERATIONS" | bc)
    avg_ttfb=$(echo "scale=0; $total_ttfb / $ITERATIONS" | bc)

    echo ""
    echo -e "${GREEN}=== Results ===${NC}"
    echo "  Avg Response Time: ${avg_time}ms"
    echo "  Avg TTFB:          ${avg_ttfb}ms"
    echo "  Min Response Time: ${min_time}ms"
    echo "  Max Response Time: ${max_time}ms"
fi

echo ""
echo -e "${GREEN}Benchmark complete.${NC}"
