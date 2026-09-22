#!/usr/bin/env bats

# Tests fuer chapters/19-mobile-performance/scripts/lighthouse-mobile.sh
# Lighthouse wird durch einen Stub ersetzt, der seine Argumente protokolliert
# und je Lauf andere Werte schreibt (Median und Spanne muessen sich aendern).

SCRIPT="./chapters/19-mobile-performance/scripts/lighthouse-mobile.sh"

setup() {
    command -v jq > /dev/null || skip "jq fehlt"
    TMP="$(mktemp -d)"
    export STUB_LOG="$TMP/args.log"
    export STUB_COUNT="$TMP/count"
    echo 0 > "$STUB_COUNT"
    cat > "$TMP/lighthouse" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
n=$(( $(cat "$STUB_COUNT") + 1 ))
echo "$n" > "$STUB_COUNT"
scores=(0.91 0.85 0.88 0.80)
lcps=(2500.4 3100 2700 2900)
tbts=(150 300 210 180)
clss=(0.1234 0.2 0.05 0.3)
i=$(( (n - 1) % 4 ))
for arg in "$@"; do
    case "$arg" in --output-path=*) out="${arg#*=}" ;; esac
done
cat > "$out" <<JSON
{"categories":{"performance":{"score":${scores[$i]}}},
 "audits":{"largest-contentful-paint":{"numericValue":${lcps[$i]}},
           "total-blocking-time":{"numericValue":${tbts[$i]}},
           "cumulative-layout-shift":{"numericValue":${clss[$i]}},
           "interaction-to-next-paint":{"numericValue":null}}}
JSON
STUB
    chmod +x "$TMP/lighthouse"
    export LIGHTHOUSE="$TMP/lighthouse"
}

teardown() {
    rm -rf "$TMP"
}

@test "--help zeigt Usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--runs=N"* ]]
}

@test "ohne URL: Exit 1" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"URL fehlt"* ]]
}

@test "ungueltige Laufzahl und unbekannte Option: Exit 1" {
    run "$SCRIPT" https://shop.example/ --runs=0
    [ "$status" -eq 1 ]
    run "$SCRIPT" https://shop.example/ --runs 3
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unbekannte Option: --runs"* ]]
}

@test "ruft Lighthouse je Lauf mit Standard-Drosselung und eigenem Report auf" {
    run "$SCRIPT" https://shop.example/ --runs=3 --output="$TMP/out"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$STUB_LOG")" -eq 3 ]
    run cat "$STUB_LOG"
    [[ "${lines[0]}" == "https://shop.example/ --only-categories=performance --output=json --output-path=$TMP/out/mobile-1.json --chrome-flags=--headless=new --quiet" ]]
    [[ "${lines[2]}" == *"--output-path=$TMP/out/mobile-3.json"* ]]
    [[ "$output" != *"--preset"* ]]
    [[ "$output" != *"throttling"* ]]
}

@test "Median und Spanne bei ungerader Laufzahl" {
    run "$SCRIPT" https://shop.example/ --runs=3 --output="$TMP/out"
    [ "$status" -eq 0 ]
    # Scores 91, 85, 88 / LCP 2500, 3100, 2700 / TBT 150, 300, 210 / CLS 0.123, 0.2, 0.05
    [[ "$output" == *"Score: 88 (85 - 91)"* ]]
    [[ "$output" == *"LCP:   2700 ms (2500 - 3100)"* ]]
    [[ "$output" == *"TBT:   210 ms (150 - 300)"* ]]
    [[ "$output" == *"CLS:   0.123 (0.05 - 0.2)"* ]]
}

@test "Median bei gerader Laufzahl ist der Mittelwert der beiden mittleren" {
    run "$SCRIPT" https://shop.example/ --runs=4 --output="$TMP/out"
    [ "$status" -eq 0 ]
    # Scores 80, 85, 88, 91 -> 86.5 / LCP 2500, 2700, 2900, 3100 -> 2800
    [[ "$output" == *"Score: 86.5 (80 - 91)"* ]]
    [[ "$output" == *"LCP:   2800 ms (2500 - 3100)"* ]]
}

@test "INP wird nicht als Messwert ausgegeben" {
    run "$SCRIPT" https://shop.example/ --runs=1 --output="$TMP/out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INP:   nicht gemessen"* ]]
    [[ "$output" != *"INP:   0"* ]]
}
