#!/bin/bash
#
# Shopware 6 Performance Audit Script
# Kapitel 2: Performance-Audit — Wo stehen Sie?
#
# Verwendung: ./audit.sh [shopware-root-pfad]
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Shopware Root (default: aktuelles Verzeichnis)
SHOPWARE_ROOT="${1:-.}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       SHOPWARE 6 PERFORMANCE AUDIT                         ║${NC}"
echo -e "${BLUE}║       Kapitel 2: Performance-Audit                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Datum: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Shopware Root: ${SHOPWARE_ROOT}"
echo ""

# Prüfen ob Shopware-Verzeichnis existiert
if [[ ! -f "${SHOPWARE_ROOT}/bin/console" ]]; then
    echo -e "${RED}Fehler: Kein Shopware-Verzeichnis gefunden.${NC}"
    echo "Verwendung: ./audit.sh /pfad/zu/shopware"
    exit 1
fi

cd "${SHOPWARE_ROOT}"

echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 1. SYSTEM-VERSIONEN                                          │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# Shopware Version
echo -n "Shopware Version: "
SHOPWARE_VERSION=$(bin/console --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unbekannt")
echo -e "${GREEN}${SHOPWARE_VERSION}${NC}"

# PHP Version
echo -n "PHP Version: "
PHP_VERSION=$(php -v | head -n 1 | grep -oP '\d+\.\d+\.\d+')
PHP_MAJOR=$(echo "${PHP_VERSION}" | cut -d. -f1)
PHP_MINOR=$(echo "${PHP_VERSION}" | cut -d. -f2)
if [[ "${PHP_MAJOR}" -ge 8 ]] && [[ "${PHP_MINOR}" -ge 2 ]]; then
    echo -e "${GREEN}${PHP_VERSION} ✓${NC}"
else
    echo -e "${YELLOW}${PHP_VERSION} (8.2+ empfohlen)${NC}"
fi

# MySQL/MariaDB Version
echo -n "MySQL/MariaDB: "
if command -v mysql &> /dev/null; then
    MYSQL_VERSION=$(mysql --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    echo -e "${GREEN}${MYSQL_VERSION}${NC}"
else
    echo -e "${YELLOW}nicht direkt prüfbar${NC}"
fi

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 2. PLUGINS                                                   │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# Aktive Plugins zählen
ACTIVE_PLUGINS=$(bin/console plugin:list --active 2>/dev/null | tail -n +4 | wc -l)
echo -n "Aktive Plugins: "
if [[ "${ACTIVE_PLUGINS}" -le 20 ]]; then
    echo -e "${GREEN}${ACTIVE_PLUGINS} ✓${NC}"
elif [[ "${ACTIVE_PLUGINS}" -le 30 ]]; then
    echo -e "${YELLOW}${ACTIVE_PLUGINS} (grenzwertig)${NC}"
else
    echo -e "${RED}${ACTIVE_PLUGINS} (zu viele!)${NC}"
fi

# Plugin-Liste ausgeben
echo ""
echo "Installierte Plugins:"
bin/console plugin:list --active 2>/dev/null | tail -n +4 | head -20
if [[ "${ACTIVE_PLUGINS}" -gt 20 ]]; then
    echo "... und $((ACTIVE_PLUGINS - 20)) weitere"
fi

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 3. HTTP-CACHE                                                │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# HTTP-Cache Status
echo "HTTP-Cache Konfiguration:"
HTTP_CACHE_ENABLED=$(bin/console debug:config shopware http_cache 2>/dev/null | grep -E "enabled:" | head -1 || echo "")
if echo "${HTTP_CACHE_ENABLED}" | grep -q "true"; then
    echo -e "${GREEN}✓ HTTP-Cache ist aktiviert${NC}"
else
    echo -e "${RED}✗ HTTP-Cache ist DEAKTIVIERT!${NC}"
    echo -e "${YELLOW}  → Aktivieren Sie den HTTP-Cache für bessere Performance${NC}"
fi

# Cache TTL
bin/console debug:config shopware http_cache 2>/dev/null | grep -E "(default_ttl|stale)" || true

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 4. PHP OPCACHE                                               │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# OPcache Status
OPCACHE_ENABLED=$(php -i 2>/dev/null | grep "opcache.enable =>" | head -1 | awk '{print $3}')
echo -n "OPcache: "
if [[ "${OPCACHE_ENABLED}" = "On" ]] || [[ "${OPCACHE_ENABLED}" = "1" ]]; then
    echo -e "${GREEN}aktiviert ✓${NC}"

    # OPcache Memory
    OPCACHE_MEMORY=$(php -i 2>/dev/null | grep "opcache.memory_consumption" | awk '{print $3}')
    echo "Memory: ${OPCACHE_MEMORY}MB"

    # JIT Status (PHP 8+)
    JIT_ENABLED=$(php -i 2>/dev/null | grep "opcache.jit =>" | awk '{print $3}')
    if [[ -n "${JIT_ENABLED}" ]] && [[ "${JIT_ENABLED}" != "off" ]] && [[ "${JIT_ENABLED}" != "0" ]]; then
        echo -e "JIT: ${GREEN}aktiviert ✓${NC}"
    else
        echo -e "JIT: ${YELLOW}deaktiviert (empfohlen für PHP 8.2+)${NC}"
    fi
else
    echo -e "${RED}DEAKTIVIERT!${NC}"
    echo -e "${YELLOW}  → OPcache aktivieren für massive Performance-Steigerung${NC}"
fi

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 5. REDIS                                                     │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# Redis Status
echo -n "Redis: "
if command -v redis-cli &> /dev/null; then
    REDIS_PING=$(redis-cli ping 2>/dev/null || echo "FAIL")
    if [[ "${REDIS_PING}" = "PONG" ]]; then
        echo -e "${GREEN}läuft ✓${NC}"

        # Redis Memory
        REDIS_MEMORY=$(redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
        echo "Memory: ${REDIS_MEMORY}"
    else
        echo -e "${YELLOW}installiert aber nicht erreichbar${NC}"
    fi
else
    echo -e "${YELLOW}nicht installiert${NC}"
    echo -e "${YELLOW}  → Redis für Sessions und Cache empfohlen${NC}"
fi

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 6. ELASTICSEARCH                                             │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# Elasticsearch Status
echo -n "Elasticsearch: "
ES_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "localhost:9200/_cluster/health" 2>/dev/null || echo "000")
if [[ "${ES_STATUS}" = "200" ]]; then
    ES_HEALTH=$(curl -s "localhost:9200/_cluster/health" 2>/dev/null | grep -oP '"status":"[^"]+' | cut -d'"' -f4)
    if [[ "${ES_HEALTH}" = "green" ]]; then
        echo -e "${GREEN}läuft (${ES_HEALTH}) ✓${NC}"
    elif [[ "${ES_HEALTH}" = "yellow" ]]; then
        echo -e "${YELLOW}läuft (${ES_HEALTH})${NC}"
    else
        echo -e "${RED}läuft (${ES_HEALTH})${NC}"
    fi
else
    echo -e "${YELLOW}nicht erreichbar${NC}"
    echo -e "${YELLOW}  → Empfohlen bei > 5.000 Produkten${NC}"
fi

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 7. MESSAGE QUEUE WORKER                                      │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# CLI Worker Status
echo -n "CLI Worker: "
WORKER_RUNNING=$(ps aux 2>/dev/null | grep -c "messenger:consume" || echo "0")
if [[ "${WORKER_RUNNING}" -gt 1 ]]; then
    echo -e "${GREEN}$((WORKER_RUNNING - 1)) Prozess(e) laufen ✓${NC}"
else
    echo -e "${YELLOW}nicht aktiv${NC}"
    echo -e "${YELLOW}  → CLI Worker statt Admin Worker empfohlen${NC}"
fi

# Queue Status
echo ""
echo "Message Queue Status:"
bin/console messenger:stats 2>/dev/null | head -10 || echo "  (nicht verfügbar)"

echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ 8. RESSOURCEN                                                │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"

# Bildgrößen
echo "Große Bilder (> 1MB) im Media-Ordner:"
LARGE_IMAGES=$(find public/media -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) -size +1M 2>/dev/null | wc -l)
if [[ "${LARGE_IMAGES}" -eq 0 ]]; then
    echo -e "${GREEN}✓ Keine Bilder > 1MB gefunden${NC}"
else
    echo -e "${RED}${LARGE_IMAGES} Bilder > 1MB gefunden!${NC}"
    echo "Top 5 größte Bilder:"
    find public/media -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) -size +1M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h -r | head -5
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       AUDIT ABGESCHLOSSEN                                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Nächste Schritte:"
echo "1. PageSpeed Insights für Ihre wichtigsten URLs testen"
echo "2. Chrome DevTools → Lighthouse für detaillierte Analyse"
echo "3. Audit-Template ausfüllen (templates/AUDIT-TEMPLATE.md)"
echo ""
