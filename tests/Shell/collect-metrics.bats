#!/usr/bin/env bats

# BATS-Tests fuer chapters/24-ausblick/scripts/collect-metrics.sh (MEM-321).
#
# curl ist ein Stub, der seine Argumente protokolliert. CURL_MODE=429 liefert
# die gekuerzte echte Antwort der PageSpeed API ohne Key (abgerufen 2026-09-24,
# quota_limit_value 0); frueher speicherte das Skript daraus eine Zeile mit
# lauter null und meldete "Metriken gespeichert".
# Intervall und Dauer je 1 s: genau eine Messung.

SCRIPT="./chapters/24-ausblick/scripts/collect-metrics.sh"

setup() {
    [ -f "$SCRIPT" ] || skip "Skript fehlt: $SCRIPT"
    command -v jq >/dev/null 2>&1 || skip "jq fehlt (Image localhost/bats-ubuntu-jq-bc:24.04)"
    TMP="$(mktemp -d)"
    export CALLS="$TMP/calls"
    unset PSI_API_KEY

    cat > "$TMP/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$CALLS"
case "$CURL_MODE" in
    429) echo '{"error": {"code": 429, "message": "Quota exceeded for quota metric '"'"'Queries'"'"' and limit '"'"'Queries per day'"'"' of service '"'"'pagespeedonline.googleapis.com'"'"' for consumer '"'"'project_number:583797351490'"'"'.", "status": "RESOURCE_EXHAUSTED"}}' ;;
    junk) echo '<html>502 Bad Gateway</html>' ;;
    empty) ;;
    nolh) echo '{"captchaResult": "CAPTCHA_NOT_NEEDED", "id": "https://shop.example/"}' ;;
    *) echo '{"lighthouseResult":{"audits":{"server-response-time":{"numericValue":123.4},"first-contentful-paint":{"numericValue":900},"largest-contentful-paint":{"numericValue":1800},"cumulative-layout-shift":{"numericValue":0.05},"total-blocking-time":{"numericValue":0},"speed-index":{"numericValue":1500}},"categories":{"performance":{"score":0.93}}}}' ;;
esac
STUB
    chmod +x "$TMP/curl"
    export PATH="$TMP:$PATH"
    OUT="$TMP/metrics.json"
}

teardown() {
    if [ -n "${TMP:-}" ]; then rm -rf "$TMP"; fi
}

@test "collect-metrics: --help zeigt Usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == "Usage: PSI_API_KEY=<key> "*" <url> [output.json] [intervall-s] [dauer-s]" ]]
}

@test "collect-metrics: ohne URL Exit 1, keine API-Abfrage" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [ ! -f "$CALLS" ]
}

@test "collect-metrics: HTTP 429 speichert keine null-Zeile, Exit 1" {
    CURL_MODE=429 run bash "$SCRIPT" https://shop.example/ "$OUT" 1 1
    [ "$status" -eq 1 ]
    grep -qxF "API-Fehler 429: Quota exceeded for quota metric 'Queries' and limit 'Queries per day' of service 'pagespeedonline.googleapis.com' for consumer 'project_number:583797351490'." <<< "$(sed 's/^\[[^]]*\] //' <<< "$output")"
    [[ "$output" != *"Metriken gespeichert"* ]]
    [ "$(jq length "$OUT")" -eq 0 ]
    grep -qxF "Neu gespeichert: 0" <<< "$output"
    grep -qxF "Fehler: keine einzige Messung gespeichert (siehe Meldungen oben)" <<< "$output"
}

@test "collect-metrics: Antwort ohne JSON ist ein Fehler, keine Zeile" {
    CURL_MODE=junk run bash "$SCRIPT" https://shop.example/ "$OUT" 1 1
    [ "$status" -eq 1 ]
    grep -qxF "API-Fehler Antwort ist kein JSON" <<< "$(sed 's/^\[[^]]*\] //' <<< "$output")"
    [ "$(jq length "$OUT")" -eq 0 ]
}

@test "collect-metrics: JSON ohne lighthouseResult ist ein Fehler, keine null-Zeile" {
    CURL_MODE=nolh run bash "$SCRIPT" https://shop.example/ "$OUT" 1 1
    [ "$status" -eq 1 ]
    grep -qxF "API-Fehler Antwort ohne lighthouseResult" <<< "$(sed 's/^\[[^]]*\] //' <<< "$output")"
    [ "$(jq length "$OUT")" -eq 0 ]
}

@test "collect-metrics: leere Antwort ist ein Fehler" {
    CURL_MODE=empty run bash "$SCRIPT" https://shop.example/ "$OUT" 1 1
    [ "$status" -eq 1 ]
    grep -qxF "Fehler: Keine API-Antwort" <<< "$(sed 's/^\[[^]]*\] //' <<< "$output")"
}

@test "collect-metrics: gueltige Antwort wird mit allen Feldern gespeichert" {
    run bash "$SCRIPT" https://shop.example/ "$OUT" 1 1
    [ "$status" -eq 0 ]
    grep -qxF "Neu gespeichert: 1" <<< "$output"
    grep -qxF "  python scripts/detect-anomalies.py --input $OUT" <<< "$output"
    [ "$(jq -c '.[0] | del(.timestamp)' "$OUT")" = '{"TTFB":123.4,"FCP":900,"LCP":1800,"CLS":0.05,"TBT":0,"SI":1500,"score":0.93}' ]
}

@test "collect-metrics: URL wird kodiert, PSI_API_KEY angehaengt" {
    PSI_API_KEY=k123 run bash "$SCRIPT" "https://shop.example/?a=1&b=2" "$OUT" 1 1
    [ "$status" -eq 0 ]
    grep -qF "runPagespeed?url=https%3A%2F%2Fshop.example%2F%3Fa%3D1%26b%3D2&strategy=mobile&key=k123" "$CALLS"
    [[ "$output" != *"PSI_API_KEY nicht gesetzt"* ]]
}

@test "collect-metrics: ohne Key ein Hinweis, kein key-Parameter" {
    run bash "$SCRIPT" https://shop.example/ "$OUT" 1 1
    grep -qxF "Hinweis: PSI_API_KEY nicht gesetzt, anonyme Aufrufe scheitern meist mit HTTP 429" <<< "$output"
    ! grep -qF "key=" "$CALLS"
}
