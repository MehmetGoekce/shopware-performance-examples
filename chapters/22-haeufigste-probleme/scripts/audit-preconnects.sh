#!/bin/bash
#
# Problem 5: Fehlende Preconnects
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Prüft ob Preconnect-Headers für Third-Party-Domains gesetzt sind.
#
# Verwendung: ./audit-preconnects.sh [SHOP_URL]
#

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: audit-preconnects.sh [SHOP_URL] [SHOP_PATH]

Prueft, welche fremden Domains die Startseite einbindet und ob dafuer
preconnect- oder dns-prefetch-Hinweise gesetzt sind.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

SHOP_URL="${1:-http://localhost}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Bekannte Third-Party-Domains die preconnect benötigen
KNOWN_THIRD_PARTY=(
    "www.googletagmanager.com"
    "www.google-analytics.com"
    "fonts.googleapis.com"
    "fonts.gstatic.com"
    "www.facebook.com"
    "connect.facebook.net"
    "platform.twitter.com"
    "cdn.jsdelivr.net"
    "unpkg.com"
    "www.youtube.com"
    "player.vimeo.com"
    "js.stripe.com"
    "www.paypal.com"
    "cdn.shopify.com"
    "static.hotjar.com"
    "snap.licdn.com"
)

echo "=== Preconnect Audit ==="
echo "URL: ${SHOP_URL}"
echo ""

ISSUES=0

# HTML und Headers holen
HTML=$(curl -sL "${SHOP_URL}" 2>/dev/null)
HEADERS=$(curl -sS -o /dev/null -D - -L "${SHOP_URL}" 2>/dev/null || true)

# Vorhandene Preconnects finden
echo -e "${BLUE}1. Vorhandene Preconnects${NC}"

# Zwei Fallen auf einmal: Shopware umbricht Link-Attribute (rel und href
# stehen oft auf verschiedenen Zeilen), und die Reihenfolge der Attribute
# ist frei — <link href="..." rel="preconnect"> ist genauso gueltig.
# Deshalb erst jeden <link>-Tag isolieren, dann je Tag pruefen.
LINK_TAGS=$(printf '%s\n' "${HTML}" | tr '\n' ' ' | grep -oE '<link[^>]*>' || true)

links_with_rel() {
    # $1 = rel-Wert
    local want="$1" tag href
    while IFS= read -r tag; do
        [[ -z "${tag}" ]] && continue
        printf '%s' "${tag}" | grep -qE "rel=\"?${want}\"?([[:space:]>]|$)" || continue
        href=$(printf '%s' "${tag}" | grep -oE 'href="[^"]*"' | head -1 \
            | sed 's/^href="//; s/"$//')
        [[ -n "${href}" ]] && printf '%s\n' "${href}"
    done <<< "${LINK_TAGS}"
}

PRECONNECTS=$(links_with_rel 'preconnect' || true)
DNS_PREFETCH=$(links_with_rel 'dns-prefetch' || true)

if [[ -n "${PRECONNECTS}" ]]; then
    echo "   Preconnects gefunden:"
    for pc in ${PRECONNECTS}; do
        echo -e "   ${GREEN}✓${NC} ${pc}"
    done
else
    echo -e "   ${YELLOW}Keine Preconnects gefunden${NC}"
fi

if [[ -n "${DNS_PREFETCH}" ]]; then
    echo ""
    echo "   DNS-Prefetch gefunden:"
    for dp in ${DNS_PREFETCH}; do
        echo -e "   ${GREEN}✓${NC} ${dp}"
    done
fi

# Third-Party-Domains im HTML finden
echo ""
echo -e "${BLUE}2. Third-Party-Domains in Verwendung${NC}"

# Externe URLs extrahieren
EXTERNAL_DOMAINS=$(echo "${HTML}" | grep -oE '(src|href)="https?://[^/"]*' | \
    sed 's/src="//g' | sed 's/href="//g' | \
    sed 's|https\?://||g' | \
    sort -u | \
    grep -v "$(echo "${SHOP_URL}" | sed 's|https\?://||g' | cut -d'/' -f1)" || true)

MISSING_PRECONNECTS=()

for domain in ${EXTERNAL_DOMAINS}; do
    # Prüfen ob Preconnect existiert
    if echo "${PRECONNECTS} ${DNS_PREFETCH}" | grep -q "${domain}"; then
        echo -e "   ${GREEN}✓${NC} ${domain} (preconnect vorhanden)"
    else
        echo -e "   ${YELLOW}⚠${NC} ${domain} (kein preconnect)"
        MISSING_PRECONNECTS+=("${domain}")
    fi
done

# Empfehlungen für bekannte Third-Party-Domains
echo ""
echo -e "${BLUE}3. Empfohlene Preconnects${NC}"

RECOMMENDATIONS=()
for known in "${KNOWN_THIRD_PARTY[@]}"; do
    if echo "${HTML}" | grep -q "${known}"; then
        if ! echo "${PRECONNECTS} ${DNS_PREFETCH}" | grep -q "${known}"; then
            RECOMMENDATIONS+=("${known}")
            echo -e "   ${RED}✗${NC} ${known} - wird verwendet aber kein preconnect"
            ISSUES=$((ISSUES + 1))
        fi
    fi
done

if [[ ${#RECOMMENDATIONS[@]} -eq 0 ]]; then
    if [[ -z "${EXTERNAL_DOMAINS}" ]]; then
        echo "   Die Seite bindet keine fremden Domains ein — dann ist auch kein"
        echo "   Preconnect noetig. Das ist der beste Fall."
    else
        echo -e "   ${GREEN}Alle erkannten Third-Party-Domains haben preconnect${NC}"
    fi
fi

# Zusammenfassung und Code-Empfehlung
echo ""
echo "=== Zusammenfassung ==="

if [[ "${ISSUES}" -eq 0 ]] && [[ ${#MISSING_PRECONNECTS[@]} -eq 0 ]]; then
    echo -e "${GREEN}Preconnect-Konfiguration optimal.${NC}"
    exit 0
else
    echo -e "${YELLOW}${#MISSING_PRECONNECTS[@]} Third-Party-Domain(s) ohne preconnect${NC}"
    echo ""
    echo "Empfohlene Ergänzungen in <head>:"
    echo ""

    # crossorigin gehoert NUR an Preconnects fuer CORS-anonyme Abrufe, also
    # vor allem Schriftdateien. Wer es ueberall anhaengt, oeffnet eine zweite,
    # ungenutzte Verbindung statt die bestehende wiederzuverwenden — genau das
    # Gegenteil dessen, was der Preconnect bewirken soll.
    emit_preconnect() {
        case "$1" in
            fonts.gstatic.com|*.fontawesome.com|use.typekit.net|fonts.googleapis.com/s/*)
                echo "<link rel=\"preconnect\" href=\"https://$1\" crossorigin>" ;;
            *)
                echo "<link rel=\"preconnect\" href=\"https://$1\">" ;;
        esac
    }

    for domain in "${MISSING_PRECONNECTS[@]}"; do
        emit_preconnect "${domain}"
    done

    for rec in "${RECOMMENDATIONS[@]}"; do
        if ! printf '%s\n' "${MISSING_PRECONNECTS[@]}" | grep -q "^${rec}$"; then
            emit_preconnect "${rec}"
        fi
    done

    echo ""
    echo "Bei Google Fonts braucht es BEIDE Zeilen: das Stylesheet kommt von"
    echo "fonts.googleapis.com, die Schriftdateien von fonts.gstatic.com —"
    echo "und nur die zweite Verbindung braucht crossorigin:"
    echo ""
    echo "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">"
    echo "<link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>"
    echo ""
    echo "Schneller als jeder Preconnect ist allerdings, die Schriften selbst"
    echo "auszuliefern — das spart die fremde Verbindung ganz und erspart die"
    echo "datenschutzrechtliche Diskussion gleich mit."
    echo ""
    echo "Für weniger kritische Domains reicht:"
    echo "<link rel=\"dns-prefetch\" href=\"https://example.com\">"
    echo ""
    echo "In Shopware kommt das nicht per Hand in den <head>, sondern ueber ein"
    echo "Theme- oder Plugin-Template:"
    echo "  src/Resources/views/storefront/layout/meta.html.twig"
    echo "  {% sw_extends '@Storefront/storefront/layout/meta.html.twig' %}"
    echo "  {% block layout_head_meta_tags %}{{ parent() }} ... {% endblock %}"

    exit 1
fi
