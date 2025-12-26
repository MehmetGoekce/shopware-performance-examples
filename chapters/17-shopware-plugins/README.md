# Kapitel 17: Shopware 6 Plugins - Performance-Optimierung

Companion-Code zum Buchkapitel "Shopware 6 Plugins - Performance-Optimierung".

## Inhalt

```
chapters/17-shopware-plugins/
├── src/
│   ├── Service/
│   │   ├── OptimizedProductService.php    # DAL Best Practices
│   │   ├── FastIdLookupService.php        # DBAL für Performance
│   │   └── CacheAwareService.php          # Cache-Integration
│   ├── Subscriber/
│   │   ├── PerformanceAwareSubscriber.php # Loop-sicherer Subscriber
│   │   ├── ChangesetAwareSubscriber.php   # Changeset-Handling
│   │   ├── CacheTagSubscriber.php         # Custom Cache-Tags
│   │   └── SelectiveCacheInvalidation.php # Kontrollierte Invalidierung
│   ├── Indexer/
│   │   └── OptimizedEntityIndexer.php     # Performanter Custom-Indexer
│   └── MessageQueue/
│       ├── ProductImportMessage.php       # Async Message
│       └── AsyncProductHandler.php        # Message Handler
├── config/
│   ├── services.xml                       # Service-Konfiguration
│   ├── message-queue.yaml                 # Queue-Routing
│   └── supervisor.conf                    # Supervisor-Konfiguration
├── scripts/
│   ├── profile-plugin.sh                  # Plugin-Performance-Test
│   └── analyze-subscribers.php            # Subscriber-Analyse
└── tests/
    └── Performance/
        └── DalPerformanceTest.php         # Performance-Tests
```

## Kernkonzepte

### 1. DAL vs DBAL

**DAL (Data Abstraction Layer)**: Shopwares ORM-Alternative
- Verwenden für: API-Responses, komplexe Entity-Operationen
- Vermeiden für: Interne Prozesse, ID-Lookups, Batch-Updates

**DBAL (Doctrine Database Abstraction Layer)**: Plain SQL
- 10-100x schneller für einfache Operationen
- Triggert keine Events (wichtig für Indexer!)
- Empfohlen für Subscriber und Indexer

### 2. Event-Subscriber Patterns

```php
// Loop-Schutz
if ($this->isProcessing) {
    return;
}

// Nur Live-Version
if ($context->getVersionId() !== Defaults::LIVE_VERSION) {
    return;
}

// DBAL statt DAL
$this->connection->executeStatement(...);
```

### 3. Message Queue

```bash
# Admin-Worker deaktivieren (shopware.yaml)
shopware:
    admin_worker:
        enable_admin_worker: false

# CLI-Worker starten
bin/console messenger:consume async --time-limit=60 --memory-limit=256M
```

## Quick Start

### 1. Services registrieren

```xml
<!-- config/services.xml -->
<service id="App\Service\OptimizedProductService">
    <argument type="service" id="product.repository"/>
</service>

<service id="App\Subscriber\PerformanceAwareSubscriber">
    <argument type="service" id="Doctrine\DBAL\Connection"/>
    <tag name="kernel.event_subscriber"/>
</service>
```

### 2. Supervisor einrichten

```bash
sudo cp config/supervisor.conf /etc/supervisor/conf.d/shopware-messenger.conf
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start shopware-messenger:*
```

### 3. Plugin-Performance testen

```bash
chmod +x scripts/profile-plugin.sh
./scripts/profile-plugin.sh MyPlugin /produkt/test-produkt
```

## Performance-Ziele

| Metrik | Vorher | Nachher |
|--------|--------|---------|
| DAL-Query Zeit | 500ms+ | < 50ms |
| Event-Processing | 100ms/Event | < 10ms/Event |
| Indexer-Durchsatz | 100 Produkte/s | 1000+ Produkte/s |
| Message-Queue-Lag | Minuten | Sekunden |

## Anti-Patterns vermeiden

### 1. Zu viele Assoziationen

```php
// SCHLECHT
$criteria->addAssociation('categories.media.thumbnails');

// BESSER
$criteria->addAssociation('cover.media');
```

### 2. DAL in Indexern

```php
// SCHLECHT - triggert Events, Endlosschleife möglich
$this->productRepository->update([...], $context);

// BESSER - keine Events
$this->connection->executeStatement('UPDATE product SET ...');
```

### 3. Synchrone schwere Operationen

```php
// SCHLECHT - blockiert Request
$this->processAllProducts();

// BESSER - async via Message Queue
$this->messageBus->dispatch(new ProductImportMessage($ids));
```

## Profiling-Tools

### Blackfire

```bash
blackfire run bin/console dal:refresh:index
```

### Tideways

Automatisches Monitoring aller Requests mit detaillierten Traces.

## Weiterführende Links

- [Shopware DAL Dokumentation](https://developer.shopware.com/docs/concepts/framework/data-abstraction-layer.html)
- [Message Queue Guide](https://developer.shopware.com/docs/guides/hosting/infrastructure/message-queue.html)
- [Performance Tweaks](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html)
- [Blackfire Shopware Metrics](https://blog.blackfire.io/optimize-your-shopware-6-x-applications-with-new-specific-metrics.html)
