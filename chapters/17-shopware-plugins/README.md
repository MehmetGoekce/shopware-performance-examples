# Kapitel 17: Shopware 6 Plugins - Performance-Optimierung

Companion-Code zum Buchkapitel "Shopware 6 Plugins - Performance-Optimierung".

Getestet mit Shopware 6.6.10.6 (Dockware, Demo-Daten): jede Klasse als Plugin
installiert und gegen den laufenden Shop ausgeführt. Versionsgrenzen stehen im
Kopfkommentar der jeweiligen Datei.

## Inhalt

```
chapters/17-shopware-plugins/
├── src/
│   ├── Service/
│   │   ├── OptimizedProductService.php    # DAL: nur laden, was angezeigt wird
│   │   ├── FastIdLookupService.php        # DBAL für ID-Lookups
│   │   └── CustomTagInvalidator.php       # eigenes Cache-Tag invalidieren
│   ├── Subscriber/
│   │   ├── PerformanceAwareSubscriber.php # Guard-Clauses, DBAL-Write
│   │   ├── ChangesetAwareSubscriber.php   # Changeset nur bei Bedarf
│   │   └── CacheTagSubscriber.php         # eigenes Cache-Tag setzen
│   ├── Indexer/
│   │   └── OptimizedEntityIndexer.php     # eigener Entity-Indexer
│   └── MessageQueue/
│       ├── ProductImportMessage.php       # Nachricht für low_priority
│       └── AsyncProductHandler.php        # Handler im Worker
├── config/
│   ├── services.xml                       # Service-Definitionen
│   └── message-queue.yaml                 # Admin-Worker aus, Routing
└── scripts/
    ├── profile-plugin.sh                  # Seite mit/ohne Plugin messen
    └── analyze-subscribers.sh             # Listener je Namespace
```

Tests: `tests/Shell/plugin-scripts.bats` (beide Skripte, Stubs für
`bin/console` und `curl`).

## Einbinden

Die Klassen stehen im Namespace `App\`. Als Plugin: Dateien unter `src/`
übernehmen, `App\` durch den Plugin-Namespace ersetzen und
`config/services.xml` nach `src/Resources/config/services.xml` legen.

`config/message-queue.yaml` gehört nach `config/packages/`. Die Worker selbst
(`messenger:consume async low_priority` und `scheduled-task:run`) stehen in
Anhang C: `chapters/anhang-c-konfigurationen/config/supervisor-shopware.conf`.

## Was die Beispiele zeigen

| Datei | Kernpunkt |
|---|---|
| `OptimizedProductService` | Staffelpreise mit Sortierung begrenzen, sonst ist "der erste" beliebig; `searchIds()` hydriert nichts |
| `FastIdLookupService` | `LIMIT :limit` braucht `ParameterType::INTEGER`, sonst `LIMIT '1000'` → MySQL-Fehler 1064 |
| `PerformanceAwareSubscriber` | `name` kommt als `product_translation.written`, nicht als `product.written`; `custom_fields` liegt in `product_translation` |
| `ChangesetAwareSubscriber` | `hasChanged('price')` ist bei JSON-Spalten auch ohne Änderung `true` - Inhalte vergleichen |
| `ProductImportMessage` | `LowPriorityMessageInterface` statt `framework.messenger.routing` (sonst doppelt verarbeitet) |
| `CacheTagSubscriber` + `CustomTagInvalidator` | `AddCacheTagEvent` (ab 6.6.6.0); Setzer und Invalidierer bauen das Tag mit derselben Methode |
| `OptimizedEntityIndexer` | Varianten über die Datenbank auf das Hauptprodukt abbilden, nicht über den Payload |

Den Schreibweg per DBAL samt Cache-Invalidierung zeigt Kapitel 7
(`chapters/07-shopware-cache/src/Service/ProductUpdateService.php`).

## Plugin-Kosten messen

```bash
# Als Benutzer des Webservers, NICHT auf dem Live-Shop:
sudo -u www-data SHOPWARE_ROOT=/var/www/html \
    ./scripts/profile-plugin.sh MyPlugin /Mein-Produkt/SW10001
```

Misst A-B-A (mit, ohne, wieder mit), je Phase nach Cache-Leeren und
Aufwärmen, jeden Aufruf am HTTP-Cache vorbei. Ist der Unterschied nicht
grösser als die Abweichung der beiden Mit-Phasen, meldet das Skript ihn als
nicht belastbar.

```bash
./scripts/analyze-subscribers.sh               # Listener je Namespace
./scripts/analyze-subscribers.sh 'Swag\PayPal' # Listener eines Plugins
```

Die Zahl der Listener ist eine Orientierung, keine Messung.

## Weiterführende Links

- [Shopware DAL](https://developer.shopware.com/docs/concepts/framework/data-abstraction-layer.html)
- [Message Queue](https://developer.shopware.com/docs/guides/hosting/infrastructure/message-queue.html)
- [Performance Tweaks](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html)
- [Eigener Indexer](https://developer.shopware.com/docs/guides/plugins/plugins/framework/data-handling/add-data-indexer.html)
