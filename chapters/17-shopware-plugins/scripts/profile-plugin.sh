#!/bin/bash
#
# Plugin Performance Analyzer
#
# Measures the performance impact of a specific plugin
# by comparing response times with and without the plugin.
#
# Usage:
#   ./profile-plugin.sh <plugin-name> [test-url]
#   ./profile-plugin.sh MyCustomPlugin /produkt/test-produkt
#
# Requirements:
#   - curl
#   - bc (for floating point math)
#   - Shopware 6 CLI (bin/console)
#

set -euo pipefail

# Configuration
SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
ITERATIONS="${ITERATIONS:-5}"
WARMUP="${WARMUP:-2}"
BASE_URL="${BASE_URL:-http://localhost}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Arguments
PLUGIN_NAME="${1:-}"
TEST_URL="${2:-/}"

# Help
show_help() {
    echo "Usage: $0 <plugin-name> [test-url]"
    echo ""
    echo "Arguments:"
    echo "  plugin-name    Name of the plugin to test"
    echo "  test-url       URL path to test (default: /)"
    echo ""
    echo "Environment variables:"
    echo "  SHOPWARE_ROOT  Shopware installation path (default: /var/www/html)"
    echo "  ITERATIONS     Number of test iterations (default: 5)"
    echo "  BASE_URL       Base URL for requests (default: http://localhost)"
    echo ""
    echo "Examples:"
    echo "  $0 MyPlugin"
    echo "  $0 PayPal /checkout/cart"
    echo "  ITERATIONS=10 $0 CustomTheme /kategorie/test"
    echo ""
}

if [ -z "$PLUGIN_NAME" ]; then
    show_help
    exit 1
fi

# Functions
measure_url() {
    local url=$1
    local total=0
    local times=()

    # Warmup requests
    for ((i=1; i<=$WARMUP; i++)); do
        curl -s -o /dev/null -w '' "${BASE_URL}${url}" || true
    done

    # Measured requests
    for ((i=1; i<=$ITERATIONS; i++)); do
        time=$(curl -s -o /dev/null -w '%{time_total}' "${BASE_URL}${url}")
        times+=("$time")
        total=$(echo "$total + $time" | bc)
    done

    # Calculate average
    avg=$(echo "scale=4; $total / $ITERATIONS" | bc)

    # Calculate min/max
    min=$(printf '%s\n' "${times[@]}" | sort -n | head -1)
    max=$(printf '%s\n' "${times[@]}" | sort -n | tail -1)

    echo "$avg $min $max"
}

clear_cache() {
    cd "$SHOPWARE_ROOT"
    bin/console cache:clear > /dev/null 2>&1
    bin/console http:cache:clear > /dev/null 2>&1
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Plugin Performance Analyzer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Plugin:      ${YELLOW}$PLUGIN_NAME${NC}"
echo -e "URL:         $TEST_URL"
echo -e "Iterations:  $ITERATIONS"
echo -e "Warmup:      $WARMUP"
echo ""

# Check if plugin exists
cd "$SHOPWARE_ROOT"
if ! bin/console plugin:list | grep -q "$PLUGIN_NAME"; then
    echo -e "${RED}Error: Plugin '$PLUGIN_NAME' not found${NC}"
    echo ""
    echo "Available plugins:"
    bin/console plugin:list --columns=name,active | head -20
    exit 1
fi

# Phase 1: Measure with plugin active
echo -e "${YELLOW}Phase 1: Measuring WITH plugin active...${NC}"
clear_cache

read -r with_avg with_min with_max <<< "$(measure_url "$TEST_URL")"

echo -e "  Average: ${with_avg}s (min: ${with_min}s, max: ${with_max}s)"

# Phase 2: Deactivate plugin
echo -e "${YELLOW}Phase 2: Deactivating plugin...${NC}"
bin/console plugin:deactivate "$PLUGIN_NAME" > /dev/null 2>&1
clear_cache

# Phase 3: Measure without plugin
echo -e "${YELLOW}Phase 3: Measuring WITHOUT plugin...${NC}"
read -r without_avg without_min without_max <<< "$(measure_url "$TEST_URL")"

echo -e "  Average: ${without_avg}s (min: ${without_min}s, max: ${without_max}s)"

# Phase 4: Reactivate plugin
echo -e "${YELLOW}Phase 4: Reactivating plugin...${NC}"
bin/console plugin:activate "$PLUGIN_NAME" > /dev/null 2>&1
clear_cache

# Calculate difference
diff=$(echo "scale=4; $with_avg - $without_avg" | bc)
percent=$(echo "scale=1; ($diff / $without_avg) * 100" | bc 2>/dev/null || echo "0")

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "With plugin:    ${with_avg}s"
echo -e "Without plugin: ${without_avg}s"
echo ""

# Determine impact
if (( $(echo "$diff > 0.1" | bc -l) )); then
    echo -e "Impact:         ${RED}+${diff}s (+${percent}%)${NC}"
    echo ""
    echo -e "${RED}[WARNING] Plugin has significant performance impact!${NC}"
    echo ""
    echo "Recommendations:"
    echo "  1. Profile with Blackfire or Tideways"
    echo "  2. Check for debug logging"
    echo "  3. Review event subscribers"
    echo "  4. Check database queries"
    EXIT_CODE=1
elif (( $(echo "$diff > 0.05" | bc -l) )); then
    echo -e "Impact:         ${YELLOW}+${diff}s (+${percent}%)${NC}"
    echo ""
    echo -e "${YELLOW}[MODERATE] Plugin has noticeable impact${NC}"
    EXIT_CODE=0
else
    echo -e "Impact:         ${GREEN}+${diff}s (+${percent}%)${NC}"
    echo ""
    echo -e "${GREEN}[OK] Plugin has minimal performance impact${NC}"
    EXIT_CODE=0
fi

# Additional metrics if available
echo ""
echo -e "${BLUE}Additional Analysis:${NC}"

# Check if plugin has event subscribers
SUBSCRIBER_COUNT=$(grep -r "EventSubscriberInterface" "$SHOPWARE_ROOT/custom/plugins/$PLUGIN_NAME" 2>/dev/null | wc -l || echo "0")
echo -e "  Event Subscribers: $SUBSCRIBER_COUNT"

# Check for slow patterns
DBAL_COUNT=$(grep -r "createQueryBuilder\|executeStatement" "$SHOPWARE_ROOT/custom/plugins/$PLUGIN_NAME" 2>/dev/null | wc -l || echo "0")
DAL_COUNT=$(grep -r "EntityRepository\|->search\|->create\|->update" "$SHOPWARE_ROOT/custom/plugins/$PLUGIN_NAME" 2>/dev/null | wc -l || echo "0")
echo -e "  DBAL Operations: $DBAL_COUNT"
echo -e "  DAL Operations: $DAL_COUNT"

echo ""
exit ${EXIT_CODE:-0}
