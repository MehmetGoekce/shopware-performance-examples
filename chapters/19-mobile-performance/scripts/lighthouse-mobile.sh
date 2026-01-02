#!/bin/bash
#
# Lighthouse Mobile Performance Test
#
# Runs Lighthouse audit with mobile emulation settings.
# Generates HTML and JSON reports.
#
# Usage:
#   ./lighthouse-mobile.sh https://example.com
#   ./lighthouse-mobile.sh https://example.com --iterations 3
#
# Requirements:
#   - Node.js
#   - Lighthouse (npm install -g lighthouse)
#   - Chrome/Chromium

set -euo pipefail

# Configuration
URL="${1:-}"
OUTPUT_DIR="${OUTPUT_DIR:-./reports}"
ITERATIONS="${ITERATIONS:-1}"
THROTTLING="${THROTTLING:-mobile}"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --iterations=*)
            ITERATIONS="${arg#*=}"
            ;;
        --output=*)
            OUTPUT_DIR="${arg#*=}"
            ;;
        --no-throttle)
            THROTTLING="none"
            ;;
        --help)
            echo "Usage: $0 <url> [options]"
            echo ""
            echo "Options:"
            echo "  --iterations=N    Number of test runs (default: 1)"
            echo "  --output=DIR      Output directory (default: ./reports)"
            echo "  --no-throttle     Disable network throttling"
            echo "  --help            Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 https://example.com"
            echo "  $0 https://example.com --iterations=3"
            exit 0
            ;;
        -*)
            ;;
        *)
            if [ -z "$URL" ]; then
                URL="$arg"
            fi
            ;;
    esac
done

if [ -z "$URL" ]; then
    echo "Error: URL required"
    echo "Usage: $0 <url>"
    exit 1
fi

# Check dependencies
if ! command -v lighthouse &> /dev/null; then
    echo "Error: Lighthouse not found"
    echo "Install with: npm install -g lighthouse"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Lighthouse Mobile Performance Test${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "URL:        $URL"
echo "Iterations: $ITERATIONS"
echo "Throttling: $THROTTLING"
echo "Output:     $OUTPUT_DIR"
echo ""

# Timestamp for filename
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DOMAIN=$(echo "$URL" | sed -e 's|https\?://||' -e 's|/.*||' -e 's|[^a-zA-Z0-9]|_|g')

# Throttling settings
if [ "$THROTTLING" = "mobile" ]; then
    THROTTLE_ARGS="--throttling.cpuSlowdownMultiplier=4 --throttling.downloadThroughputKbps=1600 --throttling.uploadThroughputKbps=750 --throttling.rttMs=150"
else
    THROTTLE_ARGS="--throttling-method=provided"
fi

# Run tests
SCORES=()
LCP_VALUES=()
INP_VALUES=()
CLS_VALUES=()

for i in $(seq 1 $ITERATIONS); do
    echo -e "${YELLOW}Running test $i of $ITERATIONS...${NC}"

    REPORT_NAME="${DOMAIN}_${TIMESTAMP}_run${i}"

    lighthouse "$URL" \
        --preset=perf \
        --form-factor=mobile \
        --screenEmulation.mobile=true \
        --screenEmulation.width=412 \
        --screenEmulation.height=823 \
        --screenEmulation.deviceScaleFactor=2.625 \
        $THROTTLE_ARGS \
        --output=html,json \
        --output-path="$OUTPUT_DIR/$REPORT_NAME" \
        --chrome-flags="--headless --no-sandbox --disable-gpu" \
        --quiet

    # Extract scores
    JSON_FILE="$OUTPUT_DIR/${REPORT_NAME}.report.json"

    if [ -f "$JSON_FILE" ]; then
        SCORE=$(jq '.categories.performance.score * 100' "$JSON_FILE")
        LCP=$(jq '.audits["largest-contentful-paint"].numericValue // 0' "$JSON_FILE")
        INP=$(jq '.audits["interaction-to-next-paint"].numericValue // 0' "$JSON_FILE")
        CLS=$(jq '.audits["cumulative-layout-shift"].numericValue // 0' "$JSON_FILE")

        SCORES+=("$SCORE")
        LCP_VALUES+=("$LCP")
        INP_VALUES+=("$INP")
        CLS_VALUES+=("$CLS")

        echo "  Score: ${SCORE}%  LCP: ${LCP}ms  INP: ${INP}ms  CLS: ${CLS}"
    fi

    # Wait between runs to avoid rate limiting
    if [ $i -lt $ITERATIONS ]; then
        sleep 5
    fi
done

echo ""

# Calculate averages
calc_avg() {
    local values=("$@")
    local sum=0
    local count=${#values[@]}

    for val in "${values[@]}"; do
        sum=$(echo "$sum + $val" | bc)
    done

    echo "scale=2; $sum / $count" | bc
}

if [ ${#SCORES[@]} -gt 0 ]; then
    AVG_SCORE=$(calc_avg "${SCORES[@]}")
    AVG_LCP=$(calc_avg "${LCP_VALUES[@]}")
    AVG_INP=$(calc_avg "${INP_VALUES[@]}")
    AVG_CLS=$(calc_avg "${CLS_VALUES[@]}")

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Results Summary${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo "Average Scores ($ITERATIONS runs):"
    echo "-------------------------------------------"
    printf "  Performance Score: %6.1f%%\n" "$AVG_SCORE"
    printf "  LCP:               %6.0fms\n" "$AVG_LCP"
    printf "  INP:               %6.0fms\n" "$AVG_INP"
    printf "  CLS:               %6.3f\n" "$AVG_CLS"
    echo ""

    # Determine status
    echo "Core Web Vitals Status:"
    echo "-------------------------------------------"

    # LCP
    if (( $(echo "$AVG_LCP <= 2500" | bc -l) )); then
        echo -e "  LCP: ${GREEN}Good${NC} (≤2.5s)"
    elif (( $(echo "$AVG_LCP <= 4000" | bc -l) )); then
        echo -e "  LCP: ${YELLOW}Needs Improvement${NC} (2.5-4s)"
    else
        echo -e "  LCP: ${RED}Poor${NC} (>4s)"
    fi

    # INP
    if (( $(echo "$AVG_INP <= 200" | bc -l) )); then
        echo -e "  INP: ${GREEN}Good${NC} (≤200ms)"
    elif (( $(echo "$AVG_INP <= 500" | bc -l) )); then
        echo -e "  INP: ${YELLOW}Needs Improvement${NC} (200-500ms)"
    else
        echo -e "  INP: ${RED}Poor${NC} (>500ms)"
    fi

    # CLS
    if (( $(echo "$AVG_CLS <= 0.1" | bc -l) )); then
        echo -e "  CLS: ${GREEN}Good${NC} (≤0.1)"
    elif (( $(echo "$AVG_CLS <= 0.25" | bc -l) )); then
        echo -e "  CLS: ${YELLOW}Needs Improvement${NC} (0.1-0.25)"
    else
        echo -e "  CLS: ${RED}Poor${NC} (>0.25)"
    fi

    echo ""
    echo "Reports saved to: $OUTPUT_DIR"
    echo ""

    # Create summary JSON
    cat > "$OUTPUT_DIR/summary_${DOMAIN}_${TIMESTAMP}.json" << EOF
{
    "url": "$URL",
    "timestamp": "$(date -Iseconds)",
    "iterations": $ITERATIONS,
    "throttling": "$THROTTLING",
    "averages": {
        "performance": $AVG_SCORE,
        "lcp_ms": $AVG_LCP,
        "inp_ms": $AVG_INP,
        "cls": $AVG_CLS
    },
    "runs": [
        $(for i in "${!SCORES[@]}"; do
            echo "{"
            echo "  \"performance\": ${SCORES[$i]},"
            echo "  \"lcp_ms\": ${LCP_VALUES[$i]},"
            echo "  \"inp_ms\": ${INP_VALUES[$i]},"
            echo "  \"cls\": ${CLS_VALUES[$i]}"
            if [ $i -lt $((${#SCORES[@]} - 1)) ]; then
                echo "},"
            else
                echo "}"
            fi
        done)
    ]
}
EOF

    echo "Summary JSON: $OUTPUT_DIR/summary_${DOMAIN}_${TIMESTAMP}.json"
fi
