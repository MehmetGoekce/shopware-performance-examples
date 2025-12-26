# Kapitel 12: Real User Monitoring (RUM)

Companion-Code zum Buchkapitel "Real User Monitoring (RUM)".

## Architektur

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Browser       │────▶│   RUM Endpoint  │────▶│   Analytics/    │
│   web-vitals    │     │   /api/rum      │     │   Dashboard     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │                       │                       │
        ▼                       ▼                       ▼
   LCP, INP, CLS          Log-Dateien            Grafana/GA4
   FCP, TTFB              rum.log                Alerts
```

## Dateien

### src/

| Datei | Beschreibung |
|-------|--------------|
| `rum-tracker.js` | Web-Vitals Integration für Shopware |
| `RumController.php` | Symfony Controller für RUM-Endpoint |
| `RumAlertService.php` | Alert-Service für Performance-Regression |
| `RumDashboardController.php` | Admin-Dashboard Controller |

### config/

| Datei | Beschreibung |
|-------|--------------|
| `monolog-rum.yaml` | Monolog-Konfiguration für RUM-Logging |
| `rum-alerts.yaml` | Schwellenwerte und Alert-Konfiguration |

### scripts/

| Script | Beschreibung |
|--------|--------------|
| `rum-alert-check.sh` | Cron-Script für Alert-Prüfung |
| `rum-stats.sh` | Statistik-Auswertung aus Logs |

### dashboards/

| Datei | Beschreibung |
|-------|--------------|
| `grafana-rum.json` | Grafana Dashboard Import |

### templates/

| Datei | Beschreibung |
|-------|--------------|
| `rum-dashboard.html.twig` | Einfaches Admin-Dashboard |

## Quick Start

### 1. web-vitals einbinden

```bash
# Option A: npm
npm install web-vitals

# Option B: CDN (im Template)
# Siehe src/rum-tracker.js
```

### 2. In Shopware Theme integrieren

```twig
{# views/storefront/layout/meta.html.twig #}

{% sw_extends '@Storefront/storefront/layout/meta.html.twig' %}

{% block layout_head_javascript_tracking %}
    {{ parent() }}
    {% if app.environment == 'prod' %}
        <script type="module" src="{{ asset('bundles/yourtheme/rum-tracker.js') }}"></script>
    {% endif %}
{% endblock %}
```

### 3. RUM-Endpoint einrichten

```bash
# Controller kopieren
cp src/RumController.php /var/www/shop/src/Controller/

# Monolog konfigurieren
cp config/monolog-rum.yaml /var/www/shop/config/packages/

# Cache leeren
bin/console cache:clear
```

### 4. Alerts einrichten

```bash
# Cron-Job hinzufügen
echo "*/15 * * * * www-data cd /var/www/shop && bin/console rum:check-alerts" \
    | sudo tee /etc/cron.d/rum-alerts
```

## Core Web Vitals Schwellenwerte

| Metrik | Gut | Verbesserungswürdig | Schlecht |
|--------|-----|---------------------|----------|
| **LCP** | ≤ 2500ms | 2500-4000ms | > 4000ms |
| **INP** | ≤ 200ms | 200-500ms | > 500ms |
| **CLS** | ≤ 0.1 | 0.1-0.25 | > 0.25 |

## Datenanalyse

### Log-Statistiken

```bash
# Letzte Stunde analysieren
./scripts/rum-stats.sh /var/log/shopware/rum.log 1h

# Heute analysieren
./scripts/rum-stats.sh /var/log/shopware/rum.log 24h
```

### Beispiel-Output

```
=== RUM Statistiken (letzte 1h) ===

LCP (ms):
  Samples: 1,234
  p50: 1,850
  p75: 2,340
  p90: 3,120
  Rating: GOOD (75% unter 2500ms)

INP (ms):
  Samples: 987
  p50: 95
  p75: 156
  p90: 245
  Rating: GOOD (75% unter 200ms)

CLS:
  Samples: 1,234
  p50: 0.02
  p75: 0.08
  p90: 0.15
  Rating: GOOD (75% unter 0.1)
```

## Google Analytics 4 Integration

### Events prüfen

1. GA4 → Configure → DebugView
2. Filter: Event name contains "LCP" or "INP" or "CLS"
3. Prüfen ob Events ankommen

### Custom Report erstellen

1. GA4 → Explore → Blank
2. Dimensions: Page path, Device category
3. Metrics: LCP (custom event), INP, CLS
4. Filter: metric_rating = "poor"

## Troubleshooting

### Keine RUM-Daten

```bash
# 1. Prüfen ob Script geladen wird
curl -I https://shop.de/bundles/yourtheme/rum-tracker.js

# 2. Browser Console prüfen
# "[RUM] Web Vitals Monitoring aktiv" sollte erscheinen

# 3. Network Tab prüfen
# /api/rum Requests sollten sichtbar sein
```

### Hohe Werte trotz Optimierung

```javascript
// Attribution-Build für Details
import { onLCP } from 'web-vitals/attribution';

onLCP((metric) => {
    console.log('LCP Element:', metric.attribution.element);
    console.log('Resource:', metric.attribution.url);
    console.log('TTFB:', metric.attribution.timeToFirstByte);
});
```

### Alerts kommen nicht

```bash
# 1. Cron-Job prüfen
grep rum /var/log/syslog

# 2. Manuell ausführen
bin/console rum:check-alerts -v

# 3. Slack Webhook testen
curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test"}' \
    $SLACK_WEBHOOK_URL
```

## Weiterführende Ressourcen

- [web-vitals Library](https://github.com/GoogleChrome/web-vitals)
- [Chrome UX Report](https://developer.chrome.com/docs/crux/)
- [web.dev: Web Vitals](https://web.dev/articles/vitals)
- [INP Optimization Guide](https://web.dev/articles/optimize-inp)
