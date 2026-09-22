# Kapitel 7: Shopwares Application Cache meistern

Konfigurationen, Service und Skripte für den Application Cache (Object-Cache, HTTP-Cache-Speicher) und Sessions in Redis.

Getestet mit Shopware 6.6.10.6 (Dockware), Redis 7.4 und PHP 8.3 mit `redis`-Extension. Die Redis-Configs laufen ab Redis 6.0, `INFO errorstats` im Diagnose-Skript braucht 6.2.

## Dateien

```
07-shopware-cache/
├── config/
│   ├── framework.yaml            # Cache-Pools und Sessions in Redis
│   ├── shopware.yaml             # Redis-Connection für Warenkörbe, verzögerte Invalidierung (ab 6.6.8.0)
│   └── redis/
│       ├── redis-cache.conf      # Instanz für Caches: volatile-lru, ohne Persistenz
│       ├── redis-session.conf    # Instanz für Sessions: allkeys-lru, mit Persistenz
│       └── redis-critical.conf   # Instanz für Warenkörbe: volatile-lru, mit Persistenz
├── deploy/
│   └── deploy-cache-step.yml     # GitHub-Actions-Schritt: leeren, Sitemap, Warmup (Kapitel 7.6)
├── scripts/
│   ├── cache-hit-rate.sh         # Trefferquote einer Redis-Instanz
│   └── redis-diagnostics.sh      # Policy, Persistenz, Keys ohne TTL, OOM je Rolle
└── src/
    ├── Example/
    │   └── CacheTagExample.php   # Cache-Tags nach dem Symfony-Prinzip (Kapitel 7.5)
    ├── Resources/config/services.xml
    └── Service/
        └── ProductUpdateService.php  # Invalidierung nach direkten SQL-Updates
```

Cache-Warmup nach dem Deployment: [`06-http-cache/scripts/cache-warmup.sh`](../06-http-cache/scripts/cache-warmup.sh) (liest den Sitemap-Index samt `.xml.gz`-Teilen). `deploy/deploy-cache-step.yml` erwartet es im Shop-Repo unter `scripts/cache-warmup.sh`, ausführbar und mit dem Code ausgerollt, und prüft das, bevor es die Caches leert.

## Schnellstart

### 1. Redis-Instanzen

Eine Instanz pro Datenkategorie, weil die Eviction-Policy für die ganze Instanz gilt:

```bash
sudo cp config/redis/redis-cache.conf /etc/redis/
# redis-session.conf und redis-critical.conf analog, eigene systemd-Units/Ports
```

**Die Cache-Instanz muss `volatile-lru` (oder `noeviction`) haben.** Mit `allkeys-lru` speichert `cache.adapter.redis_tag_aware` nichts, ohne Fehlermeldung.

### 2. .env.local

```bash
REDIS_URL=redis://127.0.0.1:6379/0
REDIS_SESSION_URL=redis://127.0.0.1:6380/0
REDIS_CRITICAL_URL=redis://127.0.0.1:6381
```

### 3. Konfiguration kopieren

```bash
cp config/framework.yaml /var/www/shop/config/packages/cache.yaml
# shopware.yaml in den bestehenden shopware:-Block übernehmen
bin/console cache:clear
bin/console cart:migrate sql       # vorhandene Warenkörbe MySQL -> Redis
```

Nummernkreise nicht ohne Übernahme der Zählerstände auf Redis umstellen (siehe Kommentar in `shopware.yaml`).

### 4. Cache leeren - mit Redis anders

```bash
bin/console cache:clear        # Container, Twig - NICHT Object-/HTTP-Cache in Redis
bin/console cache:clear:all    # Object- und HTTP-Cache, verwirft gesammelte Tags (ab 6.6.8.0)
bin/console cache:clear:http   # nur HTTP-Cache (ab 6.6.10.0)
```

Vor 6.6.8.0 statt `cache:clear:all`: `bin/console cache:pool:clear cache.object cache.http`.

## Prüfen

```bash
./scripts/redis-diagnostics.sh --role cache redis://127.0.0.1:6379
./scripts/redis-diagnostics.sh --role session redis://127.0.0.1:6380
./scripts/cache-hit-rate.sh redis://127.0.0.1:6379

# Keys ansehen (SCAN statt KEYS, blockiert Redis nicht)
redis-cli -n 0 --scan | head -20
```

Tests (aus dem Repo-Root ausführen): `bats tests/Shell/redis-cache-scripts.bats tests/Shell/deploy-cache-step.bats`

## Weiterführende Ressourcen

- [Shopware: Redis](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html)
- [Shopware: Caches](https://developer.shopware.com/docs/guides/hosting/performance/caches.html)
- [Shopware: Session](https://developer.shopware.com/docs/guides/hosting/performance/session.html)
- [Symfony: Redis Cache Adapter](https://symfony.com/doc/current/cache/adapters/redis_adapter.html)
