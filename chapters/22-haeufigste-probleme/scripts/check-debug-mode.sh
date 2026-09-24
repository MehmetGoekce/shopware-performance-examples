#!/bin/bash
#
# Problem 13: Debug-Modus in Produktion diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#
# APP_ENV und APP_DEBUG koennen aus sechs Quellen kommen: der Umgebung,
# .env.local.php und vier .env-Dateien (.env, .env.local, .env.prod,
# .env.prod.local; die spaetere gewinnt). Ein grep ueber .env und .env.local
# sieht zwei davon. Gemessen (MEM-327, Shopware 6.6.10.6): APP_ENV=dev in
# .env.prod oder .env.prod.local schaltet CLI und Web auf dev, obwohl Symfony
# die Datei nach APP_ENV=prod auswaehlt. Ohne jede Angabe gilt dev.
# Der Webserver kann eigene Werte setzen (FPM env[], Apache SetEnv); sie
# schlagen jede Datei und stehen in keiner. Deshalb fragt Abschnitt 2 den
# Webserver selbst: Mit Debug enthaelt die Fehlerantwort der API einen
# Stacktrace (ErrorResponseFactory, "trace").

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-debug-mode.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob der Shop in der prod-Umgebung und ohne Debug laeuft.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
              Abschnitt 2 ruft dort eine unbekannte /api-Route auf.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Abschnitt 1 liest APP_ENV und APP_DEBUG in Symfonys Reihenfolge: Umgebung,
.env.local.php, sonst .env, .env.local, .env.<APP_ENV>, .env.<APP_ENV>.local.
Das ist die Sicht von bin/console. Abschnitt 2 zeigt die des Webservers.

Exit-Codes: 0 = prod ohne Debug, 1 = Problem gefunden,
            64 = Aufruffehler, 69 = keine .env/.env.dist/.env.local.php
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

SHOP_URL="${1:-http://localhost}"
SHOP_PATH="${2:-.}"

# >>> dotenv_get (wortgleich in allen Skripten dieses Kapitels, siehe BATS)
# Liest eine Variable so, wie Symfonys Dotenv::bootEnv() sie fuer die CLI
# (bin/console) ermittelt. Setzt DOTENV_VALUE und DOTENV_SOURCE; beide leer,
# wenn die Variable nirgends steht. Reihenfolge (symfony/dotenv 7.2-7.4):
#   1. Umgebung dieses Aufrufs — schlaegt jede Datei.
#   2. .env.local.php (composer dump-env) — ersetzt ALLE .env-Dateien,
#      ausser die Umgebung setzt ein anderes APP_ENV als die Datei.
#   3. .env, .env.local, .env.<APP_ENV>, .env.<APP_ENV>.local; die spaetere
#      Datei gewinnt, auch fuer APP_ENV selbst. Die Dateiwahl folgt dem
#      APP_ENV nach .env/.env.local (ohne Angabe: dev); bei APP_ENV=test
#      entfaellt .env.local. Ohne .env, .env.dist und .env.local.php liest
#      Shopware gar keine Datei.
# DOTENV_NOTE ist gesetzt, wenn der Wert nicht sicher ist (Text: dotenv_note):
# "Verweis" = $VAR/${VAR} in der Datei, den Symfony einsetzt, diese Funktion
# nicht; "Format" = .env.local.php nicht im Format von composer dump-env.
# Eine vorhandene, aber nicht lesbare Datei beendet das Skript mit Exit 69.
# Die Umgebung des Webservers (FPM env[], Apache SetEnv, nginx fastcgi_param)
# sieht diese Funktion nicht; sie schlaegt im Web ebenfalls jede Datei.
dotenv_get() {
    local name="$1" root="${SHOP_PATH:-.}" f env_name line php_env
    DOTENV_VALUE="" DOTENV_SOURCE="" DOTENV_NOTE=""
    if line=$(printenv "$name"); then
        DOTENV_VALUE="$line" DOTENV_SOURCE="Umgebung"
        return 0
    fi
    if [[ -f "$root/.env.local.php" ]]; then
        dotenv_need "$root/.env.local.php"
        php_env=$(dotenv_php_value "$root/.env.local.php" APP_ENV)
        if ! env_name=$(printenv APP_ENV) || [[ -z "$php_env" || "$env_name" == "$php_env" ]]; then
            if grep -qE "^[[:space:]]*'${name}'[[:space:]]*=>" "$root/.env.local.php"; then
                DOTENV_SOURCE=".env.local.php"
                if grep -qE "^[[:space:]]*'${name}'[[:space:]]*=>[[:space:]]*'" "$root/.env.local.php"; then
                    DOTENV_VALUE=$(dotenv_php_value "$root/.env.local.php" "$name")
                else
                    DOTENV_NOTE="Format"
                fi
            fi
            return 0
        fi
    fi
    [[ -f "$root/.env" || -f "$root/.env.dist" ]] || return 0
    f="$root/.env"; [[ -f "$f" ]] || f="$root/.env.dist"
    dotenv_need "$f"
    env_name=$(printenv APP_ENV) || env_name=$(dotenv_file_value "$f" APP_ENV)
    local files=("$f")
    if [[ "${env_name:-dev}" != "test" && -f "$root/.env.local" ]]; then
        dotenv_need "$root/.env.local"
        files+=("$root/.env.local")
        printenv APP_ENV >/dev/null || env_name=$(dotenv_file_value "$root/.env.local" APP_ENV "$env_name")
    fi
    env_name="${env_name:-dev}"
    if [[ "$env_name" != "local" ]]; then
        files+=("$root/.env.$env_name" "$root/.env.$env_name.local")
    fi
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        dotenv_need "$f"
        if line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$f" | tail -n 1); then
            DOTENV_VALUE=$(dotenv_file_value "$f" "$name")
            DOTENV_SOURCE="${f##*/}"
            DOTENV_NOTE=""
            # In '...' setzt Symfony nichts ein, sonst schon.
            [[ "${line#*=}" != \'* && "$DOTENV_VALUE" == *'$'* ]] && DOTENV_NOTE="Verweis"
        fi
    done
    return 0
}
dotenv_need() {
    [[ -r "$1" ]] && return 0
    echo "Nicht lesbar: $1" >&2
    echo "Das Skript mit den Rechten des Shops starten, z. B. sudo -u www-data $0 ..." >&2
    exit 69
}
dotenv_note() {
    case "$DOTENV_NOTE" in
        Verweis) echo "enthaelt einen \$-Verweis, den Symfony einsetzt, dieses Skript nicht" ;;
        Format) echo "steht in .env.local.php nicht im Format von composer dump-env" ;;
    esac
}
# Letzte Zuweisung NAME=... einer .env-Datei; "export " davor erlaubt.
# Entfernt umschliessende Anfuehrungszeichen und einen Kommentar hinter
# einem Wert ohne Anfuehrungszeichen. ${VAR}-Verweise bleiben unaufgeloest.
# $3 = Rueckgabe, wenn die Datei die Variable nicht setzt.
dotenv_file_value() {
    local line v
    line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$1" | tail -n 1) || { printf '%s' "${3:-}"; return 0; }
    v="${line#*=}"
    case "$v" in
        \"*\"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*\'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *) v="${v%%[[:space:]]#*}"; v="${v%"${v##*[![:space:]]}"}" ;;
    esac
    printf '%s' "$v"
}
# Wert aus .env.local.php (var_export-Format von composer dump-env).
dotenv_php_value() {
    grep -E "^[[:space:]]*'$2'[[:space:]]*=>" "$1" | tail -n 1 \
        | sed -E "s/^[^=]*=>[[:space:]]*'(.*)',?[[:space:]]*$/\1/; s/\\\\'/'/g; s/\\\\\\\\/\\\\/g" || true
}
# <<< dotenv_get

# Symfony wertet APP_DEBUG so aus: (int) $wert || filter_var($wert, BOOL).
# (int) liest eine fuehrende Ganzzahl ("2", "-1", "1abc" = an).
is_on() {
    local v
    v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    case "$v" in
        1|true|on|yes) return 0 ;;
    esac
    [[ "$v" =~ ^[+-]?0*[1-9] ]]
}

echo "=== Problem 13: Debug-Modus Status ==="
echo ""

if [[ ! -f "${SHOP_PATH}/.env" && ! -f "${SHOP_PATH}/.env.dist" \
      && ! -f "${SHOP_PATH}/.env.local.php" ]]; then
    echo "Keine .env, .env.dist oder .env.local.php in: ${SHOP_PATH}" >&2
    echo "Falscher SHOP_PATH? Ohne diese Dateien liest Shopware keine .env-Datei." >&2
    exit 69
fi

PROBLEMS_FOUND=0

echo "1. Sicht der CLI (bin/console), Reihenfolge wie Symfonys Dotenv..."
for f in .env .env.dist .env.local .env.dev .env.dev.local .env.prod .env.prod.local .env.local.php; do
    [[ -f "${SHOP_PATH}/$f" ]] || continue
    LINES=$(grep -E "^[[:space:]]*(export[[:space:]]+)?APP_(ENV|DEBUG)=|^[[:space:]]*'APP_(ENV|DEBUG)'[[:space:]]*=>" \
        "${SHOP_PATH}/$f" || true)
    [[ -n "${LINES}" ]] && printf '%s\n' "${LINES}" | sed "s|^[[:space:]]*|   $f: |"
done

# Ein Wert, den das Skript nicht sicher kennt ($-Verweis, fremdes Format),
# wird angezeigt, aber nicht bewertet.
ENV_UNSURE=0
DEBUG_UNSURE=0
dotenv_get APP_ENV
CLI_ENV="${DOTENV_VALUE}"
if [[ -n "${DOTENV_NOTE}" ]]; then
    ENV_UNSURE=1
    echo "   => APP_ENV=${CLI_ENV} (aus ${DOTENV_SOURCE}) $(dotenv_note)"
elif [[ -n "${CLI_ENV}" ]]; then
    echo "   => APP_ENV=${CLI_ENV} (aus ${DOTENV_SOURCE})"
elif [[ "${DOTENV_SOURCE}" == "" && -f "${SHOP_PATH}/.env.local.php" ]] \
        && ! printenv APP_ENV >/dev/null \
        && ! grep -qE "^[[:space:]]*'APP_ENV'[[:space:]]*=>" "${SHOP_PATH}/.env.local.php"; then
    # bootEnv() laesst APP_ENV dann ungesetzt: bin/console nimmt prod,
    # public/index.php nimmt dev; APP_DEBUG wird 1.
    CLI_ENV="dev"
    echo "   => .env.local.php ohne APP_ENV — bin/console laeuft in prod mit Debug,"
    echo "      das Web in dev."
else
    CLI_ENV="dev"
    echo "   => APP_ENV nirgends gesetzt — Symfony nimmt dev"
fi
dotenv_get APP_DEBUG
if [[ -n "${DOTENV_NOTE}" ]]; then
    DEBUG_UNSURE=1
    CLI_DEBUG_RAW=""
    echo "   => APP_DEBUG=${DOTENV_VALUE} (aus ${DOTENV_SOURCE}) $(dotenv_note)"
elif [[ -n "${DOTENV_SOURCE}" ]]; then
    CLI_DEBUG_RAW="${DOTENV_VALUE}"
    echo "   => APP_DEBUG=${CLI_DEBUG_RAW} (aus ${DOTENV_SOURCE})"
elif [[ "${ENV_UNSURE}" -eq 1 ]]; then
    DEBUG_UNSURE=1
    CLI_DEBUG_RAW=""
    echo "   => APP_DEBUG nicht gesetzt — folgt aus APP_ENV, das hier nicht sicher ist"
else
    # Ohne Angabe leitet Symfony APP_DEBUG aus APP_ENV ab.
    CLI_DEBUG_RAW=$([[ "${CLI_ENV}" == "prod" ]] && echo 0 || echo 1)
    echo "   => APP_DEBUG nicht gesetzt — folgt aus APP_ENV=${CLI_ENV}: ${CLI_DEBUG_RAW}"
fi
if [[ -f "${SHOP_PATH}/.env.local.php" ]]; then
    echo "   .env.local.php vorhanden — Symfony liest dann keine .env-Datei,"
    echo "   ausser die Umgebung setzt ein anderes APP_ENV als die Datei."
fi

UNCHECKED=""
if [[ "${ENV_UNSURE}" -eq 1 ]]; then
    echo "   ⚠ APP_ENV nicht bewertet — bin/console about zeigt den Wert."
    UNCHECKED="${UNCHECKED} APP_ENV (CLI)"
elif [[ "${CLI_ENV}" != "prod" ]]; then
    echo ""
    echo "   ✗ KRITISCH: APP_ENV=${CLI_ENV} statt prod!"
    echo "     Dies verursacht extreme Performance-Probleme."
    PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
else
    echo "   ✓ APP_ENV=prod"
fi
if [[ "${DEBUG_UNSURE}" -eq 1 ]]; then
    echo "   ⚠ APP_DEBUG nicht bewertet — bin/console about zeigt den Wert."
    UNCHECKED="${UNCHECKED} APP_DEBUG (CLI)"
elif is_on "${CLI_DEBUG_RAW}"; then
    echo ""
    echo "   ✗ KRITISCH: APP_DEBUG an!"
    echo "     Symfony sammelt Debug-Daten mit, Memory-Verbrauch steigt."
    PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
else
    echo "   ✓ APP_DEBUG aus"
fi

echo ""
echo "2. Sicht des Webservers (${SHOP_URL%/}/api/...)..."
# Die Route gibt es absichtlich nicht: Shopware antwortet mit einem JSON-404,
# und mit kernel.debug=true haengt es einen Stacktrace ("trace") an.
# -L folgt Weiterleitungen (http -> https, ohne -> mit www).
if ! command -v curl >/dev/null 2>&1; then
    echo "   curl fehlt — nicht geprueft."
    UNCHECKED="${UNCHECKED} Debug (Webserver)"
elif ! BODY=$(curl -sSL --max-time 15 -w '\n%{http_code} %{url_effective}' \
        "${SHOP_URL%/}/api/_info/check-debug-mode" 2>/dev/null); then
    echo "   ${SHOP_URL} nicht erreichbar — nicht geprueft."
    UNCHECKED="${UNCHECKED} Debug (Webserver)"
elif [[ "${BODY}" != *'"errors"'* ]]; then
    echo "   Keine Shopware-API-Fehlerantwort (HTTP ${BODY##*$'\n'}) — nicht geprueft."
    UNCHECKED="${UNCHECKED} Debug (Webserver)"
elif [[ "${BODY}" == *'"trace"'* ]]; then
    echo "   ✗ KRITISCH: Die Fehlerantwort enthaelt einen Stacktrace — Debug ist im Web an."
    PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
else
    echo "   ✓ Kein Stacktrace in der Fehlerantwort — Debug ist im Web aus."
fi
echo "   APP_ENV des Webservers prueft das Skript nicht. Die Administration zeigt"
echo "   sie: Einstellungen > System > Caches & Indizes (Umgebung). Weicht sie von"
echo "   Abschnitt 1 ab, setzt der Webserver eigene Werte (FPM env[], Apache"
echo "   SetEnv, nginx fastcgi_param)."
UNCHECKED="${UNCHECKED} APP_ENV (Webserver)"

echo ""
echo "3. Cache-Verzeichnis prüfen..."
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
    echo "1. Den Wert dort aendern, woher er kommt (Abschnitt 1 nennt die Quelle):"
    echo ""
    cat << 'EOF'
APP_ENV=prod
APP_DEBUG=0
EOF
    echo ""
    echo "   Eine spaetere Datei schlaegt eine fruehere: .env < .env.local <"
    echo "   .env.prod < .env.prod.local. Ein Wert in .env.local hilft also nicht,"
    echo "   wenn .env.prod ihn wieder setzt. Existiert eine .env.local.php"
    echo "   (erzeugt von 'composer dump-env prod'), liest Symfony nur sie: dort"
    echo "   aendern oder die Datei neu erzeugen. Setzt der Webserver den Wert"
    echo "   (Abschnitt 2 weicht ab), in dessen Konfiguration aendern."
    echo ""
    echo "2. Cache leeren (cache:clear:all ab Shopware 6.6.8.0, davor cache:clear):"
    echo "   bin/console cache:clear:all"
    echo "   Assets und Theme bleiben gueltig: ihr Pfad haengt nicht an APP_ENV"
    echo "   (gemessen: all.css unter demselben Pfad in prod, dev und wieder prod)."
    echo ""
    echo "3. Dev-Cache entfernen (Shopware haengt einen Hash an):"
    echo "   rm -rf var/cache/dev*"
    echo ""
    exit 1
elif [[ -n "${UNCHECKED}" ]]; then
    echo "Kein Problem gefunden. Nicht geprueft:${UNCHECKED}."
    exit 0
else
    echo "Debug-Modus ist korrekt konfiguriert."
    exit 0
fi
