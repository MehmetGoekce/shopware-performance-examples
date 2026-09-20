#!/bin/bash
#
# JIT-Benchmark fuer Shopware
#
# Begleitend zu Buch-Kapitel 9 ("Shop-Performance in 30 Tagen", 2nd Edition).
#
# Misst denselben Request mit und ohne JIT, mehrfach abwechselnd, und meldet
# den Median je Konfiguration.
#
# Drei Dinge, an denen die naive Fassung dieses Skripts scheitert:
#
#   1. `opcache.jit=tracing` in der Konfiguration heisst NICHT, dass JIT laeuft.
#      Sobald eine Erweiterung zend_execute_ex() ueberschreibt, schaltet PHP JIT
#      still ab und schreibt nur ins Error-Log. Gemessen: pcov -> aus,
#      Xdebug -> aus, Tideways -> laeuft weiter. Ohne Gegenprobe vergleicht das
#      Skript dann "aus" mit "aus" und meldet erwartungsgemaess "kein Effekt".
#   2. Eine einzelne Messung entscheidet nichts. Auf einem Rechner mit anderer
#      Last streuen die Werte staerker als der Effekt, den man sucht. Deshalb
#      mehrere Runden und Median statt Mittelwert.
#   3. Eine gecachte Seite misst den HTTP-Cache, nicht PHP. Nehmen Sie eine
#      Route mit `Cache-Control: no-store` - z. B. /account/login.
#
# Ergebnis der Buchmessung (Dockware 6.6.10.6, Demo-Daten, /account/login,
# 14 Paare): Median 56,5 -> 62,5 req/s, rund +10 %. Auf einem Shop mit echter
# Datenmenge faellt der CPU-Anteil kleiner aus.
#
# @see https://www.php.net/manual/en/opcache.configuration.php

set -euo pipefail

URL="http://localhost/account/login"
REQUESTS=250
CONCURRENCY=4
ROUNDS=5
PHP_VERSION="8.3"
OPCACHE_INI=""
DOCROOT=""
PROBE=""

usage() {
    cat <<'EOF'
Usage: jit-benchmark.sh [-u URL] [-n REQUESTS] [-c CONCURRENCY] [-r ROUNDS]
                        [-v PHP_VERSION] [-i OPCACHE_INI] [-d DOCROOT] [-h]

Vergleicht Durchsatz mit und ohne JIT ueber mehrere Runden.

  -u URL            Zu messende URL. Nimm eine ungecachte Route.
                    (Vorgabe: http://localhost/account/login)
  -n REQUESTS       Requests je Messung           (Vorgabe: 250)
  -c CONCURRENCY    Gleichzeitige Verbindungen    (Vorgabe: 4)
  -r ROUNDS         Runden je Konfiguration       (Vorgabe: 5)
  -v PHP_VERSION    PHP-Version fuer Pfade/Dienst (Vorgabe: 8.3)
  -i OPCACHE_INI    Pfad zur OPcache-Datei
                    (Vorgabe: /etc/php/<v>/fpm/conf.d/99-shopware-opcache.ini)
  -d DOCROOT        Webroot. Wird gesetzt, prueft das Skript ueber eine
                    kurzzeitig abgelegte Datei, ob JIT WIRKLICH laeuft.
                    Ohne -d nur die statische Pruefung auf bekannte Blocker.
  -h                Diese Hilfe

Umgebungsvariablen:
  FPM_RESTART_CMD   Befehl zum Neustart von PHP-FPM
                    (Vorgabe: systemctl restart php<version>-fpm)

Exit-Codes:
  0  Messung durchgelaufen
  1  Voraussetzung fehlt (ab, Root-Rechte, Konfigurationsdatei)
  2  JIT laesst sich nicht aktivieren (blockierende Erweiterung geladen)
  3  URL ist gecacht oder nicht erreichbar - die Messung waere wertlos
EOF
}

# Lange Optionen auf die kurzen abbilden - getopts kann sie nicht.
ARGS=()
for arg in "$@"; do
    case "${arg}" in
        --help) ARGS+=("-h") ;;
        *)      ARGS+=("${arg}") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

while getopts ":u:n:c:r:v:i:d:h" opt; do
    case "${opt}" in
        u) URL="${OPTARG}" ;;
        n) REQUESTS="${OPTARG}" ;;
        c) CONCURRENCY="${OPTARG}" ;;
        r) ROUNDS="${OPTARG}" ;;
        v) PHP_VERSION="${OPTARG}" ;;
        i) OPCACHE_INI="${OPTARG}" ;;
        d) DOCROOT="${OPTARG}" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

[[ -n "${OPCACHE_INI}" ]] || OPCACHE_INI="/etc/php/${PHP_VERSION}/fpm/conf.d/99-shopware-opcache.ini"

FPM_SERVICE="php${PHP_VERSION}-fpm"
FPM_BIN="php-fpm${PHP_VERSION}"
BACKUP=""

# Neustart-Befehl. Ueberschreibbar, damit das Skript auch dort laeuft, wo es
# kein systemd gibt (Container, Tests):
#   FPM_RESTART_CMD="service php8.3-fpm restart" sudo -E ./jit-benchmark.sh
FPM_RESTART_CMD="${FPM_RESTART_CMD:-systemctl restart ${FPM_SERVICE}}"

cleanup() {
    [[ -n "${PROBE}" && -f "${PROBE}" ]] && rm -f "${PROBE}"
    if [[ -n "${BACKUP}" && -f "${BACKUP}" ]]; then
        echo ""
        echo "Stelle die urspruengliche OPcache-Konfiguration wieder her."
        mv -f "${BACKUP}" "${OPCACHE_INI}"
        ${FPM_RESTART_CMD} > /dev/null || true
    fi
}
trap cleanup EXIT

# =============================================================================
# Voraussetzungen
# =============================================================================

echo "=== JIT Benchmark ==="
echo ""

if ! command -v ab > /dev/null 2>&1; then
    echo "FEHLER: Apache Benchmark (ab) nicht installiert." >&2
    echo "        sudo apt install apache2-utils" >&2
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "FEHLER: Root-Rechte erforderlich, das Skript startet PHP-FPM neu." >&2
    echo "        sudo ./jit-benchmark.sh" >&2
    exit 1
fi

if [[ ! -f "${OPCACHE_INI}" ]]; then
    echo "FEHLER: OPcache-Konfiguration nicht gefunden: ${OPCACHE_INI}" >&2
    echo "        Anderen Pfad mit -i angeben." >&2
    exit 1
fi

# --- Blockiert eine Erweiterung den JIT? ------------------------------------
BLOCKERS="$("${FPM_BIN}" -m 2>/dev/null | grep -ixE 'xdebug|pcov' || true)"
if [[ -n "${BLOCKERS}" ]]; then
    echo "FEHLER: Diese Erweiterungen schalten JIT still ab:" >&2
    printf '          %s\n' ${BLOCKERS} >&2
    echo "        Sie ueberschreiben zend_execute_ex(). Jede Messung waere ein" >&2
    echo "        Vergleich von 'aus' mit 'aus'." >&2
    echo "        In Production haben beide ohnehin nichts verloren - pcov allein" >&2
    echo "        kostete in unserer Messung rund ein Drittel des Durchsatzes." >&2
    echo "        Abschalten: sudo phpdismod -s fpm pcov xdebug && sudo systemctl restart ${FPM_SERVICE}" >&2
    exit 2
fi

# --- Ist die URL ueberhaupt ungecacht? --------------------------------------
HEADERS="$(curl -s -D- -o /dev/null --max-time 15 "${URL}" || true)"
if [[ -z "${HEADERS}" ]]; then
    echo "FEHLER: ${URL} ist nicht erreichbar." >&2
    exit 3
fi
# Zwei Merkmale, beide notwendig:
#
#   1. Kein Age-Header. Age setzt der Cache, der die Antwort ausliefert - ist
#      er da, kam die Seite nicht aus PHP.
#   2. no-store in Cache-Control. Shopware schickt auf den CACHEBAREN Seiten
#      "no-cache, private"; no-cache heisst "revalidieren", nicht "nicht
#      speichern". Nur no-store kennzeichnet eine Seite, die jeder Request
#      neu in PHP erzeugt.
if printf '%s' "${HEADERS}" | grep -qiE '^age:'; then
    AGE_VALUE="$(printf '%s' "${HEADERS}" | grep -iE '^age:' | tr -d '\r' | awk '{print $2}')"
    echo "FEHLER: ${URL} kam aus dem HTTP-Cache (Age: ${AGE_VALUE})." >&2
    echo "        Gemessen wuerde der Cache, nicht PHP." >&2
    echo "        Nehmen Sie z. B. /account/login oder /checkout/cart." >&2
    exit 3
fi
if ! printf '%s' "${HEADERS}" | grep -qi 'cache-control:.*no-store'; then
    echo "FEHLER: ${URL} traegt kein no-store und ist damit cachebar." >&2
    echo "        'no-cache, private' reicht NICHT - das steht bei Shopware auf" >&2
    echo "        den Seiten, die der HTTP-Cache ausliefert." >&2
    echo "        Nehmen Sie z. B. /account/login oder /checkout/cart." >&2
    exit 3
fi

echo "URL:          ${URL}"
echo "Requests:     ${REQUESTS} bei Nebenlaeufigkeit ${CONCURRENCY}"
echo "Runden:       ${ROUNDS} je Konfiguration"
echo "Konfig-Datei: ${OPCACHE_INI}"
echo ""

BACKUP="${OPCACHE_INI}.jitbench.bak"
cp -p "${OPCACHE_INI}" "${BACKUP}"

# =============================================================================
# Hilfsfunktionen
# =============================================================================

set_jit() {  # $1 = off | on
    grep -v -E '^[[:space:]]*opcache\.jit(_buffer_size)?[[:space:]]*=' "${BACKUP}" > "${OPCACHE_INI}"
    if [[ "$1" == "on" ]]; then
        printf 'opcache.jit=1255\nopcache.jit_buffer_size=100M\n' >> "${OPCACHE_INI}"
    else
        printf 'opcache.jit=off\nopcache.jit_buffer_size=0\n' >> "${OPCACHE_INI}"
    fi
    ${FPM_RESTART_CMD} > /dev/null
    sleep 2
}

jit_runtime_state() {  # echo "true"/"false"/"unbekannt"
    if [[ -z "${DOCROOT}" ]]; then
        echo "unbekannt"
        return
    fi
    PROBE="${DOCROOT}/jit-benchmark-probe-$$.php"
    printf '<?php $j=opcache_get_status(false)["jit"]??null; echo $j&&$j["enabled"]?"true":"false";' > "${PROBE}"
    # Basis-URL = Schema + Host (+ Port), unabhaengig vom gemessenen Pfad.
    local rest base state
    rest="${URL#*://}"
    base="${URL%%://*}://${rest%%/*}"
    state="$(curl -s --max-time 15 "${base}/$(basename "${PROBE}")" || true)"
    rm -f "${PROBE}"; PROBE=""
    [[ "${state}" == "true" || "${state}" == "false" ]] && echo "${state}" || echo "unbekannt"
}

measure() {  # $1 = Label; gibt "req/s" auf stdout
    ab -n 60 -c "${CONCURRENCY}" "${URL}" > /dev/null 2>&1   # Warmlauf
    ab -n "${REQUESTS}" -c "${CONCURRENCY}" "${URL}" 2>/dev/null \
        | awk '/Requests per second/ {print $4}'
}

median() {  # liest Zahlen von stdin
    sort -g | awk '{v[NR]=$1} END {
        if (NR == 0) { print "n/a"; exit }
        if (NR % 2) printf "%.2f", v[(NR+1)/2]
        else printf "%.2f", (v[NR/2] + v[NR/2+1]) / 2
    }'
}

# =============================================================================
# Gegenprobe: laeuft JIT wirklich?
# =============================================================================

set_jit on
STATE="$(jit_runtime_state)"
case "${STATE}" in
    true)
        echo "Gegenprobe: JIT ist zur Laufzeit aktiv."
        ;;
    false)
        echo "FEHLER: JIT ist eingetragen, laeuft aber nicht." >&2
        echo "        opcache_get_status()['jit']['enabled'] meldet false." >&2
        echo "        Sieh ins Error-Log der FPM-Pools - dort steht der Grund." >&2
        exit 2
        ;;
    *)
        echo "Hinweis: Ohne -d DOCROOT kann nicht geprueft werden, ob JIT zur"
        echo "         Laufzeit wirklich laeuft. Die bekannten Blocker sind"
        echo "         ausgeschlossen, mehr sagt diese Messung nicht."
        ;;
esac
echo ""

# =============================================================================
# Messung
# =============================================================================

OFF_FILE="$(mktemp)"; ON_FILE="$(mktemp)"
trap 'rm -f "${OFF_FILE}" "${ON_FILE}"; cleanup' EXIT

for ((i = 1; i <= ROUNDS; i++)); do
    set_jit off
    off_rps="$(measure)"
    echo "${off_rps}" >> "${OFF_FILE}"

    set_jit on
    on_rps="$(measure)"
    echo "${on_rps}" >> "${ON_FILE}"

    printf 'Runde %d/%d   ohne JIT %8s req/s   mit JIT %8s req/s\n' \
        "${i}" "${ROUNDS}" "${off_rps}" "${on_rps}"
done

OFF_MEDIAN="$(median < "${OFF_FILE}")"
ON_MEDIAN="$(median < "${ON_FILE}")"

echo ""
echo "=== ERGEBNIS (Median aus ${ROUNDS} Runden) ==="
echo ""
printf '  ohne JIT:  %s req/s\n' "${OFF_MEDIAN}"
printf '  mit JIT:   %s req/s\n' "${ON_MEDIAN}"

awk -v off="${OFF_MEDIAN}" -v on="${ON_MEDIAN}" '
BEGIN {
    if (off <= 0) { print "\n  Kein Vergleich moeglich."; exit }
    diff = (on - off) / off * 100
    printf "  Unterschied: %+.1f %%\n\n", diff
    if (diff < 5 && diff > -5)
        print "  Unter 5 % - fuer diesen Workload entscheidet JIT nichts.\n  Lassen Sie ihn aus; der Buffer waere sonst verschenkter Speicher."
    else if (diff >= 5)
        print "  Messbarer Vorteil. Vor dem Einschalten pruefen, ob die\n  jit_buffer_size zusaetzlich zu memory_consumption noch passt."
    else
        print "  JIT ist hier langsamer. Ausgeschaltet lassen."
}'

echo ""
echo "Streuung pruefen, bevor Sie dem Ergebnis glauben:"
echo "  ohne JIT: $(tr '\n' ' ' < "${OFF_FILE}")"
echo "  mit JIT:  $(tr '\n' ' ' < "${ON_FILE}")"
echo "Liegen die Einzelwerte einer Konfiguration weiter auseinander als die"
echo "beiden Mediane, misst die Maschine sich selbst. Dann mehr Runden."
