#!/usr/bin/env bash
#
# test-session-lock.sh
#
# Problem 8: Session-Lock Blocking.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Der naheliegende Test taugt nicht:
#
#     time ( curl -s shop/page1 & curl -s shop/page2 & wait )
#
# Ohne gemeinsamen Cookie-Jar bekommt jeder curl eine eigene Session. Zwei
# verschiedene Sessions sperren sich nie gegenseitig — der Test kann das
# Problem gar nicht zeigen. Und selbst bei echter Sperre waere das Ergebnis
# ungefaehr die *Summe* der Einzelzeiten, nicht mehr; ein Kriterium
# "> 2x Einzelzeit" loest also praktisch nie aus.
#
# Dieses Skript legt zuerst eine Session an und schickt dann beide Requests
# mit demselben Cookie. Verglichen wird parallel gegen sequenziell:
#
#   parallel ~ sequenziell  -> die Requests werden serialisiert (Sperre)
#   parallel ~ sequenziell/2 -> sie laufen wirklich parallel (keine Sperre)
#
# Gemessen wird ueber mehrere Runden, ausgewertet wird der Median — eine
# einzelne Messung schwankt zu stark.
#
# Verwendung:
#   ./test-session-lock.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = keine Serialisierung erkennbar
#   1 = die Requests werden serialisiert
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: test-session-lock.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob zwei gleichzeitige Requests derselben Session serialisiert werden.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Optional. Wurzel der Shopware-Installation; wird nur benutzt, um
              den konfigurierten Session-Handler anzuzeigen.

Umgebungsvariablen:
  ROUNDS      Anzahl Messrunden. Default: 5
  TEST_PATH   Pfad, der gemessen wird. Default: /checkout/cart
              Diese Seite ist bewusst nicht cachebar und beruehrt die Session,
              landet also immer in PHP.
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
SHOP_URL="${SHOP_URL%/}"
SHOP_PATH="${2:-}"
ROUNDS="${ROUNDS:-5}"
TEST_PATH="${TEST_PATH:-/checkout/cart}"

COOKIE_JAR=$(mktemp)
trap 'rm -f "${COOKIE_JAR}"' EXIT

echo "=== Problem 8: Session-Lock ==="
echo
echo "Prueft: ${SHOP_URL}${TEST_PATH}  (${ROUNDS} Runden)"
echo

# Session anlegen: einmal die Startseite und einmal die Testseite abrufen,
# damit das Session-Cookie sicher gesetzt ist.
curl -sS -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -o /dev/null -L "${SHOP_URL}/" || {
    echo "Shop nicht erreichbar: ${SHOP_URL}" >&2
    exit 1
}
curl -sS -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -o /dev/null -L "${SHOP_URL}${TEST_PATH}"

SESSION_COOKIE=$(grep -c 'session' "${COOKIE_JAR}" || true)
if [[ "${SESSION_COOKIE}" -eq 0 ]]; then
    echo "Warnung: im Cookie-Jar steht kein Session-Cookie. Der Test misst dann"
    echo "nur die allgemeine Parallelitaet des Servers, nicht die Session-Sperre."
    echo
fi

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

hit() {
    curl -sS -b "${COOKIE_JAR}" -o /dev/null -L "${SHOP_URL}${TEST_PATH}"
}

median() {
    # liest Zahlen von stdin
    sort -n | awk '{ v[NR] = $1 } END { if (NR == 0) { print 0 } else { print v[int((NR + 1) / 2)] } }'
}

PARALLEL_TIMES=""
SEQUENTIAL_TIMES=""

for _ in $(seq "${ROUNDS}"); do
    start=$(now_ms)
    hit & p1=$!
    hit & p2=$!
    wait "${p1}" "${p2}"
    end=$(now_ms)
    PARALLEL_TIMES="${PARALLEL_TIMES}$((end - start))"$'\n'

    start=$(now_ms)
    hit
    hit
    end=$(now_ms)
    SEQUENTIAL_TIMES="${SEQUENTIAL_TIMES}$((end - start))"$'\n'
done

PARALLEL=$(printf '%s' "${PARALLEL_TIMES}" | median)
SEQUENTIAL=$(printf '%s' "${SEQUENTIAL_TIMES}" | median)

echo "1. Messung (Median aus ${ROUNDS} Runden)"
echo "   zwei Requests parallel:     ${PARALLEL} ms"
echo "   zwei Requests nacheinander: ${SEQUENTIAL} ms"

if [[ "${SEQUENTIAL}" -le 0 ]]; then
    echo
    echo "Die sequenzielle Messung ergab 0 ms — die Seite antwortet zu schnell"
    echo "fuer diese Aufloesung. Mit TEST_PATH eine langsamere Seite waehlen."
    exit 0
fi

# Anteil der parallelen an der sequenziellen Zeit, in Prozent.
RATIO=$(( PARALLEL * 100 / SEQUENTIAL ))
echo "   parallel entspricht ${RATIO} % der sequenziellen Zeit"

if [[ -n "${SHOP_PATH}" ]]; then
    echo
    echo "2. Konfigurierter Session-Handler"
    HANDLER=$(grep -rh 'handler_id' "${SHOP_PATH}/config/packages/" 2>/dev/null | head -3 || true)
    if [[ -n "${HANDLER}" ]]; then
        printf '%s\n' "${HANDLER}" | sed 's/^[[:space:]]*/   /'
    else
        echo "   Kein handler_id gesetzt — es gilt der Save-Handler aus der php.ini"
        echo "   (Default: files). Der sperrt die Session waehrend des Requests."
    fi
    for f in "${SHOP_PATH}/.env" "${SHOP_PATH}/.env.local"; do
        [[ -f "$f" ]] || continue
        REDIS_LINES=$(grep -E '^REDIS_(SESSION_)?URL=' "$f" || true)
        [[ -n "${REDIS_LINES}" ]] && printf '%s\n' "${REDIS_LINES}" | sed "s|^|   ${f##*/}: |"
    done
fi

echo
echo "=== Ergebnis ==="
echo

# Serialisiert heisst: parallel dauert fast so lange wie nacheinander.
if [[ "${RATIO}" -ge 80 ]]; then
    cat <<'EOF'
Die beiden Requests werden serialisiert — das sieht nach einer Session-Sperre aus.

PHPs Standard-Save-Handler "files" haelt die Session-Datei fuer die Dauer des
Requests exklusiv gesperrt. Ein zweiter Request derselben Session wartet, bis
der erste fertig ist. Bei einer Seite mit mehreren AJAX-Aufrufen summiert sich
das sichtbar auf.

Zwei Wege heraus:

  1. Sessions in Redis ablegen. Der Redis-Handler sperrt nicht.

     WICHTIG: dafuer eine EIGENE Redis-Instanz nehmen, nicht die Cache-Instanz.
     Die Cache-Instanz laeuft ueblicherweise mit maxmemory-policy volatile-lru
     und ohne Persistenz — ein Neustart wuerde alle Kunden ausloggen und jeden
     Warenkorb leeren.

       # .env.local
       REDIS_SESSION_URL=redis://127.0.0.1:6380/0

       # config/packages/framework.yaml
       framework:
           session:
               handler_id: '%env(REDIS_SESSION_URL)%'

     Vorlage: config/redis-session.yaml

  2. Die Session im eigenen Code frueh schliessen, wenn der Request sie nicht
     mehr braucht. In Symfony/Shopware nicht session_write_close() aufrufen,
     sondern die Abstraktion benutzen:

       $request->getSession()->save();

     Danach sind nur noch Lesezugriffe erlaubt.
EOF
    exit 1
fi

echo "Keine Serialisierung erkennbar: parallel dauert ${RATIO} % der sequenziellen"
echo "Zeit, die Requests laufen also tatsaechlich nebeneinander."
exit 0
