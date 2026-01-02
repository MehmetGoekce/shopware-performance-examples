# Kompatibilität

## Getestete Versionen

| Komponente | Versionen | Status |
|------------|-----------|--------|
| **Shopware** | 6.5.x, 6.6.x | Getestet |
| **PHP** | 8.2, 8.3, 8.4 | Getestet |
| **MySQL** | 8.0+ | Getestet |
| **MariaDB** | 10.11+ | Getestet |
| **Redis** | 7.0+ | Kapitel 10, 11 |
| **Elasticsearch** | 8.x | Kapitel 18 |
| **Node.js** | 20 LTS | Build-Tools |

## Kapitel-spezifische Anforderungen

| Kapitel | Zusaetzliche Abhaengigkeiten |
|---------|------------------------------|
| 10 - Redis Sentinel | Redis 7.0+ mit Sentinel |
| 11 - CDN Integration | Bunny.net oder Cloudflare Account |
| 18 - Elasticsearch | ES 8.x oder OpenSearch 2.x |
| 19 - Mobile Performance | Lighthouse CLI, Chrome |
| 24 - Ausblick | Cloudflare Workers (optional) |

## Bekannte Shopware 6.6 API-Aenderungen

Die folgenden API-Aenderungen wurden in Shopware 6.6 eingefuehrt und sind im Code dokumentiert:

| Aenderung | Betroffene Dateien | Loesung |
|-----------|-------------------|---------|
| `CacheTagCollector` -> `CacheTagCollection` | CacheTagSubscriber.php | Gefixt |
| `Entity::getStock()` Type-Hint | CachedProductService.php | `ProductEntity` verwenden |
| `Context::getSalesChannelId()` | CachedProductService.php | `SalesChannelContext` nutzen |
| `StorefrontRenderEvent::setParameters()` | ScriptLoadingSubscriber.php | Deprecated, Alternative dokumentiert |

Siehe `phpstan-shopware.neon` fuer die vollstaendige Liste der ignorierten Fehler.

## Test-Matrix

```
PHP 8.2 + Shopware 6.5.x  -> Vollstaendig getestet
PHP 8.3 + Shopware 6.5.x  -> Vollstaendig getestet
PHP 8.3 + Shopware 6.6.x  -> Vollstaendig getestet
PHP 8.4 + Shopware 6.6.x  -> Getestet (minor Type-Hints)
```

## Aktualisierung

Letzte Aktualisierung: Januar 2026

Bei Fragen zur Kompatibilitaet: [GitHub Issues](https://github.com/MehmetGoekce/shopware-performance-examples/issues)
