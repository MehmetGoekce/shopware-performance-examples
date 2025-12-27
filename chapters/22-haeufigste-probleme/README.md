# Kapitel 22: Die 20 häufigsten Performance-Probleme - Companion Code

Dieses Verzeichnis enthält Diagnose-Scripts und Konfigurations-Beispiele für die 20 häufigsten Performance-Probleme in Shopware 6.

## Übersicht

| Problem | Script | Lösung |
|---------|--------|--------|
| 1. Langsame DB-Queries | `diagnose-slow-queries.sh` | Index-Empfehlungen |
| 2. HTTP-Cache inaktiv | `check-http-cache.sh` | Config-Vorlage |
| 3. Große JS-Bundles | `analyze-bundles.js` | Webpack-Config |
| 4. Unoptimierte Bilder | `check-images.sh` | WebP-Konvertierung |
| 5. Fehlende Preconnects | `audit-preconnects.sh` | HTML-Vorlage |
| 6. Render-Blocking CSS | `check-render-blocking.sh` | Critical CSS |
| 7. N+1 Queries | `detect-n1-queries.php` | Criteria-Beispiele |
| 8. Session-Lock | `test-session-lock.sh` | Redis-Config |
| 9. Warenkorb-Berechnungen | `profile-cart.php` | Rule-Caching |
| 10. Zu viele Plugins | `audit-plugins.sh` | Plugin-Report |
| 11. Elasticsearch fehlt | `check-elasticsearch.sh` | ES-Config |
| 12. OPcache inaktiv | `check-opcache.php` | PHP-Config |
| 13. Debug-Modus | `check-debug-mode.sh` | Env-Fix |
| 14. Keine Gzip-Kompression | `check-compression.sh` | Nginx/Apache-Config |
| 15. Cronjobs blockieren | `analyze-cronjobs.sh` | Crontab-Vorlage |
| 16. Theme-Probleme | `audit-themes.sh` | Theme-Optimierung |
| 17. Große Log-Dateien | `check-logs.sh` | Logrotate-Config |
| 18. Kein CDN | `check-cdn.sh` | CDN-Config |
| 19. Synchrone API-Calls | `detect-sync-calls.php` | Async-Beispiele |
| 20. Keine Browser-Cache-Header | `check-cache-headers.sh` | Apache/Nginx-Config |

## Schnellstart

```bash
# Alle Diagnose-Scripts ausführen
./scripts/run-all-diagnostics.sh

# Einzelnes Problem diagnostizieren
./scripts/diagnose-slow-queries.sh

# Report generieren
./scripts/generate-report.sh > performance-report.md
```

## Voraussetzungen

- Bash 4.0+
- curl
- jq
- PHP CLI 8.0+
- MySQL Client
- Node.js 18+ (für Bundle-Analyse)

## Installation

```bash
cd chapters/22-haeufigste-probleme
chmod +x scripts/*.sh
npm install  # Für Bundle-Analyse
```

## Verzeichnisstruktur

```
22-haeufigste-probleme/
├── README.md
├── QUICKSTART.md
├── config/
│   ├── shopware-cache.yaml      # HTTP-Cache Konfiguration
│   ├── php-opcache.ini          # OPcache Konfiguration
│   ├── nginx-gzip.conf          # Gzip für Nginx
│   ├── apache-compression.conf  # Gzip für Apache
│   ├── redis-session.yaml       # Redis Session-Handler
│   ├── elasticsearch.yaml       # Elasticsearch Config
│   └── logrotate.conf           # Log-Rotation
├── scripts/
│   ├── run-all-diagnostics.sh   # Alle Diagnosen ausführen
│   ├── generate-report.sh       # Bericht generieren
│   ├── diagnose-slow-queries.sh # Problem 1
│   ├── check-http-cache.sh      # Problem 2
│   ├── analyze-bundles.js       # Problem 3
│   └── ...
└── src/
    ├── Diagnostic/
    │   └── PerformanceDiagnosticCommand.php
    └── Subscriber/
        └── CacheDebugSubscriber.php
```

## Verwendung mit Shopware

Die PHP-Klassen in `src/` können als Shopware-Plugin verwendet werden:

```bash
# Plugin installieren
cp -r src/* custom/plugins/PerformanceDiagnostic/src/
bin/console plugin:refresh
bin/console plugin:install PerformanceDiagnostic
bin/console plugin:activate PerformanceDiagnostic

# Diagnose-Command ausführen
bin/console performance:diagnose
```

## Lizenz

MIT License - Frei verwendbar für kommerzielle und private Projekte.

## Weiterführende Ressourcen

- [Kapitel 22 im Buch](../../manuscript/chapter-22-haeufigste-probleme.md)
- [Shopware Performance Documentation](https://developer.shopware.com/docs/guides/hosting/performance)
- [memotech.ch/performance-audit](https://memotech.ch/performance-audit)
