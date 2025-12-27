#!/bin/bash
#
# Problem 8: Session-Lock Blocking
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# Testet ob parallele Requests sich gegenseitig blockieren.
# PHP-Sessions sind standardmäßig exklusiv gelockt.
#
# Verwendung: ./test-session-lock.sh [SHOP_URL]
#

set -e

SHOP_URL="${1:-https://localhost}"
TIMEOUT=10

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Session-Lock Blocking Test ==="
echo "URL: $SHOP_URL"
echo ""

# Test 1: Parallele Requests ohne Session
echo -n "Test 1: Parallele Requests (ohne Session)... "

START=$(date +%s.%N)
curl -s -o /dev/null -w "" "$SHOP_URL/" &
PID1=$!
curl -s -o /dev/null -w "" "$SHOP_URL/" &
PID2=$!
wait $PID1 $PID2
END=$(date +%s.%N)

TIME_PARALLEL=$(echo "$END - $START" | bc)
echo "Zeit: ${TIME_PARALLEL}s"

# Test 2: Sequentielle Requests zum Vergleich
echo -n "Test 2: Sequentielle Requests... "

START=$(date +%s.%N)
curl -s -o /dev/null "$SHOP_URL/"
curl -s -o /dev/null "$SHOP_URL/"
END=$(date +%s.%N)

TIME_SEQUENTIAL=$(echo "$END - $START" | bc)
echo "Zeit: ${TIME_SEQUENTIAL}s"

# Test 3: Parallele Requests MIT Session-Cookie
echo -n "Test 3: Parallele Requests (mit Session)... "

# Session starten und Cookie speichern
COOKIE_FILE=$(mktemp)
curl -s -c "$COOKIE_FILE" -o /dev/null "$SHOP_URL/checkout/cart" 2>/dev/null || true

START=$(date +%s.%N)
curl -s -b "$COOKIE_FILE" -o /dev/null "$SHOP_URL/checkout/cart" &
PID1=$!
curl -s -b "$COOKIE_FILE" -o /dev/null "$SHOP_URL/account" &
PID2=$!
wait $PID1 $PID2
END=$(date +%s.%N)

TIME_SESSION=$(echo "$END - $START" | bc)
echo "Zeit: ${TIME_SESSION}s"

rm -f "$COOKIE_FILE"

# Analyse
echo ""
echo "=== Analyse ==="

# Wenn Session-Zeit > 1.5x der parallelen Zeit ohne Session = Blocking
RATIO=$(echo "$TIME_SESSION / $TIME_PARALLEL" | bc -l 2>/dev/null || echo "0")
RATIO_INT=$(printf "%.0f" "$RATIO" 2>/dev/null || echo "0")

if [ "$RATIO_INT" -ge 2 ]; then
    echo -e "${RED}Session-Lock Blocking erkannt!${NC}"
    echo ""
    echo "Parallele Zeit mit Session ist ${RATIO_INT}x langsamer."
    echo ""
    echo "Empfohlene Lösungen:"
    echo "  1. Redis für Sessions verwenden:"
    echo "     framework.session.handler_id: 'redis://localhost:6379/0'"
    echo ""
    echo "  2. Session früh schließen:"
    echo "     session_write_close();"
    echo ""
    echo "  3. Read-only Session für lesende Requests"
    exit 1
elif [ "$RATIO_INT" -ge 1 ]; then
    echo -e "${YELLOW}Leichtes Blocking möglich.${NC}"
    echo "Ratio: ${RATIO_INT}x - Beobachten Sie unter Last."
    exit 0
else
    echo -e "${GREEN}Kein Session-Lock Blocking erkannt.${NC}"
    echo "Parallele Requests werden nicht blockiert."
    exit 0
fi
