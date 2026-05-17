#!/bin/bash
#
# Section 18.12 — OpenSearch counterpart to the ES 8.x RRF hybrid query.
#
# OpenSearch has NO RRF retriever. Hybrid search is a Search Pipeline with
# a normalization-processor: lexical (BM25) and neural queries run in
# parallel, scores are normalised (min_max) and combined (arithmetic_mean
# or an explicit weight like 0.3 * BM25 + 0.7 * neural).
#
# Trade-off vs. ES RRF: the weighting is EXPLICIT and configurable here
# (0.3 / 0.7), not implicit via rank_constant — at the cost of three
# pipeline components to maintain instead of one query.
#
# Sketch, not turnkey: a deployed text-embedding model id is required
# (register/deploy via the ml-commons plugin first). Verified against
# OpenSearch neural-search + hybrid-search docs (OpenSearch 2.x).
#
# Usage:  OS_URL=http://localhost:9200 MODEL_ID=<deployed-model> \
#           ./opensearch-hybrid-pipeline.sh
set -euo pipefail

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
