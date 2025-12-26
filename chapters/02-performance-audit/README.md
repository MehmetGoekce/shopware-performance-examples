# Kapitel 2: Performance-Audit

Code-Beispiele und Tools für das Performance-Audit-Kapitel.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/audit.sh` | Komplettes Audit-Script für Shopware 6 |
| `scripts/analyze-images.sh` | Bildgrößen-Analyse |
| `config/shopware-http-cache.yaml` | HTTP-Cache Konfigurationsbeispiel |
| `config/shopware-worker.conf` | Supervisor-Konfiguration für CLI Worker |
| `config/mysql-slow-query.cnf` | MySQL Slow Query Log Konfiguration |
| `templates/AUDIT-TEMPLATE.md` | Audit-Dokumentations-Template |

## Verwendung

### Komplettes Audit durchführen

```bash
# Vom Shopware-Root-Verzeichnis ausführen
./chapters/02-performance-audit/scripts/audit.sh
```

Das Script prüft:
- Shopware- und PHP-Version
- Aktive Plugins
- HTTP-Cache-Status
- PHP OPcache
- MySQL Buffer Pool
- Redis-Status
- Message Queue Worker

### Bildgrößen analysieren

```bash
# Große Bilder finden (> 500KB)
./chapters/02-performance-audit/scripts/analyze-images.sh /var/www/shop/public/media
```

### CLI Worker einrichten

```bash
# Supervisor-Konfiguration kopieren
sudo cp config/shopware-worker.conf /etc/supervisor/conf.d/

# Supervisor neu laden
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start shopware-worker:*
```

## Die 7 Performance-Dimensionen

| Dimension | Metrik | Zielwert | Tool |
|-----------|--------|----------|------|
| Server Response | TTFB | < 800ms | PageSpeed Insights |
| Render | LCP | < 2.5s | Lighthouse |
| Render | FCP | < 1.8s | Lighthouse |
| Interaktivität | INP | < 200ms | Chrome UX Report |
| Interaktivität | TBT | < 200ms | Lighthouse |
| Stabilität | CLS | < 0.1 | Lighthouse |
| Ressourcen | Page Weight | < 1.5MB | Network Panel |

## Performance-Killer Checkliste

Die häufigsten Probleme in Shopware 6:

- [ ] Unoptimierte Bilder (> 500KB, kein WebP)
- [ ] JavaScript-Bloat (> 500KB JS)
- [ ] Zu viele Plugins (> 30 aktiv)
- [ ] HTTP-Cache deaktiviert
- [ ] Datenbankprobleme (> 100 Queries/Request)
- [ ] Synchrone Third-Party-Calls
- [ ] Admin Worker statt CLI Worker

## Quellen

- [TTFB Thresholds (web.dev)](https://web.dev/articles/ttfb)
- [Core Web Vitals (web.dev)](https://web.dev/articles/vitals)
- [INP Metric (web.dev)](https://web.dev/articles/inp)
- [Frosh Tools (GitHub)](https://github.com/FriendsOfShopware/FroshTools)
