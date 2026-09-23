#!/bin/bash
#
# Shopware 6 Performance-Audit: Bestandsaufnahme auf dem Server
# Kapitel 2: Performance-Audit — Wo stehen Sie?
#
# Liest nur, ändert nichts. Aufruf als der Benutzer, unter dem der Shop läuft
# (meist www-data), im Shopware-Verzeichnis oder mit dem Pfad als Argument.
#
# Geprüft wird (getestet mit Shopware 6.6.10.6):
#   1. Versionen: Shopware, PHP-CLI und jede gefundene PHP-FPM-Binary, dazu,
#      welche davon läuft. php -v zeigt nur die CLI.
#   2. Plugins: aktive Plugins über plugin:list --json.
#      plugin:list --active gibt es nicht, plugin:list | wc -l zählt Tabellenrahmen.
#   3. HTTP-Cache: SHOPWARE_HTTP_CACHE_ENABLED/_DEFAULT_TTL über debug:dotenv,
#      mit SHOP_URL zusätzlich zwei Abrufe als Gast. Treffer = Age wächst um
#      mindestens die Pause UND Date bleibt gleich: Nur eine gespeicherte Kopie
#      wiederholt ihr Date. Gibt Symfony X-Symfony-Cache aus (dev oder
#      framework.http_cache.trace_level), entscheidet der Header, nur "fresh"
#      ist ein Treffer. Age allein reicht nicht: Symfony setzt beim Speichern
#      Age = Sekunden seit Date, und ab 6.7 trägt jede Seite das Age ihres
#      ältesten ESI-Fragments (Header, Footer), auch der nie gecachte Warenkorb.
#      Wächst Age, Date aber auch, ist es nicht entscheidbar: ESI-Fragment oder
#      ein Proxy davor, der Date neu setzt (nginx proxy_pass).
#      debug:config bricht in APP_ENV=prod mit "frozen ParameterBag" ab.
#      debug:dotenv kennt nur Variablen aus .env-Dateien (auch .env.prod.local);
#      eine Variable, die nur in der Umgebung steht (FPM env[], Apache SetEnv),
#      sieht es nicht. Die Sicht des Webservers zeigt die Administration unter
#      Einstellungen > System > Caches & Indizes.
#   4. OPcache der FPM-SAPI über php-fpmX.Y -i. php -i liest die CLI-Konfiguration.
#      Als www-data fehlen ini-Dateien, die nur root lesen darf - das Skript
#      meldet sie. Pool-Werte (php_admin_value) zeigt -i nicht.
#   5. Message Queue: CLI-Worker auf diesem Host (aus ps), Admin-Worker-Schalter,
#      messenger:stats.
#   6. Redis (redis-cli ping) und OpenSearch/Elasticsearch, falls eingeschaltet.
#   7. Grosse Originalbilder unter public/media.
#
# Umgebungsvariablen:
#   SHOP_URL        Basis-URL für den Abruf-Test (Default: leer = kein Test)
#   AUDIT_WAIT      Pause zwischen den beiden Abrufen in ganzen Sekunden
#                   (Default: 2, mindestens 1)
#   IMAGE_MIN_KB    Schwelle für grosse Bilder in KB (Default: 500)
#   PHP_FPM_CMD     FPM-Binary; leer = alle php-fpm* unter /usr/sbin, /usr/local/sbin
#   CONSOLE_CMD, PHP_CMD, CURL_CMD, REDIS_CLI_CMD, PS_CMD
#                   Befehle (Defaults: bin/console, php, curl, redis-cli,
#                   "ps -eo args"), für Tests austauschbar
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
read -r -a PS <<< "${PS_CMD:-ps -eo args}"

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

if ! [[ "${AUDIT_WAIT}" =~ ^[0-9]+$ ]] || [[ "${AUDIT_WAIT}" -lt 1 ]]; then
    echo "Fehler: AUDIT_WAIT muss eine ganze Zahl >= 1 sein: ${AUDIT_WAIT}" >&2
    exit 2
fi
if ! [[ "${IMAGE_MIN_KB}" =~ ^[0-9]+$ ]]; then
    echo "Fehler: IMAGE_MIN_KB muss eine ganze Zahl in KB sein: ${IMAGE_MIN_KB}" >&2
    exit 2
fi

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

# Zeile einer Variablen aus der debug:dotenv-Tabelle: "gesetzt|<wert>" oder leer.
# Ein leerer Wert verschiebt die Spalten; dann steht in Spalte 2 "n/a".
dotenv_value() {
    awk -v name="$1" '$1 == name { v = ($2 == "n/a") ? "" : $2; print "gesetzt|" v; exit }' <<< "$2"
}

# Wert eines Antwort-Headers (Name ohne Doppelpunkt, gross/klein egal), ohne CR
response_header() {
    awk -v key="$1" '{
        i = index($0, ":")
        if (i > 1 && tolower(substr($0, 1, i - 1)) == key) {
            v = substr($0, i + 1); sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit
        }
    }' <<< "$2"
}

# Shopware übergibt den Wert ohne bool:-Prozessor an einen bool-Parameter;
# PHP castet: nur "0" und "" sind falsch, "false", "off" oder "no" sind an.
php_bool() {
    case "$1" in
        0|"") echo "aus" ;;
        *) echo "an" ;;
    esac
}

echo "Shopware Performance-Audit - $(date '+%Y-%m-%d %H:%M')"
echo "Verzeichnis: $(pwd)"

procs=$("${PS[@]}" 2>/dev/null) || procs=""

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

# Läuft ein FPM-Master dieser Version? Debian/Ubuntu: "(/etc/php/8.3/fpm/...)"
fpm_running() {
    local ver="${1##*php-fpm}" line
    while IFS= read -r line; do
        [[ "$line" == "php-fpm: master process"* ]] || continue
        if [[ -z "$ver" || "$line" == *"/${ver}/"* ]]; then
            return 0
        fi
    done <<< "$procs"
    return 1
}

if [[ ${#fpm_bins[@]} -eq 0 ]]; then
    echo "PHP-FPM:   keine php-fpm-Binary gefunden (Apache mit mod_php? Dann phpinfo() im Web prüfen)"
fi
for f in ${fpm_bins[@]+"${fpm_bins[@]}"}; do
    v=$("$f" -v 2>/dev/null) || v="nicht ermittelbar"
    state="installiert, kein Master-Prozess gefunden"
    fpm_running "$f" && state="läuft"
    echo "PHP-FPM:   ${f}: $(first_line "$v") [${state}]"
done
if [[ ${#fpm_bins[@]} -gt 1 ]]; then
    echo "           Mehrere FPM-Versionen installiert. Welche der Webserver anspricht,"
    echo "           steht in dessen Konfiguration (nginx: fastcgi_pass, Apache: SetHandler proxy:...)."
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

dotenv_ok=1
dotenv=$("${CONSOLE[@]}" debug:dotenv 2>/dev/null) || { dotenv=""; dotenv_ok=0; }

if [[ ${dotenv_ok} -eq 0 ]]; then
    echo "debug:dotenv nicht verfügbar (keine .env?) - Schalter aus Sicht der CLI nicht ermittelbar."
else
    enabled_row=$(dotenv_value SHOPWARE_HTTP_CACHE_ENABLED "$dotenv")
    ttl_row=$(dotenv_value SHOPWARE_HTTP_DEFAULT_TTL "$dotenv")
    if [[ -z "${enabled_row}" ]]; then
        echo "SHOPWARE_HTTP_CACHE_ENABLED: in keiner .env-Datei (Vorgabe 1, sofern die Umgebung nichts setzt)"
    else
        enabled="${enabled_row#gesetzt|}"
        echo "SHOPWARE_HTTP_CACHE_ENABLED: ${enabled:-leer} (wirkt als: $(php_bool "${enabled}"))"
        if [[ -z "${enabled}" ]]; then
            echo "Hinweis: leerer Wert - Shopware nimmt die Vorgabe 1."
        elif [[ "${enabled}" == "0" ]]; then
            echo "WARNUNG: HTTP-Cache ist abgeschaltet."
        elif [[ "${enabled}" != "1" ]]; then
            echo "Hinweis: Nur 0 schaltet ab. Shopware castet den Wert nach PHP-Regeln,"
            echo "         «${enabled}» gilt als an."
        fi
    fi
    if [[ -z "${ttl_row}" ]]; then
        echo "SHOPWARE_HTTP_DEFAULT_TTL:   in keiner .env-Datei (Vorgabe 7200, sofern die Umgebung nichts setzt)"
    else
        ttl="${ttl_row#gesetzt|}"
        echo "SHOPWARE_HTTP_DEFAULT_TTL:   ${ttl:-leer (Vorgabe 7200)}"
    fi
fi
echo "Das ist die Sicht der CLI. Setzt der Webserver die Variable selbst (FPM env[],"
echo "Apache SetEnv, Container-Umgebung), gilt dort ein anderer Wert. Die Sicht des"
echo "Webservers: Administration > Einstellungen > System > Caches & Indizes (HTTP-Cache An/Aus)."

if [[ -n "${SHOP_URL}" ]]; then
    url="${SHOP_URL%/}/"
    ages=()
    dates=()
    trace=""
    for i in 1 2; do
        sleep "${AUDIT_WAIT}"
        headers=$("${CURL[@]}" -s -o /dev/null -D - -w 'ttfb: %{time_starttransfer}\n' "$url" 2>/dev/null) || headers=""
        ttfb=$(awk 'tolower($1) == "ttfb:" { print $2; exit }' <<< "$headers")
        age=$(response_header age "$headers")
        date_hdr=$(response_header date "$headers")
        trace=$(response_header x-symfony-cache "$headers")
        echo "Abruf ${i} (Gast, ohne Cookies): TTFB ${ttfb:-?} s, Age ${age:--}, Date ${date_hdr:--}${trace:+, X-Symfony-Cache ${trace}}"
        ages+=("${age}")
        dates+=("${date_hdr}")
    done
    # Symfonys Trace entscheidet, wenn er da ist. Er nennt zuerst die Hauptanfrage,
    # ESI-Fragmente folgen nach ";". Nur "fresh" zählt: "valid" hat die Seite neu gerendert.
    main_trace="${trace%%;*}"
    main_trace="${main_trace##*: }"
    trace_hit=0
    for token in ${main_trace//[\/,]/ }; do
        [[ "${token}" == "fresh" ]] && trace_hit=1
    done
    aged=0
    if [[ "${ages[0]}" =~ ^[0-9]+$ && "${ages[1]}" =~ ^[0-9]+$ ]] \
        && [[ $((ages[1] - ages[0])) -ge "${AUDIT_WAIT}" ]]; then
        aged=1
    fi
    if [[ -n "${trace}" && "${trace_hit}" -eq 1 ]]; then
        echo "Treffer: X-Symfony-Cache meldet \"fresh\" für den 2. Abruf."
    elif [[ -n "${trace}" ]]; then
        echo "Kein Treffer: X-Symfony-Cache meldet \"${main_trace}\" für den 2. Abruf."
        echo "Einstellung und Messung des Caches: Kapitel 6."
    elif [[ "${aged}" -eq 1 && -n "${dates[0]}" && "${dates[0]}" == "${dates[1]}" ]]; then
        echo "Treffer: Age ist um mindestens die Pause (${AUDIT_WAIT} s) gewachsen, Date unverändert."
    elif [[ "${aged}" -eq 1 ]]; then
        echo "Nicht entscheidbar: Age ist um die Pause gewachsen, Date aber nicht gleich geblieben."
        echo "Entweder bindet die neu gerenderte Seite ein gecachtes ESI-Fragment ein (ab 6.7"
        echo "Header und Footer, dann trägt sie dessen Age), oder ein Proxy davor setzt Date neu"
        echo "(nginx proxy_pass ohne proxy_pass_header Date). Eindeutig mit"
        echo "framework.http_cache.trace_level: short (Kapitel 6)."
    else
        echo "Kein Treffer erkennbar. Age > 0 allein ist kein Treffer: beim MISS"
        echo "steht dort die Zeit seit dem Date-Header, ab 6.7 das Age der ESI-Fragmente."
        echo "Einstellung und Messung des Caches: Kapitel 6."
    fi
else
    echo "Abruf-Test übersprungen (SHOP_URL nicht gesetzt)."
fi

# --- 4. OPcache (FPM) --------------------------------------------------------
section "4. OPcache der PHP-FPM-SAPI"

for f in ${fpm_bins[@]+"${fpm_bins[@]}"}; do
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
    scan_dir=$(ini_value "Scan this dir for additional .ini files" "$ini")
    echo "${f}:"
    echo "  opcache.enable              ${enable:-nicht geladen}"
    echo "  opcache.memory_consumption  ${memory:--} MB"
    echo "  opcache.validate_timestamps ${timestamps:--}"
    case "${jit}" in
        ""|"no value"|off|disable|0) jit_state="aus" ;;
        *) if [[ "${jit_buffer}" == "0" ]]; then jit_state="aus (jit_buffer_size = 0)"; else jit_state="konfiguriert (${jit}); ob er läuft, zeigt nur opcache_get_status() im Request"; fi ;;
    esac
    echo "  JIT                         ${jit_state}"
    if [[ "${enable}" != "On" && "${enable}" != "1" ]]; then
        echo "  WARNUNG: OPcache ist für FPM nicht aktiv."
    fi
    # Als www-data unlesbare ini-Dateien fehlen in -i, FPM (root) liest sie
    if [[ -n "${scan_dir}" && -d "${scan_dir}" ]]; then
        for ini_file in "${scan_dir}"/*.ini; do
            [[ -e "${ini_file}" && ! -r "${ini_file}" ]] || continue
            echo "  WARNUNG: ${ini_file} ist für $(id -un) nicht lesbar - die Werte oben"
            echo "           können von dem abweichen, was FPM lädt (Kapitel 9)."
        done
    fi
done
echo "Pool-Werte (php_admin_value[...]) zeigt -i nicht."
echo "Konfiguration und Begründung (auch, warum JIT aus bleibt): Kapitel 9."

# --- 5. Message Queue --------------------------------------------------------
section "5. Message Queue (Prozesse auf diesem Host)"

consume_re='^([^ ]*/)?php[0-9.]* .*bin/console( -[^ ]+( [^- ][^ ]*)?)* messenger:consume( |$)'
task_re='^([^ ]*/)?php[0-9.]* .*bin/console( -[^ ]+( [^- ][^ ]*)?)* scheduled-task:run( |$)'
consumers=0
schedulers=0
low_priority=0
while IFS= read -r line; do
    if [[ "$line" =~ $consume_re ]]; then
        consumers=$((consumers + 1))
        [[ "$line" == *" low_priority"* ]] && low_priority=$((low_priority + 1))
        [[ "$line" == *" scheduler_shopware"* ]] && schedulers=$((schedulers + 1))
    elif [[ "$line" =~ $task_re ]]; then
        schedulers=$((schedulers + 1))
    fi
done <<< "$procs"
echo "Laufende messenger:consume-Prozesse:   ${consumers}"
echo "davon mit low_priority:                ${low_priority}"
echo "Scheduler (scheduled-task:run oder scheduler_shopware): ${schedulers}"

admin_json=$("${CONSOLE[@]}" debug:container --parameter=shopware.admin_worker.enable_admin_worker --format=json 2>/dev/null) || admin_json=""
admin_worker=$("${PHP[@]}" -r '
    $p = json_decode(stream_get_contents(STDIN), true);
    if (!is_array($p)) { exit(1); }
    echo current($p) ? "an" : "aus";
' <<< "$admin_json" 2>/dev/null) || admin_worker="nicht ermittelbar"
echo "Admin-Worker (enable_admin_worker):    ${admin_worker}"

if [[ "${consumers}" -eq 0 && "${admin_worker}" == "an" ]]; then
    echo "WARNUNG: Auf diesem Host läuft kein CLI-Worker - die Queue wird nur abgearbeitet,"
    echo "         solange jemand im Admin angemeldet ist (oder Worker laufen auf einem anderen Host)."
elif [[ "${consumers}" -eq 0 && "${admin_worker}" == "aus" ]]; then
    echo "WARNUNG: Kein CLI-Worker auf diesem Host und Admin-Worker aus. Laufen die Worker"
    echo "         nicht anderswo, wird die Queue nicht abgearbeitet (messenger:stats unten)."
elif [[ "${consumers}" -gt 0 && "${admin_worker}" == "an" ]]; then
    echo "Hinweis: CLI-Worker läuft, der Admin-Worker ist trotzdem an (Anhang C schaltet ihn ab)."
fi
if [[ "${consumers}" -gt 0 && "${low_priority}" -eq 0 ]]; then
    echo "Hinweis: Kein Worker konsumiert low_priority - der Transport bleibt liegen, sobald der"
    echo "         Admin-Worker aus ist (Anhang C: messenger:consume async low_priority)."
fi
if [[ "${consumers}" -gt 0 && "${schedulers}" -eq 0 && "${admin_worker}" == "aus" ]]; then
    echo "Hinweis: Kein laufender Scheduler gefunden. Bei Cron mit scheduled-task:run --no-wait"
    echo "         ist das normal; sonst werden geplante Aufgaben nicht mehr eingestellt."
fi

# messenger:stats schreibt die Tabelle auf stderr, deshalb 2>&1
stats=$("${CONSOLE[@]}" messenger:stats 2>&1) || stats=""
rows=$(grep -E '^ +[A-Za-z0-9_.-]+ +[0-9]+ *$' <<< "$stats") || rows=""
if [[ -n "$rows" ]]; then
    echo "Nachrichten je Transport (failed = fehlgeschlagen, sonst wartend):"
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
        echo "Redis: keine Antwort von redis-cli ping (Standard localhost:6379 ohne Passwort;"
        echo "       anderer Host oder AUTH? Dann REDIS_CLI_CMD mit -h/-a setzen)"
    fi
else
    echo "Redis: redis-cli nicht installiert"
fi

if [[ ${dotenv_ok} -eq 0 ]]; then
    echo "Suche: nicht ermittelbar (debug:dotenv nicht verfügbar)."
else
    es_row=$(dotenv_value SHOPWARE_ES_ENABLED "$dotenv")
    es_enabled="${es_row#gesetzt|}"
    url_row=$(dotenv_value OPENSEARCH_URL "$dotenv")
    es_url="${url_row#gesetzt|}"
    es_url="${es_url%%,*}"
    case "${es_enabled,,}" in
        1|true|on|yes)
            health=$("${CURL[@]}" -s -m 5 "${es_url%/}/_cluster/health" 2>/dev/null) || health=""
            status=$("${PHP[@]}" -r '
                $h = json_decode(stream_get_contents(STDIN), true);
                echo is_array($h) && isset($h["status"]) ? $h["status"] : "";
            ' <<< "$health" 2>/dev/null) || status=""
            echo "OpenSearch/Elasticsearch (${es_url}): ${status:-nicht erreichbar}"
            ;;
        *)
            echo "Suche: MySQL (SHOPWARE_ES_ENABLED=${es_enabled:-nicht gesetzt})."
            echo "Kapitel 18: Evaluierung von Elasticsearch ab rund 30 000 Produkten."
            ;;
    esac
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
echo "Nicht geprüft: MySQL (Buffer Pool, Slow Query Log) - Befehle in Kapitel 2, Schritt 4."
echo "Fertig. Nächste Schritte: PageSpeed Insights und Lighthouse für die fünf"
echo "wichtigsten URLs, dann templates/AUDIT-TEMPLATE.md ausfüllen."
