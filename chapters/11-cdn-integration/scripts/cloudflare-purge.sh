#!/bin/bash
#
# Cloudflare Cache Purge Script
# Invalidiert den Cloudflare-Cache nach Deployments
#
# Verwendung:
#   ./cloudflare-purge.sh --all
#   ./cloudflare-purge.sh --urls "/media/*,/theme/*"
#   ./cloudflare-purge.sh --tags "product,category-123"
#   ./cloudflare-purge.sh --test
#
# Voraussetzungen:
#   - CLOUDFLARE_API_TOKEN (Zone:Cache Purge Berechtigung)
#   - CLOUDFLARE_ZONE_ID
#
# Token erstellen: https://dash.cloudflare.com/profile/api-tokens
# Zone ID: Dashboard > Übersicht > rechte Sidebar

set -e

# Konfiguration aus Umgebungsvariablen
API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
API_BASE="https://api.cloudflare.com/client/v4"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Verwendung: $0 <option>"
    echo ""
    echo "Optionen:"
    echo "  --all              Gesamten Cache purgen (Vorsicht!)"
    echo "  --urls <pattern>   Bestimmte URLs purgen (kommasepariert)"
    echo "  --tags <tags>      Cache-Tags purgen (Enterprise only)"
    echo "  --prefixes <paths> URL-Prefixes purgen (Enterprise only)"
    echo "  --test             Verbindung testen"
    echo ""
    echo "Beispiele:"
    echo "  $0 --all"
    echo "  $0 --urls 'https://shop.de/media/*,https://shop.de/theme/*'"
    echo "  $0 --tags 'product,category-123'"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  CLOUDFLARE_API_TOKEN  API Token mit Cache Purge Berechtigung"
    echo "  CLOUDFLARE_ZONE_ID    Zone ID aus dem Dashboard"
    exit 1
}

check_config() {
    if [[ -z "${API_TOKEN}" ]]; then
        echo -e "${RED}FEHLER: CLOUDFLARE_API_TOKEN nicht gesetzt${NC}"
        echo ""
        echo "Token erstellen:"
        echo "  1. https://dash.cloudflare.com/profile/api-tokens"
        echo "  2. 'Create Token' > 'Custom Token'"
        echo "  3. Permissions: Zone > Cache Purge > Purge"
        exit 1
    fi

    if [[ -z "${ZONE_ID}" ]]; then
        echo -e "${RED}FEHLER: CLOUDFLARE_ZONE_ID nicht gesetzt${NC}"
        echo ""
        echo "Zone ID finden:"
        echo "  Dashboard > Ihre Domain > Übersicht > rechte Sidebar"
        exit 1
    fi
}

# ============================================================================
# API-Aufruf
# ============================================================================

api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    response=$(curl -s -X "${method}" \
        "${API_BASE}${endpoint}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        ${data:+-d "${data}"})

    echo "${response}"
}

# ============================================================================
# Verbindungstest
# ============================================================================

test_connection() {
    echo "=== Cloudflare API Test ==="
    echo ""

    check_config

    echo "Zone ID: ${ZONE_ID}"
    echo ""

    # Zone-Details abrufen
    response=$(api_call "GET" "/zones/${ZONE_ID}")

    success=$(echo "${response}" | jq -r '.success')
    if [[ "${success}" == "true" ]]; then
        zone_name=$(echo "${response}" | jq -r '.result.name')
        zone_status=$(echo "${response}" | jq -r '.result.status')

        echo -e "${GREEN}Verbindung erfolgreich!${NC}"
        echo ""
        echo "Zone:   ${zone_name}"
        echo "Status: ${zone_status}"
    else
        echo -e "${RED}Verbindung fehlgeschlagen!${NC}"
        echo ""
        echo "${response}" | jq -r '.errors[]?.message // .errors'
        exit 1
    fi
}

# ============================================================================
# Purge: Alles
# ============================================================================

purge_all() {
    echo "=== Purge: Gesamter Cache ==="
    echo ""

    check_config

    echo -e "${YELLOW}WARNUNG: Dies löscht den gesamten Cache!${NC}"
    read -p "Fortfahren? (y/N) " -n 1 -r
    echo

    if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
        echo "Abgebrochen."
        exit 0
    fi

    response=$(api_call "POST" "/zones/${ZONE_ID}/purge_cache" '{"purge_everything":true}')

    success=$(echo "${response}" | jq -r '.success')
    if [[ "${success}" == "true" ]]; then
        echo -e "${GREEN}Cache erfolgreich geleert!${NC}"
    else
        echo -e "${RED}Purge fehlgeschlagen!${NC}"
        echo "${response}" | jq -r '.errors[]?.message // .errors'
        exit 1
    fi
}

# ============================================================================
# Purge: Bestimmte URLs
# ============================================================================

purge_urls() {
    local urls="$1"

    echo "=== Purge: URLs ==="
    echo ""

    check_config

    # URLs in JSON-Array konvertieren
    IFS=',' read -ra URL_ARRAY <<< "${urls}"
    json_urls=$(printf '%s\n' "${URL_ARRAY[@]}" | jq -R . | jq -s .)

    echo "URLs zu purgen:"
    echo "${json_urls}" | jq -r '.[]'
    echo ""

    response=$(api_call "POST" "/zones/${ZONE_ID}/purge_cache" "{\"files\":${json_urls}}")

    success=$(echo "${response}" | jq -r '.success')
    if [[ "${success}" == "true" ]]; then
        echo -e "${GREEN}URLs erfolgreich gepurged!${NC}"
    else
        echo -e "${RED}Purge fehlgeschlagen!${NC}"
        echo "${response}" | jq -r '.errors[]?.message // .errors'
        exit 1
    fi
}

# ============================================================================
# Purge: Cache-Tags (Enterprise)
# ============================================================================

purge_tags() {
    local tags="$1"

    echo "=== Purge: Cache-Tags (Enterprise) ==="
    echo ""

    check_config

    # Tags in JSON-Array konvertieren
    IFS=',' read -ra TAG_ARRAY <<< "${tags}"
    json_tags=$(printf '%s\n' "${TAG_ARRAY[@]}" | jq -R . | jq -s .)

    echo "Tags zu purgen:"
    echo "${json_tags}" | jq -r '.[]'
    echo ""

    response=$(api_call "POST" "/zones/${ZONE_ID}/purge_cache" "{\"tags\":${json_tags}}")

    success=$(echo "${response}" | jq -r '.success')
    if [[ "${success}" == "true" ]]; then
        echo -e "${GREEN}Tags erfolgreich gepurged!${NC}"
    else
        echo -e "${RED}Purge fehlgeschlagen!${NC}"
        echo ""
        echo "Hinweis: Cache-Tags sind nur im Enterprise-Plan verfügbar."
        echo "${response}" | jq -r '.errors[]?.message // .errors'
        exit 1
    fi
}

# ============================================================================
# Purge: Prefixes (Enterprise)
# ============================================================================

purge_prefixes() {
    local prefixes="$1"

    echo "=== Purge: URL-Prefixes (Enterprise) ==="
    echo ""

    check_config

    # Prefixes in JSON-Array konvertieren
    IFS=',' read -ra PREFIX_ARRAY <<< "${prefixes}"
    json_prefixes=$(printf '%s\n' "${PREFIX_ARRAY[@]}" | jq -R . | jq -s .)

    echo "Prefixes zu purgen:"
    echo "${json_prefixes}" | jq -r '.[]'
    echo ""

    response=$(api_call "POST" "/zones/${ZONE_ID}/purge_cache" "{\"prefixes\":${json_prefixes}}")

    success=$(echo "${response}" | jq -r '.success')
    if [[ "${success}" == "true" ]]; then
        echo -e "${GREEN}Prefixes erfolgreich gepurged!${NC}"
    else
        echo -e "${RED}Purge fehlgeschlagen!${NC}"
        echo ""
        echo "Hinweis: Prefix-Purge ist nur im Enterprise-Plan verfügbar."
        echo "${response}" | jq -r '.errors[]?.message // .errors'
        exit 1
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
    --urls)
        if [[ -z "$2" ]]; then
            echo -e "${RED}FEHLER: URLs erforderlich${NC}"
            usage
        fi
        purge_urls "$2"
        ;;
    --tags)
        if [[ -z "$2" ]]; then
            echo -e "${RED}FEHLER: Tags erforderlich${NC}"
            usage
        fi
        purge_tags "$2"
        ;;
    --prefixes)
        if [[ -z "$2" ]]; then
            echo -e "${RED}FEHLER: Prefixes erforderlich${NC}"
            usage
        fi
        purge_prefixes "$2"
        ;;
    --test)
        test_connection
        ;;
    *)
        usage
        ;;
esac
