#!/usr/bin/env bats

# BATS tests for the chapter 10 Redis Sentinel scripts.
# redis-cli and curl are replaced by stubs on PATH that answer from fixtures.

DIR="./chapters/10-redis-sentinel/scripts"

setup() {
    TMP="$(mktemp -d)"
    FIX="$TMP/fix"
    mkdir -p "$TMP/bin" "$FIX/26379" "$FIX/6379" "$FIX/6380"

    # Stub: fixture is keyed by target port and the remaining arguments, so the
    # sentinel (26379) and the two instances (6379/6380) can answer differently.
    cat > "$TMP/bin/redis-cli" <<'STUB'
#!/bin/bash
port=6379
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h) shift 2 ;;
        -p) port="$2"; shift 2 ;;
        --user) shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
key="$(IFS=_; echo "${args[*]}")"
[[ -f "$FIX/$port/$key" ]] || exit 1
out="$(cat "$FIX/$port/$key")"
printf '%s\n' "$out"

# Ein angenommenes Failover schaltet die Master-Adresse um, sonst koennte das
# Skript gar nichts bemerken. Die neue Adresse liegt als ".after" bereit.
if [[ "$key" == SENTINEL_failover_* && "$out" == OK* ]]; then
    addr="$FIX/$port/SENTINEL_get-master-addr-by-name_${key#SENTINEL_failover_}"
    [[ -f "$addr.after" ]] && mv "$addr.after" "$addr"
fi
exit 0
STUB
    chmod +x "$TMP/bin/redis-cli"
    export FIX
    export PATH="$TMP/bin:$PATH"

    # Gesundes Cluster: zwei Master, je zwei Replicas.
    printf 'PONG\n' > "$FIX/26379/PING"
    for master in shopware-cache shopware-session; do
        printf 'OK 3 usable Sentinels. Quorum and failover authorization can be reached\n' \
            > "$FIX/26379/SENTINEL_ckquorum_$master"
        printf 'name\nreplica-a\nname\nreplica-b\n' > "$FIX/26379/SENTINEL_replicas_$master"
        printf 'name\n%s\nip\n10.0.0.1\nfailover-timeout\n60000\n' "$master" \
            > "$FIX/26379/SENTINEL_master_$master"
        printf 'OK\n' > "$FIX/26379/SENTINEL_failover_$master"
    done
    printf '10.0.0.1\n6379\n' > "$FIX/26379/SENTINEL_get-master-addr-by-name_shopware-cache"
    printf '10.0.0.4\n6380\n' > "$FIX/26379/SENTINEL_get-master-addr-by-name_shopware-session"

    for port in 6379 6380; do
        printf 'PONG\n' > "$FIX/$port/PING"
        printf 'used_memory:536870912\nused_memory_human:512.00M\n' > "$FIX/$port/INFO_memory"
        printf 'maxmemory\n1073741824\n' > "$FIX/$port/CONFIG_GET_maxmemory"
        printf 'keyspace_hits:950\nkeyspace_misses:50\nevicted_keys:0\nrejected_connections:0\n' \
            > "$FIX/$port/INFO_stats"
        printf 'connected_clients:7\n' > "$FIX/$port/INFO_clients"
    done

    export REDIS_AUTH_PASSWORD='test-pass'
    export SENTINEL_HOST='10.0.0.99'
}

teardown() {
    rm -rf "$TMP"
}

@test "all three sentinel scripts show help with --help" {
    for script in redis-monitor.sh test-failover.sh redis-impact-test.sh; do
        run "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "all three sentinel scripts reject unknown options with 64" {
    for script in redis-monitor.sh test-failover.sh redis-impact-test.sh; do
        run "$DIR/$script" --nope
        [ "$status" -eq 64 ]
    done
}

@test "redis-monitor.sh refuses to run without a password" {
    unset REDIS_AUTH_PASSWORD
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 64 ]
    [[ "$output" == *"REDIS_AUTH_PASSWORD"* ]]
}

@test "redis-monitor.sh reports both masters as healthy" {
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shopware-cache"* ]]
    [[ "$output" == *"shopware-session"* ]]
    [[ "$output" == *"Ergebnis: OK"* ]]
}

@test "redis-monitor.sh checks the session instance on its own port" {
    # Die Session-Instanz laeuft auf 6380. Eine Fassung, die den Port aus
    # get-master-addr-by-name ignoriert, wuerde hier 6379 abfragen.
    printf 'connected_clients:99\n' > "$FIX/6380/INFO_clients"
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"10.0.0.4:6380"* ]]
    [[ "$output" == *"Verbundene Clients: 99"* ]]
}

@test "redis-monitor.sh warns at 1 replica and exits 1" {
    printf 'name\nreplica-a\n' > "$FIX/26379/SENTINEL_replicas_shopware-cache"
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Nur 1 Replica"* ]]
    [[ "$output" == *"Ergebnis: WARNUNG"* ]]
}

@test "redis-monitor.sh exits 2 when the quorum is gone" {
    printf 'NOQUORUM 1 usable Sentinels.\n' > "$FIX/26379/SENTINEL_ckquorum_shopware-cache"
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Quorum nicht erreichbar"* ]]
}

@test "redis-monitor.sh exits 2 when the master does not answer" {
    rm "$FIX/6379/PING"
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"nicht erreichbar"* ]]
}

@test "redis-monitor.sh computes memory usage and hit rate" {
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Speicher: 50%"* ]]
    [[ "$output" == *"Hit-Rate: 95%"* ]]
}

@test "redis-monitor.sh falls back to MAXMEMORY_<MASTER> without CONFIG GET" {
    rm "$FIX/6379/CONFIG_GET_maxmemory"
    MAXMEMORY_SHOPWARE_CACHE=1073741824 run "$DIR/redis-monitor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"maxmemory aus MAXMEMORY_SHOPWARE_CACHE"* ]]
    [[ "$output" == *"Speicher: 50%"* ]]
}

@test "redis-monitor.sh skips the hit rate on the session instance" {
    run "$DIR/redis-monitor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hit-Rate: nicht bewertet"* ]]
}

@test "test-failover.sh exits 2 when sentinel is unreachable" {
    rm "$FIX/26379/PING"
    run "$DIR/test-failover.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"nicht erreichbar"* ]]
}

@test "test-failover.sh reports a completed failover for both masters" {
    # Nach dem Failover meldet Sentinel eine andere Adresse.
    printf '10.0.0.2\n6379\n' > "$FIX/26379/SENTINEL_get-master-addr-by-name_shopware-cache.after"
    printf '10.0.0.5\n6380\n' > "$FIX/26379/SENTINEL_get-master-addr-by-name_shopware-session.after"
    run "$DIR/test-failover.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Master nachher: 10.0.0.2:6379"* ]]
    [[ "$output" == *"Master nachher: 10.0.0.5:6380"* ]]
}

@test "test-failover.sh names the lockout from failover-timeout" {
    printf '10.0.0.2\n6379\n' > "$FIX/26379/SENTINEL_get-master-addr-by-name_shopware-cache.after"
    run "$DIR/test-failover.sh" shopware-cache
    [ "$status" -eq 0 ]
    # 2 * 60000 ms = 120 s, und die Sperre gilt nur fuer den automatischen Failover.
    [[ "$output" == *"in 120 s"* ]]
    [[ "$output" == *"AUTOMATISCHEN"* ]]
}

@test "test-failover.sh exits 1 and names rename-command when nothing is promoted" {
    run env WAIT_SECONDS=2 "$DIR/test-failover.sh" shopware-cache
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht innerhalb von 2 s"* ]]
    [[ "$output" == *"rename-command"* ]]
}

@test "test-failover.sh exits 2 without a replica to promote" {
    : > "$FIX/26379/SENTINEL_replicas_shopware-cache"
    run "$DIR/test-failover.sh" shopware-cache
    [ "$status" -eq 2 ]
    [[ "$output" == *"Mindestens 1 Replica"* ]]
}

@test "test-failover.sh exits 2 when sentinel refuses the failover" {
    printf 'NOGOODSLAVE No suitable replica to promote\n' > "$FIX/26379/SENTINEL_failover_shopware-cache"
    run "$DIR/test-failover.sh" shopware-cache
    [ "$status" -eq 2 ]
    [[ "$output" == *"lehnt das Failover ab"* ]]
}

@test "redis-impact-test.sh needs exactly one url" {
    run "$DIR/redis-impact-test.sh"
    [ "$status" -eq 64 ]
    run "$DIR/redis-impact-test.sh" http://a/ http://b/
    [ "$status" -eq 64 ]
}

@test "redis-impact-test.sh reports both phases and restarts redis" {
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/bash
# Antwortet je nach Marker-Datei schnell oder langsam.
for arg; do :; done
if [[ -f "$FIX/redis-down" ]]; then
    printf '5.100000'
else
    printf '0.012000'
fi
STUB
    chmod +x "$TMP/bin/curl"

    run env REQUESTS=3 ASSUME_YES=1 \
        REDIS_STOP_CMD="touch $FIX/redis-down" \
        REDIS_START_CMD="rm -f $FIX/redis-down" \
        "$DIR/redis-impact-test.sh" http://shop.example/
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mit Redis   : min 12 ms | median 12 ms | max 12 ms | 0 Fehler von 3"* ]]
    [[ "$output" == *"Ohne Redis  : min 5100 ms | median 5100 ms | max 5100 ms | 0 Fehler von 3"* ]]
    [[ "$output" == *"Starte Redis wieder"* ]]
    [ ! -f "$FIX/redis-down" ]
}

@test "redis-impact-test.sh restarts redis even when every request fails" {
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/bash
[[ -f "$FIX/redis-down" ]] && exit 28
printf '0.012000'
STUB
    chmod +x "$TMP/bin/curl"

    run env REQUESTS=2 ASSUME_YES=1 \
        REDIS_STOP_CMD="touch $FIX/redis-down" \
        REDIS_START_CMD="rm -f $FIX/redis-down" \
        "$DIR/redis-impact-test.sh" http://shop.example/
    [ "$status" -eq 0 ]
    [[ "$output" == *"keine erfolgreiche Antwort (2 Fehler von 2)"* ]]
    [ ! -f "$FIX/redis-down" ]
}

@test "redis-impact-test.sh exits 2 when the url is dead before the test" {
    cat > "$TMP/bin/curl" <<'STUB'
#!/bin/bash
exit 7
STUB
    chmod +x "$TMP/bin/curl"

    run env ASSUME_YES=1 "$DIR/redis-impact-test.sh" http://shop.example/
    [ "$status" -eq 2 ]
    [[ "$output" == *"schon vor dem Test nicht erreichbar"* ]]
}
