#!/bin/bash
#
# Performance-Diagnose-Report generieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_URL="${1:-https://localhost}"
SHOP_PATH="${2:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "# Shopware 6 Performance-Diagnose-Report"
echo ""
echo "**Generiert:** $(date '+%Y-%m-%d %H:%M:%S')"
echo "**Shop URL:** $SHOP_URL"
echo "**Shop Path:** $SHOP_PATH"
echo ""
echo "---"
echo ""

# Funktion: Check ausführen und Ergebnis formatieren
run_check() {
    local name="$1"
    local script="$2"
    local number="$3"

    echo "## Problem $number: $name"
    echo ""

    if [ -f "$SCRIPT_DIR/$script" ]; then
        OUTPUT=$(bash "$SCRIPT_DIR/$script" "$SHOP_URL" "$SHOP_PATH" 2>&1)
        EXIT_CODE=$?

        if [ $EXIT_CODE -eq 0 ]; then
            echo "**Status:** ✅ OK"
        else
            echo "**Status:** ❌ Problem gefunden"
        fi

        echo ""
        echo "\`\`\`"
        echo "$OUTPUT"
        echo "\`\`\`"
    else
        echo "**Status:** ⚠️ Script nicht verfügbar"
    fi

    echo ""
    echo "---"
    echo ""
}

# Checks ausführen
run_check "Langsame DB-Queries" "diagnose-slow-queries.sh" 1
run_check "HTTP-Cache Status" "check-http-cache.sh" 2
run_check "Debug-Modus" "check-debug-mode.sh" 13
run_check "OPcache" "check-opcache.sh" 12
run_check "Gzip-Kompression" "check-compression.sh" 14
run_check "Plugin-Anzahl" "audit-plugins.sh" 10
run_check "Log-Dateien" "check-logs.sh" 17
run_check "Browser-Cache-Header" "check-cache-headers.sh" 20

# Zusammenfassung
echo "## Zusammenfassung"
echo ""
echo "Die Top 5 Maßnahmen für Ihren Shop:"
echo ""
echo "1. HTTP-Cache aktivieren → -50% TTFB"
echo "2. OPcache aktivieren → -30% TTFB"
echo "3. Debug-Modus deaktivieren → -70% Ladezeit"
echo "4. Gzip aktivieren → -60% Transfergröße"
echo "5. Bilder optimieren → -40% LCP"
echo ""
echo "---"
echo ""
echo "**Detaillierte Lösungen:** Kapitel 22 im Buch"
echo ""
echo "**Professionelles Audit:** [memotech.ch/performance-audit](https://memotech.ch/performance-audit)"
