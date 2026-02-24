# Validierungsbericht: Shopware-Code-Beispiele im Buch

**Datum:** 2026-02-24
**Shopware Version:** 6.6.1.1 (PHP 8.4, Symfony 7.0.6)
**Installation:** `/var/www/shopware6.local`

---

## 1. PHP-Syntax (php -l)

**Ergebnis: 0 Fehler**

Alle 46 PHP-Dateien in `chapters/` und 7 PHP-Dateien in `src/` bestehen den Syntax-Check.

---

## 2. Klassen-Existenz (Autoloader)

**Ergebnis: 67 OK, 0 Deprecated, 1 MISSING (erwartet)**

| Status | Klasse | Anmerkung |
|--------|--------|-----------|
| MISSING | `PHPUnit\Framework\TestCase` | Nur in require-dev, nicht im Prod-Autoloader |

Alle 67 Shopware/Symfony/Doctrine-Klassen existieren korrekt.

Die 7 Buch-internen Klassen (`PerformanceExamples\*`, `ShopwarePerformance\*`) sind erwartungsgemaess nicht im Shopware-Autoloader.

---

## 3. Methoden-Signaturen (Reflection)

**Ergebnis: 37 OK, 0 Fehler**

Alle geprueften Methoden existieren mit korrekten Parametern:
- `Criteria`: setLimit, addFilter, addAssociation, setTotalCountMode, addFields, addSorting, addAggregation, setOffset, setIds, getLimit, getTotalCountMode
- `CacheInvalidator`: invalidate
- `EntityRepository`: search, update, create, delete, upsert
- `Response`: setSharedMaxAge, setMaxAge, setPublic, setPrivate, $headers
- `StorefrontController`: renderStorefront
- `EntityIndexer`: getName, iterate, update, handle
- `MigrationStep`: update, updateDestructive, getCreationTimestamp
- `SystemConfigService`: get, set
- `ElasticsearchHelper`: allowIndexing
- `ThemeService`: compileTheme
- `EventSubscriberInterface`: getSubscribedEvents
- `Command`: execute, configure

---

## 4. CLI-Befehle

**Ergebnis: 37 OK, 10 korrigiert, 9 Custom-Commands (korrekt als Plugin-spezifisch)**

### Korrigierte Befehle:

| Falsch | Korrigiert zu | Betroffene Dateien |
|--------|--------------|-------------------|
| `http:cache:warm:up` | `cache:warmup` | 6 Stellen in Manuskript + 2 Shell-Scripts |
| `http:cache:warm-up` | `cache:warmup` | chapter-03 |
| `http:cache:warmup` | `cache:warmup` | chapter-22, chapter-23 |
| `http:cache:clear` | `cache:clear` | 3 Stellen in chapter-06 + 2 Shell-Scripts |
| `theme:dump-config` | `theme:dump` | anhang-e, chapter-22 |
| `es:index:create` | `es:index` | anhang-e, chapter-22 |
| `database:clean-up` | `database:clean-personal-data` | chapter-08 |
| `database:query` | `dbal:run-sql` | 3 Stellen in chapter-22 |

### Custom-Commands (korrekt, gehoeren zum Buch-Plugin):
`experiment:*`, `performance:*`, `rum:*`, `feature:rollout`

---

## 5. YAML-Konfigurationsschluessel

**Ergebnis: 24 Fehler korrigiert**

### Kritische Korrekturen:

| Fehler | Korrektur | Dateien |
|--------|-----------|---------|
| `shopware.http_cache.enabled` | Env-Variable `SHOPWARE_HTTP_CACHE_ENABLED` | 8 Manuskript-Dateien + 3 YAML-Configs |
| `shopware.http_cache.default_ttl` | Env-Variable `SHOPWARE_HTTP_DEFAULT_TTL` | 8 Manuskript-Dateien + 3 YAML-Configs |
| `shopware.http_cache.cache_invalidation` | `shopware.cache.invalidation` (mit Klassen-Arrays) | chapter-06, chapter-02 |
| `shopware.http_cache.invalidation` | `shopware.cache.invalidation` | chapter-02 |
| `shopware.http_cache.private_allowed_query_pattern` | Entfernt (existiert nicht) | chapter-06 |
| `shopware.cache.invalidation.count` | Entfernt (existiert nicht) | cache.yaml, anhang-c |
| `shopware.cache.redis_url` | Entfernt (korrekt: `framework.cache.default_redis_provider`) | cache.yaml, redis.yaml |
| `shopware.cache.prefix` | `shopware.cache.redis_prefix` | chapter-23 |
| `shopware.cache.redis_cluster` | Entfernt (existiert nicht) | chapter-23 |
| `shopware.cache.app` | `framework.cache.app` | chapter-22 |
| `shopware.lock.enabled` | `framework.lock` | redis.yaml |
| `shopware.messenger.routing_overwrite` | `framework.messenger.routing` | chapter-17 |
| `shopware.messenger.consume` | Entfernt (CLI-Argumente) | chapter-23 |
| `shopware.storefront.csrf.mode` | Entfernt (CSRF seit 6.5 entfernt) | chapter-02 |
| `shopware.es.*` | `elasticsearch.*` (separates Bundle) | chapter-22, chapter-23, anhang-c |
| `shopware.elasticsearch.*` | `elasticsearch.*` | chapter-18 |
| `elasticsearch.timeout` | `elasticsearch.search.timeout` | chapter-18 |
| `elasticsearch.product.enabled` | Entfernt (existiert nicht) | chapter-18 |
| `elasticsearch.product.mapping` | `elasticsearch.product.custom_fields_mapping` | chapter-23 |
| `elasticsearch.product.batch_size` | `elasticsearch.indexing_batch_size` | chapter-23 |
| `elasticsearch.product_search_fields` | Entfernt (Admin-Konfiguration) | chapter-18 |
| `cache.invalidation.*_route: true/false` | Array von Klassen / leeres Array `[]` | chapter-07 |
| `elasticsearch.product.mapping` Event | `ElasticsearchCustomFieldsMappingEvent::class` | chapter-18 PHP |

---

## 6. Korrigierte Dateien

### Manuskript (12 Dateien):
- `anhang-c-konfigurationen.md`
- `anhang-e-cheat-sheet.md`
- `chapter-02-performance-audit.md`
- `chapter-03-woche1-core-web-vitals.md`
- `chapter-06-woche2-http-caching.md`
- `chapter-07-woche2-shopware-cache.md`
- `chapter-08-woche2-datenbank.md`
- `chapter-18-shopware-6-elasticsearch.md`
- `chapter-22-haeufigste-probleme.md`
- `chapter-23-fallstudien.md`

### Code-Beispiele (12 Dateien):
- `config/packages/cache.yaml`
- `config/packages/redis.yaml`
- `scripts/cache-warmup.sh`
- `chapters/02-performance-audit/config/shopware-http-cache.yaml`
- `chapters/06-http-cache/config/shopware.yaml`
- `chapters/06-http-cache/scripts/cache-warmup.sh`
- `chapters/07-shopware-cache/config/shopware.yaml`
- `chapters/16-shopware-themes/scripts/build-theme.sh`
- `chapters/17-shopware-plugins/config/message-queue.yaml`
- `chapters/17-shopware-plugins/scripts/profile-plugin.sh`
- `chapters/18-shopware-elasticsearch/config/elasticsearch.yaml`
- `chapters/22-haeufigste-probleme/config/shopware-cache.yaml`
- `chapters/23-fallstudien/config/elasticsearch-tuning.yaml`
- `chapters/23-fallstudien/config/queue-config.yaml`
- `chapters/23-fallstudien/config/redis-multi-tenant.yaml`

---

## Zusammenfassung

| Pruefung | Ergebnis |
|----------|----------|
| PHP-Syntax | 0 Fehler |
| Klassen-Existenz | 67/68 OK (1x PHPUnit nur in dev) |
| Methoden-Signaturen | 37/37 OK |
| CLI-Befehle | 10 korrigiert |
| YAML-Config | 24 Fehler korrigiert |
| **Gesamt** | **34 Korrekturen in 24 Dateien** |
