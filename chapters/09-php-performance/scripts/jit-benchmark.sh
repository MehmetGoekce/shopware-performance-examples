#!/bin/bash
#
# JIT-Benchmark fuer Shopware
# Vergleicht Performance mit und ohne JIT
#
# Verwendung: ./jit-benchmark.sh [URL]
#
# Voraussetzungen:
#   - Apache Benchmark (ab) installiert
#   - Root-Zugriff fuer PHP-FPM Restart
#
# Hinweis: JIT bringt fuer typische Web-Requests meist < 5% Verbesserung.
# Siehe: https://stitcher.io/blog/jit-in-real-life-web-applications

# =============================================================================
# KONFIGURATION
# =============================================================================

URL="${1:-http://localhost/}"
REQUESTS=100
CONCURRENCY=10
PHP_VERSION="8.3"
OPCACHE_INI="/etc/php/${PHP_VERSION}/fpm/conf.d/99-shopware-opcache.ini"

# =============================================================================
# PRUEFUNGEN
# =============================================================================

echo "=== JIT Benchmark ==="
echo ""

# Apache Benchmark vorhanden?
if ! command -v ab &> /dev/null; then
    echo "FEHLER: Apache Benchmark (ab) nicht installiert!"
    echo "        sudo apt install apache2-utils"
    exit 1
fi

# Root-Rechte?
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Root-Rechte erforderlich fuer PHP-FPM Neustart"
    echo "        sudo ./jit-benchmark.sh"
    exit 1
fi

# OPcache-Konfiguration vorhanden?
if [ ! -f "$OPCACHE_INI" ]; then
    echo "FEHLER: OPcache-Konfiguration nicht gefunden: $OPCACHE_INI"
    exit 1
fi

echo "URL:         $URL"
echo "Requests:    $REQUESTS"
echo "Concurrency: $CONCURRENCY"
echo ""

# =============================================================================
# WARMUP
# =============================================================================

echo "Warmup..."
curl -s "$URL" > /dev/null
curl -s "$URL" > /dev/null
sleep 1

# =============================================================================
# TEST MIT JIT
# =============================================================================

echo ""
echo "=== Test 1: MIT JIT ==="

# JIT aktivieren falls noetig
if ! grep -q "opcache.jit=tracing" "$OPCACHE_INI"; then
    sed -i 's/opcache.jit=.*/opcache.jit=tracing/' "$OPCACHE_INI"
    systemctl reload php${PHP_VERSION}-fpm
    sleep 2
    # Warmup
    curl -s "$URL" > /dev/null
    curl -s "$URL" > /dev/null
fi

RPS_WITH_JIT=$(ab -n $REQUESTS -c $CONCURRENCY "$URL" 2>/dev/null | grep "Requests per second" | awk '{print $4}')
echo "Requests per second: $RPS_WITH_JIT"

# =============================================================================
# TEST OHNE JIT
# =============================================================================

echo ""
echo "=== Test 2: OHNE JIT ==="

# JIT deaktivieren
sed -i 's/opcache.jit=tracing/opcache.jit=off/' "$OPCACHE_INI"
systemctl reload php${PHP_VERSION}-fpm
sleep 2

# Warmup
curl -s "$URL" > /dev/null
curl -s "$URL" > /dev/null

RPS_WITHOUT_JIT=$(ab -n $REQUESTS -c $CONCURRENCY "$URL" 2>/dev/null | grep "Requests per second" | awk '{print $4}')
echo "Requests per second: $RPS_WITHOUT_JIT"

# =============================================================================
# JIT WIEDER AKTIVIEREN
# =============================================================================

sed -i 's/opcache.jit=off/opcache.jit=tracing/' "$OPCACHE_INI"
systemctl reload php${PHP_VERSION}-fpm

# =============================================================================
# ERGEBNIS
# =============================================================================

echo ""
echo "=== ERGEBNIS ==="
echo ""
echo "Mit JIT:    $RPS_WITH_JIT req/s"
echo "Ohne JIT:   $RPS_WITHOUT_JIT req/s"

# Differenz berechnen (bash kann keine Floats, daher awk)
DIFF=$(echo "$RPS_WITH_JIT $RPS_WITHOUT_JIT" | awk '{
    if ($2 > 0) {
        diff = (($1 - $2) / $2) * 100
        printf "%.1f", diff
    } else {
        print "N/A"
    }
}')

echo "Unterschied: ${DIFF}%"
echo ""

# Empfehlung
if (( $(echo "$DIFF < 3" | bc -l 2>/dev/null || echo "1") )); then
    echo "Empfehlung: JIT bringt fuer diesen Workload kaum Vorteile."
    echo "            Sie koennen JIT aktiviert lassen (schadet nicht),"
    echo "            aber erwarten Sie keine Wunder."
else
    echo "Empfehlung: JIT zeigt messbaren Vorteil. Aktiviert lassen!"
fi
