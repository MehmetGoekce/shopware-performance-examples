#!/bin/bash
#
# Problem 12: OPcache nicht aktiviert diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_PATH="${2:-.}"

echo "=== Problem 12: OPcache Status ==="
echo ""

# OPcache via PHP CLI prüfen
echo "1. OPcache Status (CLI)..."
OPCACHE_STATUS=$(php -r 'echo json_encode(opcache_get_status(false));' 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$OPCACHE_STATUS" ]; then
    ENABLED=$(echo "$OPCACHE_STATUS" | php -r 'echo json_decode(file_get_contents("php://stdin"))->opcache_enabled ? "true" : "false";' 2>/dev/null)
    MEMORY=$(echo "$OPCACHE_STATUS" | php -r '$s=json_decode(file_get_contents("php://stdin")); echo round($s->memory_usage->used_memory / 1024 / 1024, 2) . "MB / " . round(($s->memory_usage->used_memory + $s->memory_usage->free_memory) / 1024 / 1024, 2) . "MB";' 2>/dev/null)
    HIT_RATE=$(echo "$OPCACHE_STATUS" | php -r '$s=json_decode(file_get_contents("php://stdin")); $hits=$s->opcache_statistics->hits ?? 0; $misses=$s->opcache_statistics->misses ?? 0; echo ($hits+$misses > 0) ? round($hits/($hits+$misses)*100, 2) : 0;' 2>/dev/null)
    CACHED=$(echo "$OPCACHE_STATUS" | php -r '$s=json_decode(file_get_contents("php://stdin")); echo $s->opcache_statistics->num_cached_scripts ?? 0;' 2>/dev/null)

    if [ "$ENABLED" = "true" ]; then
        echo "   ✓ OPcache ist aktiviert"
        echo "   Memory: $MEMORY"
        echo "   Hit Rate: ${HIT_RATE}%"
        echo "   Cached Scripts: $CACHED"
    else
        echo "   ✗ OPcache ist DEAKTIVIERT!"
    fi
else
    echo "   ⚠ OPcache Status konnte nicht abgerufen werden"
fi

# PHP INI prüfen
echo ""
echo "2. PHP-Konfiguration..."
php -i 2>/dev/null | grep -E "^opcache\." | head -15

# Wichtige Settings prüfen
echo ""
echo "3. Kritische OPcache-Einstellungen..."

VALIDATE_TS=$(php -r 'echo ini_get("opcache.validate_timestamps");' 2>/dev/null)
REVALIDATE=$(php -r 'echo ini_get("opcache.revalidate_freq");' 2>/dev/null)
MAX_FILES=$(php -r 'echo ini_get("opcache.max_accelerated_files");' 2>/dev/null)
MEMORY_CONSUMPTION=$(php -r 'echo ini_get("opcache.memory_consumption");' 2>/dev/null)

echo "   opcache.validate_timestamps = $VALIDATE_TS"
echo "   opcache.revalidate_freq = $REVALIDATE"
echo "   opcache.max_accelerated_files = $MAX_FILES"
echo "   opcache.memory_consumption = ${MEMORY_CONSUMPTION}MB"

PROBLEMS=0

if [ "$VALIDATE_TS" = "1" ]; then
    echo ""
    echo "   ⚠ validate_timestamps=1 - In Produktion auf 0 setzen!"
    PROBLEMS=$((PROBLEMS + 1))
fi

if [ "${MAX_FILES:-0}" -lt 10000 ]; then
    echo "   ⚠ max_accelerated_files zu niedrig für Shopware (mind. 20000)"
    PROBLEMS=$((PROBLEMS + 1))
fi

if [ "${MEMORY_CONSUMPTION:-0}" -lt 128 ]; then
    echo "   ⚠ memory_consumption zu niedrig (mind. 256MB empfohlen)"
    PROBLEMS=$((PROBLEMS + 1))
fi

# Empfehlungen
echo ""
echo "=== Empfehlung ==="
echo ""

if [ "$ENABLED" != "true" ] || [ $PROBLEMS -gt 0 ]; then
    echo "OPcache optimal konfigurieren (php.ini):"
    echo ""
    cat << 'EOF'
; OPcache Basiseinstellungen
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000

; Produktion: keine Dateisystem-Checks
opcache.validate_timestamps=0
opcache.revalidate_freq=0

; JIT (PHP 8.0+)
opcache.jit=1255
opcache.jit_buffer_size=100M
EOF
    echo ""
    echo "Nach Änderung: php-fpm reload"
    exit 1
else
    echo "OPcache ist optimal konfiguriert."
    exit 0
fi
