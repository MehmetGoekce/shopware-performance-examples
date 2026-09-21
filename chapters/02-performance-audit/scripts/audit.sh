#!/bin/bash
#
# Shopware 6 Performance-Audit: Bestandsaufnahme auf dem Server
# Kapitel 2: Performance-Audit — Wo stehen Sie?
#
# Liest nur, ändert nichts. Aufruf als der Benutzer, unter dem der Shop läuft
# (meist www-data), im Shopware-Verzeichnis oder mit dem Pfad als Argument.
#
# Geprüft wird (getestet mit Shopware 6.6.10.6):
#   1. Versionen: Shopware, PHP-CLI und jede gefundene PHP-FPM-Binary.
#      php -v zeigt nur die CLI; der Webserver kann eine andere Version nutzen.
#   2. Plugins: aktive Plugins über plugin:list --json.
#      plugin:list --active gibt es nicht, plugin:list | wc -l zählt Tabellenrahmen.
#   3. HTTP-Cache: SHOPWARE_HTTP_CACHE_ENABLED/_DEFAULT_TTL über debug:dotenv,
#      mit SHOP_URL zusätzlich ein Abruf-Test als Gast (Age > 0 = Treffer).
#      debug:config bricht in APP_ENV=prod mit "frozen ParameterBag" ab.
#   4. OPcache der FPM-SAPI über php-fpmX.Y -i. php -i liest die CLI-Konfiguration.
#   5. Message Queue: laufende CLI-Worker, Admin-Worker-Schalter, messenger:stats.
#   6. Redis (redis-cli ping) und OpenSearch/Elasticsearch, falls eingeschaltet.
#   7. Grosse Originalbilder unter public/media.
#
# Umgebungsvariablen:
#   SHOP_URL        Basis-URL für den Abruf-Test (Default: leer = kein Test)
#   AUDIT_WAIT      Pause zwischen den beiden Abrufen in Sekunden (Default: 2,
#                   damit Age bei einem Treffer mindestens 1 ist)
#   IMAGE_MIN_KB    Schwelle für grosse Bilder in KB (Default: 500)
#   PHP_FPM_CMD     FPM-Binary; leer = alle php-fpm* unter /usr/sbin, /usr/local/sbin
#   CONSOLE_CMD, PHP_CMD, CURL_CMD, REDIS_CLI_CMD, PGREP_CMD
#                   Befehle (Defaults: bin/console, php, curl, redis-cli, pgrep),
#                   für Tests austauschbar
#
# Exit-Codes: 0 Audit gelaufen, 1 kein Shopware-Verzeichnis, 2 falscher Aufruf
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -euo pipefail

SHOP_URL="${SHOP_URL:-}"
AUDIT_WAIT="${AUDIT_WAIT:-2}"
IMAGE_MIN_KB="${IMAGE_MIN_KB:-500}"
read -r -a CONSOLE <<< "${CONSOLE_CMD:-bin/console}"
read -r -a PHP <<< "${PHP_CMD:-php}"
read -r -a CURL <<< "${CURL_CMD:-curl}"
read -r -a REDIS_CLI <<< "${REDIS_CLI_CMD:-redis-cli}"
read -r -a PGREP <<< "${PGREP_CMD:-pgrep}"

show_usage() {
    echo "Usage: $0 [shopware-verzeichnis]"
    echo ""
    echo "Bestandsaufnahme für das Performance-Audit (liest nur)."
    echo "Ohne Argument wird das aktuelle Verzeichnis geprüft."
    echo ""
    echo "Beispiele:"
    echo "  sudo -u www-data $0 /var/www/shopware"
    echo "  SHOP_URL=https://ihr-shop.ch sudo -E -u www-data $0 /var/www/shopware"
}

SHOPWARE_ROOT="."
case "$#" in
    0) ;;
    1)
        case "$1" in
            -h|--help) show_usage; exit 0 ;;
            -*) echo "Unbekannte Option: $1" >&2; show_usage >&2; exit 2 ;;
            *) SHOPWARE_ROOT="$1" ;;
        esac
        ;;
    *) show_usage >&2; exit 2 ;;
esac

if [[ ! -f "${SHOPWARE_ROOT}/bin/console" ]]; then
    echo "Fehler: ${SHOPWARE_ROOT}/bin/console nicht gefunden - kein Shopware-Verzeichnis." >&2
    exit 1
fi
cd "${SHOPWARE_ROOT}"

section() {
    echo ""
    echo "== $1 =="
}

# Erste Zeile einer Ausgabe, ohne head (SIGPIPE unter pipefail)
first_line() {
    printf '%s\n' "${1%%$'\n'*}"
}

# Wert einer Direktive aus "php -i"-Ausgabe: "name => lokal => master"
ini_value() {
    awk -F ' => ' -v name="$1" '$1 == name { print $2; exit }' <<< "$2"
}

# Wert einer Variablen aus der debug:dotenv-Tabelle (leer, wenn nicht gesetzt)
dotenv_value() {
    awk -v name="$1" '$1 == name { print $2; exit }' <<< "$2"
}

echo "Shopware Performance-Audit - $(date '+%Y-%m-%d %H:%M')"
echo "Verzeichnis: $(pwd)"

# --- 1. Versionen ------------------------------------------------------------
section "1. Versionen"

sw_version=$("${CONSOLE[@]}" --version 2>/dev/null) || sw_version="nicht ermittelbar"
echo "Shopware:  $(first_line "$sw_version")"

php_cli=$("${PHP[@]}" -r 'echo PHP_VERSION;' 2>/dev/null) || php_cli="nicht ermittelbar"
echo "PHP (CLI): ${php_cli}"

fpm_bins=()
if [[ -n "${PHP_FPM_CMD:-}" ]]; then
    fpm_bins=("${PHP_FPM_CMD}")
else
    for f in /usr/sbin/php-fpm* /usr/local/sbin/php-fpm*; do
        [[ -x "$f" ]] && fpm_bins+=("$f")
    done
fi
if [[ ${#fpm_bins[@]} -eq 0 ]]; then
    echo "PHP-FPM:   keine php-fpm-Binary gefunden (Apache mit mod_php? Dann phpinfo() im Web prüfen)"
fi
for f in "${fpm_bins[@]}"; do
    v=$("$f" -v 2>/dev/null) || v="nicht ermittelbar"
    echo "PHP-FPM:   ${f}: $(first_line "$v")"
done
if [[ ${#fpm_bins[@]} -gt 1 ]]; then
    echo "           Mehrere FPM-Versionen installiert: welche der Webserver nutzt,"
    echo "           steht in der nginx-/Apache-Konfiguration (fastcgi_pass)."
fi

# --- 2. Plugins --------------------------------------------------------------
section "2. Plugins"

plugins_json=$("${CONSOLE[@]}" plugin:list --json 2>/dev/null) || plugins_json=""
active_plugins=$("${PHP[@]}" -r '
    $all = json_decode(stream_get_contents(STDIN), true);
    if (!is_array($all)) { exit(1); }
    $active = array_filter($all, fn ($p) => !empty($p["active"]));
    echo count($active), " von ", count($all), " installierten Plugins aktiv\n";
    foreach ($active as $p) { echo "  - ", $p["name"], " ", $p["version"] ?? "", "\n"; }
' <<< "$plugins_json" 2>/dev/null) || active_plugins="nicht ermittelbar (plugin:list --json)"
echo "$active_plugins"
echo "Eine belegte Obergrenze gibt es nicht: teuer ist ein einzelnes Plugin, nicht"
echo "die Anzahl. Was ein Plugin kostet, misst Kapitel 17 (A-B-A-Messung)."

# --- 3. HTTP-Cache -----------------------------------------------------------
section "3. HTTP-Cache"

dotenv=$("${CONSOLE[@]}" debug:dotenv 2>/dev/null) || dotenv=""
cache_enabled=$(dotenv_value SHOPWARE_HTTP_CACHE_ENABLED "$dotenv")
cache_ttl=$(dotenv_value SHOPWARE_HTTP_DEFAULT_TTL "$dotenv")
echo "SHOPWARE_HTTP_CACHE_ENABLED: ${cache_enabled:-nicht gesetzt (Vorgabe 1)}"
echo "SHOPWARE_HTTP_DEFAULT_TTL:   ${cache_ttl:-nicht gesetzt (Vorgabe 7200)}"
if [[ "${cache_enabled}" == "0" || "${cache_enabled}" == "false" ]]; then
    echo "WARNUNG: HTTP-Cache ist abgeschaltet."
fi
echo "Das ist die Sicht der CLI. Setzt der Webserver die Variable selbst (FPM-Pool,"
echo "Container-Umgebung), gilt dort ein anderer Wert - der Abruf-Test zeigt die Wirkung."

if [[ -n "${SHOP_URL}" ]]; then
    url="${SHOP_URL%/}/"
    age=""
    for i in 1 2; do
        sleep "${AUDIT_WAIT}"
        headers=$("${CURL[@]}" -s -o /dev/null -D - -w 'ttfb: %{time_starttransfer}\n' "$url" 2>/dev/null) || headers=""
        ttfb=$(awk 'tolower($1) == "ttfb:" { print $2; exit }' <<< "$headers")
        age=$(awk 'tolower($1) == "age:" { gsub(/\r/, "", $2); print $2; exit }' <<< "$headers")
        echo "Abruf ${i} (Gast, ohne Cookies): TTFB ${ttfb:-?} s, Age ${age:--}"
    done
    if [[ "${age}" =~ ^[0-9]+$ && "${age}" -gt 0 ]]; then
        echo "Treffer: der zweite Abruf kam aus dem Cache."
    else
        echo "Kein Treffer erkennbar. Age: 0 allein ist kein Treffer."
        echo "Details: Kapitel 6, scripts/cache-debug.sh"
    fi
else
    echo "Abruf-Test übersprungen (SHOP_URL nicht gesetzt)."
fi

# --- 4. OPcache (FPM) --------------------------------------------------------
section "4. OPcache der PHP-FPM-SAPI"

for f in "${fpm_bins[@]}"; do
    ini=$("$f" -i 2>/dev/null) || ini=""
    if [[ -z "$ini" ]]; then
        echo "${f}: -i liefert nichts"
        continue
    fi
    enable=$(ini_value opcache.enable "$ini")
    memory=$(ini_value opcache.memory_consumption "$ini")
    timestamps=$(ini_value opcache.validate_timestamps "$ini")
    jit=$(ini_value opcache.jit "$ini")
    jit_buffer=$(ini_value opcache.jit_buffer_size "$ini")
    echo "${f}:"
    echo "  opcache.enable              ${enable:-nicht geladen}"
    echo "  opcache.memory_consumption  ${memory:--} MB"
    echo "  opcache.validate_timestamps ${timestamps:--}"
    case "${jit}" in
        ""|"no value"|off|disable|0) jit_state="aus" ;;
        *) if [[ "${jit_buffer}" == "0" ]]; then jit_state="aus (jit_buffer_size = 0)"; else jit_state="an (${jit})"; fi ;;
    esac
    echo "  JIT                         ${jit_state}"
    if [[ "${enable}" != "On" && "${enable}" != "1" ]]; then
        echo "  WARNUNG: OPcache ist für FPM nicht aktiv."
    fi
done
echo "Konfiguration und Begründung (auch, warum JIT aus bleibt): Kapitel 9."

# --- 5. Message Queue --------------------------------------------------------
section "5. Message Queue"

count_procs() {
    local n
    n=$("${PGREP[@]}" -fc "(^|/)php[0-9.]* .*bin/console $1") || true
    echo "${n:-0}"
}
consumers=$(count_procs "messenger:consume")
schedulers=$(count_procs "scheduled-task:run")
echo "Laufende messenger:consume-Prozesse:   ${consumers}"
echo "Laufende scheduled-task:run-Prozesse:  ${schedulers}"

admin_json=$("${CONSOLE[@]}" debug:container --parameter=shopware.admin_worker.enable_admin_worker --format=json 2>/dev/null) || admin_json=""
admin_worker=$("${PHP[@]}" -r '
    $p = json_decode(stream_get_contents(STDIN), true);
    if (!is_array($p)) { exit(1); }
    echo current($p) ? "an" : "aus";
' <<< "$admin_json" 2>/dev/null) || admin_worker="nicht ermittelbar"
echo "Admin-Worker (enable_admin_worker):    ${admin_worker}"

if [[ "${consumers}" -eq 0 && "${admin_worker}" == "an" ]]; then
    echo "WARNUNG: Die Queue wird nur abgearbeitet, solange jemand im Admin angemeldet ist."
elif [[ "${consumers}" -eq 0 && "${admin_worker}" == "aus" ]]; then
    echo "FEHLER: Kein CLI-Worker und kein Admin-Worker - die Queue wird nicht abgearbeitet."
elif [[ "${consumers}" -gt 0 && "${admin_worker}" == "an" ]]; then
    echo "Hinweis: CLI-Worker läuft, der Admin-Worker ist trotzdem an (Anhang C schaltet ihn ab)."
fi
if [[ "${consumers}" -gt 0 && "${schedulers}" -eq 0 && "${admin_worker}" == "aus" ]]; then
    echo "WARNUNG: Kein scheduled-task:run - geplante Aufgaben werden nicht mehr eingestellt."
fi

# messenger:stats schreibt die Tabelle auf stderr, deshalb 2>&1
stats=$("${CONSOLE[@]}" messenger:stats 2>&1) || stats=""
rows=$(grep -E '^ +[a-z_]+ +[0-9]+ *$' <<< "$stats") || rows=""
if [[ -n "$rows" ]]; then
    echo "Wartende Nachrichten je Transport:"
    echo "$rows"
fi
echo "Worker-Einrichtung (Supervisor, async + low_priority): Anhang C."

# --- 6. Redis und Suche ------------------------------------------------------
section "6. Redis und Suche"

if command -v "${REDIS_CLI[0]}" > /dev/null 2>&1; then
    pong=$("${REDIS_CLI[@]}" ping 2>/dev/null) || pong=""
    if [[ "$pong" == "PONG" ]]; then
        echo "Redis: antwortet (ob Shopware ihn nutzt, zeigt die Konfiguration, nicht der Ping)"
    else
        echo "Redis: redis-cli vorhanden, Server antwortet nicht"
    fi
else
    echo "Redis: redis-cli nicht installiert"
fi

es_enabled=$(dotenv_value SHOPWARE_ES_ENABLED "$dotenv")
es_url=$(dotenv_value OPENSEARCH_URL "$dotenv")
if [[ "${es_enabled}" == "1" || "${es_enabled}" == "true" ]]; then
    health=$("${CURL[@]}" -s -m 5 "${es_url%/}/_cluster/health" 2>/dev/null) || health=""
    status=$("${PHP[@]}" -r '
        $h = json_decode(stream_get_contents(STDIN), true);
        echo is_array($h) && isset($h["status"]) ? $h["status"] : "";
    ' <<< "$health" 2>/dev/null) || status=""
    echo "OpenSearch/Elasticsearch (${es_url}): ${status:-nicht erreichbar}"
else
    echo "Suche: MySQL (SHOPWARE_ES_ENABLED=${es_enabled:-0})."
    echo "Kapitel 18: Evaluierung von Elasticsearch ab rund 30 000 Produkten."
fi

# --- 7. Bilder ---------------------------------------------------------------
section "7. Grosse Originalbilder (> ${IMAGE_MIN_KB} KB)"

if [[ -d public/media ]]; then
    sizes=$(find public/media -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
        -size "+${IMAGE_MIN_KB}k" -exec stat -c '%s %n' {} + 2>/dev/null | sort -rn) || true
    if [[ -z "$sizes" ]]; then
        echo "Keine."
    else
        echo "Anzahl: $(grep -c . <<< "$sizes")"
        echo "Die fünf grössten (Bytes, Pfad):"
        n=0
        while IFS= read -r line; do
            echo "  ${line}"
            n=$((n + 1))
            [[ $n -ge 5 ]] && break
        done <<< "$sizes"
    fi
    echo "Ausgeliefert werden meist Thumbnails; mehr dazu: scripts/analyze-images.sh, Kapitel 4."
else
    echo "public/media nicht gefunden (externer Speicher wie S3?)."
fi

echo ""
echo "Fertig. Nächste Schritte: PageSpeed Insights und Lighthouse für die fünf"
echo "wichtigsten URLs, dann templates/AUDIT-TEMPLATE.md ausfüllen."
