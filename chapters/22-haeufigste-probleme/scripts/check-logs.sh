#!/bin/bash
#
# Problem 17: Große Log-Dateien diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-logs.sh [SHOP_URL] [SHOP_PATH]

Zeigt Groesse und Anzahl der Logdateien und erklaert, welcher
Aufbewahrungs-Mechanismus wirklich greift.

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

SHOP_PATH="${2:-.}"

echo "=== Problem 17: Log-Dateien Größe ==="
echo ""

LOG_DIR="${SHOP_PATH}/var/log"

if [[ ! -d "${LOG_DIR}" ]]; then
    echo "⚠ Log-Verzeichnis nicht gefunden: ${LOG_DIR}"
    exit 1
fi

# Gesamtgröße
echo "1. Gesamtgröße des Log-Verzeichnisses..."
TOTAL_SIZE=$(du -sh "${LOG_DIR}" 2>/dev/null | cut -f1 || true)
echo "   ${LOG_DIR}: ${TOTAL_SIZE}"

# Einzelne Dateien
echo ""
echo "2. Größte Log-Dateien..."
echo ""
# Erst vollstaendig sortieren, dann kuerzen: ein head am Pipeline-Ende
# schickt sort ein SIGPIPE, und unter "set -euo pipefail" bricht das
# Skript daran ab (Exit 141).
LOG_SIZES=$(du -ah "${LOG_DIR}"/*.log 2>/dev/null | sort -rh || true)
printf '%s\n' "${LOG_SIZES}" | head -10 | while read -r size file; do
    [[ -z "${file}" ]] && continue
    echo "   ${size}  $(basename "${file}")"
done

# Warnung bei großen Logs
TOTAL_BYTES=$(du -sb "${LOG_DIR}" 2>/dev/null | cut -f1 || true)
if [[ "${TOTAL_BYTES:-0}" -gt 1073741824 ]]; then
    echo ""
    echo "   ✗ WARNUNG: Log-Verzeichnis > 1 GB!"
    PROBLEM=1
elif [[ "${TOTAL_BYTES:-0}" -gt 104857600 ]]; then
    echo ""
    echo "   ⚠ Hinweis: Log-Verzeichnis > 100 MB"
    PROBLEM=0
else
    echo ""
    echo "   ✓ Log-Größe im normalen Bereich"
    PROBLEM=0
fi

# Aufbewahrung prüfen
echo ""
echo "3. Aufbewahrung der Logdateien..."
echo "   Shopware rotiert bereits selbst: der prod-Handler 'nested' ist vom Typ"
echo "   rotating_file, die Dateien heissen deshalb prod-JJJJ-MM-TT.log."
echo "   Was fehlt, ist das Aufraeumen — MonologBundles max_files hat den"
echo "   Default 0, also unbegrenzte Aufbewahrung."
ROTATED=$(find "${LOG_DIR}" -maxdepth 1 -name 'prod-*.log' 2>/dev/null | wc -l || true)
echo "   Vorhandene tagesdatierte prod-Logs: ${ROTATED}"
if [[ -f /etc/logrotate.d/shopware ]]; then
    echo "   Zusaetzlich ist eine logrotate-Konfiguration vorhanden."
    echo "   Achtung: logrotate und Monolog rotieren dieselben Dateien. Ohne"
    echo "   copytruncate benennt logrotate eine Datei um, die PHP-FPM noch"
    echo "   offen haelt — die folgenden Eintraege gehen dann ins Leere."
fi

# Empfehlung
echo ""
echo "=== Empfehlung ==="
echo ""
echo "1. Alte Logs bereinigen:"
echo "   find ${LOG_DIR} -name '*.log' -mtime +7 -delete"
echo ""
echo "2. Aufbewahrung begrenzen — das ist der eigentliche Hebel."
echo "   config/packages/prod/monolog.yaml:"
echo ""
echo "   monolog:"
echo "       handlers:"
echo "           nested:"
echo "               max_files: 14"
echo ""
echo "   NICHT 'main: level: error' setzen: main ist ein fingers_crossed-"
echo "   Handler, dort wertet MonologBundle action_level aus, nicht level."
echo "   Und Shopware loggt in prod ohnehin schon nur ab error"
echo "   (main.action_level: error, nested.level: error) — die Zeile"
echo "   aendert also gar nichts."
echo ""
echo "3. logrotate nur, wenn es zusaetzlich sein muss — dann mit copytruncate"
echo "   und einem Muster, das die aktuelle Datei in Ruhe laesst:"
echo "   sudo cp config/logrotate.conf /etc/logrotate.d/shopware"

exit ${PROBLEM:-0}
