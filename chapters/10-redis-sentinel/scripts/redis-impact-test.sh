#!/bin/bash
#
# Redis Impact Test
# Simuliert Redis-Ausfall und misst die Auswirkung auf den Shop
#
# Verwendung: ./redis-impact-test.sh [URL]
#
# WARNUNG: Stoppt Redis temporaer! Nur in Staging/Test verwenden.
#
# Voraussetzungen:
#   - Apache Benchmark (ab) installiert: sudo apt install apache2-utils
#   - Root-Rechte fuer Redis-Dienst
#   - URL sollte eine dynamische Seite sein (nicht gecached)

URL="${1:-http://localhost/}"
REQUESTS=50
CONCURRENCY=5

echo "=== Redis Impact Test ==="
echo ""
echo "WARNUNG: Dieser Test stoppt Redis temporaer!"
echo "         Nur in Test-/Staging-Umgebungen ausfuehren!"
echo ""
echo "URL: ${URL}"
echo "Requests: ${REQUESTS}"
echo "Concurrency: ${CONCURRENCY}"
echo ""

# Pruefungen
if ! command -v ab &> /dev/null; then
    echo "FEHLER: Apache Benchmark (ab) nicht installiert!"
    echo "        sudo apt install apache2-utils"
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "FEHLER: Root-Rechte erforderlich fuer Redis-Dienst"
    echo "        sudo ./redis-impact-test.sh"
    exit 1
fi

# Redis-Status pruefen
if ! systemctl is-active --quiet redis-server; then
    echo "FEHLER: Redis laeuft nicht!"
    exit 1
fi

read -p "Test starten? (y/N) " -n 1 -r
echo
if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
    echo "Abgebrochen."
    exit 0
fi

echo ""
echo "=== Test 1: Mit Redis (Baseline) ==="
echo ""

# Warmup
curl -s "${URL}" > /dev/null
curl -s "${URL}" > /dev/null

# Baseline-Test
RESULT_WITH=$(ab -n ${REQUESTS} -c ${CONCURRENCY} "${URL}" 2>/dev/null)
RPS_WITH=$(echo "${RESULT_WITH}" | grep "Requests per second" | awk '{print $4}')
TIME_WITH=$(echo "${RESULT_WITH}" | grep "Time per request" | head -1 | awk '{print $4}')

echo "Requests per second: ${RPS_WITH}"
echo "Time per request:    ${TIME_WITH} ms"

echo ""
echo "=== Stoppe Redis temporaer... ==="
systemctl stop redis-server
sleep 2

echo ""
echo "=== Test 2: OHNE Redis ==="
echo ""

# Test ohne Redis
RESULT_WITHOUT=$(ab -n ${REQUESTS} -c ${CONCURRENCY} "${URL}" 2>/dev/null)
RPS_WITHOUT=$(echo "${RESULT_WITHOUT}" | grep "Requests per second" | awk '{print $4}')
TIME_WITHOUT=$(echo "${RESULT_WITHOUT}" | grep "Time per request" | head -1 | awk '{print $4}')

echo "Requests per second: ${RPS_WITHOUT}"
echo "Time per request:    ${TIME_WITHOUT} ms"

echo ""
echo "=== Starte Redis wieder... ==="
systemctl start redis-server
sleep 2

# Ergebnis berechnen
if [[ -n "${RPS_WITH}" ]] && [[ -n "${RPS_WITHOUT}" ]]; then
    DIFF=$(echo "${RPS_WITH} ${RPS_WITHOUT}" | awk '{
        if ($2 > 0) {
            diff = (($1 - $2) / $2) * 100
            printf "%.0f", diff
        }
    }')

    SLOWDOWN=$(echo "${TIME_WITH} ${TIME_WITHOUT}" | awk '{
        if ($1 > 0) {
            factor = $2 / $1
            printf "%.1f", factor
        }
    }')
fi

echo ""
echo "==========================================="
echo "=== ERGEBNIS ==="
echo "==========================================="
echo ""
echo "                  Mit Redis    Ohne Redis"
echo "Requests/Sek:     ${RPS_WITH}         ${RPS_WITHOUT}"
echo "Response Time:    ${TIME_WITH}ms       ${TIME_WITHOUT}ms"
echo ""
echo "Performance-Verlust ohne Redis: ~${SLOWDOWN}x langsamer"
echo ""
echo "==========================================="
echo ""
echo "Fazit: Ohne Redis ist Ihr Shop bei Last nicht ueberlebensfaehig."
echo "       Sentinel-Setup ist dringend empfohlen!"
