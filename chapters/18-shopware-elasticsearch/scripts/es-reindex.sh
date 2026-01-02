#!/bin/bash
#
# Elasticsearch Reindex Script for Shopware 6
#
# Performs optimized full reindexing with:
# - Disabled refresh during bulk import
# - Force merge after completion
# - Progress tracking
#
# Usage:
#   ./es-reindex.sh
#   ./es-reindex.sh --force     # Skip confirmations
#   ./es-reindex.sh --parallel  # Use parallel queue workers
#
# Requirements:
#   - Shopware 6 CLI (bin/console)
#   - curl
#   - jq

set -euo pipefail

# Configuration
SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
ES_URL="${ES_URL:-http://localhost:9200}"
INDEX_PREFIX="${INDEX_PREFIX:-sw_}"
FORCE="${FORCE:-false}"
PARALLEL="${PARALLEL:-false}"

# Parse arguments
for arg in "$@"; do
    case ${arg} in
        --force)
            FORCE=true
            ;;
        --parallel)
            PARALLEL=true
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force     Skip confirmation prompts"
            echo "  --parallel  Use parallel queue workers"
            echo "  --help      Show this help"
            echo ""
            echo "Environment variables:"
            echo "  SHOPWARE_ROOT  Shopware installation path (default: /var/www/html)"
            echo "  ES_URL         Elasticsearch URL (default: http://localhost:9200)"
            echo "  INDEX_PREFIX   Index prefix (default: sw_)"
            exit 0
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Reindex for Shopware 6${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Shopware: ${SHOPWARE_ROOT}"
echo "ES URL:   ${ES_URL}"
echo "Prefix:   ${INDEX_PREFIX}"
echo ""

# Check prerequisites
cd "${SHOPWARE_ROOT}"

if [[ ! -f "bin/console" ]]; then
    echo -e "${RED}Error: Shopware console not found at ${SHOPWARE_ROOT}/bin/console${NC}"
    exit 1
fi

if ! curl -s --connect-timeout 5 "${ES_URL}" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to Elasticsearch at ${ES_URL}${NC}"
    exit 1
fi

# Get current index stats
echo -e "${YELLOW}Current Index Status:${NC}"
curl -s "${ES_URL}/_cat/indices/${INDEX_PREFIX}*?v&h=index,docs.count,store.size" 2>/dev/null || echo "No indices found"
echo ""

# Confirmation
if [[ "${FORCE}" != "true" ]]; then
    read -p "Start full reindex? This may take several minutes. [y/N] " -n 1 -r
    echo
    if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Start timer
START_TIME=$(date +%s)

# Step 1: Disable refresh
echo ""
echo -e "${YELLOW}Step 1/5: Disabling refresh interval...${NC}"
curl -s -X PUT "${ES_URL}/${INDEX_PREFIX}*/_settings" \
    -H 'Content-Type: application/json' \
    -d '{"index": {"refresh_interval": "-1"}}' | jq -r '.acknowledged // "failed"'

# Step 2: Delete old indices (optional, for clean reindex)
echo ""
echo -e "${YELLOW}Step 2/5: Preparing indices...${NC}"
bin/console es:create:alias --quiet 2>/dev/null || true
echo "Done"

# Step 3: Run indexing
echo ""
echo -e "${YELLOW}Step 3/5: Starting Shopware indexing...${NC}"
echo "This may take several minutes depending on catalog size."
echo ""

if [[ "${PARALLEL}" = "true" ]]; then
    echo "Using queue workers (parallel mode)..."
    bin/console es:index
    echo ""
    echo "Waiting for queue to complete..."
    bin/console messenger:consume async --time-limit=300 --memory-limit=512M &
    WORKER_PID=$!
    sleep 5

    # Monitor queue
    while true; do
        QUEUE_SIZE=$(bin/console messenger:count async 2>/dev/null || echo "0")
        if [[ "${QUEUE_SIZE}" = "0" ]] || [[ -z "${QUEUE_SIZE}" ]]; then
            break
        fi
        echo "Queue size: ${QUEUE_SIZE} - waiting..."
        sleep 10
    done

    kill ${WORKER_PID} 2>/dev/null || true
else
    echo "Using synchronous mode..."
    bin/console es:index --no-queue
fi

# Step 4: Enable refresh
echo ""
echo -e "${YELLOW}Step 4/5: Enabling refresh interval...${NC}"
curl -s -X PUT "${ES_URL}/${INDEX_PREFIX}*/_settings" \
    -H 'Content-Type: application/json' \
    -d '{"index": {"refresh_interval": "5s"}}' | jq -r '.acknowledged // "failed"'

# Step 5: Force merge
echo ""
echo -e "${YELLOW}Step 5/5: Running force merge...${NC}"
echo "This optimizes index segments for better query performance."
curl -s -X POST "${ES_URL}/${INDEX_PREFIX}*/_forcemerge?max_num_segments=1" | jq -r '._shards.successful // "failed"'

# Final refresh
curl -s -X POST "${ES_URL}/${INDEX_PREFIX}*/_refresh" > /dev/null

# End timer
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Summary
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Reindex Complete${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo -e "${YELLOW}New Index Status:${NC}"
curl -s "${ES_URL}/_cat/indices/${INDEX_PREFIX}*?v&h=index,docs.count,store.size" 2>/dev/null
echo ""

# Health check
HEALTH=$(curl -s "${ES_URL}/_cluster/health" | jq -r '.status')
case "${HEALTH}" in
    "green")
        echo -e "Cluster Health: ${GREEN}${HEALTH}${NC}"
        ;;
    "yellow")
        echo -e "Cluster Health: ${YELLOW}${HEALTH}${NC}"
        ;;
    "red")
        echo -e "Cluster Health: ${RED}${HEALTH}${NC}"
        ;;
esac

echo ""
echo -e "${GREEN}Reindex completed successfully!${NC}"
