#!/bin/bash
#
# Section 18.8 — Slow-Log-Schwellen auf den Shopware-Indizes setzen.
#
# Warum ein Skript und kein Block in elasticsearch.yml: Seit Elasticsearch 5.x
# duerfen Index-Level-Settings nicht mehr in der Node-Konfiguration stehen. Ein
# `index.search.slowlog.*` in elasticsearch.yml laesst den Node mit
# «node settings must not contain any index level settings» und Exit-Code 1
# nicht starten (gemessen mit ES 8.15.3).
#
# Die Schwellen sind dynamische Index-Settings — sie lassen sich am offenen
# Index setzen, ohne Reindex und ohne Neustart.
#
# ACHTUNG beim Reindex: `bin/console es:index` legt jedes Mal einen frischen
# Index <alias>_<timestamp> an. Die hier gesetzten Werte wandern NICHT mit.
# Nach jedem Reindex erneut laufen lassen, oder die Schwellen dauerhaft ueber
# ein Index-Template hinterlegen.
#
# Usage:
#   ./slowlog-settings.sh [--dry-run] [--reset]
#
# Environment:
#   ES_URL         Default http://localhost:9200
#   INDEX_PREFIX   Default sw   (ohne Unterstrich — Shopware haengt ihn an)
#
# Exit codes:
#   0  Settings gesetzt
#   1  Aufrufe fehlgeschlagen / Cluster nicht erreichbar
#   2  Falscher Aufruf
set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
INDEX_PREFIX="${INDEX_PREFIX:-sw}"
DRY_RUN=0
RESET=0

usage() {
    sed -n '/^# Usage:/,/^#   2  /p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --reset)   RESET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

TARGET="${INDEX_PREFIX}_*"

if [[ "$RESET" -eq 1 ]]; then
    # null setzt ein Index-Setting auf den Default zurueck.
    BODY='{
  "index.search.slowlog.threshold.query.warn": null,
  "index.search.slowlog.threshold.query.info": null,
  "index.search.slowlog.threshold.query.debug": null,
  "index.search.slowlog.threshold.query.trace": null,
  "index.search.slowlog.threshold.fetch.warn": null,
  "index.search.slowlog.threshold.fetch.info": null,
  "index.search.slowlog.threshold.fetch.debug": null,
  "index.search.slowlog.threshold.fetch.trace": null,
  "index.indexing.slowlog.threshold.index.warn": null,
  "index.indexing.slowlog.threshold.index.info": null,
  "index.indexing.slowlog.threshold.index.debug": null,
  "index.indexing.slowlog.threshold.index.trace": null
}'
else
    BODY='{
  "index.search.slowlog.threshold.query.warn": "2s",
  "index.search.slowlog.threshold.query.info": "1s",
  "index.search.slowlog.threshold.query.debug": "500ms",
  "index.search.slowlog.threshold.query.trace": "200ms",
  "index.search.slowlog.threshold.fetch.warn": "1s",
  "index.search.slowlog.threshold.fetch.info": "500ms",
  "index.search.slowlog.threshold.fetch.debug": "200ms",
  "index.search.slowlog.threshold.fetch.trace": "100ms",
  "index.indexing.slowlog.threshold.index.warn": "10s",
  "index.indexing.slowlog.threshold.index.info": "5s",
  "index.indexing.slowlog.threshold.index.debug": "2s",
  "index.indexing.slowlog.threshold.index.trace": "500ms"
}'
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "PUT ${ES_URL}/${TARGET}/_settings"
    echo "$BODY"
    exit 0
fi

if ! curl -sf -o /dev/null "${ES_URL}/_cluster/health"; then
    echo "Cluster unter ${ES_URL} nicht erreichbar." >&2
    exit 1
fi

RESPONSE="$(curl -sS -X PUT "${ES_URL}/${TARGET}/_settings" \
    -H 'Content-Type: application/json' \
    -d "$BODY")"

if [[ "$RESPONSE" != *'"acknowledged":true'* ]]; then
    echo "Setzen der Slow-Log-Schwellen fehlgeschlagen:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

if [[ "$RESET" -eq 1 ]]; then
    echo "Slow-Log-Schwellen auf ${TARGET} zurueckgesetzt."
else
    echo "Slow-Log-Schwellen auf ${TARGET} gesetzt."
    echo "Log liegt unter path.logs als <cluster>_index_search_slowlog.json"
    echo "bzw. <cluster>_index_indexing_slowlog.json."
fi
