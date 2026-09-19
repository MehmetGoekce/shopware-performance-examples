#!/usr/bin/env bash
#
# check-http-cache.sh
#
# Problem 2: HTTP-Cache nicht aktiv.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# WICHTIG zum Verstaendnis der Ausgabe:
# Eine korrekt arbeitende Shopware-6.6-Storefront liefert an den Browser
# "Cache-Control: no-cache, private" — und zwar auch dann, wenn der HTTP-Cache
# laeuft und gerade einen Treffer ausliefert. Shopware setzt intern
# setSharedMaxAge(), also "public, s-maxage=<ttl>" fuer den Shared Cache;
# was beim Browser ankommt, ueberschreibt Symfonys AbstractSessionListener.
# "public, max-age=..." bekommt man an einer Storefront-URL nie zu sehen.
#
# Das belastbare Merkmal ist deshalb der Age-Header:
#   Age fehlt          -> kein Shared Cache im Spiel
#   Age vorhanden      -> ein Shared Cache antwortet
#   Age waechst        -> die Antwort kam aus dem Cache (Treffer)
#
# Verwendung:
#   ./check-http-cache.sh [SHOP_URL] [SHOP_PATH]
#   ./check-http-cache.sh https://shop.example.com /var/www/shopware
#
# Exit-Codes:
#   0 = HTTP-Cache arbeitet
#   1 = kein Hinweis auf einen aktiven HTTP-Cache
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-http-cache.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob vor der Storefront ein HTTP-Cache arbeitet.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Optional. Wurzel der Shopware-Installation; wird nur benutzt,
              um SHOPWARE_HTTP_CACHE_ENABLED aus .env/.env.local zu lesen.

Der Test schickt zwei GET-Requests im Abstand von zwei Sekunden und
vergleicht den Age-Header. HEAD (curl -I) ist dafuer nicht geeignet: manche
Setups beantworten HEAD anders als GET.
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
SHOP_PATH="${2:-}"

# Header per GET holen, Body verwerfen.
fetch_headers() {
    curl -sS -o /dev/null -D - -L "$1"
}

header_value() {
    # $1 = Headerblock, $2 = Headername (ohne Doppelpunkt)
    printf '%s\n' "$1" | tr -d '\r' | awk -v key="$2" \
        'BEGIN { IGNORECASE = 1 } tolower($1) == tolower(key) ":" { $1 = ""; sub(/^ /, ""); print }' \
        | tail -1
}

echo "=== Problem 2: HTTP-Cache Status ==="
echo
echo "Prueft: ${SHOP_URL}"
echo

echo "1. Erster Request..."
if ! HEADERS_1=$(fetch_headers "${SHOP_URL}"); then
    echo "   Shop nicht erreichbar: ${SHOP_URL}" >&2
    # 69 = Voraussetzung fehlt. Ein Exit 1 waere im Sammellauf nicht von
    # einem echten Fund zu unterscheiden.
    exit 69
fi
STATUS_1=$(printf '%s\n' "${HEADERS_1}" | grep -c '^HTTP/' || true)
CACHE_CONTROL=$(header_value "${HEADERS_1}" "cache-control")
AGE_1=$(header_value "${HEADERS_1}" "age")

echo "   Cache-Control: ${CACHE_CONTROL:-(nicht gesetzt)}"
echo "   Age:           ${AGE_1:-(nicht gesetzt)}"
if [[ "${STATUS_1}" -gt 1 ]]; then
    echo "   Hinweis: die URL hat weitergeleitet, geprueft wurde das Ziel."
fi

case "${CACHE_CONTROL}" in
    *no-store*)
        echo "   Diese Seite ist bewusst nicht cachebar (no-store) — Checkout oder Kundenkonto."
        echo "   Fuer den Test eine Kategorie- oder Produktseite angeben."
        ;;
    *no-cache*private*|*private*no-cache*)
        echo "   Das ist der Normalfall fuer eine Storefront-Seite und kein Defekt."
        ;;
esac

echo
echo "2. Zweiter Request (nach 2 s)..."
sleep 2
HEADERS_2=$(fetch_headers "${SHOP_URL}")
AGE_2=$(header_value "${HEADERS_2}" "age")
echo "   Age: ${AGE_2:-(nicht gesetzt)}"

echo
echo "3. Fremde Cache-Schichten..."
PROXY_HEADERS=$(printf '%s\n' "${HEADERS_1}" | tr -d '\r' \
    | grep -iE '^(x-cache|x-varnish|cf-cache-status|x-served-by|x-fastly|x-drupal-cache):' || true)
if [[ -n "${PROXY_HEADERS}" ]]; then
    printf '%s\n' "${PROXY_HEADERS}" | sed 's/^/   /'
else
    echo "   Keine Reverse-Proxy- oder CDN-Header gefunden."
fi

if [[ -n "${SHOP_PATH}" ]]; then
    echo
    echo "4. Konfiguration in .env..."
    FOUND_ENV=0
    for f in "${SHOP_PATH}/.env" "${SHOP_PATH}/.env.local"; do
        if [[ -f "$f" ]]; then
            LINES=$(grep -E '^SHOPWARE_HTTP_(CACHE_ENABLED|DEFAULT_TTL)=' "$f" || true)
            if [[ -n "${LINES}" ]]; then
                FOUND_ENV=1
                printf '%s\n' "${LINES}" | sed "s|^|   ${f##*/}: |"
            fi
        fi
    done
    if [[ -f "${SHOP_PATH}/.env.local.php" ]]; then
        echo "   Achtung: .env.local.php vorhanden — sie hat Vorrang vor .env.local."
    fi
    if [[ "${FOUND_ENV}" -eq 0 ]]; then
        echo "   Nichts gesetzt — es gelten die Defaults"
        echo "   (SHOPWARE_HTTP_CACHE_ENABLED=1, SHOPWARE_HTTP_DEFAULT_TTL=7200)."
    fi
fi

echo
echo "=== Ergebnis ==="
echo

if [[ -z "${AGE_1}" && -z "${AGE_2}" ]]; then
    cat <<'HINT'
Kein Age-Header — vor dieser URL arbeitet kein Shared Cache.

Zu pruefen, in dieser Reihenfolge:

  1. Ist der Cache ueberhaupt eingeschaltet?
       grep -E 'SHOPWARE_HTTP_(CACHE_ENABLED|DEFAULT_TTL)' .env .env.local
     Beide Werte sind ab Werk gesetzt (1 bzw. 7200). Ein Problem entsteht
     erst, wenn jemand SHOPWARE_HTTP_CACHE_ENABLED=0 gesetzt hat.

  2. Laeuft der Shop in prod?
       grep APP_ENV .env .env.local
     In dev ist cache.app ein ArrayAdapter, der Cache ueberlebt keinen Request.

  3. Ist die gepruefte Route ueberhaupt cachebar?
     Nur Routen mit _httpCache (Startseite, Kategorie, Produkt, Suche) werden
     gecacht. Checkout und Kundenkonto nie.

  4. Steht ein Reverse Proxy davor, der Age entfernt?
     Varnish/Fastly/Cloudflare direkt befragen.

Achtung: die Keys "enabled", "default_ttl" und "invalidation" gibt es unter
shopware.http_cache NICHT. Der Schalter ist die Env-Variable; unter
shopware.http_cache liegen nur cookies, ignored_url_parameters,
stale_while_revalidate, stale_if_error und reverse_proxy.
HINT
    exit 1
fi

if [[ -n "${AGE_2}" && -n "${AGE_1}" && "${AGE_2}" -gt "${AGE_1}" ]]; then
    echo "Ein Shared Cache liefert diese Seite aus (Age ${AGE_1} -> ${AGE_2})."
    echo "Der HTTP-Cache arbeitet."
    exit 0
fi

echo "Age-Header vorhanden (${AGE_1:-0} -> ${AGE_2:-0}), aber nicht gewachsen."
echo "Moegliche Gruende: der Eintrag wurde gerade erst erzeugt, die TTL ist"
echo "abgelaufen, oder jeder Request erzeugt einen eigenen Cache-Key"
echo "(z. B. durch Tracking-Parameter — siehe shopware.http_cache.ignored_url_parameters)."
echo
echo "Der zweite Fall ist die zweite Ursache aus Problem 2 und waere ein"
echo "echter Fund. Dieser Lauf kann die drei Faelle nicht auseinanderhalten:"
echo "zwei Abrufe mit laengerer Pause wiederholen."
exit 1
