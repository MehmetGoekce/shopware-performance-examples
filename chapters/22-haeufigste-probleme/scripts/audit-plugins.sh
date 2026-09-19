#!/usr/bin/env bash
#
# audit-plugins.sh
#
# Problem 10: Zu viele Plugins.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zur Zaehlweise: "bin/console plugin:list | grep -c 'Yes.*Yes'" ist kein
# verlaesslicher Zaehler. Die Tabelle hat vier Yes/No-Spalten (Installed,
# Active, Upgradeable, Required by composer); eine Zeile mit
# Installed=Yes, Active=No, Upgradeable=Yes passt auf dasselbe Muster.
# Dieses Skript wertet deshalb "plugin:list --json" aus.
#
# Zur Bewertung: eine feste Obergrenze fuer die Plugin-Anzahl gibt es nicht,
# weder im Shopware-Code noch in der Doku. Die Kosten entstehen pro Plugin
# (Subscriber, Decorator, Twig-Extensions, zusaetzliche Schreibzugriffe) und
# nicht durch das Zaehlen. Ein einzelnes schlecht geschriebenes Plugin kostet
# mehr als dreissig gute. Dieses Skript zaehlt deshalb, listet auf und zeigt,
# wie man den Beitrag eines einzelnen Plugins misst — es urteilt nicht.
#
# Verwendung:
#   ./audit-plugins.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = Auswertung erstellt
#   1 = Plugin-Liste nicht abrufbar
#   64 = Aufruffehler
#   69 = jq fehlt

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: audit-plugins.sh [SHOP_URL] [SHOP_PATH]

Listet die installierten Plugins und zeigt, welche installiert, aber nicht
aktiv sind.

Argumente:
  SHOP_URL    Wird nicht ausgewertet; nur der Einheitlichkeit halber.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Benoetigt: php, jq
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
# Dieses Skript braucht nur den Pfad; $1 wird bewusst nicht ausgewertet,
# damit run-all-diagnostics.sh alle Skripte gleich aufrufen kann.
SHOP_PATH="${2:-.}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq wird benoetigt (apt-get install jq)." >&2
    exit 69
fi

if [[ ! -f "${SHOP_PATH}/bin/console" ]]; then
    echo "Kein bin/console unter ${SHOP_PATH} — Shop-Pfad als Argument angeben." >&2
    exit 1
fi

echo "=== Problem 10: Plugin-Audit ==="
echo

PLUGIN_JSON=$(php "${SHOP_PATH}/bin/console" plugin:list --json 2>/dev/null || true)

if [[ -z "${PLUGIN_JSON}" ]] || ! printf '%s' "${PLUGIN_JSON}" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "Plugin-Liste konnte nicht gelesen werden." >&2
    echo "Gegenprobe: php ${SHOP_PATH}/bin/console plugin:list" >&2
    # 69 = Voraussetzung fehlt (kein php, kein jq, falscher SHOP_PATH).
    # Ein Exit 1 hiesse "etwas gefunden" und waere im Sammellauf
    # nicht von einem echten Fund zu unterscheiden.
    exit 69
fi

TOTAL=$(printf '%s' "${PLUGIN_JSON}" | jq 'length')
ACTIVE=$(printf '%s' "${PLUGIN_JSON}" | jq '[.[] | select(.active == true)] | length')
INSTALLED=$(printf '%s' "${PLUGIN_JSON}" | jq '[.[] | select(.installedAt != null)] | length')
INACTIVE_INSTALLED=$(printf '%s' "${PLUGIN_JSON}" | jq '[.[] | select(.installedAt != null and .active != true)] | length')

echo "1. Zahlen"
echo "   Vorhanden:                 ${TOTAL}"
echo "   Installiert:               ${INSTALLED}"
echo "   Aktiv:                     ${ACTIVE}"
echo "   Installiert, nicht aktiv:  ${INACTIVE_INSTALLED}"

echo
echo "2. Aktive Plugins"
if [[ "${ACTIVE}" -eq 0 ]]; then
    echo "   (keine)"
else
    printf '%s' "${PLUGIN_JSON}" \
        | jq -r '[.[] | select(.active == true)] | sort_by(.name) | .[]
                 | "   \(.name)  v\(.version // "?")  \(.author // "ohne Autorangabe")"'
fi

echo
echo "3. Installiert, aber nicht aktiv"
if [[ "${INACTIVE_INSTALLED}" -eq 0 ]]; then
    echo "   (keine)"
else
    printf '%s' "${PLUGIN_JSON}" \
        | jq -r '[.[] | select(.installedAt != null and .active != true)] | sort_by(.name) | .[]
                 | "   \(.name)  v\(.version // "?")"'
    echo
    echo "   Diese Plugins kosten keine Laufzeit mehr, belegen aber noch"
    echo "   Datenbanktabellen und Dateien. Entfernen mit:"
    echo "     bin/console plugin:uninstall <Name>"
    echo "   Achtung: plugin:uninstall loescht standardmaessig auch die Daten des"
    echo "   Plugins. Mit --keep-user-data bleiben sie erhalten."
fi

echo
echo "4. Den Beitrag eines einzelnen Plugins messen"
cat <<'HINT'
   Zaehlen sagt wenig. Messen schon:

     1. Baseline holen (zehn Laeufe, damit ein Ausreisser nicht taeuscht):
          for i in $(seq 10); do
              curl -s -o /dev/null -w '%{time_starttransfer}\n' https://shop/
          done

     2. Ein Plugin deaktivieren und den Cache leeren:
          bin/console plugin:deactivate <Name>
          bin/console cache:clear

     3. Dieselbe Messung wiederholen und die Differenz ansehen.

     4. Plugin wieder aktivieren:
          bin/console plugin:activate <Name>

   Auf einer Produktivumgebung gehoert das in ein Wartungsfenster: sowohl
   plugin:deactivate als auch cache:clear wirken sofort fuer alle Besucher.
HINT

echo
echo "=== Ergebnis ==="
echo
echo "${ACTIVE} aktive Plugins. Ob das zu viele sind, entscheidet die Messung"
echo "aus Abschnitt 4, nicht die Zahl."
exit 0
