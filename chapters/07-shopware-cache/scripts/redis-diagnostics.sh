#!/bin/bash
# Redis-Diagnose für Shopware
# Kapitel 7: Shopwares Application Cache meistern
#
# Prüft eine Redis-Instanz passend zu ihrer Rolle (Datenkategorie laut
# Shopware-Doku) und liest nur INFO/CONFIG - kein KEYS, kein SCAN, keine
# Änderungen. Sicher im Produktivbetrieb.
#
#   cache     Object-/HTTP-Cache  → volatile-lru, ohne Persistenz
#   session   Sessions            → allkeys-lru, mit Persistenz
#   critical  Warenkörbe          → volatile-lru, mit Persistenz
#
# Verwendung:
#   ./redis-diagnostics.sh --role cache redis://redis-cache:6379
#   ./redis-diagnostics.sh --role session redis://redis-session:6380
#
# Redis im Container:
#   REDIS_CLI="docker exec redis redis-cli" ./redis-diagnostics.sh --role cache redis://127.0.0.1:6379
#
# Exit-Code: 0 = keine FAIL-Befunde, 1 = mindestens ein FAIL oder nicht erreichbar
#
# @see https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REDIS_CLI="${REDIS_CLI:-redis-cli}"
ROLE="cache"
URL="redis://127.0.0.1:6379"
FAILS=0

show_usage() {
    echo "Usage: $0 [--role cache|session|critical] [redis-url]"
    echo ""
    echo "Optionen:"
    echo "  --role   Rolle der Instanz (Default: cache)"
    echo "  redis-url  Redis-Instanz (Default: redis://127.0.0.1:6379)"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  REDIS_CLI  Befehl für redis-cli (Default: redis-cli)"
}

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAILS=$((FAILS + 1)); }
info() { echo -e "  [INFO] $1"; }

# Fehlende Abschnitte (z. B. errorstats vor Redis 6.2) liefern leer statt abzubrechen
rcli() {
    { ${REDIS_CLI} -u "${URL}" "$@" 2>/dev/null || true; } | tr -d '\r'
}

# Wert eines Feldes aus INFO-Ausgabe (Format "name:wert")
info_field() {
    echo "$1" | awk -F: -v k="$2" '$1 == k { print $2 }'
}

# Wert aus "CONFIG GET <name>" (zweite Zeile)
config_get() {
    rcli CONFIG GET "$1" | sed -n '2p'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        --role)
            ROLE="${2:-}"
            shift 2 || { show_usage; exit 1; }
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

case "${ROLE}" in
    cache|session|critical) ;;
    *)
        echo "Unbekannte Rolle: ${ROLE}"
        show_usage
        exit 1
        ;;
esac

echo -e "${BLUE}Redis-Diagnose: ${URL} (Rolle: ${ROLE})${NC}"
echo ""

# 1. Verbindung
echo "1. Verbindung"
if [[ "$(rcli PING)" != "PONG" ]]; then
    fail "Redis nicht erreichbar"
    echo "       Prüfen: Dienst läuft, Host/Port/Passwort in der URL, Firewall"
    exit 1
fi
server=$(rcli INFO server)
ok "Redis $(info_field "${server}" redis_version) erreichbar"
echo ""

# 2. Speicher und Eviction
echo "2. Speicher und Eviction"
memory=$(rcli INFO memory)
used=$(info_field "${memory}" used_memory)
maxmemory=$(info_field "${memory}" maxmemory)
policy=$(config_get maxmemory-policy)

if [[ "${maxmemory:-0}" -eq 0 ]]; then
    warn "Kein maxmemory gesetzt - Redis wächst bis der Server-RAM voll ist"
    usage_pct=0
else
    usage_pct=$(awk -v u="${used}" -v m="${maxmemory}" 'BEGIN { printf "%d", u * 100 / m }')
    ok "maxmemory $(info_field "${memory}" maxmemory_human), belegt ${usage_pct} %"
fi

case "${ROLE}:${policy}" in
    cache:volatile-*|cache:noeviction|critical:volatile-*|critical:noeviction)
        ok "maxmemory-policy ${policy}"
        ;;
    cache:allkeys-*)
        fail "maxmemory-policy ${policy}: cache.adapter.redis_tag_aware speichert damit nichts (ohne Fehlermeldung) - volatile-lru setzen"
        ;;
    critical:allkeys-*)
        fail "maxmemory-policy ${policy}: kann Warenkörbe und Zähler ohne TTL verdrängen - volatile-lru setzen"
        ;;
    session:allkeys-lru)
        ok "maxmemory-policy ${policy}"
        ;;
    *)
        warn "maxmemory-policy ${policy} - empfohlen für ${ROLE}: $([[ "${ROLE}" == session ]] && echo allkeys-lru || echo volatile-lru)"
        ;;
esac
echo ""

# 3. Persistenz
echo "3. Persistenz"
save=$(config_get save)
aof=$(config_get appendonly)
if [[ "${ROLE}" == "cache" ]]; then
    if [[ -z "${save}" && "${aof}" == "no" ]]; then
        ok "Keine Persistenz (Cache lässt sich neu erzeugen)"
    else
        info "Persistenz aktiv (save \"${save}\", appendonly ${aof}) - für reinen Cache nicht nötig"
    fi
else
    if [[ -z "${save}" && "${aof}" == "no" ]]; then
        warn "Keine Persistenz - ein Neustart löscht alle ${ROLE}-Daten"
    else
        ok "Persistenz aktiv (save \"${save}\", appendonly ${aof})"
    fi
fi
echo ""

# 4. Keys ohne TTL (INFO keyspace: keys - expires)
echo "4. Keys ohne TTL (alle Datenbanken der Instanz)"
keyspace=$(rcli INFO keyspace)
read -r keys expires < <(echo "${keyspace}" | awk -F'[:=,]' '/^db[0-9]+:/ { k += $3; e += $5 } END { printf "%d %d\n", k, e }')
if [[ "${keys}" -eq 0 ]]; then
    info "Keine Keys"
else
    no_ttl=$((keys - expires))
    no_ttl_pct=$((no_ttl * 100 / keys))
    info "${keys} Keys, davon ${no_ttl} ohne TTL (${no_ttl_pct} %)"
    # Tag-Listen des Tag-Aware-Adapters haben keine TTL und können nicht
    # verdrängt werden. Kritisch erst, wenn der Speicher fast voll ist.
    if [[ "${ROLE}" == "cache" && "${usage_pct}" -ge 90 && "${no_ttl_pct}" -ge 50 ]]; then
        warn "Speicher fast voll und mehr als die Hälfte der Keys ohne TTL - verwaiste Cache-Tags aufräumen (FroshTools: bin/console frosh:redis-tag:cleanup)"
    fi
fi
echo ""

# 5. Zugriffe
echo "5. Zugriffe seit Start/RESETSTAT"
stats=$(rcli INFO stats)
hits=$(info_field "${stats}" keyspace_hits)
misses=$(info_field "${stats}" keyspace_misses)
evicted=$(info_field "${stats}" evicted_keys)
total=$((hits + misses))
if [[ "${total}" -gt 0 ]]; then
    info "Hit-Rate $(awk -v h="${hits}" -v t="${total}" 'BEGIN { printf "%.2f", h * 100 / t }') % (${hits} Hits, ${misses} Misses)"
else
    info "Noch keine Lesezugriffe"
fi
if [[ "${evicted:-0}" -gt 0 ]]; then
    warn "${evicted} Keys verdrängt (evicted_keys) - maxmemory prüfen"
else
    ok "Keine verdrängten Keys"
fi
oom=$(rcli INFO errorstats | awk -F'[:=,]' '$1 == "errorstat_OOM" { print $3 }')
if [[ -n "${oom}" ]]; then
    fail "${oom} OOM-Fehler (errorstat_OOM) - Redis hat Schreibzugriffe abgelehnt"
fi
echo ""

# 6. Clients
echo "6. Clients"
clients=$(rcli INFO clients)
info "Verbunden: $(info_field "${clients}" connected_clients), blockiert: $(info_field "${clients}" blocked_clients)"
echo ""

if [[ "${FAILS}" -gt 0 ]]; then
    echo -e "${RED}${FAILS} FAIL-Befund(e)${NC}"
    exit 1
fi
echo -e "${GREEN}Keine FAIL-Befunde${NC}"
