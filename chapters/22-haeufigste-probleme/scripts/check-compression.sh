#!/usr/bin/env bash
#
# check-compression.sh
#
# Problem 14: Fehlende Gzip-Kompression.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zwei Fallen, an denen die naheliegende Pruefung scheitert:
#
# 1. HEAD statt GET. "curl -I" fordert nur die Header an; ohne Body setzt
#    mod_deflate keinen Content-Encoding-Header. Die Kompression waere aktiv,
#    die Pruefung meldet trotzdem "keine".
#
# 2. Geratene Asset-Pfade. Shopware 6.6 liefert Storefront-CSS und -JS unter
#    /theme/<hash>/... aus, nicht unter /bundles/storefront/assets/...
#    Ein geratener Pfad ergibt eine 404-Seite — und die ist klein und
#    unkomprimiert, also wieder ein falsches "keine Kompression".
#
# Dieses Skript holt die echten Asset-URLs aus dem HTML der Startseite.
#
# Ausserdem wichtig: Shopware liefert sein Storefront-JS als "text/javascript"
# aus. Eine mod_deflate-Liste, die nur "application/javascript" nennt, laesst
# damit ausgerechnet die groesste Datei unkomprimiert.
#
# Verwendung:
#   ./check-compression.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = HTML, CSS und JS werden komprimiert
#   1 = mindestens eine Ressource wird nicht komprimiert
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-compression.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob der Webserver HTML, CSS und JavaScript komprimiert ausliefert.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Wird nicht ausgewertet; nur der Einheitlichkeit halber.

Die zu pruefenden CSS- und JS-URLs werden aus dem HTML der Startseite
gelesen, nicht geraten.
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

echo "=== Problem 14: Kompression ==="
echo
echo "Prueft: ${SHOP_URL}"
echo

HTML=$(curl -sS -L "${SHOP_URL}/") || {
    echo "Shop nicht erreichbar: ${SHOP_URL}" >&2
    exit 1
}

# Erste CSS- und JS-URL aus dem HTML ziehen und zu absoluten URLs machen.
absolutise() {
    case "$1" in
        http://*|https://*) printf '%s\n' "$1" ;;
        //*)                printf '%s:%s\n' "${SHOP_URL%%:*}" "$1" ;;
        /*)                 printf '%s%s\n' "${SHOP_URL}" "$1" ;;
        *)                  printf '%s/%s\n' "${SHOP_URL}" "$1" ;;
    esac
}

CSS_PATH=$(printf '%s\n' "${HTML}" | grep -oE 'href="[^"]+\.css[^"]*"' | head -1 | sed 's/^href="//; s/"$//' || true)
JS_PATH=$(printf '%s\n' "${HTML}" | grep -oE 'src="[^"]+\.js[^"]*"' | head -1 | sed 's/^src="//; s/"$//' || true)

CSS_URL=""
JS_URL=""
[[ -n "${CSS_PATH}" ]] && CSS_URL=$(absolutise "${CSS_PATH}")
[[ -n "${JS_PATH}" ]] && JS_URL=$(absolutise "${JS_PATH}")

# Gibt "<content-type>|<content-encoding>" fuer eine URL zurueck (per GET).
probe() {
    curl -sS -o /dev/null -D - -L -H 'Accept-Encoding: gzip, deflate, br' "$1" 2>/dev/null \
        | tr -d '\r' \
        | awk 'BEGIN { IGNORECASE = 1; ct = ""; ce = "" }
               tolower($1) == "content-type:"     { $1 = ""; sub(/^ /, ""); ct = $0 }
               tolower($1) == "content-encoding:" { $1 = ""; sub(/^ /, ""); ce = $0 }
               END { print ct "|" ce }'
}

PROBLEMS=0
SKIPPED=0
CHECKED=0

report() {
    # $1 = Beschriftung, $2 = URL
    local label="$1" url="$2" info ct ce
    printf '   %-12s ' "${label}"
    if [[ -z "${url}" ]]; then
        echo "keine URL im HTML gefunden — uebersprungen"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    CHECKED=$((CHECKED + 1))
    info=$(probe "${url}")
    ct="${info%%|*}"
    ce="${info#*|}"
    if [[ -n "${ce}" ]]; then
        echo "komprimiert (${ce}), Content-Type: ${ct}"
    else
        echo "NICHT komprimiert, Content-Type: ${ct}"
        PROBLEMS=$((PROBLEMS + 1))
        if [[ "${ct}" == text/javascript* ]]; then
            echo "                Shopware liefert JS als text/javascript aus. Wenn die"
            echo "                mod_deflate-/gzip_types-Liste nur application/javascript"
            echo "                nennt, bleibt genau diese Datei unkomprimiert."
        fi
    fi
}

echo "1. Kompression je Ressource"
report "HTML" "${SHOP_URL}/"
report "CSS" "${CSS_URL}"
report "JavaScript" "${JS_URL}"

echo
echo "2. Groessenvergleich"
measure() {
    # $1 = URL, $2 = Accept-Encoding
    curl -sS -o /dev/null -L -H "Accept-Encoding: $2" -w '%{size_download}' "$1" 2>/dev/null || echo 0
}

for pair in "Startseite|${SHOP_URL}/" "CSS|${CSS_URL}" "JavaScript|${JS_URL}"; do
    label="${pair%%|*}"
    url="${pair#*|}"
    [[ -z "${url}" ]] && continue
    plain=$(measure "${url}" "identity")
    gz=$(measure "${url}" "gzip")
    if [[ "${plain}" -gt 0 && "${gz}" -gt 0 ]]; then
        saved=$(( 100 - (gz * 100 / plain) ))
        printf '   %-12s %8s Byte -> %8s Byte  (%s %%)\n' "${label}" "${plain}" "${gz}" "${saved}"
    fi
done

echo
echo "=== Ergebnis ==="
echo

if [[ "${CHECKED}" -eq 0 ]]; then
    echo "Keine der drei Ressourcen war pruefbar — nichts gemessen."
    echo "Richtige URL? Ohne Host-Header antwortet Shopware mit"
    echo "\"Sales Channel Not Found\" — und zwar als HTTP 200."
    exit 69
fi

if [[ "${PROBLEMS}" -eq 0 && "${SKIPPED}" -eq 0 ]]; then
    echo "HTML, CSS und JavaScript werden komprimiert ausgeliefert."
    exit 0
fi

if [[ "${PROBLEMS}" -eq 0 ]]; then
    echo "Pruefbar waren ${CHECKED} von 3 Ressourcen; diese werden komprimiert"
    echo "ausgeliefert. Zu den uebrigen ${SKIPPED} (keine URL im HTML gefunden)"
    echo "sagt dieser Lauf nichts."
    exit 1
fi

cat <<'EOF'
Mindestens eine Ressource kommt unkomprimiert an.

Bei Apache zuerst pruefen, ob das Modul ueberhaupt geladen ist:

    a2enmod deflate && systemctl reload apache2

Shopware 6.6 liefert in public/.htaccess bereits einen vollstaendigen
mod_deflate-Block mit (26 MIME-Typen, inklusive text/javascript). Fehlt er,
ist die Datei beim Deploy verloren gegangen oder ueberschrieben worden —
die Vorlage steht in public/.htaccess.dist.

WICHTIG: Dieser Block steht zwischen "# BEGIN Shopware" und "# END Shopware".
Alles dazwischen wird von Shopware neu erzeugt und dabei ueberschrieben.
Eigene Regeln gehoeren ausserhalb dieser Marker — oder besser in die
vHost-Konfiguration.

Bei Nginx greift .htaccess nicht. Dort in den Server-Block:
EOF
echo
cat <<'EOF'
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types
    text/plain
    text/css
    text/javascript
    application/javascript
    application/json
    application/xml
    image/svg+xml
    font/woff2;
EOF
echo
echo "Vorlagen: config/nginx-gzip.conf und config/apache-compression.conf"
exit 1
