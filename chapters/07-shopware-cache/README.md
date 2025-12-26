# Kapitel 7: Shopwares Application Cache meistern

Konfigurationen und Scripts für Application Cache mit Redis.

## Dateien

```
07-shopware-cache/
├── config/
│   ├── framework.yaml      # Redis Cache-Konfiguration
│   ├── redis.conf          # Redis Server-Optimierung
│   └── shopware.yaml       # Cache-Invalidierung
├── scripts/
│   ├── cache-warmup.php    # Cache-Warming-Script
│   ├── cache-hit-rate.sh   # Cache-Hit-Rate messen
│   └── redis-diagnostics.sh # Redis Troubleshooting
└── src/Service/
    └── ProductUpdateService.php  # Programmatische Invalidierung
```

## Schnellstart

### 1. Redis installieren

```bash
sudo apt update && sudo apt install redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
redis-cli ping  # PONG
```

### 2. .env konfigurieren

```bash
REDIS_URL=redis://localhost:6379
REDIS_SESSION_URL=redis://localhost:6379/2
```

### 3. Konfiguration kopieren

```bash
cp config/framework.yaml /var/www/shop/config/packages/
cp config/shopware.yaml /var/www/shop/config/packages/
```

### 4. Cache leeren

```bash
bin/console cache:clear
```

## Zielwerte

| Metrik | Zielwert |
|--------|----------|
| Cache-Hit-Rate | >90% |
| Cache-Lookup Zeit | <1ms |
| Session-Zugriff | <1ms |

## Verwendung

### Cache-Hit-Rate prüfen

```bash
./scripts/cache-hit-rate.sh
```

### Cache aufwärmen nach Deployment

```bash
php scripts/cache-warmup.php https://ihr-shop.ch
```

### Redis-Diagnose

```bash
./scripts/redis-diagnostics.sh
```

## Weiterführende Ressourcen

- [Shopware Redis Docs](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html)
- [Redis Benchmarks](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/benchmarks/)
- [Symfony Cache Component](https://symfony.com/doc/current/cache.html)
