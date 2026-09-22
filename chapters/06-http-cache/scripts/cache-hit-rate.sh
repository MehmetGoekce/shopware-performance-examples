#!/bin/bash
# Cache Hit-Rate Calculator
# Kapitel 6: HTTP-Caching
#
# Berechnet die Cache-Hit-Rate aus Varnish-Zählern oder aus einem Access-Log,
# dessen LETZTES Feld der Cache-Status ist.
#
# Verwendung (im Ordner chapters/06-http-cache):
#   ./scripts/cache-hit-rate.sh --varnishstat
#   ./scripts/cache-hit-rate.sh /var/log/varnish/varnishncsa.log
#   ./scripts/cache-hit-rate.sh /var/log/nginx/access.log
#
# Log-Formate mit Cache-Status als letztem Feld:
#   Varnish:  varnishncsa -F '%h %t "%r" %s %b %{Varnish:handling}x'
#             (letztes Feld: hit, miss, pass, hitmiss, hitpass, pipe oder synth;
#              hitmiss/hitpass = nicht cachebare Antwort, die Varnish sich gemerkt hat)
#   Nginx mit proxy_cache statt Varnish:
#             log_format cache '$remote_addr [$time_local] "$request" $status $upstream_cache_status';
#
# Varnish im Container:
#   VARNISHSTAT_CMD="docker exec varnish varnishstat" ./scripts/cache-hit-rate.sh --varnishstat
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VARNISHSTAT_CMD="${VARNISHSTAT_CMD:-varnishstat}"

show_usage() {
    echo "Usage: $0 <logfile> | --varnishstat"
    echo ""
    echo "Optionen:"
    echo "  <logfile>      Access-Log, letztes Feld = Cache-Status (hit, miss, pass ...)"
    echo "  --varnishstat  Zähler direkt von Varnish lesen (MAIN.cache_hit / MAIN.cache_miss)"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  VARNISHSTAT_CMD  Befehl für varnishstat (Default: varnishstat)"
}

# Hit-Rate in Prozent mit zwei Nachkommastellen
percent() {
    awk -v h="$1" -v t="$2" 'BEGIN { printf "%.2f", (t > 0) ? h * 100 / t : 0 }'
}

# Schwellen wie in Kapitel 6.9: 70-90 % ist ein realistischer Zielkorridor
# für Gast-Traffic (Einschätzung, kein Shopware- oder Varnish-Richtwert).
rate_verdict() {
    local rate=$1
    echo -n "Cache Hit-Rate: "
    if awk -v r="${rate}" 'BEGIN { exit !(r >= 90) }'; then
        echo -e "${GREEN}${rate}% (über dem Zielkorridor)${NC}"
    elif awk -v r="${rate}" 'BEGIN { exit !(r >= 70) }'; then
        echo -e "${GREEN}${rate}% (im Zielkorridor 70-90 %)${NC}"
    elif awk -v r="${rate}" 'BEGIN { exit !(r >= 50) }'; then
        echo -e "${YELLOW}${rate}% (verbesserungswürdig)${NC}"
    else
        echo -e "${RED}${rate}% (schlecht)${NC}"
    fi
}

analyze_log() {
    local logfile=$1

    if [[ ! -f "${logfile}" ]]; then
        echo -e "${RED}Datei nicht gefunden: ${logfile}${NC}"
        exit 1
    fi

    echo -e "${BLUE}Analysiere Log: ${logfile}${NC}"
    echo ""

    # Letztes Feld jeder Zeile, nur bekannte Cache-Status zählen
    local counts
    counts=$(awk '
        { s = toupper($NF) }
        s ~ /^(HIT|MISS|PASS|HITMISS|HITPASS|PIPE|SYNTH|BYPASS|EXPIRED|STALE|UPDATING|REVALIDATED)$/ { n[s]++; total++ }
        END {
            printf "HIT=%d MISS=%d OTHER=%d TOTAL=%d\n", n["HIT"], n["MISS"], total - n["HIT"] - n["MISS"], total
        }' "${logfile}")

    local hits misses other total
    hits=$(echo "${counts}" | sed -n 's/.*HIT=\([0-9]*\).*/\1/p')
    misses=$(echo "${counts}" | sed -n 's/.*MISS=\([0-9]*\).*/\1/p')
    other=$(echo "${counts}" | sed -n 's/.*OTHER=\([0-9]*\).*/\1/p')
    total=$(echo "${counts}" | sed -n 's/.*TOTAL=\([0-9]*\).*/\1/p')

    if [[ "${total}" -eq 0 ]]; then
        echo -e "${YELLOW}Kein Cache-Status im letzten Feld gefunden.${NC}"
        echo "Log-Format prüfen (siehe Kopf dieses Skripts)."
        return 1
    fi

    printf "  HIT:     %8d\n" "${hits}"
    printf "  MISS:    %8d\n" "${misses}"
    printf "  Andere:  %8d  (PASS, HITMISS, BYPASS ...)\n" "${other}"
    printf "  Gesamt:  %8d\n" "${total}"
    echo ""
    rate_verdict "$(percent "${hits}" "$((hits + misses))")"
    echo "(Basis: HIT / (HIT + MISS). Anteil aller Requests aus dem Cache: $(percent "${hits}" "${total}")%)"
}

analyze_varnishstat() {
    echo -e "${BLUE}Analysiere Varnish-Zähler${NC}"
    echo ""

    local stats
    if ! stats=$(${VARNISHSTAT_CMD} -1 2>/dev/null); then
        echo -e "${RED}varnishstat nicht ausführbar: ${VARNISHSTAT_CMD}${NC}"
        exit 1
    fi

    local hits misses hitpass passes n_object
    hits=$(echo "${stats}" | awk '$1 == "MAIN.cache_hit" { print $2 }')
    misses=$(echo "${stats}" | awk '$1 == "MAIN.cache_miss" { print $2 }')
    hitpass=$(echo "${stats}" | awk '$1 == "MAIN.cache_hitpass" { print $2 }')
    passes=$(echo "${stats}" | awk '$1 == "MAIN.s_pass" { print $2 }')
    n_object=$(echo "${stats}" | awk '$1 == "MAIN.n_object" { print $2 }')
    hits=${hits:-0}
    misses=${misses:-0}
    hitpass=${hitpass:-0}

    local total=$((hits + misses))
    if [[ "${total}" -eq 0 ]]; then
        echo -e "${YELLOW}Noch keine cachebaren Requests seit dem Varnish-Start${NC}"
        return 1
    fi

    printf "  cache_hit:     %12d\n" "${hits}"
    printf "  cache_miss:    %12d\n" "${misses}"
    printf "  cache_hitpass: %12d  (Hit-for-Pass-Objekte)\n" "${hitpass}"
    printf "  s_pass:        %12d  (Requests am Cache vorbei)\n" "${passes:-0}"
    printf "  Objekte:       %12d\n" "${n_object:-0}"
    echo ""
    rate_verdict "$(percent "${hits}" "${total}")"
    echo "(Basis: cache_hit / (cache_hit + cache_miss). Achtung: Besucher mit Login oder Warenkorb,"
    echo " die config/varnish.vcl in vcl_hit auf Pass schickt, zählt Varnish als cache_hit UND s_pass."
    echo " Die Quote ist dann zu hoch - genauer ist das Log mit %{Varnish:handling}x.)"
}

if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

case $1 in
    --varnishstat|-v)
        analyze_varnishstat
        ;;
    --help|-h)
        show_usage
        exit 0
        ;;
    -*)
        echo "Unbekannte Option: $1"
        show_usage
        exit 1
        ;;
    *)
        analyze_log "$1"
        ;;
esac
