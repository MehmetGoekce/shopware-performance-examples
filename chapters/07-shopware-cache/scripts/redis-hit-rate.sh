#!/bin/bash
# Redis Hit-Rate
# Kapitel 7: Shopwares Application Cache meistern
#
# Liest keyspace_hits und keyspace_misses einer Redis-Instanz und berechnet
# die Trefferquote. Die Zähler gelten für die ganze Instanz seit dem Start
# (oder seit "CONFIG RESETSTAT") - liegen Sessions auf derselben Instanz,
# zählen sie mit.
#
# Verwendung (im Ordner chapters/07-shopware-cache):
#   ./scripts/redis-hit-rate.sh                          # redis://127.0.0.1:6379
#   ./scripts/redis-hit-rate.sh redis://redis-cache:6379
#
# Messen ohne Altlasten:
#   redis-cli -u <url> CONFIG RESETSTAT  →  Traffic laufen lassen  →  Skript
#
# Redis im Container:
#   REDIS_CLI="docker exec redis redis-cli" ./scripts/redis-hit-rate.sh redis://127.0.0.1:6379
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REDIS_CLI="${REDIS_CLI:-redis-cli}"

show_usage() {
    echo "Usage: $0 [redis-url]"
    echo ""
    echo "Argumente:"
    echo "  redis-url  Redis-Instanz (Default: redis://127.0.0.1:6379)"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  REDIS_CLI  Befehl für redis-cli (Default: redis-cli)"
}

# Wert eines Feldes aus "INFO <section>" (Format "name:wert", CRLF)
info_field() {
    echo "$1" | tr -d '\r' | awk -F: -v k="$2" '$1 == k { print $2 }'
}

URL="redis://127.0.0.1:6379"

while [[ $# -gt 0 ]]; do
    case $1 in
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
            URL="$1"
            shift
            ;;
    esac
done

echo -e "${BLUE}Redis Hit-Rate: ${URL}${NC}"
echo ""

if ! stats=$(${REDIS_CLI} -u "${URL}" INFO stats 2>/dev/null) || [[ -z "$(info_field "${stats}" keyspace_hits)" ]]; then
    echo -e "${RED}Redis nicht erreichbar: ${URL}${NC}"
    echo "Prüfen: ${REDIS_CLI} -u ${URL} ping"
    exit 1
fi

hits=$(info_field "${stats}" keyspace_hits)
misses=$(info_field "${stats}" keyspace_misses)
total=$((hits + misses))

printf "  keyspace_hits:   %12d\n" "${hits}"
printf "  keyspace_misses: %12d\n" "${misses}"
echo ""

if [[ "${total}" -eq 0 ]]; then
    echo -e "${YELLOW}Noch keine Lesezugriffe seit Start oder RESETSTAT${NC}"
    exit 0
fi

rate=$(awk -v h="${hits}" -v t="${total}" 'BEGIN { printf "%.2f", h * 100 / t }')

# Schwelle 80 % ist eine Einschätzung, kein Shopware- oder Redis-Richtwert:
# Im Testshop (Kapitel 7) lag die Quote direkt nach dem Leeren bei 82 %,
# mit warmem Cache bei 91 %.
echo -n "Hit-Rate: "
if awk -v r="${rate}" 'BEGIN { exit !(r >= 80) }'; then
    echo -e "${GREEN}${rate}%${NC}"
else
    echo -e "${YELLOW}${rate}% (niedrig)${NC}"
    echo ""
    echo "Mögliche Ursachen:"
    echo "  - Cache wurde gerade geleert (Deployment, cache:clear:all) - später erneut messen"
    echo "  - maxmemory-policy allkeys-* mit redis_tag_aware: Cache speichert nichts"
    echo "    (./scripts/redis-diagnostics.sh --role cache ${URL})"
    echo "  - maxmemory zu klein: viele evicted_keys"
fi
