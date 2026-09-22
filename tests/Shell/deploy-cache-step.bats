#!/usr/bin/env bats

# BATS tests for the chapter 7 deploy step (deploy/deploy-cache-step.yml).
# The heredoc body that ssh sends to the server is cut out of the YAML and run
# with sh against a fake shop root: bin/console and scripts/cache-warmup.sh are
# stubs that log their arguments.

YML="./chapters/07-shopware-cache/deploy/deploy-cache-step.yml"

setup() {
    TMP="$(mktemp -d)"
    SHOP="$TMP/shop"
    LOG="$TMP/log"
    mkdir -p "$SHOP/bin" "$SHOP/scripts"
    : > "$LOG"

    # Stub: bin/console loggt, FAIL_CMD laesst genau diesen Befehl scheitern
    cat > "$SHOP/bin/console" <<'STUB'
#!/bin/sh
echo "console $*" >> "$LOG"
[ "$1" = "${FAIL_CMD:-}" ] && exit 1
exit 0
STUB
    cat > "$SHOP/scripts/cache-warmup.sh" <<'STUB'
#!/bin/sh
echo "warmup $*" >> "$LOG"
STUB
    chmod +x "$SHOP/bin/console" "$SHOP/scripts/cache-warmup.sh"
    export LOG

    # Heredoc-Rumpf zwischen "<< 'EOF'" und der Zeile "EOF"
    awk '/<< *'\''EOF'\''$/ {on=1; next} on && /^[[:space:]]*EOF$/ {exit} on' "$YML" > "$TMP/body.sh"
    [ "$(grep -c '^[[:space:]]*cd /var/www/shop$' "$TMP/body.sh")" -eq 1 ]
    sed -i "s#cd /var/www/shop#cd $SHOP#" "$TMP/body.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "deploy step: ssh opens the run block, EOF closes it at the same indent" {
    # YAML entfernt die Einrueckung der ersten Blockzeile. Nur wenn ssh diese
    # Zeile ist und EOF genauso tief steht, landet EOF in Spalte 0.
    first=$(awk '/^ *run: [|]$/ {getline; print; exit}' "$YML")
    last=$(awk 'NF {l=$0} END {print l}' "$YML")
    [[ "$first" =~ ^(\ +)ssh\ .*\<\<\ *\'EOF\'$ ]]
    indent="${BASH_REMATCH[1]}"
    [ "$last" = "${indent}EOF" ]
}

@test "deploy step: clears, generates the sitemap, then warms in this order" {
    run sh "$TMP/body.sh"
    [ "$status" -eq 0 ]
    expected="console cache:clear
console cache:clear:all
console sitemap:generate --force
warmup https://ihr-shop.ch --sitemap --parallel 4 --limit 500"
    [ "$(cat "$LOG")" = "$expected" ]
}

@test "deploy step: missing warmup script stops before any cache is cleared" {
    rm "$SHOP/scripts/cache-warmup.sh"
    run sh "$TMP/body.sh"
    [ "$status" -ne 0 ]
    [ ! -s "$LOG" ]
}

@test "deploy step: warmup script without exec bit stops before clearing" {
    chmod -x "$SHOP/scripts/cache-warmup.sh"
    run sh "$TMP/body.sh"
    [ "$status" -ne 0 ]
    [ ! -s "$LOG" ]
}

@test "deploy step: each failing console command stops the step" {
    for cmd in cache:clear cache:clear:all sitemap:generate; do
        : > "$LOG"
        FAIL_CMD="$cmd" run sh "$TMP/body.sh"
        [ "$status" -ne 0 ]
        [[ "$(tail -n 1 "$LOG")" == "console $cmd"* ]]
        [ "$(grep -c '^warmup' "$LOG")" -eq 0 ]
    done
}
