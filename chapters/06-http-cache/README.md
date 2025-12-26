# Kapitel 6: HTTP-Caching

Code-Beispiele und Konfigurationen aus Kapitel 6 des Buches "Shop-Performance in 30 Tagen".

## Inhalt

```
06-http-cache/
├── README.md                           # Diese Datei
├── config/
│   ├── shopware.yaml                   # HTTP-Cache Konfiguration
│   └── varnish.vcl                     # Varnish VCL für Shopware 6
├── scripts/
│   ├── cache-debug.sh                  # Cache-Header analysieren
│   ├── cache-warmup.sh                 # Cache aufwärmen
│   └── cache-hit-rate.sh               # Hit-Rate aus Logs berechnen
└── src/Controller/
    ├── CacheableController.php         # Controller mit Cache-Headers
    └── EsiWidgetController.php         # ESI-Widget Beispiel
```

## Schnellstart

### 1. HTTP-Cache aktivieren

```bash
# In .env
HTTP_CACHE_ENABLED=1
APP_ENV=prod

# Cache leeren und aufwärmen
bin/console cache:clear
bin/console http:cache:warm:up
```

### 2. Cache-Status prüfen

```bash
# Cache-Header inspizieren
./scripts/cache-debug.sh https://ihr-shop.ch

# Erwartete Ausgabe:
# X-Cache: HIT
# Age: 1234
# Cache-Control: public, max-age=7200
```

### 3. Hit-Rate messen

```bash
# Aus Nginx-Logs
./scripts/cache-hit-rate.sh /var/log/nginx/access.log

# Ziel: > 80%, Exzellent: > 95%
```

## Konfiguration

### Shopware HTTP-Cache (shopware.yaml)

```yaml
shopware:
    http_cache:
        enabled: true
        default_ttl: 7200                    # 2 Stunden
        stale_while_revalidate: 14400        # 4 Stunden
        stale_if_error: 86400                # 24 Stunden
```

### Varnish (varnish.vcl)

Die mitgelieferte VCL enthält:
- Shopware 6 kompatible Konfiguration
- Statische Assets mit 7d TTL
- Grace Mode für Ausfallsicherheit
- Debug-Header für Entwicklung

## Erwartete Verbesserungen

| Metrik | Vorher | Nachher | Verbesserung |
|--------|--------|---------|--------------|
| TTFB | 800-2.000ms | 20-100ms | -90% bis -98% |
| Server-CPU | 60-90% | 10-30% | -60% bis -80% |
| Requests/s | 50-100 | 2.000-5.000 | +2.000% |

## Weiterführende Links

- [Web Almanac 2024 - Performance](https://almanac.httparchive.org/en/2024/performance)
- [web.dev - TTFB](https://web.dev/articles/ttfb)
- [web.dev - stale-while-revalidate](https://web.dev/articles/stale-while-revalidate)
- [Shopware HTTP Cache Docs](https://developer.shopware.com/docs/guides/hosting/performance/caches.html)
- [Varnish Documentation](https://varnish-cache.org/docs/)

## Lizenz

MIT - Siehe [LICENSE](../../LICENSE)
