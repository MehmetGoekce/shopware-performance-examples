#!/bin/bash
#
# Elasticsearch Reindex Script for Shopware 6
#
# Getestet gegen Shopware 6.6.10.6 und Elasticsearch 8.15.3.
#
# Was dieses Skript NICHT mehr tut, und warum — drei Dinge, die in der
# ersten Fassung standen und gegen den laufenden Shop gemessen wurden:
#
# 1. KEIN refresh_interval-Wrapper mehr um es:index.
#    Das Muster «refresh_interval auf -1, indexieren, zurueck auf 5s» ist
#    fuer Shopware-Reindexe wirkungslos: es:index schreibt nicht in die
#    bestehenden Indizes, sondern legt fuer jede Entitaet einen NEUEN an
#    (<alias>_<timestamp>, ElasticsearchIndexer.php:191-202). Das vorher
#    gesetzte -1 trifft nur die alten. Und nach dem Alias-Swap setzt
#    Shopware refresh_interval selbst — auf null, also den ES-Default,
#    nicht auf den vorher gesetzten Wert (CreateAliasTaskHandler.php:109).
#    Gemessen: konfigurierte 5s, nach dem Swap stand dort null.
#    Wer den Wert fuer den Aufbau steuern will, setzt ihn dort, wo er beim
#    Anlegen greift: elasticsearch.index_settings.refresh_interval in
#    config/packages/elasticsearch.yaml.
#
# 2. es:create:alias laeuft jetzt NACH dem Indexieren, nicht davor.
#    Davor ist es im besten Fall wirkungslos und im schlechtesten schaedlich:
#    Der Befehl schwenkt den Alias auf das, was in elasticsearch_index_task
#    steht — vor dem Lauf also auf einen Index aus einem frueheren Durchgang.
#
# 3. Force-Merge ist OPT-IN (--force-merge), nicht mehr Standard.
#    Elastic: «We recommend only force merging a read-only index (meaning
#    the index is no longer receiving writes).» Ein Shopware-Index wird im
#    Live-Betrieb laufend beschrieben. Force-Merge auf max_num_segments=1
#    erzeugt dort Segmente ueber 5 GB, die fuer regulaere Merges nicht mehr
#    in Frage kommen; geloeschte Dokumente sammeln sich darin an.
#
# Usage:
#   ./es-reindex.sh
#   ./es-reindex.sh --force          # ohne Rueckfrage
#   ./es-reindex.sh --parallel       # ueber die Queue statt --no-queue
#   ./es-reindex.sh --force-merge    # Force-Merge am Ende (siehe Punkt 3)
#   ./es-reindex.sh --cleanup        # Indizes der Vorlaeufe loeschen
#
# Environment:
#   SHOPWARE_ROOT  Default /var/www/html
#   ES_URL         Default http://localhost:9200
#   INDEX_PREFIX   Default sw   (OHNE Unterstrich — Shopware haengt ihn an;
#                  'sw_' ergibt den Alias sw__product)
#
# Exit codes:
#   0  Reindex durch
#   1  Voraussetzung fehlt / Cluster nicht erreichbar / Queue nicht leer
#   2  Falscher Aufruf
#
# Requirements: Shopware 6 CLI (bin/console), curl, jq

set -euo pipefail

SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
ES_URL="${ES_URL:-http://localhost:9200}"
INDEX_PREFIX="${INDEX_PREFIX:-sw}"
FORCE="${FORCE:-false}"
PARALLEL="${PARALLEL:-false}"
FORCE_MERGE="${FORCE_MERGE:-false}"
CLEANUP="${CLEANUP:-false}"
QUEUE_TIMEOUT="${QUEUE_TIMEOUT:-600}"

usage() {
    sed -n '/^# Usage:/,/^#   2  /p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case ${arg} in
        --force)       FORCE=true ;;
        --parallel)    PARALLEL=true ;;
        --force-merge) FORCE_MERGE=true ;;
        --cleanup)     CLEANUP=true ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "Unbekannte Option: ${arg}" >&2; usage >&2; exit 2 ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INDEX_GLOB="${INDEX_PREFIX}_*"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Reindex for Shopware 6${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Shopware: ${SHOPWARE_ROOT}"
echo "ES URL:   ${ES_URL}"
echo "Prefix:   ${INDEX_PREFIX}  (Indizes: ${INDEX_GLOB})"
echo ""

cd "${SHOPWARE_ROOT}"

if [[ ! -f "bin/console" ]]; then
    echo -e "${RED}Fehler: bin/console nicht unter ${SHOPWARE_ROOT}${NC}" >&2
    exit 1
fi

if ! curl -sf --connect-timeout 5 -o /dev/null "${ES_URL}/_cluster/health"; then
    echo -e "${RED}Fehler: Cluster unter ${ES_URL} nicht erreichbar${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Aktueller Stand:${NC}"
curl -s "${ES_URL}/_cat/indices/${INDEX_GLOB}?v&h=index,docs.count,store.size" || echo "keine Indizes"
echo ""

if [[ "${FORCE}" != "true" ]]; then
    read -r -p "Vollreindex starten? Das dauert je nach Katalog mehrere Minuten. [y/N] " -n 1 REPLY
    echo
    if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
        echo "Abgebrochen."
        exit 0
    fi
fi

START_TIME=$(date +%s)

# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}Schritt 1/3: Indexierung${NC}"
echo ""

if [[ "${PARALLEL}" = "true" ]]; then
    echo "Queue-Modus: es:index stellt die Arbeit ein, ein Worker holt sie ab."
    bin/console es:index

    bin/console messenger:consume async \
        --time-limit="${QUEUE_TIMEOUT}" --memory-limit=512M --quiet &
    WORKER_PID=$!

    # messenger:count gibt es nicht. Der Befehl heisst messenger:stats und
    # liefert mit --format=json {"transports":{"async":{"count":N}}}.
    WAITED=0
    while true; do
        QUEUE_SIZE="$(bin/console messenger:stats async --format=json 2>/dev/null \
            | jq -r '.transports.async.count // 0')"
        if [[ "${QUEUE_SIZE}" == "0" ]]; then
            break
        fi
        if [[ "${WAITED}" -ge "${QUEUE_TIMEOUT}" ]]; then
            echo -e "${RED}Queue nach ${QUEUE_TIMEOUT}s nicht leer (${QUEUE_SIZE} offen).${NC}" >&2
            kill "${WORKER_PID}" 2>/dev/null || true
            exit 1
        fi
        echo "Queue: ${QUEUE_SIZE} offen — warte ..."
        sleep 10
        WAITED=$((WAITED + 10))
    done

    kill "${WORKER_PID}" 2>/dev/null || true
    wait "${WORKER_PID}" 2>/dev/null || true
else
    echo "Synchron (--no-queue): der Befehl kehrt erst zurueck, wenn alles drin ist."
    bin/console es:index --no-queue
fi

# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}Schritt 2/3: Alias schwenken${NC}"
# Erst jetzt: der Swap setzt voraus, dass der neue Index gefuellt ist
# (CreateAliasTaskHandler prueft doc_count == 0 in elasticsearch_index_task).
# Im Normalbetrieb erledigt das der Scheduled Task; hier ziehen wir ihn vor,
# damit das Skript einen definierten Zustand hinterlaesst.
bin/console es:create:alias
curl -s "${ES_URL}/_cat/aliases/${INDEX_GLOB}?h=alias,index" || true

# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}Schritt 3/3: Abschluss${NC}"
curl -s -X POST "${ES_URL}/${INDEX_GLOB}/_refresh" > /dev/null

if [[ "${FORCE_MERGE}" = "true" ]]; then
    echo "Force-Merge auf max_num_segments=1 (nur sinnvoll, wenn in diesen"
    echo "Index bis zum naechsten Reindex nichts mehr geschrieben wird)."
    curl -s -X POST "${ES_URL}/${INDEX_GLOB}/_forcemerge?max_num_segments=1" \
        | jq -r '._shards.successful // "fehlgeschlagen"'
else
    echo "Kein Force-Merge (mit --force-merge anfordern, siehe Kopf des Skripts)."
fi

# Aufraeumen: Shopware laesst die Indizes der Vorlaeufe stehen. Das Loeschen
# ist bewusst opt-in (--cleanup).
#
# ACHTUNG, die beiden Befehle verhalten sich GEGENSAETZLICH:
#   es:index:cleanup braucht -f/--force. Mit --no-interaction bricht er ab
#     («Deletion aborted») — die Rueckfrage hat dort NEIN als Vorgabe.
#   es:reset dagegen hat JA als Vorgabe; ein --no-interaction loescht dort.
if [[ "${CLEANUP}" = "true" ]]; then
    bin/console es:index:cleanup --force
else
    OLD_COUNT="$(curl -s "${ES_URL}/_cat/indices/${INDEX_GLOB}?h=index" | wc -l)"
    if [[ "${OLD_COUNT}" -gt 1 ]]; then
        echo "${OLD_COUNT} Indizes unter ${INDEX_GLOB}; die Vorlaeufer bleiben"
        echo "liegen. Loeschen: ./es-reindex.sh --cleanup oder"
        echo "bin/console es:index:cleanup --force"
    fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Reindex abgeschlossen${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Dauer: ${DURATION} Sekunden"
echo ""
echo -e "${YELLOW}Neuer Stand:${NC}"
curl -s "${ES_URL}/_cat/indices/${INDEX_GLOB}?v&h=index,docs.count,store.size"
echo ""
# docs.count zaehlt Lucene-Dokumente inklusive der verschachtelten Felder und
# liegt deshalb deutlich ueber der Produktzahl. Die steht in _count.
PRODUCTS="$(curl -s "${ES_URL}/${INDEX_PREFIX}_product/_count" | jq -r '.count // "n/a"')"
echo "Produkte hinter dem Alias ${INDEX_PREFIX}_product: ${PRODUCTS}"
echo ""

HEALTH="$(curl -s "${ES_URL}/_cluster/health" | jq -r '.status')"
case "${HEALTH}" in
    green)  echo -e "Cluster: ${GREEN}${HEALTH}${NC}" ;;
    yellow) echo -e "Cluster: ${YELLOW}${HEALTH}${NC}"
            echo "  (Ein Einzelknoten steht mit Shopwares Replica-Default 3"
            echo "   dauerhaft auf yellow — dann gehoert number_of_replicas: 0"
            echo "   in elasticsearch.index_settings.)" ;;
    red)    echo -e "Cluster: ${RED}${HEALTH}${NC}" ;;
esac
echo ""
