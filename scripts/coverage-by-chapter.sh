#!/bin/bash
#
# Generate coverage report per chapter
# Analyzes which chapters have tests and their coverage status
#
# Usage: ./scripts/coverage-by-chapter.sh [--json] [--verbose]
#
# Options:
#   --json       Output as JSON
#   --verbose    Show detailed file lists
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse arguments
JSON_MODE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_MODE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Colors (disabled in JSON mode)
if [[ "$JSON_MODE" == false ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Collect chapter data
declare -A CHAPTER_DATA

for chapter_dir in chapters/*/; do
    chapter=$(basename "$chapter_dir")

    # Count source files
    php_count=$(find "$chapter_dir" -name "*.php" 2>/dev/null | wc -l)
    js_count=$(find "$chapter_dir" -name "*.js" 2>/dev/null | wc -l)
    sh_count=$(find "$chapter_dir" -name "*.sh" 2>/dev/null | wc -l)
    twig_count=$(find "$chapter_dir" -name "*.twig" 2>/dev/null | wc -l)

    total=$((php_count + js_count + sh_count + twig_count))

    # Check for related tests
    chapter_num="${chapter%%-*}"  # Extract number (e.g., "16" from "16-shopware-themes")

    # Disable exit on error for grep (returns 1 when no matches)
    set +e

    # PHP tests
    php_tests=$(grep -rl "chapters/$chapter_num" tests/Unit/ 2>/dev/null | wc -l)
    php_tests2=$(grep -rl "$chapter" tests/Unit/ 2>/dev/null | wc -l)
    php_tests=$((php_tests + php_tests2))

    # JavaScript tests
    js_tests=$(grep -rl "chapters/$chapter_num" tests/JavaScript/ 2>/dev/null | wc -l)
    js_tests2=$(grep -rl "$chapter" tests/JavaScript/ 2>/dev/null | wc -l)
    js_tests=$((js_tests + js_tests2))

    # E2E tests
    e2e_tests=$(grep -rl "$chapter" tests/E2E/ 2>/dev/null | wc -l)

    # Snapshot tests
    snapshot_tests=$(grep -c "$chapter" tests/Snapshots/TwigTemplateTest.php 2>/dev/null)
    [[ -z "$snapshot_tests" ]] && snapshot_tests=0

    # Re-enable exit on error
    set -e

    total_tests=$((php_tests + js_tests + e2e_tests + snapshot_tests))

    CHAPTER_DATA["$chapter"]="$php_count,$js_count,$sh_count,$twig_count,$total,$php_tests,$js_tests,$e2e_tests,$snapshot_tests,$total_tests"
done

if [[ "$JSON_MODE" == true ]]; then
    # JSON output
    echo "{"
    echo '  "generated": "'$(date -Iseconds)'",'
    echo '  "chapters": ['

    first=true
    for chapter in $(echo "${!CHAPTER_DATA[@]}" | tr ' ' '\n' | sort); do
        IFS=',' read -r php js sh twig total php_t js_t e2e_t snap_t total_t <<< "${CHAPTER_DATA[$chapter]}"

        [[ "$first" == true ]] || echo ","
        first=false

        coverage_status="none"
        [[ $total_t -gt 0 ]] && coverage_status="partial"
        [[ $total_t -ge $total && $total -gt 0 ]] && coverage_status="full"

        echo -n "    {"
        echo -n '"name": "'"$chapter"'", '
        echo -n '"files": {"php": '"$php"', "js": '"$js"', "sh": '"$sh"', "twig": '"$twig"', "total": '"$total"'}, '
        echo -n '"tests": {"php": '"$php_t"', "js": '"$js_t"', "e2e": '"$e2e_t"', "snapshot": '"$snap_t"', "total": '"$total_t"'}, '
        echo -n '"status": "'"$coverage_status"'"'
        echo -n "}"
    done

    echo ""
    echo "  ]"
    echo "}"
else
    # Human-readable output
    echo "=== Coverage Report by Chapter ==="
    echo ""
    printf "%-35s %4s %4s %4s %4s | %4s %4s %4s %4s | %s\n" \
        "Chapter" "PHP" "JS" "SH" "Twig" "PHP" "JS" "E2E" "Snap" "Status"
    printf "%s\n" "$(printf '%.0s-' {1..95})"

    total_files=0
    total_tests=0
    covered_chapters=0

    for chapter in $(echo "${!CHAPTER_DATA[@]}" | tr ' ' '\n' | sort); do
        IFS=',' read -r php js sh twig total php_t js_t e2e_t snap_t total_t <<< "${CHAPTER_DATA[$chapter]}"

        total_files=$((total_files + total))
        total_tests=$((total_tests + total_t))

        # Determine status
        if [[ $total_t -eq 0 ]]; then
            status="${RED}No tests${NC}"
        elif [[ $total_t -lt $total ]]; then
            status="${YELLOW}Partial${NC}"
            covered_chapters=$((covered_chapters + 1))
        else
            status="${GREEN}Covered${NC}"
            covered_chapters=$((covered_chapters + 1))
        fi

        printf "%-35s %4d %4d %4d %4d | %4d %4d %4d %4d | %b\n" \
            "$chapter" "$php" "$js" "$sh" "$twig" "$php_t" "$js_t" "$e2e_t" "$snap_t" "$status"

        if [[ "$VERBOSE" == true && $total -gt 0 ]]; then
            echo "  Files:"
            find "chapters/$chapter" -type f \( -name "*.php" -o -name "*.js" -o -name "*.sh" -o -name "*.twig" \) 2>/dev/null | head -5 | sed 's/^/    /'
            [[ $(find "chapters/$chapter" -type f \( -name "*.php" -o -name "*.js" -o -name "*.sh" -o -name "*.twig" \) 2>/dev/null | wc -l) -gt 5 ]] && echo "    ..."
        fi
    done

    printf "%s\n" "$(printf '%.0s-' {1..95})"
    echo ""
    echo "Summary:"
    echo "  Total chapters: ${#CHAPTER_DATA[@]}"
    echo "  Chapters with tests: $covered_chapters"
    echo "  Total source files: $total_files"
    echo "  Total test references: $total_tests"
    echo ""
    echo "Legend:"
    echo "  PHP/JS/SH/Twig = Source file counts"
    echo "  PHP/JS/E2E/Snap = Test reference counts"
fi
