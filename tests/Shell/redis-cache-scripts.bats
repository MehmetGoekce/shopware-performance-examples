#!/usr/bin/env bats

# BATS tests for the chapter 7 Redis cache scripts.
# redis-cli is replaced by a stub that answers from fixture files.

DIR="./chapters/07-shopware-cache/scripts"

setup() {
    TMP="$(mktemp -d)"
    FIX="$TMP/fix"
    mkdir -p "$FIX"

    # Stub: "redis-cli -u <url> INFO stats" -> $FIX/INFO_stats
    cat > "$TMP/redis-cli" <<'STUB'
#!/bin/bash
shift 2
name=$(echo "$*" | tr ' ' '_')
[[ -f "$FIX/$name" ]] || exit 1
cat "$FIX/$name"
STUB
    chmod +x "$TMP/redis-cli"
    export FIX
    export REDIS_CLI="$TMP/redis-cli"

    # Gesunde Cache-Instanz
    printf 'PONG\r\n' > "$FIX/PING"
    printf 'redis_version:7.4.11\r\n' > "$FIX/INFO_server"
    printf 'used_memory:524288000\r\nmaxmemory:1073741824\r\nmaxmemory_human:1.00G\r\n' > "$FIX/INFO_memory"
    printf 'maxmemory-policy\r\nvolatile-lru\r\n' > "$FIX/CONFIG_GET_maxmemory-policy"
    printf 'save\r\n\r\n' > "$FIX/CONFIG_GET_save"
    printf 'appendonly\r\nno\r\n' > "$FIX/CONFIG_GET_appendonly"
    printf '# Keyspace\r\ndb0:keys=100,expires=60,avg_ttl=1000\r\ndb2:keys=20,expires=20,avg_ttl=1000\r\n' > "$FIX/INFO_keyspace"
    printf 'keyspace_hits:910\r\nkeyspace_misses:90\r\nevicted_keys:0\r\n' > "$FIX/INFO_stats"
    printf '# Errorstats\r\n' > "$FIX/INFO_errorstats"
    printf 'connected_clients:3\r\nblocked_clients:0\r\n' > "$FIX/INFO_clients"
}

teardown() {
    rm -rf "$TMP"
}

@test "both redis scripts show help with --help" {
    for script in cache-hit-rate.sh redis-diagnostics.sh; do
        run "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "both redis scripts reject unknown options" {
    for script in cache-hit-rate.sh redis-diagnostics.sh; do
        run "$DIR/$script" --nope
        [ "$status" -eq 1 ]
    done
}

@test "cache-hit-rate.sh computes the rate from keyspace hits and misses" {
    run "$DIR/cache-hit-rate.sh" redis://cache:6379
    [ "$status" -eq 0 ]
    [[ "$output" == *"91.00%"* ]]
    [[ "$output" != *"niedrig"* ]]
}

@test "cache-hit-rate.sh flags a rate below 80 percent" {
    printf 'keyspace_hits:300\r\nkeyspace_misses:700\r\n' > "$FIX/INFO_stats"
    run "$DIR/cache-hit-rate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"30.00% (niedrig)"* ]]
}

@test "cache-hit-rate.sh handles zero reads" {
    printf 'keyspace_hits:0\r\nkeyspace_misses:0\r\n' > "$FIX/INFO_stats"
    run "$DIR/cache-hit-rate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Noch keine Lesezugriffe"* ]]
}

@test "cache-hit-rate.sh exits 1 when redis is unreachable" {
    rm "$FIX/INFO_stats"
    run "$DIR/cache-hit-rate.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht erreichbar"* ]]
}

@test "redis-diagnostics.sh passes a healthy cache instance" {
    run "$DIR/redis-diagnostics.sh" --role cache redis://cache:6379
    [ "$status" -eq 0 ]
    [[ "$output" == *"maxmemory-policy volatile-lru"* ]]
    [[ "$output" == *"120 Keys, davon 40 ohne TTL (33 %)"* ]]
    [[ "$output" == *"Keine FAIL-Befunde"* ]]
}

@test "redis-diagnostics.sh fails a cache instance with allkeys-lru" {
    printf 'maxmemory-policy\r\nallkeys-lru\r\n' > "$FIX/CONFIG_GET_maxmemory-policy"
    run "$DIR/redis-diagnostics.sh" --role cache
    [ "$status" -eq 1 ]
    [[ "$output" == *"redis_tag_aware speichert damit nichts"* ]]
}

@test "redis-diagnostics.sh accepts allkeys-lru for sessions but warns without persistence" {
    printf 'maxmemory-policy\r\nallkeys-lru\r\n' > "$FIX/CONFIG_GET_maxmemory-policy"
    run "$DIR/redis-diagnostics.sh" --role session
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"*"maxmemory-policy allkeys-lru"* ]]
    [[ "$output" == *"Keine Persistenz - ein Neustart löscht alle session-Daten"* ]]
}

@test "redis-diagnostics.sh warns about keys without TTL only when memory is nearly full" {
    printf 'used_memory:1000000000\r\nmaxmemory:1073741824\r\nmaxmemory_human:1.00G\r\n' > "$FIX/INFO_memory"
    printf 'db0:keys=100,expires=30,avg_ttl=1000\r\n' > "$FIX/INFO_keyspace"
    run "$DIR/redis-diagnostics.sh" --role cache
    [ "$status" -eq 0 ]
    [[ "$output" == *"frosh:redis-tag:cleanup"* ]]
}

@test "redis-diagnostics.sh reports OOM errors as FAIL" {
    printf '# Errorstats\r\nerrorstat_OOM:count=7\r\n' > "$FIX/INFO_errorstats"
    run "$DIR/redis-diagnostics.sh" --role cache
    [ "$status" -eq 1 ]
    [[ "$output" == *"7 OOM-Fehler"* ]]
}

@test "redis-diagnostics.sh tolerates a redis without errorstats" {
    rm "$FIX/INFO_errorstats"
    run "$DIR/redis-diagnostics.sh" --role cache
    [ "$status" -eq 0 ]
    [[ "$output" == *"Keine FAIL-Befunde"* ]]
}

@test "redis-diagnostics.sh warns when maxmemory is not set" {
    printf 'used_memory:1000\r\nmaxmemory:0\r\nmaxmemory_human:0B\r\n' > "$FIX/INFO_memory"
    run "$DIR/redis-diagnostics.sh" --role cache
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kein maxmemory gesetzt"* ]]
}

@test "redis-diagnostics.sh rejects an unknown role and an unreachable server" {
    run "$DIR/redis-diagnostics.sh" --role db
    [ "$status" -eq 1 ]
    rm "$FIX/PING"
    run "$DIR/redis-diagnostics.sh" --role cache
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht erreichbar"* ]]
}
