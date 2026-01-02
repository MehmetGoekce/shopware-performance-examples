#!/bin/bash
#
# Cache-Hit-Rate analysieren - Fallstudie 1 & 5
# Kapitel 23: Reale Fallstudien aus 26 Jahren
#
# Analysiert Nginx/Varnish Access-Logs für Cache-Hit-Rate.
#

LOG_FILE="${1:-/var/log/nginx/access.log}"
HOURS="${2:-24}"

echo "=== Cache-Hit-Rate Analyse ==="
echo ""
echo "Log-Datei: ${LOG_FILE}"
echo "Zeitraum: letzte ${HOURS} Stunden"
echo ""

if [[ ! -f "${LOG_FILE}" ]]; then
    echo "Fehler: Log-Datei nicht gefunden: ${LOG_FILE}"
    exit 1
fi

# Zeitstempel für Filter
SINCE=$(date -d "${HOURS} hours ago" '+%d/%b/%Y:%H')

# Nginx-Format: ${upstream_cache_status} in Log
# HIT, MISS, BYPASS, EXPIRED, STALE, UPDATING, REVALIDATED

echo "1. Cache-Status-Verteilung:"
echo ""

# Zähle Cache-Status (anpassen je nach Log-Format)
if grep -q "HIT\|MISS\|BYPASS" "${LOG_FILE}" 2>/dev/null; then
    TOTAL=$(grep -c "" "${LOG_FILE}")
    HIT=$(grep -c "HIT" "${LOG_FILE}" || echo 0)
    MISS=$(grep -c "MISS" "${LOG_FILE}" || echo 0)
    BYPASS=$(grep -c "BYPASS" "${LOG_FILE}" || echo 0)
    EXPIRED=$(grep -c "EXPIRED" "${LOG_FILE}" || echo 0)

    echo "   HIT:     ${HIT}"
    echo "   MISS:    ${MISS}"
    echo "   BYPASS:  ${BYPASS}"
    echo "   EXPIRED: ${EXPIRED}"
    echo ""

    if [[ ${TOTAL} -gt 0 ]]; then
        HIT_RATE=$(echo "scale=2; ${HIT} * 100 / ${TOTAL}" | bc)
        echo "   Hit-Rate: ${HIT_RATE}%"
        echo ""

        # Bewertung
        if (( $(echo "${HIT_RATE} > 90" | bc -l) )); then
            echo "   Status: Excellent"
        elif (( $(echo "${HIT_RATE} > 70" | bc -l) )); then
            echo "   Status: Gut"
        elif (( $(echo "${HIT_RATE} > 50" | bc -l) )); then
            echo "   Status: Verbesserungswürdig"
        else
            echo "   Status: KRITISCH - Cache nicht effektiv!"
        fi
    fi
else
    echo "   Keine Cache-Status-Informationen im Log gefunden."
    echo "   Tipp: Nginx-Log-Format anpassen:"
    echo ""
    echo '   log_format cache '"'"'${remote_addr} - ${upstream_cache_status} [${time_local}] "${request}"'"'"';'
fi

echo ""
echo "2. Top 10 MISS-URLs (Cache-Optimierungs-Kandidaten):"
echo ""

grep "MISS" "${LOG_FILE}" 2>/dev/null | \
    awk '{print $7}' | \
    sort | uniq -c | sort -rn | head -10 | \
    while read count url; do
        printf "   %6d  %s\n" "${count}" "${url}"
    done

echo ""
echo "3. BYPASS-Gründe analysieren:"
echo ""

grep "BYPASS" "${LOG_FILE}" 2>/dev/null | \
    grep -oP 'Cookie:[^"]*' | \
    sort | uniq -c | sort -rn | head -5 | \
    while read count reason; do
        printf "   %6d  %s\n" "${count}" "${reason}"
    done

echo ""
echo "=== Empfehlungen ==="
echo ""
echo "- Hit-Rate < 70%: Cache-Regeln überprüfen"
echo "- Viele BYPASS: Session-Cookie-Handling optimieren"
echo "- Viele MISS bei gleichen URLs: Cache-Warming einsetzen"
