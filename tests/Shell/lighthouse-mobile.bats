#!/usr/bin/env bats

# BATS tests for lighthouse-mobile.sh

SCRIPT="./chapters/19-mobile-performance/scripts/lighthouse-mobile.sh"

setup() {
    [ -f "$SCRIPT" ] || skip "Script not found: $SCRIPT"
    [ -x "$SCRIPT" ] || chmod +x "$SCRIPT"
}

@test "lighthouse-mobile.sh requires URL parameter" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"URL required"* ]]
}

@test "lighthouse-mobile.sh shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--iterations"* ]]
}

@test "lighthouse-mobile.sh accepts --iterations parameter" {
    run "$SCRIPT" --help
    [[ "$output" == *"iterations"* ]]
}

@test "lighthouse-mobile.sh accepts --no-throttle parameter" {
    run "$SCRIPT" --help
    [[ "$output" == *"--no-throttle"* ]]
}
