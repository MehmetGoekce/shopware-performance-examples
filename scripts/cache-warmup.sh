#!/bin/bash
# Shopware Cache Warmup Script
# Kapitel 6-8: Caching

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Shopware Cache Warmup ===${NC}"
echo ""

# Check if we're in Docker or local
if [ -f /var/www/html/bin/console ]; then
    CONSOLE="/var/www/html/bin/console"
elif [ -f bin/console ]; then
    CONSOLE="bin/console"
else
    echo "Error: Shopware console not found"
    exit 1
fi

echo -e "${YELLOW}1. Clearing all caches...${NC}"
$CONSOLE cache:clear

echo ""
echo -e "${YELLOW}2. Warming HTTP cache...${NC}"
$CONSOLE http:cache:warm:up

echo ""
echo -e "${YELLOW}3. Warming theme cache...${NC}"
$CONSOLE theme:compile

echo ""
echo -e "${YELLOW}4. Warming product search index...${NC}"
$CONSOLE es:index --no-queue 2>/dev/null || $CONSOLE dal:refresh:index

echo ""
echo -e "${YELLOW}5. Warming sitemap...${NC}"
$CONSOLE sitemap:generate

echo ""
echo -e "${GREEN}=== Cache Warmup Complete ===${NC}"
echo ""
echo "All caches are now warm. First requests should be fast."
