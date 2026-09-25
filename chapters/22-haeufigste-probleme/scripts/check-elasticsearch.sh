#!/usr/bin/env bash
#
# check-elasticsearch.sh
#
# Problem 11: Elasticsearch nicht konfiguriert.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zur Konfiguration: Seit Oktober 2024 legt Shopwares Flex-Rezept KEINE
# config/packages/elasticsearch.yaml mehr an. Aeltere Rezepte (6.4 fuer
# 6.4/6.5, 6.6 bis zum 2024-10-01) taten es; solche Shops haben meist eine,
# die nur hosts an OPENSEARCH_URL bindet, denselben Wert wie die Bundle-Datei
# (vendor/shopware/elasticsearch/Resources/config/packages/elasticsearch.yaml).
# Die bindet alles an Umgebungsvariablen:
#
#   SHOPWARE_ES_ENABLED            Suche laeuft ueber Elasticsearch
#   SHOPWARE_ES_INDEXING_ENABLED   Indizierung ist erlaubt
#   OPENSEARCH_URL                 Host, kommasepariert fuer mehrere
#   SHOPWARE_ES_INDEX_PREFIX       Default: sw
#
# Der Root-Key heisst "elasticsearch", nicht "shopware.es". Shopware 6.6
# spricht ueber den OpenSearch-PHP-Client mit dem Cluster; Elasticsearch und
# OpenSearch funktionieren beide.
#
# Die Variablen koennen aus sechs Quellen kommen: der Umgebung,
# .env.local.php und vier .env-Dateien (.env, .env.local, .env.prod,
# .env.prod.local; die spaetere gewinnt). Gemessen (MEM-327, 6.6.10.6):
# SHOPWARE_ES_ENABLED=1 in .env.prod, .env.prod.local oder .env.local.php
# schaltet die Suche um, ein grep ueber .env und .env.local zeigt 0.
# Setzt der Webserver den Wert (FPM env[], Apache SetEnv), sieht ihn keine
# Datei und keine CLI. Was der Webserver wirklich benutzt, steht im
# Quelltext der Admin-Anmeldeseite: storefrontEsEnable (ab 6.5.2.0,
# AdministrationController, ohne Login). Fuer OPENSEARCH_URL gibt es keine
# solche Anzeige.
#
# Verwendung:
#   ./check-elasticsearch.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = Elasticsearch aktiv und erreichbar
#   1 = nicht aktiv, CLI und Webserver uneins, nicht erreichbar, ohne Indizes
#       oder der Alias fehlt bzw. zeigt auf einen leeren Index
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-elasticsearch.sh [SHOP_URL] [SHOP_PATH]

Prueft, ob die Shopware-Suche ueber Elasticsearch/OpenSearch laeuft.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
              Dort liest das Skript storefrontEsEnable aus der Admin-
              Anmeldeseite: den Schalter, wie der Webserver ihn sieht.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Die Variablen liest es wie bin/console: Umgebung, .env.local.php, sonst
.env, .env.local, .env.<APP_ENV>, .env.<APP_ENV>.local (spaetere gewinnt).

Umgebungsvariablen:
  ES_HOST     Host:Port des Clusters. Ohne Angabe OPENSEARCH_URL wie oben,
              sonst localhost:9200.
  ADMIN_PATH  Pfad der Administration. Default: SHOPWARE_ADMINISTRATION_PATH_NAME
              wie oben, sonst admin
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

# Aufrufkonvention aller Skripte dieses Kapitels: $1 = SHOP_URL, $2 = SHOP_PATH.
SHOP_URL="${1:-http://localhost}"
SHOP_PATH="${2:-.}"
# Cluster-Adresse per Umgebungsvariable, damit die Argumentfolge einheitlich bleibt.
ES_HOST_ARG="${ES_HOST:-}"

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

# Shopware liest den Schalter als %env(bool:SHOPWARE_ES_ENABLED)%:
# true/on/yes/1 oder eine Zahl ungleich 0.
is_on() {
    local v
    v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    case "$v" in
        1|true|on|yes) return 0 ;;
    esac
    [[ "$v" =~ ^[+-]?[0-9]*\.?[0-9]+$ && ! "$v" =~ ^[+-]?0*\.?0*$ ]]
}

echo "=== Problem 11: Elasticsearch ==="
echo

# Wert und Quelle je Variable, wie bin/console sie sieht.
show() {
    dotenv_get "$1"
    if [[ -n "${DOTENV_NOTE}" ]]; then
        printf '   %-28s = %s (%s) %s\n' "$1" "${DOTENV_VALUE}" "${DOTENV_SOURCE}" "$(dotenv_note)"
    elif [[ -n "${DOTENV_SOURCE}" ]]; then
        printf '   %-28s = %s (%s)\n' "$1" "${DOTENV_VALUE}" "${DOTENV_SOURCE}"
    else
        printf '   %-28s = (nicht gesetzt)\n' "$1"
    fi
}

# Abschnitte fortlaufend nummerieren. Fest verdrahtete Nummern springen,
# sobald ein Abschnitt uebersprungen wird (1 -> 2 -> 4).
SECTION_NO=0
section() {
    SECTION_NO=$((SECTION_NO + 1))
    echo "${SECTION_NO}. $1"
}

section "Konfiguration aus Sicht der CLI (Umgebung, .env.local.php, .env-Dateien)"
show SHOPWARE_ES_ENABLED;          ES_ENABLED="${DOTENV_VALUE}" ES_SRC="${DOTENV_SOURCE}" ES_NOTE="${DOTENV_NOTE}"
show SHOPWARE_ES_INDEXING_ENABLED
show OPENSEARCH_URL;               ES_URL="${DOTENV_VALUE}" URL_NOTE="${DOTENV_NOTE}"
show SHOPWARE_ES_INDEX_PREFIX;     ES_PREFIX="${DOTENV_VALUE:-sw}"
if [[ -z "${ADMIN_PATH:-}" ]]; then
    dotenv_get SHOPWARE_ADMINISTRATION_PATH_NAME
    ADMIN_PATH="${DOTENV_VALUE:-admin}"
fi
if [[ -f "${SHOP_PATH}/.env.local.php" ]]; then
    echo "   .env.local.php vorhanden — Symfony liest dann keine .env-Datei,"
    echo "   ausser die Umgebung setzt ein anderes APP_ENV als die Datei."
fi

if [[ -n "${ES_HOST_ARG}" ]]; then
    ES_BASE="${ES_HOST_ARG}"
elif [[ -n "${URL_NOTE}" ]]; then
    ES_BASE=""
elif [[ -n "${ES_URL}" ]]; then
    ES_BASE="${ES_URL%%,*}"
else
    ES_BASE="localhost:9200"
fi
case "${ES_BASE}" in
    "") : ;;
    http://*|https://*) : ;;
    *) ES_BASE="http://${ES_BASE}" ;;
esac

ISSUES=0

echo
section "Sicht des Webservers (${SHOP_URL%/}/${ADMIN_PATH})"
WEB_ES=""
if ! command -v curl >/dev/null 2>&1; then
    echo "   curl fehlt — nicht geprueft."
elif ! ADMIN_HTML=$(curl -sSL --max-time 15 -w '\n%{http_code}' "${SHOP_URL%/}/${ADMIN_PATH}" 2>/dev/null); then
    echo "   ${SHOP_URL%/}/${ADMIN_PATH} nicht erreichbar — nicht geprueft."
elif [[ "${ADMIN_HTML}" =~ storefrontEsEnable:[[:space:]]*(true|false) ]]; then
    WEB_ES="${BASH_REMATCH[1]}"
    echo "   storefrontEsEnable: ${WEB_ES}"
else
    echo "   Kein storefrontEsEnable in der Antwort (HTTP ${ADMIN_HTML##*$'\n'}; vor 6.5.2.0"
    echo "   oder anderer Admin-Pfad, siehe ADMIN_PATH) — nicht geprueft."
fi

CLI_ES=false
is_on "${ES_ENABLED}" && CLI_ES=true
[[ -n "${ES_NOTE}" ]] && CLI_ES=""
if [[ -n "${WEB_ES}" && -n "${CLI_ES}" && "${WEB_ES}" != "${CLI_ES}" ]]; then
    echo "   ✗ Webserver (${WEB_ES}) und CLI (${CLI_ES}) sind uneins."
    if [[ "${ES_SRC}" == "Umgebung" ]]; then
        echo "     Die CLI hat den Wert aus der Umgebung dieser Shell; die sieht der"
        echo "     Webserver nicht."
    else
        echo "     Der Webserver setzt eigene Werte (FPM env[], Apache SetEnv, nginx"
        echo "     fastcgi_param)."
    fi
    echo "     Dann stimmt auch OPENSEARCH_URL oben nicht sicher; die des Webservers"
    echo "     zeigt Shopware nirgends an, sie steht in dessen Konfiguration."
    ISSUES=$((ISSUES + 1))
fi
SEARCH_ES="${WEB_ES:-${CLI_ES}}"
if [[ -z "${SEARCH_ES}" ]]; then
    echo "   SHOPWARE_ES_ENABLED nicht bewertet (siehe Abschnitt 1)."
elif [[ "${SEARCH_ES}" != "true" ]]; then
    echo "   Die Suche laeuft NICHT ueber Elasticsearch."
    ISSUES=$((ISSUES + 1))
fi

echo
if [[ -z "${ES_BASE}" ]]; then
    section "Cluster"
    echo "   OPENSEARCH_URL ist nicht sicher (siehe Abschnitt 1) — nicht geprueft."
    echo "   Adresse von Hand mitgeben: ES_HOST=host:9200 $0 ..."
else
    section "Cluster unter ${ES_BASE}"
    if ROOT=$(curl -sS --connect-timeout 5 "${ES_BASE}" 2>/dev/null) && [[ -n "${ROOT}" ]]; then
        # Elasticsearch meldet kein "distribution" (nur OpenSearch); ohne
        # "|| true" beendete set -e das Skript hier still mit Exit 1 (MEM-330).
        VERSION=$(printf '%s' "${ROOT}" | grep -oE '"number"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        DISTRO=$(printf '%s' "${ROOT}" | grep -oE '"distribution"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        echo "   erreichbar — ${DISTRO:-elasticsearch} ${VERSION:-?}"

        HEALTH=$(curl -sS "${ES_BASE}/_cluster/health" 2>/dev/null \
            | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        case "${HEALTH}" in
            green)  echo "   Cluster-Status: green" ;;
            yellow) echo "   Cluster-Status: yellow — bei einem einzelnen Knoten normal," ;;
            *)      echo "   Cluster-Status: ${HEALTH:-unbekannt}"; ISSUES=$((ISSUES + 1)) ;;
        esac
        if [[ "${HEALTH}" == "yellow" ]]; then
            echo "   weil die konfigurierten Replicas keinen zweiten Knoten finden."
        fi

        echo
        section "Shopware-Indizes (Praefix ${ES_PREFIX})"
        INDICES=$(curl -sS "${ES_BASE}/_cat/indices/${ES_PREFIX}*?h=index,docs.count,store.size" 2>/dev/null || true)
        if [[ -z "${INDICES}" ]]; then
            echo "   Keine Indizes mit diesem Praefix."
            ISSUES=$((ISSUES + 1))
        else
            printf '%s\n' "${INDICES}" | sed 's/^/   /'
            # Die Suche fragt den Alias, nicht den Index. Nach es:index ohne
            # --no-queue und ohne Worker zeigt er beim ersten Aufbau auf einen
            # leeren Index (gemessen, MEM-330: 0 statt 4 Treffer).
            ALIAS_INDEX=$(curl -sS "${ES_BASE}/_cat/aliases/${ES_PREFIX}_product?h=index" 2>/dev/null \
                | head -1 | tr -d '[:space:]' || true)
            if [[ -z "${ALIAS_INDEX}" ]]; then
                echo "   ✗ Kein Alias ${ES_PREFIX}_product: Die Suche findet keinen Index."
                ISSUES=$((ISSUES + 1))
            else
                ALIAS_DOCS=$(printf '%s\n' "${INDICES}" | awk -v i="${ALIAS_INDEX}" '$1 == i {print $2}')
                echo "   Alias ${ES_PREFIX}_product -> ${ALIAS_INDEX} (${ALIAS_DOCS:-?} Dokumente)"
                if [[ "${ALIAS_DOCS}" == "0" ]]; then
                    echo "   ✗ Der Alias zeigt auf einen leeren Index; die Suche findet nichts."
                    echo "     So bleibt es nach es:index ohne --no-queue, solange kein Worker"
                    echo "     die Queue abarbeitet."
                    ISSUES=$((ISSUES + 1))
                fi
            fi
        fi
    else
        echo "   NICHT erreichbar."
        echo "   Gegenprobe: curl -v ${ES_BASE}"
        ISSUES=$((ISSUES + 1))
    fi
fi

if [[ -f "${SHOP_PATH}/bin/console" ]]; then
    echo
    section "Sicht von Shopware aus"
    if STATUS=$(php "${SHOP_PATH}/bin/console" es:status 2>&1); then
        printf '%s\n' "${STATUS}" | head -20 | sed 's/^/   /'
    else
        printf '%s\n' "${STATUS}" | head -5 | sed 's/^/   /'
        ISSUES=$((ISSUES + 1))
    fi
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Elasticsearch ist aktiv, erreichbar und hat Indizes."
    exit 0
fi

cat <<EOF
${ISSUES} Punkt(e) offen.

Einschalten geschieht ueber Umgebungsvariablen, nicht ueber eine eigene
config/packages/elasticsearch.yaml. Eintragen dort, wo Abschnitt 1 die
Quelle nennt; .env.prod und .env.prod.local schlagen .env.local, eine
.env.local.php ersetzt alle .env-Dateien. Erst indexieren, dann die Suche
umschalten:

  # .env.local
  OPENSEARCH_URL=${ES_BASE#http://}
  SHOPWARE_ES_INDEXING_ENABLED=1
  SHOPWARE_ES_INDEX_PREFIX=${ES_PREFIX}

  bin/console es:index --no-queue
  curl -s '${ES_BASE:-http://localhost:9200}/_cat/indices/${ES_PREFIX}_*?h=index,docs.count'

  # danach in derselben Datei:
  SHOPWARE_ES_ENABLED=1

Mit SHOPWARE_ES_ENABLED=1 vor dem Index antwortete die Suchvorschau
(/suggest) im Test mit HTTP 500, weil SHOPWARE_ES_THROW_EXCEPTION ab Werk
an ist.

Das --no-queue ist wichtig. Ohne den Schalter legt es:index nur den neuen
Index an und stellt die Indexing-Messages in die Queue. Abgearbeitet werden
sie von einem "messenger:consume"-Worker oder, solange jemand in der
Administration angemeldet ist, von deren Admin-Worker (ab Werk an). Laeuft
keiner von beiden, bleibt der Index leer, und beim ersten Aufbau zeigt der
Alias sofort auf ihn: Im Test fand die Suche mit SHOPWARE_ES_ENABLED=1 dann
0 statt 4 Produkte. Bei einem Neuaufbau schwenkt ein Scheduled Task den
Alias um, und der laeuft nur mit SHOPWARE_ES_ENABLED=1. Im Regelbetrieb
laufen Worker ohnehin — dann ist der Queue-Weg der richtige.

Ein naechtlicher Vollindex per Cron ist nicht noetig: Aenderungen gehen
laufend inkrementell ueber die Queue.
EOF
exit 1
