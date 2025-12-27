#!/bin/bash
#
# Problem 13: Debug-Modus in Produktion diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_PATH="${2:-.}"

echo "=== Problem 13: Debug-Modus Status ==="
echo ""

PROBLEMS_FOUND=0

# Check .env
echo "1. .env Datei prüfen..."
if [ -f "$SHOP_PATH/.env" ]; then
    APP_ENV=$(grep "^APP_ENV=" "$SHOP_PATH/.env" | cut -d'=' -f2)
    APP_DEBUG=$(grep "^APP_DEBUG=" "$SHOP_PATH/.env" | cut -d'=' -f2)

    echo "   APP_ENV=$APP_ENV"
    echo "   APP_DEBUG=$APP_DEBUG"

    if [ "$APP_ENV" = "dev" ]; then
        echo ""
        echo "   ✗ KRITISCH: APP_ENV=dev in Produktion!"
        echo "     Dies verursacht extreme Performance-Probleme."
        PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
    elif [ "$APP_ENV" = "prod" ]; then
        echo "   ✓ APP_ENV=prod"
    fi

    if [ "$APP_DEBUG" = "1" ] || [ "$APP_DEBUG" = "true" ]; then
        echo ""
        echo "   ✗ KRITISCH: APP_DEBUG=1 in Produktion!"
        echo "     Symfony Profiler läuft mit, Memory-Verbrauch steigt."
        PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
    else
        echo "   ✓ APP_DEBUG=0"
    fi
else
    echo "   ⚠ .env nicht gefunden in: $SHOP_PATH"
fi

# Check .env.local (überschreibt .env)
echo ""
echo "2. .env.local prüfen..."
if [ -f "$SHOP_PATH/.env.local" ]; then
    LOCAL_ENV=$(grep "^APP_ENV=" "$SHOP_PATH/.env.local" 2>/dev/null | cut -d'=' -f2)
    LOCAL_DEBUG=$(grep "^APP_DEBUG=" "$SHOP_PATH/.env.local" 2>/dev/null | cut -d'=' -f2)

    if [ -n "$LOCAL_ENV" ]; then
        echo "   APP_ENV=$LOCAL_ENV (überschreibt .env)"
        if [ "$LOCAL_ENV" = "dev" ]; then
            PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
        fi
    fi
    if [ -n "$LOCAL_DEBUG" ]; then
        echo "   APP_DEBUG=$LOCAL_DEBUG (überschreibt .env)"
        if [ "$LOCAL_DEBUG" = "1" ]; then
            PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
        fi
    fi
else
    echo "   .env.local nicht vorhanden (OK)"
fi

# Check Cache-Directory
echo ""
echo "3. Cache-Verzeichnis prüfen..."
if [ -d "$SHOP_PATH/var/cache/dev" ]; then
    DEV_SIZE=$(du -sh "$SHOP_PATH/var/cache/dev" 2>/dev/null | cut -f1)
    echo "   ⚠ var/cache/dev existiert: $DEV_SIZE"
    echo "     Hinweis: Dev-Cache sollte in Produktion nicht existieren"
fi
if [ -d "$SHOP_PATH/var/cache/prod" ]; then
    PROD_SIZE=$(du -sh "$SHOP_PATH/var/cache/prod" 2>/dev/null | cut -f1)
    echo "   ✓ var/cache/prod existiert: $PROD_SIZE"
fi

# Empfehlungen
echo ""
echo "=== Empfehlung ==="
echo ""

if [ $PROBLEMS_FOUND -gt 0 ]; then
    echo "Kritische Probleme gefunden! Sofort beheben:"
    echo ""
    echo "1. .env.local erstellen/anpassen:"
    echo ""
    cat << 'EOF'
APP_ENV=prod
APP_DEBUG=0
EOF
    echo ""
    echo "2. Cache leeren:"
    echo "   bin/console cache:clear --env=prod"
    echo ""
    echo "3. Dev-Cache entfernen:"
    echo "   rm -rf var/cache/dev"
    echo ""
    exit 1
else
    echo "Debug-Modus ist korrekt konfiguriert."
    exit 0
fi
