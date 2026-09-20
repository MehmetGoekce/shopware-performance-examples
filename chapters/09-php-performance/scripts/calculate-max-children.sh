#!/bin/bash
#
# PHP-FPM pm.max_children Kalkulator
#
# Begleitend zu Buch-Kapitel 9 ("Shop-Performance in 30 Tagen", 2nd Edition).
#
# Die Vorgabewerte beschreiben den Beispielserver des Buchs: 16 GB RAM, auf
# denen alles zusammen laeuft. Dasselbe Budget steht in Anhang C und fuehrt
# dort zu denselben 50 Workern.
#
# Verwendung:
#   ./calculate-max-children.sh                       # Beispielserver
#   ./calculate-max-children.sh -r 32768 -w 95        # eigener Server
#
# Den Wert fuer -w liefert ./php-fpm-memory.sh am LAUFENDEN, warmen Shop.
# Schaetzen Sie ihn nicht: kalt gemessen sind es rund 16 MB, warm rund 82 MB.
#
# Quelle: https://tideways.com/profiler/blog/an-introduction-to-php-fpm-tuning

set -euo pipefail

# =============================================================================
# Vorgabewerte - Beispielserver des Buchs (16 GB, alles auf einer Maschine)
# =============================================================================

TOTAL_RAM_MB=16384        # Server-RAM in MB
OS_RESERVE_MB=3072        # Betriebssystem und Dateisystem-Cache
OTHER_SERVICES_MB=9216    # MySQL Buffer Pool 4 GB + Redis-Cache 4 GB + Sessions 1 GB
BUFFER_PERCENT=0          # zusaetzlicher Puffer; die OS-Reserve ist bereits einer
AVG_WORKER_MB=80          # gemessen an Shopware 6.6 mit warmen Workern

usage() {
    cat <<'EOF'
Usage: calculate-max-children.sh [-r RAM_MB] [-o OS_MB] [-s SERVICES_MB]
                                 [-b BUFFER_PROZENT] [-w WORKER_MB] [-h]

Berechnet pm.max_children und die abgeleiteten Pool-Werte.

  -r RAM_MB           Gesamt-RAM des Servers in MB      (Vorgabe: 16384)
  -o OS_MB            Reserve fuer das Betriebssystem   (Vorgabe: 3072)
  -s SERVICES_MB      RAM fuer MySQL, Redis, Suche ...  (Vorgabe: 9216)
  -b BUFFER_PROZENT   zusaetzlicher Puffer in Prozent   (Vorgabe: 0)
  -w WORKER_MB        RSS je Worker, gemessen           (Vorgabe: 80)
  -h                  Diese Hilfe

Exit-Codes:
  0  Berechnung erfolgreich
  1  ungueltige Eingabe
  2  Budget geht nicht auf (Reserven groesser als der vorhandene RAM)
EOF
}

is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 ))
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

while getopts ":r:o:s:b:w:h" opt; do
    case "${opt}" in
        r) TOTAL_RAM_MB="${OPTARG}" ;;
        o) OS_RESERVE_MB="${OPTARG}" ;;
        s) OTHER_SERVICES_MB="${OPTARG}" ;;
        b) BUFFER_PERCENT="${OPTARG}" ;;
        w) AVG_WORKER_MB="${OPTARG}" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

for pair in "RAM:${TOTAL_RAM_MB}" "OS-Reserve:${OS_RESERVE_MB}" \
            "Services:${OTHER_SERVICES_MB}" "Worker-RAM:${AVG_WORKER_MB}"; do
    if ! is_positive_int "${pair#*:}"; then
        echo "FEHLER: ${pair%%:*} muss eine positive ganze Zahl sein (war: '${pair#*:}')." >&2
        exit 1
    fi
done

if ! [[ "${BUFFER_PERCENT}" =~ ^[0-9]+$ ]] || (( BUFFER_PERCENT > 90 )); then
    echo "FEHLER: Sicherheitspuffer muss zwischen 0 und 90 Prozent liegen." >&2
    exit 1
fi

# =============================================================================
# Berechnung
# =============================================================================

AVAILABLE_RAM=$((TOTAL_RAM_MB - OS_RESERVE_MB - OTHER_SERVICES_MB))

if (( AVAILABLE_RAM <= 0 )); then
    echo "FEHLER: Fuer PHP-FPM bleibt nichts uebrig." >&2
    echo "        ${TOTAL_RAM_MB} MB - ${OS_RESERVE_MB} MB - ${OTHER_SERVICES_MB} MB = ${AVAILABLE_RAM} MB" >&2
    echo "        Reserven senken oder dem Server mehr RAM geben." >&2
    exit 2
fi

BUFFER=$((AVAILABLE_RAM * BUFFER_PERCENT / 100))
PHP_RAM=$((AVAILABLE_RAM - BUFFER))
MAX_CHILDREN=$((PHP_RAM / AVG_WORKER_MB))

if (( MAX_CHILDREN < 8 )); then
    MAX_CHILDREN=8
    FLOOR_HINT="  (auf das Minimum von 8 angehoben)"
else
    FLOOR_HINT=""
fi

START_SERVERS=$((MAX_CHILDREN / 5))
MIN_SPARE=$((MAX_CHILDREN / 10))
MAX_SPARE=$((MAX_CHILDREN * 2 / 5))
(( START_SERVERS < 1 )) && START_SERVERS=1
(( MIN_SPARE < 1 )) && MIN_SPARE=1
(( MAX_SPARE < START_SERVERS )) && MAX_SPARE=${START_SERVERS}

# =============================================================================
# Ausgabe
# =============================================================================

echo "=== PHP-FPM Kalkulation ==="
echo ""
echo "Eingabewerte:"
printf '  %-20s %6s MB\n' "Gesamt-RAM:"        "${TOTAL_RAM_MB}"
printf '  %-20s %6s MB\n' "OS-Reserve:"        "${OS_RESERVE_MB}"
printf '  %-20s %6s MB\n' "Andere Services:"   "${OTHER_SERVICES_MB}"
printf '  %-20s %6s MB\n' "RSS je Worker:"     "${AVG_WORKER_MB}"
printf '  %-20s %6s %%\n' "Sicherheitspuffer:" "${BUFFER_PERCENT}"
echo ""
echo "Berechnung:"
printf '  %-20s %6s MB\n' "Verfuegbar:"   "${AVAILABLE_RAM}"
printf '  %-20s %6s MB\n' "Minus Puffer:" "${BUFFER}"
printf '  %-20s %6s MB\n' "Fuer PHP-FPM:" "${PHP_RAM}"
echo ""
echo "=== Zum Kopieren in shopware-fpm.conf ===${FLOOR_HINT}"
cat <<EOF

pm = dynamic
pm.max_children = ${MAX_CHILDREN}
pm.start_servers = ${START_SERVERS}
pm.min_spare_servers = ${MIN_SPARE}
pm.max_spare_servers = ${MAX_SPARE}

EOF

echo "Die Vorlage shopware-fpm.conf traegt 50 ein - dieselbe Rechnung, auf eine"
echo "runde Zahl abgerundet. Ein Worker mehr oder weniger ist Rauschen."
echo ""
echo "Diese Rechnung ist ein Startwert, kein Ergebnis."
echo "Pruefen Sie danach die Statusseite des Pools:"
echo "  curl -s http://127.0.0.1/fpm-status | grep -E 'listen queue|max children'"
echo "'max children reached' darf nie ueber 0 stehen, 'listen queue' nie dauerhaft."
