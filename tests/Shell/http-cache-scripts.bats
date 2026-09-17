#!/usr/bin/env bats

# BATS tests for the chapter 6 HTTP cache scripts

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
        echo "200 0.010"
        exit 0
    fi
done
if [[ -f "$FIXTURES/first.headers" ]]; then
    n=$(cat "$FIXTURES/count" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$FIXTURES/count"
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

@test "cache-debug.sh does not report a hit for Age: 0 (MISS stored, e.g. APP_ENV=dev)" {
    make_curl_stub
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nAge: 0\r\nTTFB=0.120\n' > "$FIXTURES/first.headers"
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nAge: 0\r\nTTFB=0.110\n' > "$FIXTURES/second.headers"
    CURL_CMD="$TMP/curl" CACHE_DEBUG_WAIT=0 run "$DIR/cache-debug.sh" http://shop.test /
    [ "$status" -eq 0 ]
    [[ "$output" != *"aus dem Cache"* ]]
    [[ "$output" == *"Nicht gecacht"* ]]
}

@test "cache-debug.sh reports the built-in cache for Age > 0" {
    make_curl_stub
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nAge: 0\r\nTTFB=0.130\n' > "$FIXTURES/first.headers"
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nAge: 2\r\nTTFB=0.010\n' > "$FIXTURES/second.headers"
    CURL_CMD="$TMP/curl" CACHE_DEBUG_WAIT=0 run "$DIR/cache-debug.sh" http://shop.test /
    [ "$status" -eq 0 ]
    [[ "$output" == *"Eingebauter Shopware-Cache: 2. Aufruf aus dem Cache"* ]]
}

@test "cache-debug.sh does not trust a faster second call without Age" {
    make_curl_stub
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nTTFB=0.300\n' > "$FIXTURES/first.headers"
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-cache, private\r\nTTFB=0.050\n' > "$FIXTURES/second.headers"
    CURL_CMD="$TMP/curl" CACHE_DEBUG_WAIT=0 run "$DIR/cache-debug.sh" http://shop.test /
    [[ "$output" == *"kein Age > 0"* ]]
}

@test "cache-debug.sh reports a Varnish HIT" {
    make_curl_stub
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store\r\nX-Cache: MISS\r\nTTFB=0.080\n' > "$FIXTURES/first.headers"
    printf 'HTTP/1.1 200 OK\r\nCache-Control: no-store\r\nX-Cache: HIT\r\nAge: 2\r\nTTFB=0.001\n' > "$FIXTURES/second.headers"
    CURL_CMD="$TMP/curl" CACHE_DEBUG_WAIT=0 run "$DIR/cache-debug.sh" http://shop.test /
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
