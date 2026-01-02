#!/bin/bash
#
# Bunny CDN Cache Purge Script
# Invalidiert den Bunny CDN Cache
#
# Verwendung:
#   ./bunny-purge.sh --all
#   ./bunny-purge.sh --url "https://cdn.shop.de/media/image.jpg"
#   ./bunny-purge.sh --test
#
# Voraussetzungen:
#   - BUNNY_API_KEY (Account API Key)
#   - BUNNY_PULL_ZONE_ID (Pull Zone ID)
#
# API Key: bunny.net > Account > API Keys
# Pull Zone ID: bunny.net > Pull Zones > Ihre Zone > ID in URL

set -e

# Konfiguration
API_KEY="${BUNNY_API_KEY:-}"
PULL_ZONE_ID="${BUNNY_PULL_ZONE_ID:-}"
API_BASE="https://api.bunny.net"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Verwendung: $0 <option>"
    echo ""
    echo "Optionen:"
    echo "  --all          Gesamten Pull Zone Cache purgen"
    echo "  --url <url>    Einzelne URL purgen"
    echo "  --test         Verbindung testen"
    echo ""
    echo "Beispiele:"
    echo "  $0 --all"
    echo "  $0 --url 'https://cdn.shop.de/media/product.jpg'"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  BUNNY_API_KEY       Account API Key"
    echo "  BUNNY_PULL_ZONE_ID  Pull Zone ID"
    exit 1
}

check_config() {
    if [[ -z "${API_KEY}" ]]; then
        echo -e "${RED}FEHLER: BUNNY_API_KEY nicht gesetzt${NC}"
        echo ""
        echo "API Key finden:"
        echo "  bunny.net > Account > API Keys"
        exit 1
    fi
}

check_zone_config() {
    check_config

    if [[ -z "${PULL_ZONE_ID}" ]]; then
        echo -e "${RED}FEHLER: BUNNY_PULL_ZONE_ID nicht gesetzt${NC}"
        echo ""
        echo "Pull Zone ID finden:"
        echo "  bunny.net > Pull Zones > Ihre Zone > ID in der URL"
        exit 1
    fi
}

# ============================================================================
# Verbindungstest
# ============================================================================

test_connection() {
    echo "=== Bunny CDN API Test ==="
    echo ""

    check_config

    # Account-Info abrufen
    response=$(curl -s -X GET \
        "${API_BASE}/user" \
        -H "AccessKey: ${API_KEY}")

    # Prüfen ob Antwort gültig
    if echo "${response}" | jq -e '.Id' > /dev/null 2>&1; then
        email=$(echo "${response}" | jq -r '.Email')
        balance=$(echo "${response}" | jq -r '.Balance')

        echo -e "${GREEN}Verbindung erfolgreich!${NC}"
        echo ""
        echo "Account: ${email}"
        echo "Balance: \$${balance}"

        # Pull Zones auflisten
        echo ""
        echo "Pull Zones:"
        zones=$(curl -s -X GET \
            "${API_BASE}/pullzone" \
            -H "AccessKey: ${API_KEY}")

        echo "${zones}" | jq -r '.[] | "  - \(.Name) (ID: \(.Id))"'
    else
        echo -e "${RED}Verbindung fehlgeschlagen!${NC}"
        echo "${response}"
        exit 1
    fi
}

# ============================================================================
# Purge: Gesamte Pull Zone
# ============================================================================

purge_all() {
    echo "=== Purge: Gesamte Pull Zone ==="
    echo ""

    check_zone_config

    echo "Pull Zone ID: ${PULL_ZONE_ID}"
    echo ""

    echo -e "${YELLOW}WARNUNG: Dies löscht den gesamten Cache der Pull Zone!${NC}"
    read -p "Fortfahren? (y/N) " -n 1 -r
    echo

    if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
        echo "Abgebrochen."
        exit 0
    fi

    response=$(curl -s -X POST \
        "${API_BASE}/pullzone/${PULL_ZONE_ID}/purgeCache" \
        -H "AccessKey: ${API_KEY}" \
        -H "Content-Length: 0")

    # Bunny gibt bei Erfolg leere Antwort
    if [[ -z "${response}" ]] || [[ "${response}" == "{}" ]]; then
        echo -e "${GREEN}Cache erfolgreich geleert!${NC}"
    else
        echo -e "${RED}Purge fehlgeschlagen!${NC}"
        echo "${response}"
        exit 1
    fi
}

# ============================================================================
# Purge: Einzelne URL
# ============================================================================

purge_url() {
    local url="$1"

    echo "=== Purge: Einzelne URL ==="
    echo ""

    check_config

    echo "URL: ${url}"
    echo ""

    # URL encodieren
    encoded_url=$(echo -n "${url}" | jq -sRr @uri)

    response=$(curl -s -X POST \
        "${API_BASE}/purge?url=${encoded_url}" \
        -H "AccessKey: ${API_KEY}" \
        -H "Content-Length: 0")

    if [[ -z "${response}" ]] || [[ "${response}" == "{}" ]]; then
        echo -e "${GREEN}URL erfolgreich gepurged!${NC}"
    else
        echo -e "${RED}Purge fehlgeschlagen!${NC}"
        echo "${response}"
        exit 1
    fi
}

# ============================================================================
# Statistiken abrufen
# ============================================================================

get_stats() {
    echo "=== Pull Zone Statistiken ==="
    echo ""

    check_zone_config

    # Letzte 24 Stunden
    response=$(curl -s -X GET \
        "${API_BASE}/pullzone/${PULL_ZONE_ID}/statistics" \
        -H "AccessKey: ${API_KEY}")

    if echo "${response}" | jq -e '.TotalBandwidthUsed' > /dev/null 2>&1; then
        bandwidth=$(echo "${response}" | jq -r '.TotalBandwidthUsed')
        requests=$(echo "${response}" | jq -r '.TotalRequestsServed')
        cache_hits=$(echo "${response}" | jq -r '.CacheHitRate // "N/A"')

        echo "Bandwidth:  $(numfmt --to=iec-i --suffix=B ${bandwidth} 2>/dev/null || echo "${bandwidth} bytes")"
        echo "Requests:   ${requests}"
        echo "Hit Rate:   ${cache_hits}"
    else
        echo "Statistiken nicht verfügbar"
        echo "${response}"
    fi
}

# ============================================================================
# Hauptlogik
# ============================================================================

if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    --all)
        purge_all
        ;;
    --url)
        if [[ -z "$2" ]]; then
            echo -e "${RED}FEHLER: URL erforderlich${NC}"
            usage
        fi
        purge_url "$2"
        ;;
    --test)
        test_connection
        ;;
    --stats)
        get_stats
        ;;
    *)
        usage
        ;;
esac
