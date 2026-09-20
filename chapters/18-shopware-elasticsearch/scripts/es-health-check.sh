#!/bin/bash
#
# Elasticsearch Health Check Script
#
# Comprehensive health check for Elasticsearch/OpenSearch clusters.
#
# Usage:
#   ./es-health-check.sh
#   ES_URL=http://elastic:password@localhost:9200 ./es-health-check.sh
#
# Requirements:
#   - curl
#   - jq (for JSON parsing)
#

set -euo pipefail

# Parse arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Elasticsearch/OpenSearch cluster health check."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help"
    echo ""
    echo "Environment:"
    echo "  ES_URL        Elasticsearch URL (default: http://localhost:9200)"
    echo "  INDEX_PREFIX  Shopware index prefix (default: sw, ohne Unterstrich)"
    echo "  ES_LOG_DIR    Slow-Log-Verzeichnis (default: /var/log/elasticsearch)"
    exit 0
fi

# Configuration
ES_URL="${ES_URL:-http://localhost:9200}"
INDEX_PREFIX="${INDEX_PREFIX:-sw}"
WARNING_HEAP_PERCENT=75
CRITICAL_HEAP_PERCENT=85
WARNING_DISK_PERCENT=80

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Exit codes
EXIT_OK=0
EXIT_WARNING=1
EXIT_CRITICAL=2
FINAL_EXIT=${EXIT_OK}

update_exit() {
    local new_exit=$1
    if [[ ${new_exit} -gt ${FINAL_EXIT} ]]; then
        FINAL_EXIT=$new_exit
    fi
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Health Check${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "URL: ${ES_URL}"
echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check connectivity
echo -e "${BLUE}1. Connectivity${NC}"
echo "-------------------------------------------"
if ! curl -s --connect-timeout 5 "${ES_URL}" > /dev/null 2>&1; then
    echo -e "   ${RED}[CRITICAL] Cannot connect to Elasticsearch!${NC}"
    exit ${EXIT_CRITICAL}
fi
echo -e "   ${GREEN}[OK] Connection successful${NC}"
echo ""

# Cluster Health
echo -e "${BLUE}2. Cluster Health${NC}"
echo "-------------------------------------------"
CLUSTER_HEALTH=$(curl -s "${ES_URL}/_cluster/health")
CLUSTER_STATUS=$(echo "${CLUSTER_HEALTH}" | jq -r '.status')
CLUSTER_NAME=$(echo "${CLUSTER_HEALTH}" | jq -r '.cluster_name')
NODE_COUNT=$(echo "${CLUSTER_HEALTH}" | jq -r '.number_of_nodes')
ACTIVE_SHARDS=$(echo "${CLUSTER_HEALTH}" | jq -r '.active_shards')
UNASSIGNED_SHARDS=$(echo "${CLUSTER_HEALTH}" | jq -r '.unassigned_shards')
# Das Feld heisst number_of_pending_tasks. `.pending_tasks` liefert null,
# und `// 0` macht daraus stillschweigend eine 0 — der Check meldete nie etwas.
PENDING_TASKS=$(echo "${CLUSTER_HEALTH}" | jq -r '.number_of_pending_tasks // 0')

echo "   Cluster:    ${CLUSTER_NAME}"
echo "   Nodes:      ${NODE_COUNT}"
echo "   Shards:     ${ACTIVE_SHARDS} active, ${UNASSIGNED_SHARDS} unassigned"
echo "   Tasks:      ${PENDING_TASKS} pending"

case "${CLUSTER_STATUS}" in
    "green")
        echo -e "   Status:     ${GREEN}${CLUSTER_STATUS}${NC}"
        ;;
    "yellow")
        echo -e "   Status:     ${YELLOW}${CLUSTER_STATUS}${NC}"
        update_exit ${EXIT_WARNING}
        ;;
    "red")
        echo -e "   Status:     ${RED}${CLUSTER_STATUS}${NC}"
        update_exit ${EXIT_CRITICAL}
        ;;
esac
echo ""

# Node Stats
echo -e "${BLUE}3. Node Resources${NC}"
echo "-------------------------------------------"
NODE_STATS=$(curl -s "${ES_URL}/_nodes/stats/jvm,fs,os,process")

# Parse each node
# Prozess-Substitution statt Pipe: `cmd | while ...` laeuft in einer Subshell,
# update_exit veraendert dort eine KOPIE von FINAL_EXIT. Der Heap-, Disk- und
# GC-Check hat deshalb frueher zwar CRITICAL gedruckt, den Exit-Code aber nie
# angefasst.
while IFS='|' read -r node_id node_name heap_percent fs_avail fs_total open_fd max_fd; do
    echo "   Node: ${node_name}"

    # Heap check
    heap_int=${heap_percent%.*}
    if [[ "${heap_int}" -ge "${CRITICAL_HEAP_PERCENT}" ]]; then
        echo -e "     Heap:       ${RED}${heap_percent}% [CRITICAL]${NC}"
        update_exit ${EXIT_CRITICAL}
    elif [[ "${heap_int}" -ge "${WARNING_HEAP_PERCENT}" ]]; then
        echo -e "     Heap:       ${YELLOW}${heap_percent}% [WARNING]${NC}"
        update_exit ${EXIT_WARNING}
    else
        echo -e "     Heap:       ${GREEN}${heap_percent}%${NC}"
    fi

    # Disk check
    if [[ -n "${fs_total}" ]] && [[ "${fs_total}" != "null" ]] && [[ "${fs_total}" -gt 0 ]]; then
        disk_used_percent=$((100 - (fs_avail * 100 / fs_total)))
        if [[ "${disk_used_percent}" -ge "${WARNING_DISK_PERCENT}" ]]; then
            echo -e "     Disk:       ${YELLOW}${disk_used_percent}% used [WARNING]${NC}"
            update_exit ${EXIT_WARNING}
        else
            echo -e "     Disk:       ${GREEN}${disk_used_percent}% used${NC}"
        fi
    fi

    # File descriptors
    if [[ -n "${max_fd}" ]] && [[ "${max_fd}" != "null" ]] && [[ "${max_fd}" -gt 0 ]]; then
        fd_percent=$((open_fd * 100 / max_fd))
        echo "     FDs:        ${open_fd} / ${max_fd} (${fd_percent}%)"
    fi
    echo ""
done < <(echo "${NODE_STATS}" | jq -r '.nodes | to_entries[] | "\(.key)|\(.value.name)|\(.value.jvm.mem.heap_used_percent)|\(.value.fs.total.available_in_bytes)|\(.value.fs.total.total_in_bytes)|\(.value.process.open_file_descriptors)|\(.value.process.max_file_descriptors)"')

# GC Stats
echo -e "${BLUE}4. Garbage Collection${NC}"
echo "-------------------------------------------"
while IFS='|' read -r node_name old_count old_time young_count young_time; do
    echo "   Node: ${node_name}"
    echo "     Old GC:     ${old_count} collections, ${old_time}ms total"
    echo "     Young GC:   ${young_count} collections, ${young_time}ms total"

    # Check for excessive GC
    if [[ "${old_count}" -gt 0 ]]; then
        avg_old_gc=$((old_time / old_count))
        if [[ "${avg_old_gc}" -gt 1000 ]]; then
            echo -e "     ${YELLOW}[WARNING] Average Old GC time: ${avg_old_gc}ms${NC}"
            update_exit ${EXIT_WARNING}
        fi
    fi
    echo ""
done < <(echo "${NODE_STATS}" | jq -r '.nodes | to_entries[] | "\(.value.name)|\(.value.jvm.gc.collectors.old.collection_count // 0)|\(.value.jvm.gc.collectors.old.collection_time_in_millis // 0)|\(.value.jvm.gc.collectors.young.collection_count // 0)|\(.value.jvm.gc.collectors.young.collection_time_in_millis // 0)"')

# Index Stats
echo -e "${BLUE}5. Index Statistics${NC}"
echo "-------------------------------------------"
# docs.count aus _cat/indices ist die Zahl der LUCENE-Dokumente — Shopware
# indexiert verschachtelte Felder, deshalb liegt der Wert deutlich ueber der
# Produktzahl (gemessen: 234 gegen 14). Und er haengt am Refresh: direkt nach
# dem Indexieren steht dort minutenlang 0. Die Produktzahl liefert _count.
echo "   Index                          Lucene-Docs      Size"
echo "   -------------------------------------------"
while read -r index docs size; do
    printf "   %-30s %11s %10s\n" "${index}" "${docs}" "${size}"
done < <(curl -s "${ES_URL}/_cat/indices?v&s=store.size:desc&h=index,docs.count,store.size" 2>/dev/null | tail -n +2 | head -10)
echo ""
ALIAS_COUNT=$(curl -s "${ES_URL}/${INDEX_PREFIX}_product/_count" 2>/dev/null | jq -r '.count // "n/a"')
echo "   Produkte hinter dem Alias ${INDEX_PREFIX}_product: ${ALIAS_COUNT}"
echo ""

# Slow Log Entries (if available)
echo -e "${BLUE}6. Recent Slow Queries${NC}"
echo "-------------------------------------------"
# In Elasticsearch 8.x heisst die Datei <cluster>_index_search_slowlog.JSON
# und traegt ECS-JSON, nicht mehr .log mit Klartext
# (distribution/src/config/log4j2.properties@v8.15.0, RollingFile-Appender).
# Im offiziellen Docker-Image ist derselbe Appender ein Console-Appender —
# dort steht der Slow-Log in `docker logs`, nicht in einer Datei.
SLOWLOG_PATH="${ES_LOG_DIR:-/var/log/elasticsearch}/*_index_search_slowlog.json"
# shellcheck disable=SC2086  # Glob soll expandieren
if ls ${SLOWLOG_PATH} 1> /dev/null 2>&1; then
    # shellcheck disable=SC2086
    SLOW_COUNT=$(cat ${SLOWLOG_PATH} 2>/dev/null | wc -l)
    if [[ "${SLOW_COUNT}" -gt 0 ]]; then
        echo -e "   ${YELLOW}${SLOW_COUNT} Slow-Log-Zeilen${NC}"
        echo "   Die drei letzten:"
        # shellcheck disable=SC2086
        tail -3 ${SLOWLOG_PATH} 2>/dev/null \
            | jq -r '"     \(.["elasticsearch.slowlog.took"] // "?") — \(.["elasticsearch.slowlog.id"] // .message // "" | tostring | .[0:70])"' 2>/dev/null \
            || tail -3 ${SLOWLOG_PATH} | cut -c1-100
    else
        echo -e "   ${GREEN}Keine Slow-Log-Eintraege${NC}"
    fi
else
    echo "   Slow-Log nicht gefunden (Pfad: ${SLOWLOG_PATH})."
    echo "   Im Docker-Image geht der Slow-Log auf stdout: docker logs <container>."
    echo "   Schwellen setzen: ./slowlog-settings.sh"
fi
echo ""

# Pending Tasks
echo -e "${BLUE}7. Pending Tasks${NC}"
echo "-------------------------------------------"
PENDING=$(curl -s "${ES_URL}/_cluster/pending_tasks")
PENDING_COUNT=$(echo "${PENDING}" | jq '.tasks | length')
if [[ "${PENDING_COUNT}" -gt 0 ]]; then
    echo -e "   ${YELLOW}${PENDING_COUNT} pending tasks${NC}"
    echo "${PENDING}" | jq -r '.tasks[] | "     \(.priority): \(.source)"' | head -5
else
    echo -e "   ${GREEN}No pending tasks${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}============================================${NC}"
case ${FINAL_EXIT} in
    0)
        echo -e "   Overall Status: ${GREEN}HEALTHY${NC}"
        ;;
    1)
        echo -e "   Overall Status: ${YELLOW}WARNING${NC}"
        ;;
    2)
        echo -e "   Overall Status: ${RED}CRITICAL${NC}"
        ;;
esac
echo ""

exit ${FINAL_EXIT}
