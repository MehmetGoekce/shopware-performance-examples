#!/bin/bash
#
# Cloudflare Cache Purge Script
# Invalidiert den Cloudflare-Cache nach Deployments
#
# Usage:
#   ./cloudflare-purge.sh --all
#   ./cloudflare-purge.sh --urls "https://shop.de/media/a.jpg,https://shop.de/b.css"
#   ./cloudflare-purge.sh --tags "product-abc123,navigation"
#   ./cloudflare-purge.sh --prefixes "shop.de/theme/,shop.de/bundles/"
#   ./cloudflare-purge.sh --test
#
# Plan-Verfuegbarkeit (Cloudflare-Doku, Stand 2026-09): URL, Hostname, Tag,
# Prefix und Purge Everything gibt es auf ALLEN Plans - seit April 2025.
# Unterschiedlich sind nur die Rate-Limits: Free 5/min, Pro 5/s, Business 10/s,
# Enterprise 50/s. Pro Request sind 100 Operationen erlaubt; dieses Skript
# zerlegt laengere Listen automatisch.
#
# Wildcards gibt es beim URL-Purge nicht: "Wildcards are not supported on single
# file purge, and you must use purge by hostname, prefix, or implement cache tags
# as an alternative solution." URLs muessen vollqualifiziert sein.
#
# Voraussetzungen:
#   - CLOUDFLARE_API_TOKEN (Zone:Cache Purge Berechtigung)
#   - CLOUDFLARE_ZONE_ID
#
# Token erstellen: https://dash.cloudflare.com/profile/api-tokens
# Zone ID: Dashboard > Übersicht > rechte Sidebar

set -euo pipefail

# Konfiguration aus Umgebungsvariablen
API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
API_BASE="https://api.cloudflare.com/client/v4"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# exit_code 0 fuer --help, 2 fuer Aufruffehler
usage() {
    echo "Usage: $0 <option>"
    echo ""
    echo "Optionen:"
    echo "  --all              Gesamten Cache purgen (Vorsicht!)"
    echo "  --urls <urls>      Vollqualifizierte URLs purgen (kommasepariert)"
    echo "  --tags <tags>      Cache-Tags purgen"
    echo "  --prefixes <paths> URL-Prefixes purgen, z.B. shop.de/theme/"
    echo "  --test             Verbindung testen"
    echo "  --help             Diese Hilfe"
    echo ""
    echo "Beispiele:"
    echo "  $0 --all"
    echo "  $0 --urls 'https://shop.de/media/a.jpg,https://shop.de/b.css'"
    echo "  $0 --tags 'product-abc123,navigation'"
    echo "  $0 --prefixes 'shop.de/theme/,shop.de/bundles/'"
    echo ""
    echo "Alle Purge-Arten sind auf allen Plans verfuegbar; Wildcards sind beim"
    echo "URL-Purge nicht erlaubt. Listen ueber 100 Eintraege werden gestueckelt."
    echo ""
    echo "Umgebungsvariablen:"
    echo "  CLOUDFLARE_API_TOKEN  API Token mit Cache Purge Berechtigung"
    echo "  CLOUDFLARE_ZONE_ID    Zone ID aus dem Dashboard"
    exit "${1:-2}"
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
# Purge: URLs, Tags, Prefixes
# ============================================================================

# Cloudflare erlaubt 100 Operationen pro Request.
MAX_ITEMS_PER_REQUEST=100

# purge_items <json-key> <Bezeichnung> <kommaseparierte Liste>
purge_items() {
    local key="$1" label="$2" csv="$3"
    local items=() chunk=() json response success item

    echo "=== Purge: ${label} ==="
    echo ""

    check_config

    IFS=',' read -ra items <<< "${csv}"

    # Leere Eintraege entfernen und Wildcards fruehzeitig abfangen.
    local cleaned=()
    for item in "${items[@]}"; do
        item="$(printf '%s' "${item}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "${item}" ] || continue

        if [ "${key}" = "files" ]; then
            case "${item}" in
                *\**)
                    echo -e "${RED}FEHLER: Wildcards sind beim URL-Purge nicht erlaubt: ${item}${NC}" >&2
                    echo "Nutze stattdessen --prefixes oder --tags." >&2
                    exit 1
                    ;;
                http*) ;;
                *)
                    echo -e "${RED}FEHLER: URL muss vollqualifiziert sein (mit https://): ${item}${NC}" >&2
                    exit 1
                    ;;
            esac
        fi

        cleaned+=("${item}")
    done

    if [ "${#cleaned[@]}" -eq 0 ]; then
        echo -e "${RED}FEHLER: keine ${label} angegeben${NC}" >&2
        exit 2
    fi

    echo "${#cleaned[@]} Eintraege, ${MAX_ITEMS_PER_REQUEST} pro Request"
    echo ""

    local i=0
    while [ "${i}" -lt "${#cleaned[@]}" ]; do
        chunk=("${cleaned[@]:i:MAX_ITEMS_PER_REQUEST}")
        json=$(printf '%s\n' "${chunk[@]}" | jq -R . | jq -s .)

        response=$(api_call "POST" "/zones/${ZONE_ID}/purge_cache" "{\"${key}\":${json}}")
        success=$(echo "${response}" | jq -r '.success')

        if [ "${success}" != "true" ]; then
            echo -e "${RED}Purge fehlgeschlagen!${NC}" >&2
            echo "${response}" | jq -r '.errors[]?.message // .errors' >&2
            exit 1
        fi

        echo -e "${GREEN}${#chunk[@]} ${label} gepurged${NC}"
        i=$((i + MAX_ITEMS_PER_REQUEST))
    done
}

purge_urls()     { purge_items "files" "URLs" "$1"; }
purge_tags()     { purge_items "tags" "Cache-Tags" "$1"; }
purge_prefixes() { purge_items "prefixes" "Prefixes" "$1"; }

# ============================================================================
# Hauptlogik
# ============================================================================

if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    --help|-h)
        usage 0
        ;;
    --all)
        purge_all
        ;;
    --urls)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}FEHLER: URLs erforderlich${NC}"
            usage
        fi
        purge_urls "$2"
        ;;
    --tags)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}FEHLER: Tags erforderlich${NC}"
            usage
        fi
        purge_tags "$2"
        ;;
    --prefixes)
        if [[ -z "${2:-}" ]]; then
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
