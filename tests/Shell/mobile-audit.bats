#!/usr/bin/env bats

# BATS tests for mobile-audit.sh

SCRIPT="./chapters/19-mobile-performance/scripts/mobile-audit.sh"

setup() {
    # Ensure script exists and is executable
    [ -f "$SCRIPT" ] || skip "Script not found: $SCRIPT"
    [ -x "$SCRIPT" ] || chmod +x "$SCRIPT"
}

@test "mobile-audit.sh requires URL parameter" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"URL required"* ]]
}

@test "mobile-audit.sh shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--output"* ]]
}

@test "mobile-audit.sh accepts --output=json parameter" {
    run "$SCRIPT" --help
    [[ "$output" == *"json"* ]]
}
