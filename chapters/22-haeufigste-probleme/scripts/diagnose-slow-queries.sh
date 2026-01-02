#!/bin/bash
#
# Problem 1: Langsame Datenbankabfragen diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_PATH="${2:-.}"

echo "=== Problem 1: Langsame Datenbankabfragen ==="
echo ""

# Check 1: Slow Query Log Status
echo "1. Slow Query Log Status prüfen..."
if [[ -f "${SHOP_PATH}/.env" ]]; then
    DB_HOST=$(grep DATABASE_URL "${SHOP_PATH}/.env" | sed -n 's/.*@\([^:]*\).*/\1/p')
    echo "   Database Host: ${DB_HOST:-localhost}"
fi

# Check 2: Langsame Queries im Log suchen
SLOW_LOG="/var/log/mysql/slow.log"
if [[ -f "${SLOW_LOG}" ]]; then
    SLOW_COUNT=$(tail -1000 "${SLOW_LOG}" 2>/dev/null | grep -c "Query_time" || echo "0")
    echo "   Langsame Queries (letzte 1000 Zeilen): ${SLOW_COUNT}"

    if [[ "${SLOW_COUNT}" -gt 50 ]]; then
        echo ""
        echo "   ⚠ Zu viele langsame Queries!"
        echo ""
        echo "   Top 5 langsamste Queries:"
        tail -1000 "${SLOW_LOG}" 2>/dev/null | grep -A1 "Query_time" | head -20
        exit 1
    fi
else
    echo "   ⚠ Slow Query Log nicht gefunden: ${SLOW_LOG}"
fi

# Check 3: Fehlende Indizes prüfen (wenn mysql verfügbar)
echo ""
echo "2. Empfohlene Indizes für Shopware 6..."
echo ""
cat << 'EOF'
-- Wichtige Indizes für Performance:

-- Product-Suche
CREATE INDEX IF NOT EXISTS idx_product_name ON product(name(191));
CREATE INDEX IF NOT EXISTS idx_product_active ON product(active, available_stock);

-- Order-Abfragen
CREATE INDEX IF NOT EXISTS idx_order_state ON `order`(state_id, order_date_time);
CREATE INDEX IF NOT EXISTS idx_order_customer ON `order`(customer_id);

-- Session-Performance
CREATE INDEX IF NOT EXISTS idx_session_modified ON session(modified);

-- Customer-Suche
CREATE INDEX IF NOT EXISTS idx_customer_email ON customer(email);
EOF

# Check 4: Aktuelle Query-Performance
echo ""
echo "3. MySQL Status prüfen..."
echo ""
echo "   Führen Sie folgende Queries in MySQL aus:"
echo ""
cat << 'EOF'
-- Aktive Queries anzeigen
SHOW PROCESSLIST;

-- Tabellen-Status prüfen
SHOW TABLE STATUS WHERE Data_length > 100000000;

-- Fehlende Indizes finden
SELECT
    TABLE_NAME,
    INDEX_NAME,
    CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
ORDER BY CARDINALITY DESC
LIMIT 20;
EOF

echo ""
echo "=== Diagnose abgeschlossen ==="
echo ""
echo "Lösung: Siehe Kapitel 22, Problem 1 für Index-Empfehlungen"

exit 0
