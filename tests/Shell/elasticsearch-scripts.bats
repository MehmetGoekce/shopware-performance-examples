#!/usr/bin/env bats

# BATS-Tests fuer die Kapitel-18-Skripte.
# curl wird durch einen Stub auf dem PATH ersetzt, der aus Fixtures antwortet —
# so laufen Fehlerpfade (HTTP 400, fehlender Index) ohne Cluster.

DIR="./chapters/18-shopware-elasticsearch/scripts"

# es-benchmark.sh setzt jq voraus. Das bats/bats-Image bringt es nicht mit
# (BusyBox), GNU-Umgebungen und die CI schon — dort laufen die Tests wirklich.
require_jq() {
    command -v jq > /dev/null 2>&1 || skip "jq fehlt in dieser Umgebung"
}

setup() {
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin"

    # Stub: antwortet je nach angefragtem Pfad. CURL_CASE steuert, welche
    # Antwort die _search-Aufrufe bekommen.
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/bash
url=""
write_out=""
outfile=""
prev=""
for a in "$@"; do
    case "$prev" in
        -w) write_out="$a" ;;
        -o) outfile="$a" ;;
    esac
    case "$a" in
        http*) url="$a" ;;
    esac
    prev="$a"
done

emit() {
    if [[ -n "$outfile" ]]; then
        printf '%s' "$1" > "$outfile"
    else
        printf '%s' "$1"
    fi
    if [[ -n "$write_out" ]]; then
        # Erst ersetzen, dann ausgeben: printf wuerde "%{http_code}" sonst als
        # eigene Formatangabe lesen ("invalid format character").
        local rendered
        rendered=$(printf '%s' "$write_out" | sed -e "s/%{http_code}/$2/" -e "s/%{time_total}/0.004/")
        printf '%b' "$rendered"
    fi
}

case "$url" in
    *_count*)
        if [[ "${CURL_CASE:-ok}" == "missing" ]]; then
            emit '{"error":{"type":"index_not_found_exception"},"status":404}' 404
        else
            emit '{"count":14}' 200
        fi
        ;;
    *_search*)
        if [[ "${CURL_CASE:-ok}" == "badquery" ]]; then
            emit '{"error":{"type":"x_content_parse_exception","reason":"Unexpected close marker"},"status":400}' 400
        else
            emit '{"took":3,"hits":{"total":{"value":7}},"aggregations":{"pn":{"buckets":[{"key":"swdemo10001"}]}}}' 200
        fi
        ;;
    *)
        emit '{}' 200
        ;;
esac
exit 0
STUB
    chmod +x "$TMP/bin/curl"
    PATH="$TMP/bin:$PATH"
    export PATH
}

teardown() {
    rm -rf "$TMP"
}

# --- es-benchmark.sh -------------------------------------------------------

@test "es-benchmark.sh: --help zeigt Usage und endet mit 0" {
    run "$DIR/es-benchmark.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "es-benchmark.sh: unbekanntes Argument bricht ab statt still zu messen" {
    # `--iterations 20` mit Leerzeichen stand frueher in der Usage, wurde aber
    # nie ausgewertet — der Wert landete im Default.
    run "$DIR/es-benchmark.sh" --iterations 20
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown argument"* ]]
}

@test "es-benchmark.sh: nicht-numerische Iterationen werden abgewiesen" {
    run "$DIR/es-benchmark.sh" --iterations=zwei
    [ "$status" -eq 2 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "es-benchmark.sh: fehlender Index endet mit 4" {
    require_jq
    CURL_CASE=missing run "$DIR/es-benchmark.sh" --iterations=1
    [ "$status" -eq 4 ]
}

@test "es-benchmark.sh: abgelehnte Abfrage wird als FAILED gemeldet, Exit 1" {
    require_jq
    # Der Kern des Befunds: eine Abfrage, die Elasticsearch mit HTTP 400
    # zurueckweist, darf kein Messwert sein.
    # PRODUCT_NUMBER vorgeben, damit der Fehlerfall die Messabfragen trifft
    # und nicht schon die Ermittlung der Artikelnummer.
    CURL_CASE=badquery PRODUCT_NUMBER=swdemo10001 run "$DIR/es-benchmark.sh" --iterations=1
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAILED"* ]]
    [[ "$output" == *"HTTP 400"* ]]
}

@test "es-benchmark.sh: laeuft mit Komma-Locale durch" {
    require_jq
    # Die erste Fassung brach hier nach dem ersten Test ab
    # ("printf: 3.02: Ungueltige Zahl" plus set -e).
    locale -a 2>/dev/null | grep -qi '^de_DE' || skip "Locale de_DE fehlt in dieser Umgebung"
    LC_ALL=de_DE.UTF-8 LC_NUMERIC=de_DE.UTF-8 run "$DIR/es-benchmark.sh" --iterations=2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test 8"* ]]
    [[ "$output" != *"Ung"* ]]
}

@test "es-benchmark.sh: meldet Serverzeit und Trefferzahl getrennt" {
    require_jq
    run "$DIR/es-benchmark.sh" --iterations=2
    [ "$status" -eq 0 ]
    [[ "$output" == *"took avg"* ]]
    [[ "$output" == *"hits 7"* ]]
}

@test "es-benchmark.sh: Dokumentzahl kommt aus _count, nicht aus docs.count" {
    require_jq
    run "$DIR/es-benchmark.sh" --iterations=1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Documents:  14"* ]]
}

# --- extract-dictionary.sh -------------------------------------------------

@test "extract-dictionary.sh: schreibt die Wortliste klein" {
    # Ohne Kleinschreibung feuert der Decompounder aus 18.5 nie.
    cat > "$TMP/de.dic" <<'DIC'
3
Winterjacke/N
Kinderschuhe/N
Ärmel/N
DIC
    # BusyBox sed kann kein \L; dort waere der Test falsch rot.
    printf 'Ä\n' | LC_ALL=C.UTF-8 sed 's/.*/\L&/' | grep -q 'ä' || skip "sed ohne \\L auf UTF-8"
    run env OUT="$TMP/out.txt" "$DIR/extract-dictionary.sh" "$TMP/de.dic"
    [ "$status" -eq 0 ]
    run grep -c '[[:upper:]]' "$TMP/out.txt"
    [ "$output" = "0" ]
    run grep -c 'ärmel' "$TMP/out.txt"
    [ "$output" = "1" ]
}

# --- Hilfe und Exit-Codes der uebrigen Skripte -----------------------------

@test "es-reindex.sh: --help zeigt Usage, unbekannte Option endet mit 2" {
    run "$DIR/es-reindex.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]

    run "$DIR/es-reindex.sh" --quatsch
    [ "$status" -eq 2 ]
}

@test "slowlog-settings.sh: --help zeigt Usage, unbekannte Option endet mit 2" {
    run "$DIR/slowlog-settings.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]

    run "$DIR/slowlog-settings.sh" --quatsch
    [ "$status" -eq 2 ]
}

@test "es-index-stats.sh: --help zeigt Usage" {
    run "$DIR/es-index-stats.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "alle Kapitel-18-Skripte sind ausfuehrbar" {
    for script in "$DIR"/*.sh; do
        [ -x "$script" ] || fail "nicht ausfuehrbar: $script"
    done
}
