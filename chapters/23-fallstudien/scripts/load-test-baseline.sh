#!/bin/bash
#
# Load-Test Baseline erstellen - Alle Fallstudien
# Kapitel 23: Reale Fallstudien aus 26 Jahren
#
# Erstellt Performance-Baseline vor Optimierungen.
# Verwendet ab (Apache Benchmark) oder wrk.
#

SHOP_URL="${1:-https://localhost}"
REQUESTS="${2:-1000}"
CONCURRENCY="${3:-10}"
OUTPUT_DIR="${4:-./baseline-results}"

mkdir -p "${OUTPUT_DIR}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="${OUTPUT_DIR}/baseline_${TIMESTAMP}.txt"

echo "=== Load-Test Baseline ===" | tee "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "URL: ${SHOP_URL}" | tee -a "${RESULT_FILE}"
echo "Requests: ${REQUESTS}" | tee -a "${RESULT_FILE}"
echo "Concurrency: ${CONCURRENCY}" | tee -a "${RESULT_FILE}"
echo "Timestamp: ${TIMESTAMP}" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"

# Tool-Auswahl
if command -v wrk &> /dev/null; then
    TOOL="wrk"
elif command -v ab &> /dev/null; then
    TOOL="ab"
else
    echo "Fehler: Weder 'wrk' noch 'ab' installiert."
    echo "Installation: apt install apache2-utils (für ab)"
    exit 1
fi

echo "Tool: ${TOOL}" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"

# Test-URLs
URLS=(
    "/"
    "/navigation"
    "/account/login"
)

for path in "${URLS[@]}"; do
    url="${SHOP_URL}${path}"
    echo "--- Testing: ${path} ---" | tee -a "${RESULT_FILE}"

    if [[ "${TOOL}" = "wrk" ]]; then
        wrk -t4 -c"${CONCURRENCY}" -d30s "${url}" 2>&1 | tee -a "${RESULT_FILE}"
    else
        ab -n "${REQUESTS}" -c "${CONCURRENCY}" -k "${url}" 2>&1 | \
            grep -E "Requests per second|Time per request|Transfer rate|Failed requests" | \
            tee -a "${RESULT_FILE}"
    fi

    echo "" | tee -a "${RESULT_FILE}"
done

# Zusammenfassung
echo "=== Zusammenfassung ===" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "Baseline gespeichert: ${RESULT_FILE}" | tee -a "${RESULT_FILE}"
echo "" | tee -a "${RESULT_FILE}"
echo "Nächste Schritte:" | tee -a "${RESULT_FILE}"
echo "1. Optimierungen durchführen" | tee -a "${RESULT_FILE}"
echo "2. Test wiederholen: $0 ${SHOP_URL} ${REQUESTS} ${CONCURRENCY} ${OUTPUT_DIR}" | tee -a "${RESULT_FILE}"
echo "3. Ergebnisse vergleichen" | tee -a "${RESULT_FILE}"
