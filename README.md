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
│   ├── 03-quick-wins/
│   ├── 06-http-cache/
│   ├── 08-database/
│   ├── 09-php-performance/
│   ├── 10-redis/
│   └── 11-cdn/
├── docker-compose.yml            # Entwicklungsumgebung
├── docker-compose.redis.yml      # Redis Sentinel Setup
└── Makefile                      # Convenience-Commands
```

## Kapitel-Übersicht

| Kapitel | Thema | Branch/Tag |
|---------|-------|------------|
| 3 | Quick Wins (Bilder, CSS, JS) | `chapter-03` |
| 6 | HTTP-Cache | `chapter-06` |
| 8 | Datenbank-Optimierung | `chapter-08` |
| 9 | PHP-Performance | `chapter-09` |
| 10 | Redis High Availability | `chapter-10` |
| 11 | CDN-Integration | `chapter-11` |

## Verwendung

### Bestimmtes Kapitel auschecken

```bash
# Kapitel 10: Redis
git checkout chapter-10

# Vorher/Nachher vergleichen
git diff chapter-10-before chapter-10-after
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
