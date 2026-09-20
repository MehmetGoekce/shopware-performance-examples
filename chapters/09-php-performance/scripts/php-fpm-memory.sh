#!/bin/bash
#
# PHP-FPM Memory Analysis
# Misst den Speicherverbrauch pro Worker als Grundlage fuer pm.max_children.
#
# Begleitend zu Buch-Kapitel 9 ("Shop-Performance in 30 Tagen", 2nd Edition).
#
# Zwei Dinge, die haeufig schiefgehen und hier abgefangen sind:
#
#   1. Auf Debian und Ubuntu heisst der Prozess `php-fpm8.3`, nicht `php-fpm`.
#      `ps -C php-fpm` und `pgrep -x php-fpm` finden dort nichts und melden
#      "kein Worker" bei laufendem FPM.
#   2. Der Master-Prozess belegt nur rund 12 MB, ein warmer Worker 80 MB.
#      Rechnet man den Master in den Durchschnitt, kommt ein zu kleiner Wert
#      heraus - und damit ein zu grosses pm.max_children.
#
# @see https://tideways.com/profiler/blog/an-introduction-to-php-fpm-tuning

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: php-fpm-memory.sh [-p PROZESSNAME] [-h]

Misst RSS je PHP-FPM-Worker und gibt eine Empfehlung fuer AVG_WORKER_MB aus.

  -p PROZESSNAME  Prozessname statt automatischer Erkennung (z. B. php-fpm8.2)
  -h              Diese Hilfe

Exit-Codes:
  0  Messung erfolgreich
  1  kein laufender PHP-FPM-Prozess gefunden
  2  FPM laeuft, aber kein Worker (nur der Master) - Shop einmal aufrufen
EOF
}

PROCESS_NAME=""
# Lange Optionen auf die kurzen abbilden - getopts kann sie nicht.
ARGS=()
for arg in "$@"; do
    case "${arg}" in
        --help) ARGS+=("-h") ;;
        *)      ARGS+=("${arg}") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

while getopts ":p:h" opt; do
    case "${opt}" in
        p) PROCESS_NAME="${OPTARG}" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

echo "=== PHP-FPM Memory Analysis ==="
echo ""

# --- Prozessnamen ermitteln -------------------------------------------------
if [[ -z "${PROCESS_NAME}" ]]; then
    for candidate in php-fpm8.4 php-fpm8.3 php-fpm8.2 php-fpm; do
        if pgrep -x "${candidate}" > /dev/null; then
            PROCESS_NAME="${candidate}"
            break
        fi
    done
fi

if [[ -z "${PROCESS_NAME}" ]]; then
    echo "FEHLER: Kein laufender PHP-FPM-Prozess gefunden." >&2
    echo "        Geprueft: php-fpm8.4, php-fpm8.3, php-fpm8.2, php-fpm" >&2
    echo "        Eigenen Namen mit -p angeben, falls er anders lautet:" >&2
    echo "          ps -eo comm | sort -u | grep -i php" >&2
    exit 1
fi

# Auch ein per -p uebergebener Name muss laufen, sonst meldet das Skript
# gleich "kein Worker" und verschleiert, dass es den Prozess gar nicht gibt.
if ! pgrep -x "${PROCESS_NAME}" > /dev/null; then
    echo "FEHLER: Es laeuft kein Prozess namens '${PROCESS_NAME}'." >&2
    echo "        Vorhandene PHP-Prozesse:" >&2
    ps -eo comm | sort -u | grep -i php >&2 || echo "          (keine)" >&2
    exit 1
fi

echo "Prozess: ${PROCESS_NAME}"
echo ""

# --- Worker einsammeln ------------------------------------------------------
# Nur Pool-Prozesse; der Master traegt "master process" im Kommandozeilentext.
WORKERS="$(ps --no-headers -o rss,args -C "${PROCESS_NAME}" | grep 'pool' || true)"

if [[ -z "${WORKERS}" ]]; then
    echo "FEHLER: ${PROCESS_NAME} laeuft, aber kein Worker ist aktiv." >&2
    echo "        Rufen Sie den Shop einmal auf und messen Sie erneut." >&2
    exit 2
fi

echo "Worker-Statistiken:"
echo ""
printf '%s\n' "${WORKERS}" | awk '
{
    rss_mb = $1/1024
    total += $1
    count++
    if (rss_mb > max) max = rss_mb
    if (min == 0 || rss_mb < min) min = rss_mb
}
END {
    avg = total/count/1024
    printf "  Anzahl Worker:  %d\n", count
    printf "  Durchschnitt:   %.0f MB\n", avg
    printf "  Minimum:        %.0f MB\n", min
    printf "  Maximum:        %.0f MB\n", max
    printf "\n=== Naechster Schritt ===\n"
    printf "  ./calculate-max-children.sh -w %.0f   # Durchschnitt + 10 MB Puffer\n", avg + 10
}'

echo ""
echo "Hinweis: Direkt nach einem Reload sind die Worker kalt. Messen Sie nach"
echo "         einigen Minuten echter Last erneut - der Wert steigt noch."
