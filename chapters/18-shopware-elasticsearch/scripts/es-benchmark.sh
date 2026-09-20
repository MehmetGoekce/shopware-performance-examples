#!/bin/bash
#
# Elasticsearch Query Benchmark for Shopware 6
#
# Getestet gegen Shopware 6.6.10.6 und Elasticsearch 8.15.3.
#
# Was an der ersten Fassung falsch war — alles am laufenden Cluster gemessen:
#
# 1. Die Abfragen liefen gegen Felder, die es in Shopwares Produktindex nicht
#    gibt. `name` ist dort kein Feld, sondern ein Objekt mit einem Zweig je
#    Sprache (name.<languageId>, keyword, dazu .search und .ngram). Ein
#    {"match": {"name": "..."}} ist deshalb kein Fehler, sondern liefert
#    HTTP 200 mit NULL Treffern. Gemessen wurde also die Dauer einer Suche,
#    die nichts findet. Dasselbe fuer `description` und fuer `price` — das
#    Preisfeld heisst cheapest_price_rule<id>_currency<id>_gross.
# 2. Zwei der acht Abfragen waren syntaktisch kaputt (eine Klammer `]]` zu
#    viel). Elasticsearch antwortete mit HTTP 400; das Skript schrieb die
#    Antwort nach /dev/null, mass die Zeit und meldete «[EXCELLENT]».
# 3. `printf %8.2f` bricht in jeder Locale, die das Komma als Dezimaltrenner
#    nutzt: «printf: 3.02: Ungueltige Zahl», und wegen `set -e` endete der
#    Lauf nach dem ersten Test. Gemessen unter de_DE.UTF-8: Exit 1 nach Test 1;
#    unter LC_ALL=C liefen alle acht.
# 4. `bc` wird hier nicht mehr gebraucht (und fehlt in schlanken Images).
#    Rechnen und Formatieren macht awk unter LC_ALL=C.
# 5. Die Dokumentzahl kam aus `_cat/indices docs.count`. Das ist die Zahl der
#    LUCENE-Dokumente — verschachtelte Felder zaehlen mit (gemessen: 234 bei
#    14 Produkten). Hier steht jetzt `_count`.
#
# Usage:
#   ./es-benchmark.sh
#   ./es-benchmark.sh --iterations=20
#   ./es-benchmark.sh --index=sw_product --term=Hauptprodukt
#
# Environment:
#   ES_URL       default http://localhost:9200
#   ES_USER        optional, Basic Auth (ES 8.x hat Security ab Werk an)
#   ES_PASSWORD    optional
#   PRODUCT_NUMBER optional, sonst wird die erste aus dem Index genommen
#
# Requirements:
#   - curl
#   - jq

set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
INDEX="${INDEX:-sw_product}"
ITERATIONS="${ITERATIONS:-10}"
SEARCH_TERM="${SEARCH_TERM:-Hauptprodukt}"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --iterations=N   Number of iterations per test (default: 10)"
    echo "  --index=NAME     Index or alias to test (default: sw_product)"
    echo "  --term=WORD      Search term to use (default: Hauptprodukt)"
    echo "  --help           Show this help"
}

for arg in "$@"; do
    case ${arg} in
        --iterations=*) ITERATIONS="${arg#*=}" ;;
        --index=*) INDEX="${arg#*=}" ;;
        --term=*) SEARCH_TERM="${arg#*=}" ;;
        --help) usage; exit 0 ;;
        *)
            # Die erste Fassung dokumentierte `--iterations 20` mit Leerzeichen,
            # nahm aber nur `--iterations=20` an: Der Wert landete still im
            # Default. Lieber abbrechen als falsch messen.
            echo "Unknown argument: ${arg}" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! [[ "${ITERATIONS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --iterations needs a positive integer, got '${ITERATIONS}'" >&2
    exit 2
fi

for tool in curl jq awk; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
        echo "Error: ${tool} is required" >&2
        exit 3
    fi
done

CURL_OPTS=(-s --connect-timeout 5)
if [[ -n "${ES_USER:-}" ]]; then
    CURL_OPTS+=(-u "${ES_USER}:${ES_PASSWORD:-}")
fi

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

FINAL_EXIT=0

# Fuehrt eine Abfrage ITERATIONS-mal aus und meldet Wanduhr-Zeit und die
# Server-Zeit (`took`) getrennt. Die Differenz ist Netz, TLS und JSON-Parsen —
# bei einem lokalen Cluster wenige Millisekunden, ueber WAN der groessere Teil.
run_benchmark() {
    local name=$1
    local query=$2
    local times=() tooks=() body code wall took hits

    for ((i = 1; i <= ITERATIONS; i++)); do
        local response
        response=$(curl "${CURL_OPTS[@]}" -w '\n%{http_code} %{time_total}' \
            -X POST "${ES_URL}/${INDEX}/_search" \
            -H 'Content-Type: application/json' \
            -d "${query}") || {
            echo -e "   ${RED}[FAILED]${NC} ${name}: curl konnte den Cluster nicht erreichen"
            FINAL_EXIT=1
            return 0
        }

        code=$(echo "${response}" | tail -n1 | cut -d' ' -f1)
        wall=$(echo "${response}" | tail -n1 | cut -d' ' -f2)
        body=$(echo "${response}" | sed '$d')

        # Eine abgelehnte Abfrage ist kein Messwert. Ohne diese Pruefung
        # misst das Skript, wie schnell Elasticsearch Fehler zurueckweist.
        if [[ "${code}" != "200" ]]; then
            echo -e "   ${RED}[FAILED]${NC} ${name}: HTTP ${code} — $(echo "${body}" | jq -r '.error.reason // .error.type // .' | head -c 160)"
            FINAL_EXIT=1
            return 0
        fi

        took=$(echo "${body}" | jq -r '.took')
        hits=$(echo "${body}" | jq -r '.hits.total.value')
        times+=("${wall}")
        tooks+=("${took}")
    done

    # Rechnen und Formatieren in der C-Locale: awk und printf akzeptieren
    # sonst je nach Sprachumgebung den Punkt nicht als Dezimaltrenner.
    local stats
    stats=$(LC_ALL=C awk -v n="${ITERATIONS}" '
        { v[NR] = $1 * 1000; sum += v[NR] }
        END {
            avg = sum / n
            min = v[1]; max = v[1]
            for (i = 1; i <= n; i++) {
                if (v[i] < min) min = v[i]
                if (v[i] > max) max = v[i]
                d = v[i] - avg; sq += d * d
            }
            printf "%.2f %.2f %.2f %.2f", avg, min, max, sqrt(sq / n)
        }' <<< "$(printf '%s\n' "${times[@]}")")

    local took_avg
    took_avg=$(LC_ALL=C awk -v n="${ITERATIONS}" '{ s += $1 } END { printf "%.1f", s / n }' <<< "$(printf '%s\n' "${tooks[@]}")")

    # shellcheck disable=SC2086
    set -- ${stats}
    echo -e "   ${GREEN}[OK]${NC} ${name}"
    LC_ALL=C printf '     wall avg %8.2f ms   min %8.2f   max %8.2f   stddev %6.2f\n' "$1" "$2" "$3" "$4"
    LC_ALL=C printf '     took avg %8.1f ms   hits %s\n' "${took_avg}" "${hits}"
    echo ""
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Elasticsearch Query Benchmark${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "URL:        ${ES_URL}"
echo "Index:      ${INDEX}"
echo "Iterations: ${ITERATIONS}"
echo "Term:       ${SEARCH_TERM}"
echo ""

COUNT_RESPONSE=$(curl "${CURL_OPTS[@]}" -w '\n%{http_code}' "${ES_URL}/${INDEX}/_count")
COUNT_CODE=$(echo "${COUNT_RESPONSE}" | tail -n1)
if [[ "${COUNT_CODE}" != "200" ]]; then
    echo -e "${RED}Error: ${INDEX} lieferte HTTP ${COUNT_CODE} auf _count${NC}" >&2
    exit 4
fi
DOC_COUNT=$(echo "${COUNT_RESPONSE}" | sed '$d' | jq -r '.count')
if [[ "${DOC_COUNT}" = "0" ]]; then
    echo -e "${RED}Error: ${INDEX} ist leer${NC}" >&2
    exit 4
fi
echo "Documents:  ${DOC_COUNT} (_count, also Entitaeten — nicht docs.count)"

# Tests 2 und 6 brauchen eine Artikelnummer, die es wirklich gibt — sonst
# messen sie eine Suche ohne Treffer. Die erste aus dem Index nehmen, wenn
# keine vorgegeben ist.
if [[ -z "${PRODUCT_NUMBER:-}" ]]; then
    PRODUCT_NUMBER=$(curl "${CURL_OPTS[@]}" -X POST "${ES_URL}/${INDEX}/_search" \
        -H 'Content-Type: application/json' \
        -d '{"size": 0, "aggs": {"pn": {"terms": {"field": "productNumber", "size": 1}}}}' \
        | jq -r '.aggregations.pn.buckets[0].key // empty')
fi
if [[ -z "${PRODUCT_NUMBER}" ]]; then
    echo -e "${RED}Error: keine productNumber im Index — ist das ein Shopware-Produktindex?${NC}" >&2
    exit 4
fi
echo "Artikelnr.: ${PRODUCT_NUMBER} (fuer Test 2 und 6)"
echo ""

echo -e "${YELLOW}Warming up (3 requests)...${NC}"
for _ in 1 2 3; do
    curl "${CURL_OPTS[@]}" -o /dev/null "${ES_URL}/${INDEX}/_search?size=1" || true
done
echo ""

echo -e "${YELLOW}Running benchmarks...${NC}"
echo ""

# Test 1: Volltext ueber alle Sprachzweige.
# Der Feld-Platzhalter name.*.search trifft jeden Sprachzweig — ohne ihn
# muesste hier eine konkrete languageId stehen, die von Shop zu Shop anders ist.
echo -e "${BLUE}Test 1: Multi-Match (name.*.search)${NC}"
run_benchmark "Multi-Match" '{
    "query": {
        "multi_match": {
            "query": "'"${SEARCH_TERM}"'",
            "fields": ["name.*.search^3", "description.*.search"]
        }
    },
    "size": 20
}'

# Test 2: Der schnellste Weg zum exakten Treffer.
# productNumber ist keyword mit sw_lowercase_normalizer; der term-Query wird
# NICHT analysiert. Der Wert kommt deshalb aus der Aggregation oben — also
# schon in der Form, in der er im Index steht (klein geschrieben).
echo -e "${BLUE}Test 2: Term Query (productNumber, exakt)${NC}"
run_benchmark "Term" '{
    "query": {
        "term": {
            "productNumber": "'"${PRODUCT_NUMBER}"'"
        }
    },
    "size": 20
}'

# Test 3: Wie die Storefront sucht — Textklausel als must, Sichtbarkeit und
# Bestand als filter (kein Scoring, cachebar).
echo -e "${BLUE}Test 3: Bool (must + filter)${NC}"
run_benchmark "Bool + Filter" '{
    "query": {
        "bool": {
            "must": [
                {"multi_match": {"query": "'"${SEARCH_TERM}"'", "fields": ["name.*.search"]}}
            ],
            "filter": [
                {"term": {"active": true}},
                {"range": {"stock": {"gt": 0}}}
            ]
        }
    },
    "size": 20
}'

# Test 4: Facette auf einem keyword-Feld (Kategorien im Listing).
echo -e "${BLUE}Test 4: Terms Aggregation (categoryIds)${NC}"
run_benchmark "Aggregation" '{
    "size": 0,
    "aggs": {
        "categories": {
            "terms": {"field": "categoryIds", "size": 50}
        }
    }
}'

# Test 5: Facette ueber ein nested-Feld. Deutlich teurer als Test 4 — Shopware
# legt properties, categories, options und visibilities als nested an.
echo -e "${BLUE}Test 5: Nested Aggregation (properties)${NC}"
run_benchmark "Nested Aggs" '{
    "size": 0,
    "aggs": {
        "properties": {
            "nested": {"path": "properties"},
            "aggs": {
                "ids": {"terms": {"field": "properties.id", "size": 50}}
            }
        }
    }
}'

# Test 6: Fuehrende Wildcard. Der Gegenbeweis zu Test 1 — sie kann keinen
# Index nutzen und wird mit dem Katalog linear teurer.
echo -e "${BLUE}Test 6: Wildcard (leading, typically slow)${NC}"
run_benchmark "Wildcard" '{
    "query": {
        "wildcard": {
            "productNumber": {"value": "*'"${PRODUCT_NUMBER: -4}"'*"}
        }
    },
    "size": 20
}'

# Test 7: Tippfehlertoleranz. fuzziness kostet, weil ES je Term die
# Varianten aufzaehlt.
echo -e "${BLUE}Test 7: Fuzzy (typo tolerance)${NC}"
run_benchmark "Fuzzy" '{
    "query": {
        "multi_match": {
            "query": "'"${SEARCH_TERM}"'",
            "fields": ["name.*.search"],
            "fuzziness": "AUTO"
        }
    },
    "size": 20
}'

# Test 8: Grosse Trefferliste. Zeigt, was allein das Einsammeln und
# Serialisieren der Treffer kostet.
echo -e "${BLUE}Test 8: Large Result Set (100 hits)${NC}"
run_benchmark "100 Results" '{
    "query": {"match_all": {}},
    "size": 100
}'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Benchmark Complete${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Die Zahlen gelten fuer diesen Katalog auf dieser Maschine. Ohne die"
echo "Zahl der Dokumente, die Shard-Zahl und die Hardware daneben sind sie"
echo "nicht vergleichbar — und ein Katalog mit 14 Demo-Produkten sagt ueber"
echo "einen mit 200'000 nichts aus."
echo ""
echo "Tips:"
echo "  - Fuehrende Wildcards (Test 6) nutzen keinen Index; fuer"
echo "    Teilwort-Treffer das .ngram-Subfeld verwenden, das Shopware anlegt."
echo "  - Ja/Nein-Bedingungen in den filter-Kontext (Test 3): kein Scoring,"
echo "    und der Filter-Cache greift."
echo "  - Aggregationen auf nested-Feldern (Test 5) sind die teuersten"
echo "    Facetten im Shopware-Mapping."
echo "  - doc_values sind fuer keyword-Felder ab Werk an; fielddata ist fuer"
echo "    text-Felder gedacht und im Shopware-Mapping nicht noetig."
echo ""

exit "${FINAL_EXIT}"
