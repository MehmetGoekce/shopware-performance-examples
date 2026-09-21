#!/usr/bin/env bash
#
# Plugin-Kosten messen: dieselbe Seite mit und ohne Plugin.
#
# Ablauf A-B-A: mit Plugin, ohne Plugin, wieder mit Plugin. Jede
# Phase wärmt nach dem Cache-Leeren erst auf und misst dann RUNS
# Aufrufe. Jeder Aufruf trägt einen eigenen Query-Parameter, damit
# der HTTP-Cache nicht antwortet - sonst misst man einen Cache-Treffer,
# bei dem die meisten Plugins gar nicht laufen. Der Object-Cache ist
# nach dem Aufwärmen in allen Phasen warm.
#
# Verglichen werden Mediane. Weichen die beiden A-Phasen stärker
# voneinander ab als A von B, ist der Unterschied Rauschen (Last,
# CPU-Takt, andere Prozesse) und kein Plugin-Effekt.
#
# NICHT auf einem Live-Shop ausführen: Das Plugin ist während der
# B-Phase deaktiviert, und jede Phase leert den Cache. Als Benutzer
# des Webservers aufrufen (sudo -u www-data ...), sonst gehören die
# neu erzeugten Cache-Dateien root.
#
# Getestet gegen Shopware 6.6.10.6 (Dockware).
#
# @see Kapitel 17, "Plugin-Performance analysieren"

set -euo pipefail

SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
BASE_URL="${BASE_URL:-http://localhost}"
RUNS="${RUNS:-10}"
WARMUP="${WARMUP:-3}"
CONSOLE="${CONSOLE:-${SHOPWARE_ROOT}/bin/console}"
CURL="${CURL:-curl}"
PHP="${PHP:-php}"

usage() {
    cat <<EOF
Usage: $(basename "$0") <PluginName> [pfad]

Misst die Antwortzeit von <pfad> (Vorgabe: /) mit und ohne Plugin.

Umgebungsvariablen:
  SHOPWARE_ROOT  Shopware-Verzeichnis     (Vorgabe: /var/www/html)
  BASE_URL       Basis-URL des Shops      (Vorgabe: http://localhost)
  RUNS           Messungen je Phase       (Vorgabe: 10)
  WARMUP         Aufwärm-Aufrufe je Phase (Vorgabe: 3)

Exit-Codes: 0 gemessen, 1 Fehler, 2 falscher Aufruf
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    '') usage >&2; exit 2 ;;
esac

PLUGIN="$1"
URL_PATH="${2:-/}"

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ && "$WARMUP" =~ ^[0-9]+$ ]]; then
    echo "Fehler: RUNS muss >= 1 und WARMUP >= 0 sein." >&2
    exit 2
fi

# Ist das Plugin installiert und aktiv? Nur ein aktives Plugin darf das
# Skript deaktivieren - es aktiviert es am Ende wieder.
plugin_state() {
    "$CONSOLE" plugin:list --json 2>/dev/null | "$PHP" -r '
        $name = $argv[1];
        foreach (json_decode(stream_get_contents(STDIN), true) ?? [] as $p) {
            if (($p["name"] ?? null) === $name) {
                echo $p["active"] ? "active" : "inactive";
                exit(0);
            }
        }
        echo "missing";
    ' "$PLUGIN"
}

if ! STATE="$(plugin_state)"; then
    echo "Fehler: bin/console plugin:list ist fehlgeschlagen." >&2
    exit 1
fi
if [[ "$STATE" != active ]]; then
    echo "Fehler: Plugin '${PLUGIN}' ist nicht aktiv (Status: ${STATE})." >&2
    exit 1
fi

DEACTIVATED=0
restore() {
    if [[ "$DEACTIVATED" == 1 ]]; then
        echo "Aktiviere ${PLUGIN} wieder ..." >&2
        "$CONSOLE" plugin:activate --clearCache "$PLUGIN" >/dev/null
    fi
}

SEP='?'
[[ "$URL_PATH" == *\?* ]] && SEP='&'

# Ein Aufruf, am HTTP-Cache vorbei; gibt Sekunden aus (curl time_total).
# Nur HTTP 200 zählt: Eine Weiterleitung oder Fehlerseite misst nicht
# die Seite. SEO-URLs deshalb direkt angeben, nicht /detail/<id>.
# fetch läuft in $(...), also in einer Subshell: Ein Zähler würde dort
# nicht hochzählen. Der Parameter kommt deshalb aus der Uhrzeit.
fetch() {
    local out code
    if ! out="$("$CURL" -s -o /dev/null -w '%{http_code} %{time_total}' \
        "${BASE_URL}${URL_PATH}${SEP}plugin_profile=${EPOCHREALTIME/[.,]/}${RANDOM}")"; then
        echo "Fehler: ${BASE_URL}${URL_PATH} nicht erreichbar." >&2
        return 1
    fi
    code="${out%% *}"
    if [[ "$code" != 200 ]]; then
        echo "Fehler: ${BASE_URL}${URL_PATH} antwortet mit HTTP ${code}." >&2
        return 1
    fi
    echo "${out#* }"
}

# Median in Millisekunden aus einer Liste von Sekundenwerten
median_ms() {
    sort -g | awk '{ v[NR] = $1 * 1000 }
        END {
            if (NR == 0) { exit 1 }
            m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
            printf "%.1f\n", m
        }'
}

measure() {
    local label="$1" i times=""
    "$CONSOLE" cache:clear >/dev/null
    for ((i = 0; i < WARMUP; i++)); do fetch >/dev/null; done
    for ((i = 0; i < RUNS; i++)); do times+="$(fetch)"$'\n'; done
    printf '%s' "$times" | median_ms > "$TMP/$label"
    echo "  ${label}: Median $(cat "$TMP/$label") ms (${RUNS} Aufrufe)"
}

TMP="$(mktemp -d)"
trap 'restore; rm -rf "$TMP"' EXIT

echo "Plugin: ${PLUGIN}"
echo "Seite:  ${BASE_URL}${URL_PATH}"
echo ""

measure "A1-mit"

"$CONSOLE" plugin:deactivate "$PLUGIN" >/dev/null
DEACTIVATED=1
measure "B-ohne"

"$CONSOLE" plugin:activate "$PLUGIN" >/dev/null
DEACTIVATED=0
measure "A2-mit"

awk -v a1="$(cat "$TMP/A1-mit")" -v b="$(cat "$TMP/B-ohne")" -v a2="$(cat "$TMP/A2-mit")" '
    BEGIN {
        a = (a1 + a2) / 2
        drift = a1 - a2; if (drift < 0) drift = -drift
        diff = a - b; adiff = diff < 0 ? -diff : diff
        printf "\nMit Plugin (Mittel A1/A2): %.1f ms\n", a
        printf "Ohne Plugin:               %.1f ms\n", b
        printf "Unterschied:               %+.1f ms", diff
        if (b > 0) printf " (%+.1f %%)", diff / b * 100
        printf "\nStreuung A1 gegen A2:      %.1f ms\n\n", drift
        if (adiff <= drift) {
            print "Der Unterschied liegt innerhalb der Streuung - nicht belastbar."
            print "Mehr Aufrufe (RUNS) oder ein Profiler (Blackfire, Tideways)."
        } else {
            print "Der Unterschied ist grösser als die Streuung. Wo die Zeit"
            print "liegt, zeigt ein Profiler (Blackfire, Tideways)."
        }
    }'
