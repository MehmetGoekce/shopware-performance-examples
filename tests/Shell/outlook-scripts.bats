#!/usr/bin/env bats

# BATS-Tests fuer chapters/24-ausblick/scripts/measure-carbon.sh.
#
# curl ist ein Stub, der seine Argumente protokolliert und die Antwort von
# api.websitecarbon.com/data fuer 1 000 000 Bytes nachbildet (abgerufen
# 2026-09-23). Der echte Aufruf lief gegen die API und einen Lighthouse-12.6.1-
# Report (MEM-317).

SCRIPT="./chapters/24-ausblick/scripts/measure-carbon.sh"

setup() {
    [ -f "$SCRIPT" ] || skip "Skript fehlt: $SCRIPT"
    TMP="$(mktemp -d)"
    export CALLS="$TMP/calls"
    unset CARBON_API

    cat > "$TMP/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$CALLS"
case "$CURL_MODE" in
    401) echo "curl: (22) The requested URL returned error: 401" >&2; exit 22 ;;
    junk) echo '{"error": "Unauthorised."}'; exit 0 ;;
esac
echo '{"bytes":1000000,"green":false,"gco2e":0.1042066141963005,"rating":"B","cleanerThan":0.8}'
STUB
    chmod +x "$TMP/curl"
    export PATH="$TMP:$PATH"

    printf '{"finalDisplayedUrl":"https://shop.example/","audits":{"total-byte-weight":{"numericValue":1000000.4}}}' > "$TMP/lh.json"
}

need_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq fehlt (Image localhost/bats-ubuntu-jq-bc:24.04)"
}

teardown() {
    if [ -n "${TMP:-}" ]; then rm -rf "$TMP"; fi
}

@test "measure-carbon: --help zeigt Usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: measure-carbon.sh"* ]]
}

@test "measure-carbon: ohne Eingabe Exit 1, keine API-Abfrage" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [ ! -f "$CALLS" ]
}

@test "measure-carbon: fragt /data mit Bytes und green=0, nie /site" {
    need_jq
    run bash "$SCRIPT" 1000000
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "curl -fsS --max-time 30 https://api.websitecarbon.com/data?bytes=1000000&green=0" ]
    [[ "$output" == *"CO2e je Aufruf:   0.104 g"* ]]
    [[ "$output" == *"Rating:           B "* ]]
}

@test "measure-carbon: --green setzt green=1" {
    need_jq
    run bash "$SCRIPT" --green 5000
    [ "$status" -eq 0 ]
    [[ "$(cat "$CALLS")" == *"/data?bytes=5000&green=1" ]]
    [[ "$output" == *"Green Hosting:    ja"* ]]
}

@test "measure-carbon: liest total-byte-weight aus dem Lighthouse-Report" {
    need_jq
    run bash "$SCRIPT" "$TMP/lh.json"
    [ "$status" -eq 0 ]
    [[ "$(cat "$CALLS")" == *"/data?bytes=1000000&green=0" ]]
    [[ "$output" == *"(Lighthouse, https://shop.example/)"* ]]
}

@test "measure-carbon: JSON ohne total-byte-weight ist ein Aufruffehler" {
    need_jq
    echo '{"audits":{}}' > "$TMP/other.json"
    run bash "$SCRIPT" "$TMP/other.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"kein Lighthouse-Report"* ]]
    [ ! -f "$CALLS" ]
}

@test "measure-carbon: Hochrechnung g x Aufrufe x 12 / 1000" {
    need_jq
    run bash "$SCRIPT" --views 1000000 1000000
    [ "$status" -eq 0 ]
    # 0.1042066 g x 1 000 000 x 12 / 1000 = 1250.5 kg
    [[ "$output" == *"Hochrechnung bei 1000000 Aufrufen/Monat: 1250.5 kg CO2e pro Jahr"* ]]
}

@test "measure-carbon: HTTP-Fehler der API ist Exit 2, kein 0-g-Ergebnis" {
    need_jq
    CURL_MODE=401 run bash "$SCRIPT" 1000000
    [ "$status" -eq 2 ]
    [[ "$output" == *"nicht erreichbar"* ]]
    [[ "$output" != *"CO2e je Aufruf"* ]]
}

@test "measure-carbon: Antwort ohne gco2e ist Exit 2, keine Bewertung" {
    need_jq
    CURL_MODE=junk run bash "$SCRIPT" 1000000
    [ "$status" -eq 2 ]
    [[ "$output" == *"unerwartete Antwort"* ]]
    [[ "$output" != *"Rating:"* ]]
}

@test "measure-carbon: --views ohne Zahl ist Exit 1" {
    run bash "$SCRIPT" --views viele 1000
    [ "$status" -eq 1 ]
}

@test "measure-carbon: keine Vergleichszahlen ohne Quelle (Netflix, Google-Suche)" {
    run grep -Ei 'netflix|google-suche' "$SCRIPT"
    [ "$status" -eq 1 ]
}
