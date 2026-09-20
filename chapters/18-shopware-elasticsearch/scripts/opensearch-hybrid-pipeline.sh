#!/bin/bash
#
# Section 18.12 — OpenSearch counterpart to the ES 8.x RRF hybrid query.
#
# NICHT GEGEN OPENSEARCH GEFAHREN. Die Testmatrix dieses Kapitels ist
# Elasticsearch 8.15.3 (bewusste Entscheidung). Alles hier ist an der
# OpenSearch-Dokumentation und am Quelltext belegt, aber nicht gemessen —
# anders als die uebrigen Skripte dieses Ordners.
#
# OpenSearch kennt ZWEI Wege, und seit 2.19 auch RRF:
#
# 1. normalization-processor (ab 2.10): BM25 und neurale Abfrage laufen
#    parallel, die Scores werden normalisiert (min_max) und gewichtet
#    kombiniert (arithmetic_mean, z. B. 0.3 * BM25 + 0.7 * neural).
#    Die Gewichtung ist ausdruecklich und einstellbar — das ist der
#    Unterschied zu RRF, wo nur der Rang zaehlt.
# 2. score-ranker-processor (ab 2.19, neural-search, Apache-2.0): dieselbe
#    reziproke Rangfusion wie in Elasticsearch, nur als Pipeline-Prozessor
#    statt als retriever. Der Satz «OpenSearch hat kein RRF-Pendant» stimmte
#    bis 2.18 und ist seit Februar 2025 falsch.
#
# Dieses Skript zeigt Weg 1, weil die explizite Gewichtung der Punkt ist,
# an dem sich OpenSearch von ES unterscheidet. Der Preis: drei
# Pipeline-Bestandteile statt einer Abfrage.
#
# Anders als bei Elasticsearch ist beides Apache-2.0 und braucht keine
# Lizenzstufe — die RRF-Abfrage aus config/hybrid-rrf-query.json antwortet
# auf einem ES-Basic-Cluster mit HTTP 403.
#
# Sketch, not turnkey: a deployed text-embedding model id is required
# (register/deploy via the ml-commons plugin first).
#
# @see https://opensearch.org/blog/introducing-reciprocal-rank-fusion-hybrid-search/
# @see https://docs.opensearch.org/latest/search-plugins/search-pipelines/score-ranker-processor/
#
# Usage:  OS_URL=http://localhost:9200 MODEL_ID=<deployed-model> \
#           ./opensearch-hybrid-pipeline.sh
set -euo pipefail

# Der --help-Zweig MUSS vor die ${MODEL_ID:?}-Expansion. Stand er dahinter,
# antwortete `--help` mit «MODEL_ID: Set MODEL_ID to a deployed ...» statt mit
# der Hilfe.
case "${1:-}" in
    -h|--help)
        sed -n '/^# Usage:/,/^#           \.\/opensearch-hybrid-pipeline\.sh/p' "$0" \
            | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    ?*)
        echo "Unbekannte Option: $1" >&2
        exit 2
        ;;
esac

OS_URL="${OS_URL:-http://localhost:9200}"
MODEL_ID="${MODEL_ID:?Set MODEL_ID to a deployed ml-commons text-embedding model}"
INDEX="${INDEX:-sw_product_neural}"

# 1) Ingest pipeline — text_embedding processor fills knn_vector on write
curl -sf -X PUT "$OS_URL/_ingest/pipeline/product-embedding" \
  -H 'Content-Type: application/json' -d "{
    \"description\": \"Embed product description on write\",
    \"processors\": [
      { \"text_embedding\": {
          \"model_id\": \"$MODEL_ID\",
          \"field_map\": { \"description\": \"description_embedding\" } } }
    ] }"

# 2) Vector index — knn enabled, knn_vector field, pipeline as default
curl -sf -X PUT "$OS_URL/$INDEX" \
  -H 'Content-Type: application/json' -d '{
    "settings": { "index.knn": true,
                  "default_pipeline": "product-embedding" },
    "mappings": { "properties": {
      "name":        { "type": "text" },
      "description": { "type": "text" },
      "description_embedding": {
        "type": "knn_vector", "dimension": 384,
        "method": { "name": "hnsw", "engine": "lucene",
                    "space_type": "cosinesimil" } } } } }'

# 3) Search pipeline — normalization-processor (min_max + weighted mean)
curl -sf -X PUT "$OS_URL/_search/pipeline/hybrid-search" \
  -H 'Content-Type: application/json' -d '{
    "phase_results_processors": [
      { "normalization-processor": {
          "normalization": { "technique": "min_max" },
          "combination": {
            "technique": "arithmetic_mean",
            "parameters": { "weights": [0.3, 0.7] } } } }
    ] }'

echo "OpenSearch hybrid pipeline created."
echo "Query with: POST /$INDEX/_search?search_pipeline=hybrid-search"
echo "  body: { \"query\": { \"hybrid\": { \"queries\": ["
echo "    { \"match\": { \"description\": { \"query\": \"...\" } } },"
echo "    { \"neural\": { \"description_embedding\": {"
echo "        \"query_text\": \"...\", \"model_id\": \"$MODEL_ID\", \"k\": 50 } } }"
echo "  ] } } }"
