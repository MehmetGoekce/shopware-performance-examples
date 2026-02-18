# Shopware Performance Examples

Code-Beispiele zum Buch **"Shop-Performance in 30 Tagen"** von Mehmet Gökce.

## Quick Start

```bash
# Repository klonen
git clone https://github.com/MehmetGoekce/shopware-performance-examples.git
cd shopware-performance-examples

# Docker-Umgebung starten
docker-compose up -d

# Shopware installieren (nur beim ersten Start)
make install

# Shop öffnen
open http://localhost:8000
```

## Voraussetzungen

- Docker & Docker Compose
- Git
- Make (optional, für Convenience-Commands)

## Kompatibilität

| Shopware | PHP | Extras |
|----------|-----|--------|
| 6.5.x, 6.6.x | 8.2 - 8.4 | Redis 7+, ES 8.x (optional) |

Siehe [COMPATIBILITY.md](COMPATIBILITY.md) für Details zu Versionen und bekannten API-Änderungen.

## Struktur

```
shopware-performance-examples/
├── src/                          # Shopware Plugin-Code
│   ├── Command/                  # CLI-Commands
│   ├── Service/                  # Service-Klassen
│   ├── Subscriber/               # Event Subscriber
│   └── Resources/config/         # DI-Konfiguration
├── config/packages/              # Shopware-Konfiguration
│   ├── cache.yaml                # Kapitel 6-8: Caching
│   ├── redis.yaml                # Kapitel 10: Redis
│   └── shopware.yaml             # Allgemeine Einstellungen
├── scripts/                      # Utility-Scripts
│   ├── benchmark.sh              # Performance-Tests
│   ├── cache-warmup.sh           # Cache vorwärmen
│   └── analyze-queries.sh        # DB-Query-Analyse
├── chapters/                     # Code nach Kapiteln organisiert
│   ├── 03-core-web-vitals/
│   ├── 04-image-optimization/
│   ├── 05-css-javascript/
│   ├── 06-http-cache/
│   ├── 07-shopware-cache/
│   ├── 08-database/
│   ├── 09-php-performance/
│   ├── 10-redis-sentinel/
│   ├── 11-cdn-integration/
│   ├── ...
│   └── 24-ausblick/
├── docker-compose.yml            # Entwicklungsumgebung
├── docker-compose.redis.yml      # Redis Sentinel Setup
└── Makefile                      # Convenience-Commands
```

## Kapitel-Übersicht

| Kapitel | Thema | Verzeichnis |
|---------|-------|-------------|
| 3 | Core Web Vitals | `03-core-web-vitals/` |
| 4 | Bildoptimierung | `04-image-optimization/` |
| 5 | CSS & JavaScript | `05-css-javascript/` |
| 6 | HTTP-Cache | `06-http-cache/` |
| 7 | Shopware Cache | `07-shopware-cache/` |
| 8 | Datenbank-Optimierung | `08-database/` |
| 9 | PHP-Performance | `09-php-performance/` |
| 10 | Redis Sentinel | `10-redis-sentinel/` |
| 11 | CDN-Integration | `11-cdn-integration/` |
| 12-24 | Weitere Kapitel | siehe `chapters/` |

## Verwendung

### Kapitel-Code verwenden

Jedes Kapitel hat ein eigenes Verzeichnis mit README, Code und Scripts:

```bash
# Kapitel 10: Redis Sentinel
cd chapters/10-redis-sentinel/
cat README.md

# Scripts ausführen
./chapters/10-redis-sentinel/scripts/test-failover.sh

# Alle Kapitel auflisten
ls chapters/
```

### Benchmarks ausführen

```bash
# Performance-Baseline messen
make benchmark

# Spezifischen Test
./scripts/benchmark.sh --endpoint=/api/product --iterations=100
```

### Redis Sentinel testen

```bash
# Redis Sentinel Cluster starten
docker-compose -f docker-compose.redis.yml up -d

# Failover simulieren
make redis-failover

# Logs beobachten
docker-compose -f docker-compose.redis.yml logs -f sentinel1
```

## Make-Commands

| Command | Beschreibung |
|---------|--------------|
| `make install` | Shopware installieren |
| `make start` | Container starten |
| `make stop` | Container stoppen |
| `make benchmark` | Performance-Tests |
| `make cache-warmup` | Caches vorwärmen |
| `make redis-failover` | Redis Failover simulieren |
| `make analyze-queries` | Langsame Queries finden |

## Buch kaufen

- **Leanpub:** [leanpub.com/shopware-performance](https://leanpub.com/shopware-performance)
- **Gumroad:** [memotech.gumroad.com/shopware-performance](https://memotech.gumroad.com/shopware-performance)

## Support

- **Issues:** [GitHub Issues](https://github.com/MehmetGoekce/shopware-performance-examples/issues)
- **Autor:** Mehmet Gökce ([@MehmetGoekce](https://github.com/MehmetGoekce))
- **Website:** [memotech.ch](https://memotech.ch)

## Lizenz

MIT License - siehe [LICENSE](LICENSE)

---

**Hinweis:** Dieses Repository enthält ausschliesslich Code-Beispiele. Für die vollständige Dokumentation und Erklärungen siehe das Buch.
