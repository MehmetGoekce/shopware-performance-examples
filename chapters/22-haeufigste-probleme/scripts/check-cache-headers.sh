#!/usr/bin/env bash
#
# check-cache-headers.sh
#
# Problem 20: Fehlende Browser-Caching-Header fuer statische Dateien.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zwei Fallen:
#
# 1. "Irgendein Cache-Control-Header ist da" ist kein Ergebnis. Shopware
#    antwortet auf jede Seite mit "Cache-Control: no-cache, private" — das
#    heisst ausdruecklich, dass der Browser NICHT cachen soll. Eine Pruefung,
#    die nur auf Vorhandensein testet, meldet einen ungecachten Shop als in
#    Ordnung. Entscheidend ist ein max-age groesser 0 bzw. ein Expires in der
#    Zukunft.
#
# 2. Geratene Asset-Pfade. /bundles/storefront/assets/... existiert in 6.6
#    nicht; die Storefront-Assets liegen unter /theme/<hash>/... Eine geratene
#    URL ergibt die Shopware-404-Seite, und deren Header sind die der
#    Storefront — nicht die der gesuchten Datei.
#
# Dieses Skript liest die echten Asset-URLs aus dem HTML der Startseite.
#
# Verwendung:
#   ./check-cache-headers.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = alle geprueften statischen Dateien haben brauchbare Cache-Header
#   1 = mindestens eine statische Datei wird nicht vom Browser gecacht
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-cache-headers.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob statische Dateien (CSS, JS, Bilder, Fonts) mit Cache-Headern
ausgeliefert werden, die der Browser auch wirklich nutzt.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Wird nicht ausgewertet; nur der Einheitlichkeit halber.

Die geprueften URLs stammen aus dem HTML der Startseite.
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

# Aufrufkonvention aller Skripte dieses Kapitels: $1 = SHOP_URL, $2 = SHOP_PATH.
# Dieses Skript braucht nur die URL; $2 wird bewusst entgegengenommen und
# nicht ausgewertet, damit run-all-diagnostics.sh alle gleich aufrufen kann.
SHOP_URL="${1:-http://localhost}"
SHOP_URL="${SHOP_URL%/}"

echo "=== Problem 20: Browser-Cache-Header ==="
echo
echo "Prueft: ${SHOP_URL}"
echo

HTML=$(curl -sS -L "${SHOP_URL}/") || {
    echo "Shop nicht erreichbar: ${SHOP_URL}" >&2
    exit 1
}

absolutise() {
    case "$1" in
        http://*|https://*) printf '%s\n' "$1" ;;
        //*)                printf '%s:%s\n' "${SHOP_URL%%:*}" "$1" ;;
        /*)                 printf '%s%s\n' "${SHOP_URL}" "$1" ;;
        *)                  printf '%s/%s\n' "${SHOP_URL}" "$1" ;;
    esac
}

first_match() {
    printf '%s\n' "${HTML}" | grep -oE "$1" | head -1 | sed -E 's/^[a-z-]+="//; s/"$//' || true
}

CSS_URL=""; JS_URL=""; IMG_URL=""
raw=$(first_match 'href="[^"]+\.css[^"]*"'); [[ -n "${raw}" ]] && CSS_URL=$(absolutise "${raw}")
raw=$(first_match 'src="[^"]+\.js[^"]*"');   [[ -n "${raw}" ]] && JS_URL=$(absolutise "${raw}")
raw=$(first_match 'src="[^"]+\.(png|jpg|jpeg|webp|avif|svg)[^"]*"'); [[ -n "${raw}" ]] && IMG_URL=$(absolutise "${raw}")

PROBLEMS=0
CHECKED=0

check_resource() {
    # $1 = Beschriftung, $2 = URL
    local label="$1" url="$2" headers cache_control expires max_age

    printf '   %-12s ' "${label}"
    if [[ -z "${url}" ]]; then
        echo "keine URL im HTML gefunden — uebersprungen"
        return
    fi

    headers=$(curl -sS -o /dev/null -D - -L "${url}" 2>/dev/null | tr -d '\r')
    cache_control=$(printf '%s\n' "${headers}" | awk 'BEGIN{IGNORECASE=1} tolower($1)=="cache-control:" { $1=""; sub(/^ /,""); v=$0 } END{print v}')
    expires=$(printf '%s\n' "${headers}" | awk 'BEGIN{IGNORECASE=1} tolower($1)=="expires:" { $1=""; sub(/^ /,""); v=$0 } END{print v}')

    CHECKED=$((CHECKED + 1))

    max_age=""
    if [[ "${cache_control}" =~ max-age=([0-9]+) ]]; then
        max_age="${BASH_REMATCH[1]}"
    fi

    if [[ "${cache_control}" == *no-store* || "${cache_control}" == *no-cache* ]]; then
        echo "kein Browser-Caching (Cache-Control: ${cache_control})"
        PROBLEMS=$((PROBLEMS + 1))
        return
    fi

    if [[ -n "${max_age}" && "${max_age}" -gt 0 ]]; then
        local days=$(( max_age / 86400 ))
        echo "max-age=${max_age} (~${days} Tage)"
        case "${url}" in
            */theme/*|*\?*) : ;;  # versionierte URL, lange Frist unbedenklich
            *)
                if [[ "${max_age}" -gt 2592000 ]]; then
                    echo "                Lange Frist ohne Versionskennung in der URL — nach einem"
                    echo "                Deploy sehen Bestandsbesucher die alte Datei."
                fi
                ;;
        esac
        return
    fi

    if [[ -n "${expires}" ]]; then
        local exp_ts now_ts
        exp_ts=$(date -d "${expires}" +%s 2>/dev/null || echo 0)
        now_ts=$(date +%s)
        if [[ "${exp_ts}" -gt "${now_ts}" ]]; then
            echo "Expires in der Zukunft (${expires})"
            return
        fi
        echo "Expires liegt nicht in der Zukunft (${expires}) — wirkungslos"
        PROBLEMS=$((PROBLEMS + 1))
        return
    fi

    echo "keine nutzbaren Cache-Header"
    PROBLEMS=$((PROBLEMS + 1))
}

echo "1. Statische Dateien"
check_resource "CSS" "${CSS_URL}"
check_resource "JavaScript" "${JS_URL}"
check_resource "Bild" "${IMG_URL}"

echo
echo "2. Zum Vergleich: die HTML-Seite selbst"
HTML_CC=$(curl -sS -o /dev/null -D - -L "${SHOP_URL}/" 2>/dev/null | tr -d '\r' \
    | awk 'BEGIN{IGNORECASE=1} tolower($1)=="cache-control:" { $1=""; sub(/^ /,""); v=$0 } END{print v}')
echo "   Cache-Control: ${HTML_CC:-(nicht gesetzt)}"
echo "   Dass die HTML-Seite no-cache/private ist, ist richtig so — sie ist"
echo "   personalisierbar. Nur die statischen Dateien oben gehoeren in den"
echo "   Browser-Cache."

echo
echo "=== Ergebnis ==="
echo

if [[ "${CHECKED}" -eq 0 ]]; then
    echo "Keine Asset-URLs im HTML gefunden — nichts zu pruefen."
    echo "Richtige URL? Ohne Host-Header antwortet Shopware mit"
    echo "\"Sales Channel Not Found\" — und zwar als HTTP 200."
    exit 69
fi

if [[ "${PROBLEMS}" -eq 0 ]]; then
    echo "Alle ${CHECKED} geprueften Dateien werden vom Browser gecacht."
    exit 0
fi

cat <<'EOF'
Mindestens eine statische Datei wird bei jedem Besuch neu geladen.

Shopware 6.6 liefert in public/.htaccess KEINE mod_expires-Regeln mit — anders
als beim mod_deflate-Block muss man hier selbst etwas ergaenzen.

Bei Apache (ausserhalb der "# BEGIN Shopware"/"# END Shopware"-Marker, weil
alles dazwischen ueberschrieben wird — besser gleich in den vHost):
EOF
echo
cat <<'EOF'
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType text/css                  "access plus 1 year"
    ExpiresByType text/javascript           "access plus 1 year"
    ExpiresByType application/javascript    "access plus 1 year"
    ExpiresByType image/avif                "access plus 1 year"
    ExpiresByType image/webp                "access plus 1 year"
    ExpiresByType image/png                 "access plus 1 year"
    ExpiresByType image/jpeg                "access plus 1 year"
    ExpiresByType image/svg+xml             "access plus 1 year"
    ExpiresByType font/woff2                "access plus 1 year"
</IfModule>
EOF
echo
cat <<'EOF'
Ein Jahr ist hier unbedenklich, weil Shopware die Theme-Assets unter
/theme/<hash>/ mit Versions-Query ausliefert: nach einem theme:compile
aendert sich die URL, der Browser holt die Datei neu.

Bei Nginx:

  location ~* \.(css|js|woff2|avif|webp|png|jpe?g|svg|ico)$ {
      expires 1y;
      add_header Cache-Control "public";
  }

Vorlage: config/apache-compression.conf
EOF
exit 1
