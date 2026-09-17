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
