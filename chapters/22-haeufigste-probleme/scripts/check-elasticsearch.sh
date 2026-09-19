#!/usr/bin/env bash
#
# check-elasticsearch.sh
#
# Problem 11: Elasticsearch nicht konfiguriert.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zur Konfiguration: in einer Standardinstallation gibt es KEINE
# config/packages/elasticsearch.yaml. Die Datei liegt im Bundle
# (vendor/shopware/elasticsearch/Resources/config/packages/elasticsearch.yaml)
# und bindet alles an Umgebungsvariablen:
#
#   SHOPWARE_ES_ENABLED            Suche laeuft ueber Elasticsearch
#   SHOPWARE_ES_INDEXING_ENABLED   Indizierung ist erlaubt
#   OPENSEARCH_URL                 Host, kommasepariert fuer mehrere
#   SHOPWARE_ES_INDEX_PREFIX       Default: sw
#
# Der Root-Key heisst "elasticsearch", nicht "shopware.es". Shopware 6.6
# spricht ueber den OpenSearch-PHP-Client mit dem Cluster; Elasticsearch und
# OpenSearch funktionieren beide.
#
# Verwendung:
#   ./check-elasticsearch.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = Elasticsearch aktiv und erreichbar
#   1 = nicht aktiv, nicht erreichbar oder ohne Indizes
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-elasticsearch.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob die Shopware-Suche ueber Elasticsearch/OpenSearch laeuft.

Argumente:
  SHOP_URL    Wird nicht ausgewertet; nur der Einheitlichkeit halber.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Umgebungsvariablen:
  ES_HOST     Host:Port des Clusters. Ohne Angabe wird OPENSEARCH_URL aus
              .env/.env.local benutzt, sonst localhost:9200.
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
# Cluster-Adresse per Umgebungsvariable, damit die Argumentfolge einheitlich bleibt.
ES_HOST_ARG="${ES_HOST:-}"

env_value() {
    # $1 = Variablenname. .env.local sticht .env.
    local name="$1" value=""
    for f in "${SHOP_PATH}/.env" "${SHOP_PATH}/.env.local"; do
        [[ -f "$f" ]] || continue
        local line
        line=$(grep -E "^${name}=" "$f" | tail -1 || true)
        [[ -n "${line}" ]] && value="${line#*=}"
    done
    printf '%s' "${value}" | tr -d '"'"'"''
}

echo "=== Problem 11: Elasticsearch ==="
echo

ES_ENABLED=$(env_value SHOPWARE_ES_ENABLED)
ES_INDEXING=$(env_value SHOPWARE_ES_INDEXING_ENABLED)
ES_URL=$(env_value OPENSEARCH_URL)
ES_PREFIX=$(env_value SHOPWARE_ES_INDEX_PREFIX)
ES_PREFIX="${ES_PREFIX:-sw}"

# Abschnitte fortlaufend nummerieren. Fest verdrahtete Nummern springen,
# sobald ein Abschnitt uebersprungen wird (1 -> 2 -> 4).
SECTION_NO=0
section() {
    SECTION_NO=$((SECTION_NO + 1))
    echo "${SECTION_NO}. $1"
}

section "Konfiguration in .env / .env.local"
echo "   SHOPWARE_ES_ENABLED          = ${ES_ENABLED:-(nicht gesetzt)}"
echo "   SHOPWARE_ES_INDEXING_ENABLED = ${ES_INDEXING:-(nicht gesetzt)}"
echo "   OPENSEARCH_URL               = ${ES_URL:-(nicht gesetzt)}"
echo "   SHOPWARE_ES_INDEX_PREFIX     = ${ES_PREFIX}"
if [[ -f "${SHOP_PATH}/.env.local.php" ]]; then
    echo "   Achtung: .env.local.php vorhanden — sie hat Vorrang vor .env.local."
fi

if [[ -n "${ES_HOST_ARG}" ]]; then
    ES_BASE="${ES_HOST_ARG}"
elif [[ -n "${ES_URL}" ]]; then
    ES_BASE="${ES_URL%%,*}"
else
    ES_BASE="localhost:9200"
fi
case "${ES_BASE}" in
    http://*|https://*) : ;;
    *) ES_BASE="http://${ES_BASE}" ;;
esac

ISSUES=0


if [[ "${ES_ENABLED}" != "1" ]]; then
    echo "   Die Suche laeuft NICHT ueber Elasticsearch."
    ISSUES=$((ISSUES + 1))
fi

echo
section "Cluster unter ${ES_BASE}"
if ROOT=$(curl -sS --connect-timeout 5 "${ES_BASE}" 2>/dev/null) && [[ -n "${ROOT}" ]]; then
    VERSION=$(printf '%s' "${ROOT}" | grep -oE '"number"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    DISTRO=$(printf '%s' "${ROOT}" | grep -oE '"distribution"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "   erreichbar — ${DISTRO:-elasticsearch} ${VERSION:-?}"

    HEALTH=$(curl -sS "${ES_BASE}/_cluster/health" 2>/dev/null \
        | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || true)
    case "${HEALTH}" in
        green)  echo "   Cluster-Status: green" ;;
        yellow) echo "   Cluster-Status: yellow — bei einem einzelnen Knoten normal," ;;
        *)      echo "   Cluster-Status: ${HEALTH:-unbekannt}"; ISSUES=$((ISSUES + 1)) ;;
    esac
    if [[ "${HEALTH}" == "yellow" ]]; then
        echo "   weil die konfigurierten Replicas keinen zweiten Knoten finden."
    fi

    echo
    section "Shopware-Indizes (Praefix ${ES_PREFIX})"
    INDICES=$(curl -sS "${ES_BASE}/_cat/indices/${ES_PREFIX}*?h=index,docs.count,store.size" 2>/dev/null || true)
    if [[ -z "${INDICES}" ]]; then
        echo "   Keine Indizes mit diesem Praefix."
        ISSUES=$((ISSUES + 1))
    else
        printf '%s\n' "${INDICES}" | sed 's/^/   /'
    fi
else
    echo "   NICHT erreichbar."
    echo "   Gegenprobe: curl -v ${ES_BASE}"
    ISSUES=$((ISSUES + 1))
fi

if [[ -f "${SHOP_PATH}/bin/console" ]]; then
    echo
    section "Sicht von Shopware aus"
    if STATUS=$(php "${SHOP_PATH}/bin/console" es:status 2>&1); then
        printf '%s\n' "${STATUS}" | head -20 | sed 's/^/   /'
    else
        printf '%s\n' "${STATUS}" | head -5 | sed 's/^/   /'
        ISSUES=$((ISSUES + 1))
    fi
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Elasticsearch ist aktiv, erreichbar und hat Indizes."
    exit 0
fi

cat <<EOF
${ISSUES} Punkt(e) offen.

Einschalten geschieht ueber Umgebungsvariablen, nicht ueber eine eigene
config/packages/elasticsearch.yaml:

  # .env.local
  OPENSEARCH_URL=${ES_BASE#http://}
  SHOPWARE_ES_ENABLED=1
  SHOPWARE_ES_INDEXING_ENABLED=1
  SHOPWARE_ES_INDEX_PREFIX=${ES_PREFIX}

Danach den Index aufbauen:

  bin/console es:index --no-queue

Das --no-queue ist wichtig. Ohne den Schalter stellt es:index die
Indexing-Messages nur in die Queue und schwenkt den Alias nicht um; ohne
laufenden "messenger:consume async"-Worker passiert dann gar nichts.
Im Regelbetrieb laufen solche Worker ohnehin — dann ist der Queue-Weg der
richtige, und der Scheduled Task uebernimmt das Umschwenken.

Ein naechtlicher Vollindex per Cron ist nicht noetig: Aenderungen gehen
laufend inkrementell ueber die Queue.
EOF
exit 1
