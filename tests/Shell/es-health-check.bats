#!/usr/bin/env bats

# BATS tests for es-health-check.sh

SCRIPT="./chapters/18-shopware-elasticsearch/scripts/es-health-check.sh"

setup() {
    [ -f "$SCRIPT" ] || skip "Script not found: $SCRIPT"
    [ -x "$SCRIPT" ] || chmod +x "$SCRIPT"
}

@test "es-health-check.sh shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]] || [[ "$output" == *"Elasticsearch"* ]]
}

@test "es-health-check.sh has executable permissions" {
    [ -x "$SCRIPT" ]
}
