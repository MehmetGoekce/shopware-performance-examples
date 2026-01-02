#!/bin/bash
# Cache Hit-Rate Calculator
# Kapitel 6: HTTP-Caching
#
# Berechnet die Cache-Hit-Rate aus Nginx/Varnish Logs.
#
# Verwendung:
#   ./cache-hit-rate.sh /var/log/nginx/access.log
#   ./cache-hit-rate.sh /var/log/varnish/varnishncsa.log
#   ./cache-hit-rate.sh --varnishstat
#
# Voraussetzung für Nginx:
#   Log-Format muss X-Cache Header enthalten:
#   log_format cache '${remote_addr} - ${upstream_cache_status} ...';
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Funktionen
# ============================================================

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Cache Hit-Rate Calculator${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

analyze_nginx_log() {
    local logfile=$1

    echo ""
    echo -e "${BLUE}📊 Analysiere Nginx Log: ${logfile}${NC}"
    echo ""

    if [[ ! -f "${logfile}" ]]; then
        echo -e "${RED}❌ Datei nicht gefunden: ${logfile}${NC}"
        exit 1
    fi

    # Verschiedene Log-Formate versuchen
    # Format 1: X-Cache Header am Ende
    hits=$(grep -c "HIT" "${logfile}" 2>/dev/null || echo "0")
    misses=$(grep -c "MISS" "${logfile}" 2>/dev/null || echo "0")
    bypasses=$(grep -c "BYPASS" "${logfile}" 2>/dev/null || echo "0")
    expired=$(grep -c "EXPIRED" "${logfile}" 2>/dev/null || echo "0")

    total=$((hits + misses + bypasses + expired))

    if [[ "${total}" -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Keine Cache-Status gefunden im Log.${NC}"
        echo ""
        echo "Stelle sicher, dass dein Nginx Log-Format den Cache-Status enthält:"
        echo ""
        echo '  log_format cache '"'"'${remote_addr} - ${remote_user} [${time_local}] "${request}" '
        echo '                   ${status} ${body_bytes_sent} "${http_referer}" '
        echo '                   "${http_user_agent}" ${upstream_cache_status}'"'"';'
        echo ""
        echo '  access_log /var/log/nginx/access.log cache;'
        return 1
    fi

    # Berechnung
    hit_rate=$(echo "scale=2; ${hits} * 100 / ${total}" | bc)

    echo "Cache Status Verteilung:"
    echo "───────────────────────────────────────"
    printf "  HIT:     %8d\n" "${hits}"
    printf "  MISS:    %8d\n" "${misses}"
    printf "  BYPASS:  %8d\n" "${bypasses}"
    printf "  EXPIRED: %8d\n" "${expired}"
    echo "───────────────────────────────────────"
    printf "  TOTAL:   %8d\n" "${total}"
    echo ""

    # Hit-Rate mit Bewertung
    echo -n "Cache Hit-Rate: "
    if (( $(echo "${hit_rate} >= 95" | bc -l) )); then
        echo -e "${GREEN}${hit_rate}% ✅ Exzellent${NC}"
    elif (( $(echo "${hit_rate} >= 80" | bc -l) )); then
        echo -e "${GREEN}${hit_rate}% ✅ Gut${NC}"
    elif (( $(echo "${hit_rate} >= 60" | bc -l) )); then
        echo -e "${YELLOW}${hit_rate}% ⚠ Verbesserungswürdig${NC}"
    else
        echo -e "${RED}${hit_rate}% ❌ Schlecht${NC}"
    fi
}

analyze_varnishstat() {
    echo ""
    echo -e "${BLUE}📊 Analysiere Varnish Statistiken${NC}"
    echo ""

    if ! command -v varnishstat &> /dev/null; then
        echo -e "${RED}❌ varnishstat nicht gefunden${NC}"
        exit 1
    fi

    # Varnish Statistiken abrufen
    stats=$(varnishstat -1 2>/dev/null)

    hits=$(echo "${stats}" | grep "MAIN.cache_hit " | awk '{print $2}')
    misses=$(echo "${stats}" | grep "MAIN.cache_miss " | awk '{print $2}')
    hitpass=$(echo "${stats}" | grep "MAIN.cache_hitpass " | awk '{print $2}')

    hits=${hits:-0}
    misses=${misses:-0}
    hitpass=${hitpass:-0}

    total=$((hits + misses))

    if [[ "${total}" -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Keine Requests seit Varnish-Start${NC}"
        return 1
    fi

    hit_rate=$(echo "scale=2; ${hits} * 100 / ${total}" | bc)

    echo "Varnish Cache Statistiken:"
    echo "───────────────────────────────────────"
    printf "  cache_hit:     %12d\n" "${hits}"
    printf "  cache_miss:    %12d\n" "${misses}"
    printf "  cache_hitpass: %12d\n" "${hitpass}"
    echo "───────────────────────────────────────"
    printf "  Total:         %12d\n" "${total}"
    echo ""

    echo -n "Cache Hit-Rate: "
    if (( $(echo "${hit_rate} >= 95" | bc -l) )); then
        echo -e "${GREEN}${hit_rate}% ✅ Exzellent${NC}"
    elif (( $(echo "${hit_rate} >= 80" | bc -l) )); then
        echo -e "${GREEN}${hit_rate}% ✅ Gut${NC}"
    elif (( $(echo "${hit_rate} >= 60" | bc -l) )); then
        echo -e "${YELLOW}${hit_rate}% ⚠ Verbesserungswürdig${NC}"
    else
        echo -e "${RED}${hit_rate}% ❌ Schlecht${NC}"
    fi

    # Zusätzliche Varnish-Metriken
    echo ""
    echo "Weitere Metriken:"
    echo "───────────────────────────────────────"

    n_object=$(echo "${stats}" | grep "MAIN.n_object " | awk '{print $2}')
    printf "  Objekte im Cache: %d\n" "${n_object:-0}"

    backend_conn=$(echo "${stats}" | grep "MAIN.backend_conn " | awk '{print $2}')
    printf "  Backend Verbindungen: %d\n" "${backend_conn:-0}"

    backend_fail=$(echo "${stats}" | grep "MAIN.backend_fail " | awk '{print $2}')
    if [[ "${backend_fail:-0}" -gt 0 ]]; then
        echo -e "  ${RED}Backend Fehler: ${backend_fail}${NC}"
    fi
}

print_recommendations() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Empfehlungen${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Ziel-Werte:"
    echo "  > 95%  = Exzellent (überwiegend statischer Content)"
    echo "  > 80%  = Gut (typischer E-Commerce Shop)"
    echo "  > 60%  = Verbesserungswürdig"
    echo "  < 60%  = Schlecht - Optimierung dringend nötig"
    echo ""
    echo "Verbesserungsmöglichkeiten:"
    echo "  1. TTL erhöhen (stale-while-revalidate nutzen)"
    echo "  2. Query-Parameter normalisieren (UTM etc.)"
    echo "  3. Set-Cookie Header entfernen wo möglich"
    echo "  4. Session-Cookies nur bei Bedarf setzen"
    echo "  5. ESI für dynamische Teile nutzen"
    echo ""
}

show_usage() {
    echo "Verwendung: $0 <logfile> | --varnishstat"
    echo ""
    echo "Optionen:"
    echo "  <logfile>      Nginx/Apache Access Log mit Cache-Status"
    echo "  --varnishstat  Statistiken direkt von Varnish abrufen"
    echo ""
    echo "Beispiele:"
    echo "  $0 /var/log/nginx/access.log"
    echo "  $0 /var/log/varnish/varnishncsa.log"
    echo "  $0 --varnishstat"
}

# ============================================================
# Main
# ============================================================

if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

print_header

case $1 in
    --varnishstat|-v)
        analyze_varnishstat
        ;;
    --help|-h)
        show_usage
        exit 0
        ;;
    *)
        analyze_nginx_log "$1"
        ;;
esac

print_recommendations

echo -e "${GREEN}✅ Analyse abgeschlossen${NC}"
