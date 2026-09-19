#!/bin/bash
#
# Problem 13: Debug-Modus in Produktion diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-debug-mode.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob der Shop in der prod-Umgebung laeuft.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

SHOP_PATH="${2:-.}"

echo "=== Problem 13: Debug-Modus Status ==="
echo ""

PROBLEMS_FOUND=0

if [[ ! -f "${SHOP_PATH}/.env" && ! -f "${SHOP_PATH}/.env.local" \
      && ! -f "${SHOP_PATH}/.env.local.php" ]]; then
    echo "Keine .env, .env.local oder .env.local.php in: ${SHOP_PATH}" >&2
    echo "Falscher SHOP_PATH? Ohne diese Dateien ist nichts zu pruefen." >&2
    exit 69
fi

# Check .env
echo "1. .env Datei prüfen..."
if [[ -f "${SHOP_PATH}/.env" ]]; then
    APP_ENV=$(grep "^APP_ENV=" "${SHOP_PATH}/.env" | cut -d'=' -f2 || true)
    APP_DEBUG=$(grep "^APP_DEBUG=" "${SHOP_PATH}/.env" | cut -d'=' -f2 || true)

    echo "   APP_ENV=${APP_ENV:-<nicht gesetzt>}"
    echo "   APP_DEBUG=${APP_DEBUG:-<nicht gesetzt>}"

    if [[ "${APP_ENV}" = "dev" ]]; then
        echo ""
        echo "   ✗ KRITISCH: APP_ENV=dev in Produktion!"
        echo "     Dies verursacht extreme Performance-Probleme."
        PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
    elif [[ "${APP_ENV}" = "prod" ]]; then
        echo "   ✓ APP_ENV=prod"
    fi

    if [[ "${APP_DEBUG}" = "1" ]] || [[ "${APP_DEBUG}" = "true" ]]; then
        echo ""
        echo "   ✗ KRITISCH: APP_DEBUG=1 in Produktion!"
        echo "     Symfony Profiler läuft mit, Memory-Verbrauch steigt."
        PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
    elif [[ "${APP_DEBUG}" = "0" ]]; then
        echo "   ✓ APP_DEBUG=0"
    fi
else
    echo "   ⚠ .env nicht gefunden in: ${SHOP_PATH}"
fi

# Check .env.local (überschreibt .env)
echo ""
echo "2. .env.local prüfen..."
if [[ -f "${SHOP_PATH}/.env.local" ]]; then
    LOCAL_ENV=$(grep "^APP_ENV=" "${SHOP_PATH}/.env.local" 2>/dev/null | cut -d'=' -f2 || true)
    LOCAL_DEBUG=$(grep "^APP_DEBUG=" "${SHOP_PATH}/.env.local" 2>/dev/null | cut -d'=' -f2 || true)

    if [[ -n "${LOCAL_ENV}" ]]; then
        echo "   APP_ENV=${LOCAL_ENV} (überschreibt .env)"
        if [[ "${LOCAL_ENV}" = "dev" ]]; then
            PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
        fi
    fi
    if [[ -n "${LOCAL_DEBUG}" ]]; then
        echo "   APP_DEBUG=${LOCAL_DEBUG} (überschreibt .env)"
        if [[ "${LOCAL_DEBUG}" = "1" ]]; then
            PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
        fi
    fi
else
    echo "   .env.local nicht vorhanden (OK)"
fi

# Check .env.local.php — schlaegt beide .env-Dateien
echo ""
echo "3. .env.local.php prüfen..."
if [[ -f "${SHOP_PATH}/.env.local.php" ]]; then
    echo "   .env.local.php vorhanden — sie hat Vorrang vor .env und .env.local."
    PHP_ENV=$(grep -oE "'APP_ENV'[[:space:]]*=>[[:space:]]*'[^']*'" \
        "${SHOP_PATH}/.env.local.php" | head -1 | sed -E "s/.*=>[[:space:]]*'([^']*)'/\1/" || true)
    PHP_DEBUG=$(grep -oE "'APP_DEBUG'[[:space:]]*=>[[:space:]]*'[^']*'" \
        "${SHOP_PATH}/.env.local.php" | head -1 | sed -E "s/.*=>[[:space:]]*'([^']*)'/\1/" || true)

    if [[ -n "${PHP_ENV}" ]]; then
        echo "   APP_ENV=${PHP_ENV} (maßgeblich)"
        if [[ "${PHP_ENV}" = "dev" ]]; then
            echo "   ✗ KRITISCH: APP_ENV=dev in .env.local.php!"
            echo "     Aenderungen in .env.local bleiben wirkungslos."
            PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
        fi
    fi
    if [[ -n "${PHP_DEBUG}" ]]; then
        echo "   APP_DEBUG=${PHP_DEBUG} (maßgeblich)"
        if [[ "${PHP_DEBUG}" = "1" ]]; then
            echo "   ✗ KRITISCH: APP_DEBUG=1 in .env.local.php!"
            PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
        fi
    fi
    if [[ -z "${PHP_ENV}" && -z "${PHP_DEBUG}" ]]; then
        echo "   ⚠ Weder APP_ENV noch APP_DEBUG darin lesbar — von Hand nachsehen."
    fi
else
    echo "   .env.local.php nicht vorhanden (OK)"
fi

# Check Cache-Directory
echo ""
echo "4. Cache-Verzeichnis prüfen..."
# Shopware 6.6 haengt einen Hash an: var/cache/prod_h<hash>.
if compgen -G "${SHOP_PATH}/var/cache/dev*" > /dev/null; then
    DEV_SIZE=$(du -sh "${SHOP_PATH}"/var/cache/dev* 2>/dev/null | cut -f1 | head -1 || true)
    echo "   ⚠ Dev-Cache vorhanden: ${DEV_SIZE}"
    echo "     Hinweis: Dev-Cache sollte in Produktion nicht existieren"
fi
if compgen -G "${SHOP_PATH}/var/cache/prod*" > /dev/null; then
    PROD_SIZE=$(du -sh "${SHOP_PATH}"/var/cache/prod* 2>/dev/null | cut -f1 | head -1 || true)
    echo "   ✓ Prod-Cache vorhanden: ${PROD_SIZE}"
fi

# Empfehlungen
echo ""
echo "=== Empfehlung ==="
echo ""

if [[ ${PROBLEMS_FOUND} -gt 0 ]]; then
    echo "Kritische Probleme gefunden! Sofort beheben:"
    echo ""
    echo "1. .env.local erstellen/anpassen:"
    echo ""
    cat << 'EOF'
APP_ENV=prod
APP_DEBUG=0
EOF
    echo ""
    echo "   ACHTUNG: existiert eine .env.local.php (erzeugt von"
    echo "   'composer dump-env prod'), hat sie Vorrang und .env.local wird"
    echo "   ignoriert. Dann dort aendern oder die Datei neu erzeugen."
    echo ""
    echo "2. Cache leeren. In Deployment-Skripten cache:clear:all statt"
    echo "   cache:clear, weil die Cache-Hashes je nach Plugin-Zustand"
    echo "   abweichen koennen:"
    echo "   bin/console cache:clear:all"
    echo ""
    echo "3. Dev-Cache entfernen (Shopware haengt einen Hash an):"
    echo "   rm -rf var/cache/dev*"
    echo ""
    echo "4. Der Wechsel nach prod allein reicht nicht — Assets und Theme"
    echo "   muessen fuer die neue Umgebung erzeugt werden:"
    echo "   bin/console assets:install"
    echo "   bin/console theme:compile --keep-assets --sync"
    echo "   bin/console cache:warmup"
    echo ""
    exit 1
else
    echo "Debug-Modus ist korrekt konfiguriert."
    exit 0
fi
