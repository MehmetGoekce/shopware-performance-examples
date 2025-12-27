# Installation & Setup

Schritt-für-Schritt Anleitung zur Installation des A/B Testing Systems.

## Voraussetzungen

- Shopware 6.5+
- PHP 8.2+
- Node.js 18+
- MySQL 8.0+ oder PostgreSQL 14+
- Redis (optional, für Feature Flag Caching)

## Installation

### 1. Dateien kopieren

```bash
# Kopiere Kapitel 20 in dein Shopware-Plugin
cp -r chapters/20-ab-testing custom/plugins/PerformanceABTesting/
```

### 2. Dependencies installieren

```bash
# PHP Dependencies (falls verwendet)
composer require doctrine/dbal

# JavaScript Dependencies
cd custom/plugins/PerformanceABTesting
npm install
```

### 3. Datenbank-Migration

```bash
# Migration ausführen
bin/console database:migrate --all PerformanceABTesting

# Erwartete Ausgabe:
# ✓ Migration1234567890Experiment executed
# 4 tables created: experiment, experiment_metrics, experiment_assignments, experiment_conversions
```

### 4. Cache leeren

```bash
bin/console cache:clear
```

### 5. Services registrieren

Erstelle `custom/plugins/PerformanceABTesting/src/Resources/config/services.xml`:

```xml
<?xml version="1.0" ?>
<container xmlns="http://symfony.com/schema/dic/services"
           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="http://symfony.com/schema/dic/services http://symfony.com/schema/dic/services/services-1.0.xsd">

    <services>
        <!-- Services -->
        <service id="ShopwarePerformance\ABTesting\Service\ExperimentService">
            <argument type="service" id="experiment.repository"/>
            <argument type="service" id="request_stack"/>
            <argument type="service" id="ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector"/>
        </service>

        <service id="ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector">
            <argument type="service" id="Doctrine\DBAL\Connection"/>
        </service>

        <service id="ShopwarePerformance\ABTesting\Service\StatisticalAnalyzer"/>

        <service id="ShopwarePerformance\ABTesting\Service\FeatureFlagService">
            <argument type="service" id="cache.app"/>
            <argument>%performance_ab_testing.feature_flags%</argument>
        </service>

        <!-- Subscribers -->
        <service id="ShopwarePerformance\ABTesting\Subscriber\ExperimentSubscriber">
            <argument type="service" id="ShopwarePerformance\ABTesting\Service\ExperimentService"/>
            <argument type="service" id="ShopwarePerformance\ABTesting\Service\FeatureFlagService"/>
            <tag name="kernel.event_subscriber"/>
        </service>

        <service id="ShopwarePerformance\ABTesting\Subscriber\PerformanceTrackingSubscriber">
            <argument type="service" id="ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector"/>
            <tag name="kernel.event_subscriber"/>
        </service>

        <!-- Commands -->
        <service id="ShopwarePerformance\ABTesting\Command\ExperimentAnalyzeCommand">
            <argument type="service" id="ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector"/>
            <argument type="service" id="ShopwarePerformance\ABTesting\Service\StatisticalAnalyzer"/>
            <tag name="console.command"/>
        </service>
    </services>
</container>
```

### 6. Environment-Variablen

```bash
# Kopiere .env.example
cp .env.example .env

# Bearbeite .env mit deinen Werten
nano .env
```

Wichtige Variablen:

```env
# Datenbank
DB_HOST=localhost
DB_NAME=shopware

# Slack Webhooks (optional)
SLACK_WEBHOOK_URL=https://hooks.slack.com/...

# Performance Budgets
GLOBAL_LCP_BUDGET=2500
GLOBAL_FID_BUDGET=100
```

### 7. Plugin aktivieren

```bash
bin/console plugin:refresh
bin/console plugin:install PerformanceABTesting --activate
```

## Erstes Experiment erstellen

### Via CLI

```bash
# Experiment-Konfiguration
cat > config/experiments/checkout_test.yaml <<EOF
name: "Checkout Optimization Test"
variants:
  - control
  - optimized_ajax
traffic_split: [50, 50]
performance_budget:
  lcp: 2000
  fid: 50
EOF

# Starten
bin/console experiment:start checkout_test
```

### Via PHP

```php
use ShopwarePerformance\ABTesting\Service\ExperimentService;

$experimentService->create([
    'name' => 'My First Experiment',
    'variants' => ['control', 'variant_a'],
    'traffic_split' => [50, 50],
    'performance_budget' => [
        'lcp' => 2500,
        'fid' => 100,
    ],
], $context);
```

## Frontend-Integration

### 1. Template erweitern

```twig
{# templates/storefront/page/checkout/index.html.twig #}
{% sw_extends '@Storefront/storefront/page/checkout/index.html.twig' %}

{% block page_checkout %}
    {% if experimentVariants.checkout_test == 'optimized_ajax' %}
        {# Optimierte Variante #}
        {% include '@PerformanceABTesting/checkout/optimized.html.twig' %}
    {% else %}
        {# Standard #}
        {{ parent() }}
    {% endif %}
{% endblock %}
```

### 2. JavaScript Tracking

```javascript
// Automatisch geladen via experiment-control.html.twig
// Tracked LCP, FID, CLS automatisch
```

## API-Endpunkt für Metriken

Erstelle `src/Controller/ExperimentApiController.php`:

```php
<?php

namespace ShopwarePerformance\ABTesting\Controller;

use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

#[Route(path: '/api/experiment')]
class ExperimentApiController
{
    #[Route(path: '/metric', name: 'api.experiment.metric', methods: ['POST'])]
    public function trackMetric(Request $request): JsonResponse
    {
        $experiment = $request->request->get('experiment');
        $variant = $request->request->get('variant');
        $metric = $request->request->get('metric');
        $value = (float) $request->request->get('value');

        // Track via Service
        $this->experimentService->trackMetric(
            $experiment,
            $variant,
            $metric,
            $value,
            $context
        );

        return new JsonResponse(['success' => true]);
    }
}
```

## Analyse-Tools einrichten

### 1. NPM Scripts

```bash
# Experiment analysieren
npm run analyze checkout_test

# Metriken exportieren
npm run export checkout_test --output=results.csv

# Performance-Vergleich
npm run compare checkout_test --threshold=10
```

### 2. Shell-Tools

```bash
# Signifikanz-Test
./scripts/significance-calculator.sh \
  --control=2100,2050,2200 \
  --variant=1800,1750,1900 \
  --confidence=0.95
```

## Monitoring einrichten

### Slack-Integration

```yaml
# config/performance-budgets.yaml
alerts:
  channels:
    - type: slack
      webhook: "${SLACK_WEBHOOK_URL}"
      on:
        - budget_exceeded
        - experiment_paused
```

### Grafana Dashboard (optional)

```bash
# Prometheus Metrics exportieren
bin/console experiment:export-prometheus > /var/lib/prometheus/experiments.prom
```

## Troubleshooting

### Problem: Keine Daten in experiment_metrics Tabelle

**Lösung:**

```bash
# Prüfe ob Subscriber registriert
bin/console debug:event-dispatcher StorefrontRenderEvent

# Cache leeren
bin/console cache:clear

# Subscriber manuell testen
bin/console experiment:test-tracking
```

### Problem: Varianten werden nicht zugewiesen

**Lösung:**

```bash
# Prüfe Cookie-Einstellungen
# Cookies müssen HttpOnly=false sein für JS-Zugriff

# Prüfe Experiment-Status
SELECT * FROM experiment WHERE `key` = 'your_experiment';

# Status muss 'running' sein
```

### Problem: Migration schlägt fehl

**Lösung:**

```bash
# PostgreSQL: PERCENTILE_CONT Syntax
# Für MySQL ersetze in Migration:
PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY value)
# mit:
# Kann nicht direkt in MySQL, verwende Subquery
```

### Problem: Zu wenig Traffic

**Lösung:**

```bash
# Sample Size reduzieren (nur für Tests!)
UPDATE experiment
SET target_sample_size = 100
WHERE `key` = 'your_experiment';

# Oder Traffic-Split anpassen
UPDATE experiment
SET variants = JSON_SET(variants, '$[0].traffic_percentage', 80)
WHERE `key` = 'your_experiment';
```

## Performance-Tipps

### 1. Collector Buffer optimieren

```php
// In PerformanceVariantCollector.php
private const BUFFER_SIZE = 100; // Erhöhen für weniger DB-Writes
```

### 2. Sampling aktivieren

```yaml
# config/performance-budgets.yaml
monitoring:
  client_metrics_sample_rate: 0.1  # Nur 10% tracken
```

### 3. Datenbank-Indizes prüfen

```sql
SHOW INDEX FROM experiment_metrics;

-- Sollte Indizes haben auf:
-- (experiment_id, variant)
-- (metric)
-- (created_at)
```

## Nächste Schritte

1. Erstes Experiment starten (siehe EXAMPLES.md)
2. Performance-Budgets definieren
3. Monitoring einrichten
4. Nach 7-14 Tagen analysieren
5. Gewinner deployen

## Support

Bei Fragen oder Problemen:
- Siehe EXAMPLES.md für praktische Beispiele
- Siehe README.md für Konzepte
- Issue auf GitHub erstellen

## Changelog

- v1.0.0 (2024-01): Initial Release
  - ExperimentService
  - StatisticalAnalyzer
  - Feature Flags
  - Performance Tracking
  - CLI Tools
