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
# was beim Browser ankommt, ueberschreibt Shopwares CacheControlListener
# (ausser mit shopware.http_cache.reverse_proxy.enabled).
# "public, max-age=..." bekommt man an einer Storefront-URL nie zu sehen.
#
# Das Skript vergleicht deshalb zwei GET-Abrufe im Abstand von PAUSE Sekunden:
#   Age fehlt beide Male      -> kein Shared Cache im Spiel
#   X-Symfony-Cache vorhanden -> entscheidet: "fresh" (oder "valid") beim
#                                2. Abruf = Treffer. Symfonys HttpCache gibt
#                                ihn nur im Debug-Modus aus oder mit
#                                framework.http_cache.trace_level: short.
#   Age waechst um mindestens die Pause UND Date bleibt gleich -> Treffer.
#                                Nur eine gespeicherte Kopie traegt beim
#                                2. Abruf dasselbe Date wie beim 1.
#   Age waechst, Date aber auch -> nicht eindeutig, kein Treffer:
#       - Die Seite wurde neu gerendert und bindet ein gecachtes ESI-Fragment
#         ein. Symfony setzt das Age der Seite dann auf das des aeltesten
#         Fragments (ResponseCacheStrategy). Shopware 6.7 laedt Header und
#         Footer immer per ESI, 6.6 nur mit dem Feature-Flag CACHE_REWORK.
#       - Oder ein Proxy davor (nginx mit proxy_pass, CDN) setzt Date neu.
#   Age > 0 allein und "Age waechst um 1" sind kein Treffer: Symfony setzt
#   beim Speichern Age = Sekunden seit Date, schon ein MISS ueber eine
#   Sekundengrenze traegt Age 1. Zwei MISS koennen so 0 -> 1 zeigen.
#   Die Antwortzeit (TTFB) taugt nicht als zweites Merkmal: Direkt nach
#   cache:clear ist der erste Abruf auch ohne Treffer viel langsamer.
#
# Verwendung:
#   ./check-http-cache.sh [SHOP_URL] [SHOP_PATH]
#   ./check-http-cache.sh https://shop.example.com /var/www/shopware
#
# Exit-Codes:
#   0 = HTTP-Cache arbeitet
#   1 = kein Treffer nachgewiesen (kein Cache, zwei MISS oder nicht eindeutig)
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
vergleicht Age, Date und, falls vorhanden, X-Symfony-Cache. Treffer heisst:
Age waechst um mindestens die Pause, und Date bleibt gleich. HEAD (curl -I)
ist dafuer nicht geeignet: manche Setups beantworten HEAD anders als GET.
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
# Pause zwischen den Abrufen. Bei einem Treffer waechst Age um mindestens
# diesen Wert. Nicht 1: zwei MISS koennen sich durch die Rundung auf ganze
# Sekunden um 1 unterscheiden.
PAUSE=2

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
DATE_1=$(header_value "${HEADERS_1}" "date")
TRACE_1=$(header_value "${HEADERS_1}" "x-symfony-cache")

echo "   Cache-Control: ${CACHE_CONTROL:-(nicht gesetzt)}"
echo "   Age:           ${AGE_1:-(nicht gesetzt)}"
echo "   Date:          ${DATE_1:-(nicht gesetzt)}"
[[ -n "${TRACE_1}" ]] && echo "   X-Symfony-Cache: ${TRACE_1}"
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
echo "2. Zweiter Request (nach ${PAUSE} s)..."
sleep "${PAUSE}"
HEADERS_2=$(fetch_headers "${SHOP_URL}")
AGE_2=$(header_value "${HEADERS_2}" "age")
DATE_2=$(header_value "${HEADERS_2}" "date")
TRACE_2=$(header_value "${HEADERS_2}" "x-symfony-cache")
echo "   Age:           ${AGE_2:-(nicht gesetzt)}"
echo "   Date:          ${DATE_2:-(nicht gesetzt)}"
[[ -n "${TRACE_2}" ]] && echo "   X-Symfony-Cache: ${TRACE_2}"

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

# Symfonys Trace entscheidet, wenn er da ist. Er nennt zuerst die Hauptanfrage
# ("fresh" im Format short, "GET /: fresh; GET /_esi/...: ..." im Format
# full); ESI-Fragmente dahinter zaehlen nicht.
if [[ -n "${TRACE_2}" ]]; then
    MAIN_TRACE="${TRACE_2%%;*}"
    MAIN_TRACE="${MAIN_TRACE##*: }"
    HIT=0
    for token in ${MAIN_TRACE//[\/,]/ }; do
        [[ "${token}" == "fresh" || "${token}" == "valid" ]] && HIT=1
    done
    if [[ "${HIT}" -eq 1 ]]; then
        echo "Symfony meldet fuer den 2. Abruf \"${MAIN_TRACE}\": Treffer (Age ${AGE_1:--} -> ${AGE_2:--})."
        echo "Der HTTP-Cache arbeitet."
        exit 0
    fi
    echo "Symfony meldet fuer den 2. Abruf \"${MAIN_TRACE}\": kein Treffer."
    if [[ "${TRACE_2}" == *": "* ]]; then
        echo "Der ausfuehrliche Trace (GET /: ...) erscheint ab Werk nur im Debug-Modus."
        echo "Laeuft der Shop in dev? Dort ist cache.app ein ArrayAdapter, und jeder"
        echo "Abruf ist ein MISS."
    fi
    exit 1
fi

AGE_OK=0
if [[ "${AGE_1}" =~ ^[0-9]+$ && "${AGE_2}" =~ ^[0-9]+$ ]]; then
    AGE_OK=1
fi

if [[ "${AGE_OK}" -eq 1 && $((AGE_2 - AGE_1)) -ge "${PAUSE}" ]]; then
    if [[ -n "${DATE_1}" && "${DATE_1}" == "${DATE_2}" ]]; then
        echo "Ein Shared Cache liefert diese Seite aus (Age ${AGE_1} -> ${AGE_2}, Date unveraendert)."
        echo "Der HTTP-Cache arbeitet."
        exit 0
    fi
    if [[ -z "${DATE_1}" || -z "${DATE_2}" ]]; then
        DATE_NOTE="aber ohne Date-Header laesst sich nicht pruefen, ob es eine gespeicherte Kopie ist."
    else
        DATE_NOTE="aber Date hat sich ebenfalls geaendert."
    fi
    cat <<HINT
Age ist um die Pause gewachsen (${AGE_1} -> ${AGE_2}),
${DATE_NOTE}
Das ist KEIN Nachweis fuer einen Treffer:

  - Die Seite wurde neu gerendert und bindet ein gecachtes ESI-Fragment ein.
    Dann traegt sie das Age des aeltesten Fragments. Shopware 6.7 laedt
    Header und Footer immer per ESI; ein nie gecachter Warenkorb zeigt dort
    genauso ein wachsendes Age.
  - Oder ein Proxy vor dem Shop (nginx mit proxy_pass, CDN) setzt Date neu.
    Dann kann es trotzdem ein Treffer sein.

Eindeutig wird es mit Symfonys Trace-Header. In config/packages/ eine Datei
mit

    framework:
        http_cache:
            trace_level: short

anlegen, bin/console cache:clear, dann erneut pruefen: "fresh" ist ein
Treffer, "miss" keiner. Die Datei danach wieder entfernen. Oder den Shop
unter Umgehung des Proxys direkt abfragen.
HINT
    exit 1
fi

if [[ "${AGE_OK}" -eq 1 && "${AGE_2}" -lt "${AGE_1}" ]]; then
    echo "Age gesunken (${AGE_1} -> ${AGE_2}): Der 1. Abruf kam aus dem Cache, der"
    echo "Eintrag ist danach abgelaufen oder wurde invalidiert. Erneut pruefen."
    exit 1
fi

if [[ "${AGE_OK}" -eq 0 ]]; then
    echo "Age nur bei einem der beiden Abrufe (${AGE_1:--} -> ${AGE_2:--}). Erneut pruefen."
    exit 1
fi

echo "Age-Header vorhanden (${AGE_1} -> ${AGE_2}), aber nicht um die Pause gewachsen."
echo "Kein Treffer. Age > 0 allein und ein Zuwachs um 1 kommen auch bei einem"
echo "MISS vor: Symfony setzt beim Speichern Age = Sekunden seit dem Date-Header."
echo
echo "Moegliche Gruende: der Eintrag wurde gerade erst erzeugt, der Shop laeuft"
echo "in dev (jeder Abruf ein MISS), oder jeder Request erzeugt einen eigenen"
echo "Cache-Key (z. B. durch Tracking-Parameter — siehe"
echo "shopware.http_cache.ignored_url_parameters). Der letzte Fall ist die zweite"
echo "Ursache aus Problem 2 und waere ein echter Fund. Zum Unterscheiden erneut"
echo "pruefen: arbeitet der Cache, ist der 2. Lauf ein Treffer."
exit 1
