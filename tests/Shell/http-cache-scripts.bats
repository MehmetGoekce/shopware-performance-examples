#!/usr/bin/env bats

# BATS tests for the chapter 6 HTTP cache scripts

bats_require_minimum_version 1.5.0

DIR="./chapters/06-http-cache/scripts"

setup() {
    TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP"
}

@test "all http cache scripts show help with --help" {
    for script in cache-debug.sh cache-hit-rate.sh cache-warmup.sh; do
        run "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "all http cache scripts exit 1 without arguments" {
    for script in cache-debug.sh cache-hit-rate.sh cache-warmup.sh; do
        run "$DIR/$script"
        [ "$status" -eq 1 ]
    done
}

@test "cache-hit-rate.sh counts varnishncsa handling values from the last field" {
    cat > "$TMP/varnish.log" <<'EOF'
10.0.0.1 [17/Sep/2026:14:44:20 +0000] "GET http://shop/ HTTP/1.1" 200 90164 hit
10.0.0.1 [17/Sep/2026:14:44:20 +0000] "GET http://shop/ HTTP/1.1" 200 90164 hit
10.0.0.1 [17/Sep/2026:14:44:20 +0000] "GET http://shop/hit-list/ HTTP/1.1" 200 159163 hit
10.0.0.1 [17/Sep/2026:14:44:20 +0000] "GET http://shop/new/ HTTP/1.1" 200 102690 miss
10.0.0.1 [17/Sep/2026:14:44:20 +0000] "GET http://shop/account HTTP/1.1" 200 38 pass
10.0.0.1 [17/Sep/2026:14:44:20 +0000] "GET http://shop/wishlist HTTP/1.1" 200 38 hitmiss
EOF
    run "$DIR/cache-hit-rate.sh" "$TMP/varnish.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"75.00%"* ]]
    [[ "$output" == *"Anteil aller Requests aus dem Cache: 50.00%"* ]]
}

@test "cache-hit-rate.sh does not count a URL containing HIT as a hit" {
    printf '%s\n' '10.0.0.1 "GET /HIT-sale HTTP/1.1" 200 miss' > "$TMP/one.log"
    run "$DIR/cache-hit-rate.sh" "$TMP/one.log"
    [[ "$output" == *"0.00%"* ]]
}

@test "cache-hit-rate.sh fails on a log without cache status" {
    printf '%s\n' '10.0.0.1 "GET / HTTP/1.1" 200 1234' > "$TMP/plain.log"
    run "$DIR/cache-hit-rate.sh" "$TMP/plain.log"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kein Cache-Status"* ]]
}

@test "cache-hit-rate.sh fails on a missing log file" {
    run "$DIR/cache-hit-rate.sh" "$TMP/does-not-exist.log"
    [ "$status" -eq 1 ]
}

@test "cache-hit-rate.sh reads varnishstat counters via VARNISHSTAT_CMD" {
    cat > "$TMP/varnishstat" <<'EOF'
#!/bin/bash
cat <<'STATS'
MAIN.cache_hit              300         0.10 Cache hits
MAIN.cache_hitpass            0         0.00 Cache hits for pass
MAIN.cache_miss             100         0.03 Cache misses
MAIN.s_pass                  20         0.01 Total pass-ed requests seen
MAIN.n_object                42          .   object structs made
STATS
EOF
    chmod +x "$TMP/varnishstat"
    VARNISHSTAT_CMD="$TMP/varnishstat" run "$DIR/cache-hit-rate.sh" --varnishstat
    [ "$status" -eq 0 ]
    [[ "$output" == *"75.00%"* ]]
    [[ "$output" == *"s_pass"* ]]
}

@test "cache-hit-rate.sh fails when varnishstat cannot run" {
    VARNISHSTAT_CMD="false" run "$DIR/cache-hit-rate.sh" --varnishstat
    [ "$status" -eq 1 ]
}

@test "cache-warmup.sh rejects unknown options" {
    run "$DIR/cache-warmup.sh" http://127.0.0.1:9 --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unbekannte Option"* ]]
}

@test "cache-debug.sh exits 1 when the shop is unreachable" {
    command -v curl >/dev/null || skip "curl not installed"
    run "$DIR/cache-debug.sh" http://127.0.0.1:9
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht erreichbar"* ]]
}

# curl-Stub: Antworten kommen aus Dateien in $FIXTURES.
# cache-debug.sh: Aufruf 1 -> first.headers, Aufruf 2 -> second.headers
# cache-warmup.sh: URL -> Datei (Pfad mit / durch _ ersetzt), -w -> "200 0.010"
make_curl_stub() {
    cat > "$TMP/curl" <<'STUB'
#!/bin/bash
url="${!#}"
for arg in "$@"; do
    if [[ "$arg" == "%{http_code} %{time_starttransfer}" ]]; then
        # Warmup-Aufruf: protokollieren, URLs aus $FIXTURES/fail liefern 503
        echo "$url" >> "$FIXTURES/warm.log"
        if grep -qxF "$url" "$FIXTURES/fail" 2>/dev/null; then echo "503 0.010"; else echo "200 0.010"; fi
        exit 0
    fi
done
if [[ -f "$FIXTURES/first.headers" ]]; then
    n=$(cat "$FIXTURES/count" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$FIXTURES/count"
    date +%s >> "$FIXTURES/times"
    if [[ "$n" -eq 1 ]]; then cat "$FIXTURES/first.headers"; else cat "$FIXTURES/second.headers"; fi
    exit 0
fi
file="$FIXTURES/$(echo "${url#*://}" | tr '/:' '__')"
[[ -f "$file" ]] && cat "$file"
exit 0
STUB
    chmod +x "$TMP/curl"
    export FIXTURES="$TMP/fixtures"
    mkdir -p "$FIXTURES"
}

# Header-Fixtures fuer cache-debug.sh:
#   headers <datei> <status> <age|-> <ttfb> [<date|->] [<x-symfony-cache>]
headers() {
    local age="" date="" trace=""
    [[ "$3" != "-" ]] && age="Age: $3\r\n"
    [[ -n "${5:-}" && "${5:-}" != "-" ]] && date="Date: $5\r\n"
    [[ -n "${6:-}" ]] && trace="X-Symfony-Cache: $6\r\n"
    printf "HTTP/1.1 $2 X\r\nCache-Control: no-cache, private\r\n${age}${date}${trace}TTFB=$4\n" > "$FIXTURES/$1.headers"
}

D1='Wed, 23 Sep 2026 18:00:00 GMT'
D2='Wed, 23 Sep 2026 18:00:03 GMT'

debug() {
    CURL_CMD="$TMP/curl" CACHE_DEBUG_WAIT="$1" run "$DIR/cache-debug.sh" http://shop.test /
}

@test "cache-debug.sh does not report a hit for Age: 0 (MISS stored, e.g. APP_ENV=dev)" {
    make_curl_stub
    headers first 200 0 0.120 "$D1"; headers second 200 0 0.110 "$D2"
    debug 2
    [ "$status" -eq 0 ]
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Kein Treffer erkennbar"* ]]
}

@test "cache-debug.sh reports the built-in cache when Age grows by the pause and Date stays" {
    make_curl_stub
    headers first 200 0 0.130 "$D1"; headers second 200 2 0.010 "$D1"
    debug 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Eingebauter Shopware-Cache: 2. Aufruf aus dem Cache"*"(Age um 2 s gewachsen, Date unverändert)"* ]]
    [[ "$output" == *"Date:           1. Aufruf $D1, 2. Aufruf $D1"* ]]
}

# MEM-316 F12: ein warmer Cache (Treffer -> Treffer) hat keine kuerzere TTFB
@test "cache-debug.sh reports a warm cache (hit -> hit, same TTFB) as a hit" {
    make_curl_stub
    headers first 200 40 0.010 "$D1"; headers second 200 42 0.010 "$D1"
    debug 2
    [[ "$output" == *"2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh waits the pause between the two requests" {
    make_curl_stub
    headers first 200 0 0.130 "$D1"; headers second 200 2 0.010 "$D1"
    debug 2
    t1=$(sed -n 1p "$FIXTURES/times"); t2=$(sed -n 2p "$FIXTURES/times")
    [ $((t2 - t1)) -ge 2 ]
}

# MEM-302: Symfony setzt beim Speichern Age = Sekunden seit Date, Shopware
# erzeugt die Response vor dem Twig-Rendern. Zwei langsame MISS tragen je Age 3.
@test "cache-debug.sh does not count the Age of two slow misses as a hit" {
    make_curl_stub
    headers first 200 3 3.100 "$D1"; headers second 200 3 3.050 "$D2"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Kein Treffer erkennbar"* ]]
}

# Grenze mit Pause 3: Age waechst genau um die Pause -> Treffer, um eins weniger -> keiner
@test "cache-debug.sh counts Age growth equal to the pause, not one less" {
    make_curl_stub
    headers first 200 0 0.100 "$D1"; headers second 200 3 0.010 "$D1"
    debug 3
    [[ "$output" == *"2. Aufruf aus dem Cache"* ]]
    rm -f "$FIXTURES/count" "$FIXTURES/times"
    headers second 200 2 0.010 "$D1"
    debug 3
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar: Date gleich, Age aber nicht um die Pause gewachsen"* ]]
}

# MEM-325 Review B9: gleiches Date bei gesunkenem Age (aeltestes ESI-Fragment neu gespeichert)
@test "cache-debug.sh: same Date with a dropped Age is not decidable, not a hit" {
    make_curl_stub
    headers first 200 30 0.010 "$D1"; headers second 200 2 0.010 "$D1"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar: Date gleich"* ]]
}

# MEM-316 T4: 6.7-Warenkorb direkt nach cache:clear. Age vom Header-Fragment,
# Date neu, 2. Aufruf viel schneller. Die alte TTFB-Regel meldete das gruen.
@test "cache-debug.sh does not count a much faster 2nd call with a new Date as a hit" {
    make_curl_stub
    headers first 200 0 0.990 "$D1"; headers second 200 2 0.230 "$D2"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar: Age wächst um die Pause, Date aber auch"* ]]
}

# Mit ESI setzt Symfony das Age der Seite auf das des aeltesten Fragments.
@test "cache-debug.sh: Age grows but Date is new (ESI fragment or proxy) = not decidable" {
    make_curl_stub
    headers first 200 4 0.113 "$D1"; headers second 200 6 0.115 "$D2"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar"* ]]
    [[ "$output" == *"ESI"* ]]
    [[ "$output" == *"proxy_pass_header Date;"* ]]
    [[ "$output" == *"Apache mit mod_php"* ]]
    [[ "$output" == *"trace_level: short"* ]]
}

@test "cache-debug.sh: Age grows but no Date header = not decidable" {
    make_curl_stub
    headers first 200 0 0.130; headers second 200 2 0.010
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar: Age wächst um die Pause, aber ohne Date-Header"* ]]
}

@test "cache-debug.sh: Date only on the 1st response is not the same Date" {
    make_curl_stub
    headers first 200 0 0.130 "$D1"; headers second 200 2 0.010
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar"* ]]
}

@test "cache-debug.sh reports an Age that dropped as no hit" {
    make_curl_stub
    headers first 200 2 0.010 "$D1"; headers second 200 0 0.120 "$D2"
    debug 2
    [[ "$output" == *"Age gesunken"* ]]
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh needs both Age values for a hit" {
    make_curl_stub
    headers first 200 - 0.300 "$D1"; headers second 200 5 0.010 "$D1"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *"Nicht entscheidbar: Age nur bei einem Aufruf"* ]]
    rm -f "$FIXTURES/count" "$FIXTURES/times"
    headers first 200 5 0.010 "$D1"; headers second 200 - 0.300 "$D1"
    debug 2
    [[ "$output" == *"Nicht entscheidbar: Age nur bei einem Aufruf"* ]]
}

@test "cache-debug.sh: X-Symfony-Cache fresh on the 2nd call is a hit, even without Age growth" {
    make_curl_stub
    headers first 200 0 0.130 "$D1" "miss/store"; headers second 200 0 0.010 "$D1" "fresh"
    debug 2
    [[ "$output" == *"2. Aufruf aus dem Cache"*"(X-Symfony-Cache: fresh)"* ]]
}

@test "cache-debug.sh: the trace decides over Age and Date" {
    make_curl_stub
    headers first 200 0 0.130 "$D1" "miss/store"; headers second 200 2 0.010 "$D1" "miss/store"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *'Kein Treffer: X-Symfony-Cache meldet "miss/store"'* ]]
}

@test "cache-debug.sh: only the trace of the 2nd call counts" {
    make_curl_stub
    headers first 200 0 0.130 "$D1" "fresh"; headers second 200 0 0.130 "$D2" "miss"
    debug 2
    [[ "$output" == *'Kein Treffer: X-Symfony-Cache meldet "miss"'* ]]
}

@test "cache-debug.sh: full trace format - the main request decides, not an ESI fragment" {
    make_curl_stub
    headers first 200 4 0.130 "$D1"; headers second 200 6 0.130 "$D2" "GET /: miss, store; GET /_esi/global/header: fresh"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
    [[ "$output" == *'Kein Treffer: X-Symfony-Cache meldet "miss, store"'* ]]
    rm -f "$FIXTURES/count" "$FIXTURES/times"
    headers second 200 0 0.010 "$D1" "GET /: fresh; GET /_esi/global/header: miss"
    debug 2
    [[ "$output" == *"2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh: trace valid (revalidated, re-rendered) is not a hit" {
    make_curl_stub
    headers first 200 0 0.130 "$D1"; headers second 200 2 0.010 "$D1" "stale/valid/store"
    debug 2
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh: trace stale-while-revalidate / stale-if-error is a hit (stale stored copy)" {
    for t in "stale-while-revalidate" "stale/stale-if-error"; do
        make_curl_stub; rm -f "$FIXTURES/count" "$FIXTURES/times"
        headers first 200 0 0.130 "$D1" "miss/store"; headers second 200 0 0.130 "$D2" "$t"
        debug 2
        [[ "$output" == *"2. Aufruf aus dem Cache"* ]]
    done
}

@test "cache-debug.sh: an error page is not evaluated as cache (MEM-325 Review B5)" {
    make_curl_stub
    headers first 400 4 0.100 "$D1"; headers second 400 6 0.100 "$D2"
    debug 2
    [[ "$output" == *"Fehlerseite (HTTP 400) - nicht bewertbar"* ]]
    [[ "$output" != *"Nicht entscheidbar"* ]]
}

@test "cache-debug.sh: a no-store page is reported as not cacheable, not as undecidable" {
    make_curl_stub
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store, private\r\nAge: 4\r\nDate: %s\r\nTTFB=0.100\n' "$D1" > "$FIXTURES/first.headers"
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store, private\r\nAge: 6\r\nDate: %s\r\nTTFB=0.100\n' "$D2" > "$FIXTURES/second.headers"
    debug 2
    [[ "$output" == *"Seite bewusst nicht cachebar (no-store)"* ]]
    [[ "$output" != *"Nicht entscheidbar"* ]]
}

@test "cache-debug.sh: a failed 2nd request is reported and fails the run" {
    make_curl_stub
    headers first 200 0 0.100 "$D1"; : > "$FIXTURES/second.headers"
    debug 2
    [ "$status" -eq 1 ]
    [[ "$output" == *"2. Aufruf gescheitert"* ]]
}

@test "cache-debug.sh treats a redirect as a redirect, even with growing Age" {
    make_curl_stub
    headers first 301 0 0.100; headers second 301 2 0.010
    debug 2
    [[ "$output" == *"Weiterleitung"* ]]
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh rejects a pause below two seconds" {
    for w in 0 1 x 1.5 -1 02; do
        CACHE_DEBUG_WAIT="$w" run "$DIR/cache-debug.sh" http://shop.test /
        [ "$status" -eq 1 ]
        [[ "$output" == *"CACHE_DEBUG_WAIT"* ]]
    done
}

@test "cache-debug.sh does not trust a faster second call without Age" {
    make_curl_stub
    headers first 200 - 0.300; headers second 200 - 0.050
    debug 2
    [[ "$output" == *"aber ohne Age"* ]]
    [[ "$output" != *"2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh reports a Varnish HIT" {
    make_curl_stub
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store\r\nX-Cache: MISS\r\nTTFB=0.080\n' > "$FIXTURES/first.headers"
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store\r\nX-Cache: HIT\r\nAge: 2\r\nTTFB=0.001\n' > "$FIXTURES/second.headers"
    CURL_CMD="$TMP/curl" CACHE_DEBUG_WAIT=2 run "$DIR/cache-debug.sh" http://shop.test /
    [[ "$output" == *"Varnish: 2. Aufruf aus dem Cache"* ]]
}

@test "cache-warmup.sh reads gzipped sitemap parts and warms only the requested domain" {
    make_curl_stub
    cat > "$FIXTURES/shop.test_sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex><sitemap><loc>http://shop.test/sitemap/a.xml.gz</loc></sitemap>
<sitemap><loc>http://other.test/sitemap/b.xml.gz</loc></sitemap></sitemapindex>
XML
    printf '<urlset><url><loc>http://shop.test/p1</loc></url><url><loc>http://shop.test/p2</loc></url></urlset>' \
        | gzip -c > "$FIXTURES/shop.test_sitemap_a.xml.gz"
    CURL_CMD="$TMP/curl" run "$DIR/cache-warmup.sh" http://shop.test --sitemap --parallel 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"URLs: 2"* ]]
    [[ "$output" == *"OK"*"http://shop.test/p1"* ]]
    [[ "$output" != *"other.test"*"OK"* ]]
}

make_sitemap3() {
    cat > "$FIXTURES/shop.test_sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex><sitemap><loc>http://shop.test/sitemap/a.xml.gz</loc></sitemap></sitemapindex>
XML
    printf '<urlset><url><loc>http://shop.test/p1</loc></url><url><loc>http://shop.test/p2</loc></url><url><loc>http://shop.test/p3</loc></url></urlset>' \
        | gzip -c > "$FIXTURES/shop.test_sitemap_a.xml.gz"
}

# MEM-313: Nach cache:clear legen parallele erste Aufrufe verschiedene
# Tag-Versionen an, ein Teil der Seiten ist danach kalt. Ab --parallel 2
# ruft das Skript deshalb jede URL zweimal ab.
@test "cache-warmup.sh fetches every URL twice with --parallel 2 and prints OK only once" {
    make_curl_stub
    make_sitemap3
    CURL_CMD="$TMP/curl" run "$DIR/cache-warmup.sh" http://shop.test --sitemap --parallel 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Zweiter Durchgang"* ]]
    for p in p1 p2 p3; do
        [ "$(grep -cxF "http://shop.test/$p" "$FIXTURES/warm.log")" -eq 2 ]
        [ "$(grep -c "OK.*http://shop.test/$p " <<< "$output")" -eq 1 ]
    done
    [ "$(wc -l < "$FIXTURES/warm.log")" -eq 6 ]
}

@test "cache-warmup.sh fetches every URL once with --parallel 1" {
    make_curl_stub
    make_sitemap3
    CURL_CMD="$TMP/curl" run "$DIR/cache-warmup.sh" http://shop.test --sitemap --parallel 1
    [ "$status" -eq 0 ]
    [[ "$output" != *"Zweiter Durchgang"* ]]
    [ "$(wc -l < "$FIXTURES/warm.log")" -eq 3 ]
    [ "$(sort -u "$FIXTURES/warm.log" | wc -l)" -eq 3 ]
}

@test "cache-warmup.sh second pass reports failed pages" {
    make_curl_stub
    make_sitemap3
    echo "http://shop.test/p2" > "$FIXTURES/fail"
    CURL_CMD="$TMP/curl" run "$DIR/cache-warmup.sh" http://shop.test --sitemap --parallel 2
    [ "$status" -eq 0 ]
    second="${output#*Zweiter Durchgang}"
    [[ "$second" == *"503"*"http://shop.test/p2"* ]]
    [[ "$second" != *"OK"* ]]
}

@test "cache-warmup.sh rejects --parallel values below 1 or not a number" {
    for v in 0 x -1 1x ""; do
        run "$DIR/cache-warmup.sh" http://127.0.0.1:9 --parallel "$v"
        [ "$status" -eq 1 ]
        [[ "$output" == *"--parallel braucht eine Zahl"* ]]
    done
    run "$DIR/cache-warmup.sh" http://127.0.0.1:9 --parallel
    [ "$status" -eq 1 ]
    [[ "$output" == *"--parallel braucht eine Zahl"* ]]
}

@test "cache-warmup.sh rejects --limit values below 1, not a number or too large" {
    for v in 0 x -1 1x 1000000 ""; do
        run "$DIR/cache-warmup.sh" http://127.0.0.1:9 --limit "$v"
        [ "$status" -eq 1 ]
        [[ "$output" == *"--limit braucht eine Zahl"* ]]
    done
    run "$DIR/cache-warmup.sh" http://127.0.0.1:9 --limit
    [ "$status" -eq 1 ]
    [[ "$output" == *"--limit braucht eine Zahl"* ]]
}

@test "cache-warmup.sh ignores QUIET from the caller's environment" {
    make_curl_stub
    make_sitemap3
    QUIET=1 CURL_CMD="$TMP/curl" run "$DIR/cache-warmup.sh" http://shop.test --sitemap --parallel 1
    [ "$status" -eq 0 ]
    [ "$(grep -c "OK.*http://shop.test/p" <<< "$output")" -eq 3 ]
}

# MEM-307: Das alte Root-Skript scripts/cache-warmup.sh leerte den Cache,
# und ./scripts/cache-warmup.sh aus Kapitel 6 traf es vom Repo-Root aus.
@test "no root script shares its name with a chapter script" {
    for root in scripts/*.sh; do
        name="$(basename "$root")"
        for other in chapters/*/scripts/"$name"; do
            [ ! -e "$other" ] || { echo "$root kollidiert mit $other"; return 1; }
        done
    done
}

# MEM-310: Das Buch ruft Skripte als ./scripts/<name>.sh im Kapitelordner auf.
# Heissen zwei Kapitelskripte gleich, landet der Leser im falschen Ordner beim
# falschen Skript (cache-hit-rate.sh in Kapitel 6 und 7). Bekannte Ausnahme:
# generate-report.sh in Kapitel 14 und 22 (zwei verschiedene Skripte, offen:
# Umbenennung durch die Kapitel-Owner). Jede weitere Kopie schlägt an.
@test "no two chapters ship a *.sh directly under scripts/ with the same name" {
    [ "$(ls chapters/*/scripts/*.sh | wc -l)" -gt 10 ]
    dups="$(for f in chapters/*/scripts/*.sh; do basename "$f"; done | sort | uniq -d | grep -vx 'generate-report.sh' || true)"
    [ -z "$dups" ] || { echo "doppelt: $dups"; return 1; }
    known="$(ls chapters/*/scripts/generate-report.sh | tr '\n' ' ')"
    [ "$known" = "chapters/14-performance-kultur/scripts/generate-report.sh chapters/22-haeufigste-probleme/scripts/generate-report.sh " ] \
        || { echo "generate-report.sh: $known"; return 1; }
}

@test "make cache-warmup without URL prints usage and fails" {
    command -v make >/dev/null || skip "make fehlt im Image"
    run env -u URL -u PARALLEL -u LIMIT make -s cache-warmup
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: make cache-warmup URL="* ]]
}

@test "make cache-warmup passes URL, PARALLEL and LIMIT to the chapter 6 script and nothing else" {
    command -v make >/dev/null || skip "make fehlt im Image"
    # Nur stdout: ohne TERM (GitHub Actions) schreibt tput im Makefile nach stderr.
    run --separate-stderr env -u URL -u PARALLEL -u LIMIT make -n cache-warmup URL=http://other.test PARALLEL=3 LIMIT=7
    [ "$status" -eq 0 ]
    recipe="$(grep -v '^if \[' <<< "$output")"
    [ "$recipe" = './chapters/06-http-cache/scripts/cache-warmup.sh "http://other.test" --sitemap --parallel 3 --limit 7' ]
}

@test "make cache-warmup defaults to the script defaults (parallel 2, limit 100)" {
    command -v make >/dev/null || skip "make fehlt im Image"
    run env -u URL -u PARALLEL -u LIMIT make -n cache-warmup URL=http://other.test
    [[ "$output" == *'cache-warmup.sh "http://other.test" --sitemap --parallel 2 --limit 100'* ]]
}

@test "make cache-warmup warms sitemap URLs through the real script" {
    command -v make >/dev/null || skip "make fehlt im Image"
    make_curl_stub
    cat > "$FIXTURES/shop.test_sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex><sitemap><loc>http://shop.test/sitemap/a.xml.gz</loc></sitemap></sitemapindex>
XML
    printf '<urlset><url><loc>http://shop.test/p1</loc></url><url><loc>http://shop.test/p2</loc></url><url><loc>http://shop.test/p3</loc></url></urlset>' \
        | gzip -c > "$FIXTURES/shop.test_sitemap_a.xml.gz"
    CURL_CMD="$TMP/curl" run env -u PARALLEL -u LIMIT make -s cache-warmup URL=http://shop.test PARALLEL=1 LIMIT=2
    [ "$status" -eq 0 ]
    [[ "$output" == *"URLs: 2"* ]]
    [[ "$output" == *"http://shop.test/p1"* ]]
}
