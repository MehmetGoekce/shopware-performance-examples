#!/usr/bin/env bash
#
# check-http-cache.sh
#
# Problem 2: HTTP-Cache nicht aktiv.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# WICHTIG zum Verstaendnis der Ausgabe:
# Eine korrekt arbeitende Shopware-Storefront (6.6 und 6.7) liefert an den
# Browser "Cache-Control: no-cache, private" — und zwar auch dann, wenn der
# HTTP-Cache laeuft und gerade einen Treffer ausliefert. Shopware setzt intern
# setSharedMaxAge(), also "public, s-maxage=<ttl>" fuer den Shared Cache;
# was beim Browser ankommt, ueberschreibt Shopwares CacheControlListener
# (ausser mit shopware.http_cache.reverse_proxy.enabled).
#
# Das Skript vergleicht deshalb zwei GET-Abrufe im Abstand von PAUSE Sekunden:
#   Age fehlt beide Male      -> kein Shared Cache im Spiel (nur 6.6: ab 6.7
#                                traegt jede Seite ein Age, siehe ESI unten)
#   X-Symfony-Cache vorhanden -> entscheidet: "fresh" beim 2. Abruf = Treffer.
#                                Symfonys HttpCache gibt ihn nur im Debug-Modus
#                                aus oder mit framework.http_cache.trace_level.
#   Age waechst um mindestens die Pause UND Date bleibt gleich -> Treffer.
#                                Nur eine gespeicherte Kopie traegt beim
#                                2. Abruf dasselbe Date wie beim 1.
#   Age waechst, Date aber auch -> nicht entscheidbar (Exit 69):
#       - Die Seite wurde neu gerendert und bindet ein gecachtes ESI-Fragment
#         ein. Symfony setzt das Age der Seite dann auf das des aeltesten
#         Fragments (ResponseCacheStrategy). Shopware 6.7 laedt Header und
#         Footer immer per ESI, 6.6 nur mit dem Feature-Flag CACHE_REWORK.
#         Ab 6.7 traegt deshalb auch ein abgeschalteter Cache Age 0 oder 1.
#       - Oder ein Proxy davor setzt Date neu (nginx mit proxy_pass ohne
#         "proxy_pass_header Date;", CDN).
#   Age > 0 allein und "Age waechst um 1" sind kein Treffer: Symfony setzt
#   beim Speichern Age = Sekunden seit Date, schon ein MISS ueber eine
#   Sekundengrenze traegt Age 1. Zwei MISS koennen so 0 -> 1 zeigen.
#   Die Antwortzeit (TTFB) taugt nicht als zweites Merkmal: Direkt nach
#   cache:clear ist der erste Abruf auch ohne Treffer viel langsamer.
#
# Was der Test NICHT sieht: die zweite Ursache aus Problem 2, eigene
# Cache-Keys je Besucher (Kampagnenparameter). Er ruft zweimal dieselbe URL ab.
#
# Verwendung:
#   ./check-http-cache.sh [SHOP_URL] [SHOP_PATH]
#   ./check-http-cache.sh https://shop.example.com /var/www/shopware
#
# Exit-Codes:
#   0 = HTTP-Cache arbeitet
#   1 = kein Treffer (kein Age, zwei MISS, Trace meldet miss)
#   64 = Aufruffehler (auch: URL liefert nicht 200)
#   69 = nicht entscheidbar (Shop nicht erreichbar, Age waechst bei neuem
#        Date, Age nur bei einem der beiden Abrufe)

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-http-cache.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob vor der Storefront ein HTTP-Cache arbeitet.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Optional. Wurzel der Shopware-Installation; wird nur benutzt,
              um SHOPWARE_HTTP_* aus .env, .env.local, .env.prod und
              .env.prod.local zu lesen.

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

# Header per GET holen, Body verwerfen. -L folgt Weiterleitungen; die
# Ausgabe enthaelt dann einen Headerblock je Hop.
fetch_headers() {
    curl -sS --max-time 30 -o /dev/null -D - -L "$1"
}

header_value() {
    # $1 = Header, $2 = Headername (ohne Doppelpunkt). Gewertet wird nur der
    # letzte Block (das Ziel einer Weiterleitung), nicht ein Header, den nur
    # ein Redirect davor trug. Leerzeichen nach dem Doppelpunkt sind optional.
    printf '%s\n' "$1" | tr -d '\r' | awk -v key="$2" '
        /^HTTP\// { v = "" }
        {
            i = index($0, ":")
            if (i > 1 && tolower(substr($0, 1, i - 1)) == tolower(key)) {
                v = substr($0, i + 1)
                sub(/^[ \t]+/, "", v)
                sub(/[ \t]+$/, "", v)
            }
        }
        END { print v }'
}

last_status() {
    printf '%s\n' "$1" | awk '/^HTTP\// { s = $2 } END { print s }'
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
HOPS_1=$(printf '%s\n' "${HEADERS_1}" | grep -c '^HTTP/' || true)
CODE_1=$(last_status "${HEADERS_1}")
CACHE_CONTROL=$(header_value "${HEADERS_1}" "cache-control")
AGE_1=$(header_value "${HEADERS_1}" "age")
DATE_1=$(header_value "${HEADERS_1}" "date")
TRACE_1=$(header_value "${HEADERS_1}" "x-symfony-cache")

echo "   Cache-Control: ${CACHE_CONTROL:-(nicht gesetzt)}"
echo "   Age:           ${AGE_1:-(nicht gesetzt)}"
echo "   Date:          ${DATE_1:-(nicht gesetzt)}"
[[ -n "${TRACE_1}" ]] && echo "   X-Symfony-Cache: ${TRACE_1}"
if [[ "${HOPS_1}" -gt 1 ]]; then
    echo "   Hinweis: die URL hat weitergeleitet, geprueft wurde das Ziel."
fi
if [[ "${CODE_1}" != "200" ]]; then
    echo "   Die URL liefert HTTP ${CODE_1:-?}, nicht 200. Eine Fehlerseite sagt"
    echo "   nichts ueber den Cache der Storefront: eine Kategorie- oder Produktseite angeben."
    exit 64
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
if ! HEADERS_2=$(fetch_headers "${SHOP_URL}"); then
    echo "   Zweiter Abruf gescheitert: ${SHOP_URL}" >&2
    exit 69
fi
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
    echo "4. Konfiguration in den .env-Dateien (spaetere Zeile gewinnt)..."
    FOUND_ENV=0
    # Reihenfolge wie Symfonys Dotenv in prod: jede Datei ueberschreibt die davor.
    for f in "${SHOP_PATH}/.env" "${SHOP_PATH}/.env.local" \
             "${SHOP_PATH}/.env.prod" "${SHOP_PATH}/.env.prod.local"; do
        if [[ -f "$f" ]]; then
            LINES=$(grep -E '^SHOPWARE_HTTP_(CACHE_ENABLED|DEFAULT_TTL)=' "$f" || true)
            if [[ -n "${LINES}" ]]; then
                FOUND_ENV=1
                printf '%s\n' "${LINES}" | sed "s|^|   ${f##*/}: |"
            fi
        fi
    done
    if [[ -f "${SHOP_PATH}/.env.local.php" ]]; then
        echo "   Achtung: .env.local.php vorhanden — dann liest Symfony nur sie, keine .env-Datei."
    fi
    if [[ "${FOUND_ENV}" -eq 0 ]]; then
        echo "   In keiner .env-Datei gesetzt — es gelten die Defaults"
        echo "   (SHOPWARE_HTTP_CACHE_ENABLED=1, SHOPWARE_HTTP_DEFAULT_TTL=7200),"
        echo "   sofern die Umgebung des Webservers nichts setzt."
    fi
    echo "   Eine Umgebungsvariable des Webservers (FPM env[], Apache SetEnv) schlaegt"
    echo "   jede .env-Datei und steht in keiner. Was der Webserver sieht, zeigt die"
    echo "   Administration: Einstellungen > System > Caches & Indizes (HTTP-Cache An/Aus)."
fi

echo
echo "=== Ergebnis ==="
echo

# Nach einem Treffer: was der Test nicht gesehen hat.
blind_spot() {
    echo
    echo "Geprueft ist nur diese eine URL, zweimal. Ob Besucher mit Kampagnen-"
    echo "parametern eigene Cache-Keys erzeugen (zweite Ursache aus Problem 2),"
    echo "zeigt der Test nicht: dafuer die Query-Parameter im Access-Log mit"
    echo "shopware.http_cache.ignored_url_parameters vergleichen."
}

if [[ -z "${AGE_1}" && -z "${AGE_2}" ]]; then
    cat <<'HINT'
Kein Age-Header — vor dieser URL arbeitet kein Shared Cache.

Zu pruefen, in dieser Reihenfolge:

  1. Ist der Cache ueberhaupt eingeschaltet?
       bin/console debug:dotenv SHOPWARE_HTTP
     Beide Werte sind ab Werk gesetzt (1 bzw. 7200). Ein Problem entsteht
     erst, wenn jemand SHOPWARE_HTTP_CACHE_ENABLED=0 gesetzt hat. debug:dotenv
     liest alle .env-Dateien, nicht die Umgebung des Webservers (FPM env[],
     Apache SetEnv). Die zeigt die Administration:
       Einstellungen > System > Caches & Indizes

  2. Ist die gepruefte Route ueberhaupt cachebar?
     Nur Routen mit _httpCache (Startseite, Kategorie, Produkt) werden
     gecacht. Checkout, Kundenkonto und die Suchergebnisseite nie.

  3. Steht ein Reverse Proxy davor, der Age entfernt?
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
    # Nur "fresh" zaehlt. "valid" heisst: das Backend wurde gefragt und hat
    # die Seite dafuer gerendert.
    for token in ${MAIN_TRACE//[\/,]/ }; do
        [[ "${token}" == "fresh" ]] && HIT=1
    done
    if [[ "${HIT}" -eq 1 ]]; then
        echo "Symfony meldet fuer den 2. Abruf \"${MAIN_TRACE}\": Treffer (Age ${AGE_1:--} -> ${AGE_2:--})."
        echo "Der HTTP-Cache arbeitet."
        blind_spot
        exit 0
    fi
    echo "Symfony meldet fuer den 2. Abruf \"${MAIN_TRACE}\": kein Treffer."
    echo "\"miss\" ohne \"store\": die Route wird nicht gecacht oder der Cache ist aus."
    echo "\"miss/store\" auch beim 2. Abruf: der Eintrag ueberlebt nicht (dev?)."
    if [[ "${TRACE_2}" == *": "* ]]; then
        echo "Den ausfuehrlichen Trace (GET /: ...) gibt Symfony ab Werk nur im"
        echo "Debug-Modus aus. In dev ist cache.app ein ArrayAdapter, jeder Abruf ein MISS."
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
        blind_spot
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
  - Oder ein Proxy vor dem Shop setzt Date neu. Dann kann es trotzdem ein
    Treffer sein. nginx mit proxy_pass tut das ab Werk; mit
    "proxy_pass_header Date;" im location-Block reicht er das Date des
    Shops durch.

Eindeutig wird es mit Symfonys Trace-Header. In config/packages/ eine Datei
mit

    framework:
        http_cache:
            trace_level: short

anlegen, bin/console cache:clear, dann erneut pruefen: "fresh" ist ein
Treffer, "miss" oder "miss/store" keiner. Die Datei danach wieder entfernen.
Nicht entscheidbar: trace_level: short setzen oder den Proxy umgehen.
HINT
    exit 69
fi

# Gesunkenes Age: entweder war der 1. Abruf ein Treffer und der Eintrag ist
# danach abgelaufen, oder es sind zwei MISS (1 -> 0 durch die Rundung, auch
# mit abgeschaltetem Cache auf 6.7). Beides ist kein Treffer beim 2. Abruf.
if [[ "${AGE_OK}" -eq 1 && "${AGE_2}" -lt "${AGE_1}" ]]; then
    echo "Age gesunken (${AGE_1} -> ${AGE_2}): Kam der 1. Abruf aus dem Cache, ist der"
    echo "Eintrag danach abgelaufen oder wurde invalidiert; dann erneut pruefen."
    echo
fi

if [[ "${AGE_OK}" -eq 0 ]]; then
    echo "Age nur bei einem der beiden Abrufe (${AGE_1:--} -> ${AGE_2:--})."
    echo "Nicht entscheidbar: erneut pruefen."
    exit 69
fi

cat <<HINT
Age-Header vorhanden (${AGE_1} -> ${AGE_2}), aber nicht um die Pause gewachsen:
kein Treffer. Age > 0 allein und ein Zuwachs um 1 kommen auch bei einem MISS
vor, Symfony setzt beim Speichern Age = Sekunden seit dem Date-Header. Ab 6.7
traegt jede Seite ein Age (ESI), auch wenn der Cache abgeschaltet ist.

Zu pruefen, in dieser Reihenfolge:

  1. Ist der Cache ueberhaupt eingeschaltet, und laeuft der Shop in prod?
     Ein Problem entsteht erst, wenn jemand SHOPWARE_HTTP_CACHE_ENABLED=0
     gesetzt hat; in dev ist cache.app ein ArrayAdapter, jeder Abruf ein MISS.
     Die Administration zeigt beides so, wie der Webserver es sieht:
       Einstellungen > System > Caches & Indizes (Umgebung, HTTP-Cache)
     bin/console debug:dotenv SHOPWARE_HTTP zeigt die .env-Dateien, nicht
     die Umgebung des Webservers (FPM env[], Apache SetEnv).

  2. Ist die gepruefte Route ueberhaupt cachebar? (Startseite, Kategorie und
     Produkt ja; Checkout, Kundenkonto und Suchergebnisseite nie.)

Wurde der Eintrag beim 1. Abruf erst erzeugt, ist ein zweiter Lauf ein Treffer.
HINT
exit 1
