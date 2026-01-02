#!/bin/bash
#
# Update Twig template snapshots automatically
# Run this after modifying Twig templates in chapters/
#
# Usage: ./scripts/update-snapshots.sh [--check] [--chapter XX]
#
# Options:
#   --check      Only check if snapshots are outdated (exit 1 if outdated)
#   --chapter    Only update snapshots for specific chapter (e.g., 16)
#
# Exit codes:
#   0 - Success (snapshots updated or up-to-date)
#   1 - Check failed (snapshots are outdated)
#   2 - Error (test failures or missing dependencies)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SNAPSHOT_DIR="$PROJECT_ROOT/tests/Snapshots/__snapshots__"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
CHECK_MODE=false
CHAPTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --check)
            CHECK_MODE=true
            shift
            ;;
        --chapter)
            CHAPTER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 2
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Ensure dependencies are installed
if [[ ! -d "vendor" ]]; then
    echo -e "${YELLOW}Installing PHP dependencies...${NC}"
    composer install --quiet
fi

echo "=== Twig Snapshot Manager ==="
echo ""

# Find all Twig templates
if [[ -n "$CHAPTER" ]]; then
    TWIG_PATTERN="chapters/$CHAPTER-*/templates/*.twig"
else
    TWIG_PATTERN="chapters/*/templates/*.twig"
fi

# Count templates
TEMPLATE_COUNT=$(find chapters -name "*.twig" 2>/dev/null | wc -l)
echo "Found $TEMPLATE_COUNT Twig templates"

if [[ "$CHECK_MODE" == true ]]; then
    echo ""
    echo "Running snapshot comparison..."

    # Run PHPUnit snapshot tests
    if vendor/bin/phpunit --testsuite Snapshots --no-coverage 2>/dev/null; then
        echo -e "${GREEN}All snapshots are up-to-date${NC}"
        exit 0
    else
        echo -e "${RED}Snapshots are outdated!${NC}"
        echo ""
        echo "Run: ./scripts/update-snapshots.sh"
        exit 1
    fi
else
    echo ""
    echo "Regenerating snapshots..."

    # Delete old snapshots if they exist
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        rm -rf "$SNAPSHOT_DIR"
        echo "Removed old snapshots"
    fi

    # Run tests to regenerate snapshots
    # PHPUnit snapshot libraries typically create snapshots on first run
    if vendor/bin/phpunit --testsuite Snapshots --no-coverage; then
        echo ""
        echo -e "${GREEN}Snapshots updated successfully!${NC}"

        # Count new snapshots
        if [[ -d "$SNAPSHOT_DIR" ]]; then
            SNAPSHOT_COUNT=$(find "$SNAPSHOT_DIR" -name "*.txt" 2>/dev/null | wc -l)
            echo "Created $SNAPSHOT_COUNT snapshot files"
        fi

        exit 0
    else
        echo ""
        echo -e "${RED}Failed to update snapshots${NC}"
        exit 2
    fi
fi
