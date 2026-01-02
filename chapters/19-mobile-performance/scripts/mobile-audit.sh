#!/bin/bash
#
# Mobile Performance Audit Script
#
# Comprehensive mobile performance audit for Shopware 6 shops.
# Checks multiple aspects of mobile optimization.
#
# Usage:
#   ./mobile-audit.sh https://example.com
#   ./mobile-audit.sh https://example.com --output json
#
# Requirements:
#   - curl
#   - jq (for JSON parsing)
#   - lighthouse (optional, for detailed audit)

set -euo pipefail

# Configuration
URL="${1:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
MOBILE_UA="Mozilla/5.0 (Linux; Android 10; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
for arg in "$@"; do
    case ${arg} in
        --output=*)
            OUTPUT_FORMAT="${arg#*=}"
            ;;
        --help)
            echo "Usage: $0 <url> [options]"
            echo ""
            echo "Options:"
            echo "  --output=text|json   Output format (default: text)"
            echo "  --help               Show this help"
            exit 0
            ;;
        -*)
            ;;
        *)
            if [[ -z "${URL}" ]]; then
                URL="${arg}"
            fi
            ;;
    esac
done

if [[ -z "${URL}" ]]; then
    echo "Error: URL required"
    echo "Usage: $0 <url>"
    exit 1
fi

# Results array for JSON output
declare -A RESULTS
ISSUES=()
SCORE=100

check_pass() {
    local name="$1"
    echo -e "  ${GREEN}✓${NC} ${name}"
    RESULTS["${name}"]="pass"
}

check_fail() {
    local name="$1"
    local message="$2"
    local deduction="${3:-5}"
    echo -e "  ${RED}✗${NC} ${name}: ${message}"
    RESULTS["${name}"]="fail"
    ISSUES+=("${name}: ${message}")
    SCORE=$((SCORE - deduction))
}

check_warn() {
    local name="$1"
    local message="$2"
    local deduction="${3:-2}"
    echo -e "  ${YELLOW}!${NC} ${name}: ${message}"
    RESULTS["${name}"]="warn"
    ISSUES+=("${name}: ${message}")
    SCORE=$((SCORE - deduction))
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Mobile Performance Audit${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "URL: ${URL}"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ============================================
# 1. Viewport Configuration
# ============================================
echo -e "${YELLOW}1. Viewport Configuration${NC}"
echo "-------------------------------------------"

RESPONSE=$(curl -s -A "${MOBILE_UA}" -L "${URL}")

# Check viewport meta tag
if echo "${RESPONSE}" | grep -q 'name="viewport"'; then
    VIEWPORT=$(echo "${RESPONSE}" | grep -oP 'content="[^"]*width=device-width[^"]*"' | head -1)
    if [[ -n "${VIEWPORT}" ]]; then
        check_pass "Viewport meta tag"

        # Check for problematic settings
        if echo "${VIEWPORT}" | grep -q 'user-scalable=no'; then
            check_fail "Zoom disabled" "user-scalable=no prevents accessibility" 5
        else
            check_pass "Zoom enabled"
        fi

        if echo "${VIEWPORT}" | grep -q 'maximum-scale=1'; then
            check_warn "Maximum scale restricted" "May affect accessibility" 2
        fi
    else
        check_fail "Viewport meta tag" "width=device-width not set" 10
    fi
else
    check_fail "Viewport meta tag" "Not found" 10
fi
echo ""

# ============================================
# 2. Mobile Responsiveness
# ============================================
echo -e "${YELLOW}2. Mobile Responsiveness${NC}"
echo "-------------------------------------------"

# Check for media queries
MEDIA_QUERIES=$(echo "${RESPONSE}" | grep -c '@media' || echo "0")
if [[ "${MEDIA_QUERIES}" -gt 0 ]]; then
    check_pass "CSS Media Queries found (${MEDIA_QUERIES})"
else
    check_warn "No inline media queries" "CSS may be in external files" 0
fi

# Check for responsive images
SRCSET_COUNT=$(echo "${RESPONSE}" | grep -c 'srcset=' || echo "0")
if [[ "${SRCSET_COUNT}" -gt 0 ]]; then
    check_pass "Responsive images (srcset) found (${SRCSET_COUNT})"
else
    check_warn "No srcset found" "Images may not be optimized for mobile" 5
fi

# Check for picture elements
PICTURE_COUNT=$(echo "${RESPONSE}" | grep -c '<picture' || echo "0")
if [[ "${PICTURE_COUNT}" -gt 0 ]]; then
    check_pass "Picture elements found (${PICTURE_COUNT})"
fi
echo ""

# ============================================
# 3. Touch Optimization
# ============================================
echo -e "${YELLOW}3. Touch Optimization${NC}"
echo "-------------------------------------------"

# Check for touch-action CSS
if echo "${RESPONSE}" | grep -q 'touch-action'; then
    check_pass "touch-action CSS found"
fi

# Check for minimum button/link sizes (basic check)
if echo "${RESPONSE}" | grep -qE 'min-height:\s*(44|48)px'; then
    check_pass "Touch-friendly sizes detected"
else
    check_warn "Touch target sizes" "Verify 44px+ touch targets manually" 3
fi
echo ""

# ============================================
# 4. Performance Indicators
# ============================================
echo -e "${YELLOW}4. Performance Indicators${NC}"
echo "-------------------------------------------"

# Check for preload hints
PRELOAD_COUNT=$(echo "${RESPONSE}" | grep -c 'rel="preload"' || echo "0")
if [[ "${PRELOAD_COUNT}" -gt 0 ]]; then
    check_pass "Preload hints found (${PRELOAD_COUNT})"
else
    check_warn "No preload hints" "Consider preloading critical assets" 3
fi

# Check for lazy loading
LAZY_COUNT=$(echo "${RESPONSE}" | grep -c 'loading="lazy"' || echo "0")
if [[ "${LAZY_COUNT}" -gt 0 ]]; then
    check_pass "Lazy loading enabled (${LAZY_COUNT} images)"
else
    check_fail "Lazy loading" "No loading='lazy' found" 5
fi

# Check for async/defer scripts
ASYNC_SCRIPTS=$(echo "${RESPONSE}" | grep -cE '<script[^>]*(async|defer)' || echo "0")
TOTAL_SCRIPTS=$(echo "${RESPONSE}" | grep -c '<script' || echo "0")
if [[ "${ASYNC_SCRIPTS}" -gt 0 ]]; then
    check_pass "Async/defer scripts (${ASYNC_SCRIPTS} of ${TOTAL_SCRIPTS})"
else
    check_warn "Render-blocking scripts" "Consider async/defer" 5
fi
echo ""

# ============================================
# 5. PWA Features
# ============================================
echo -e "${YELLOW}5. PWA Features${NC}"
echo "-------------------------------------------"

# Check for manifest
if echo "${RESPONSE}" | grep -q 'rel="manifest"'; then
    check_pass "Web App Manifest found"
else
    check_warn "No Web App Manifest" "PWA features unavailable" 3
fi

# Check for service worker registration
if echo "${RESPONSE}" | grep -q 'serviceWorker'; then
    check_pass "Service Worker reference found"
else
    check_warn "No Service Worker" "Offline support unavailable" 3
fi

# Check for theme-color
if echo "${RESPONSE}" | grep -q 'name="theme-color"'; then
    check_pass "Theme color meta tag found"
fi

# Check for apple-mobile-web-app
if echo "${RESPONSE}" | grep -q 'apple-mobile-web-app'; then
    check_pass "iOS web app meta tags found"
fi
echo ""

# ============================================
# 6. Mobile SEO
# ============================================
echo -e "${YELLOW}6. Mobile SEO${NC}"
echo "-------------------------------------------"

# Check for canonical
if echo "${RESPONSE}" | grep -q 'rel="canonical"'; then
    check_pass "Canonical URL found"
else
    check_warn "No canonical URL" "May cause duplicate content issues" 2
fi

# Check for structured data
if echo "${RESPONSE}" | grep -q 'application/ld+json'; then
    check_pass "Structured data (JSON-LD) found"
else
    check_warn "No structured data" "Consider adding Schema.org markup" 2
fi
echo ""

# ============================================
# 7. Response Headers
# ============================================
echo -e "${YELLOW}7. Response Headers${NC}"
echo "-------------------------------------------"

HEADERS=$(curl -s -I -A "${MOBILE_UA}" -L "${URL}")

# Check compression
if echo "${HEADERS}" | grep -qi 'content-encoding.*gzip\|br'; then
    check_pass "Compression enabled"
else
    check_fail "Compression" "Not enabled (gzip/brotli)" 10
fi

# Check cache headers
if echo "${HEADERS}" | grep -qi 'cache-control'; then
    check_pass "Cache-Control header present"
else
    check_warn "No Cache-Control header" "Caching may not be optimized" 3
fi

# Check HTTPS
if [[ "${URL}" == https://* ]]; then
    check_pass "HTTPS enabled"
else
    check_fail "HTTPS" "Site not using HTTPS" 15
fi
echo ""

# ============================================
# Summary
# ============================================
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Final score
if [[ ${SCORE} -lt 0 ]]; then
    SCORE=0
fi

if [[ ${SCORE} -ge 90 ]]; then
    GRADE="${GREEN}A${NC}"
elif [[ ${SCORE} -ge 80 ]]; then
    GRADE="${GREEN}B${NC}"
elif [[ ${SCORE} -ge 70 ]]; then
    GRADE="${YELLOW}C${NC}"
elif [[ ${SCORE} -ge 60 ]]; then
    GRADE="${YELLOW}D${NC}"
else
    GRADE="${RED}F${NC}"
fi

echo -e "Mobile Performance Score: ${SCORE}/100 (Grade: ${GRADE})"
echo ""

if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo "Issues Found:"
    for issue in "${ISSUES[@]}"; do
        echo "  - ${issue}"
    done
    echo ""
fi

echo "Recommendations:"
echo "  1. Run Lighthouse mobile audit for detailed metrics"
echo "  2. Test on real devices with Chrome DevTools"
echo "  3. Check Core Web Vitals in Search Console"
echo ""

# JSON output
if [[ "${OUTPUT_FORMAT}" = "json" ]]; then
    echo ""
    echo "JSON Output:"
    echo "{"
    echo "  \"url\": \"${URL}\","
    echo "  \"score\": ${SCORE},"
    echo "  \"issues\": ["
    printf '    "%s",\n' "${ISSUES[@]}" | sed '$ s/,$//'
    echo "  ]"
    echo "}"
fi
