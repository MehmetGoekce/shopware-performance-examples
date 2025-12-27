# Quickstart Guide - A/B Testing in 5 Minuten

## Installation (3 Befehle)

```bash
# 1. Datenbank-Migration
bin/console database:migrate --all PerformanceABTesting

# 2. Cache leeren
bin/console cache:clear

# 3. Plugin aktivieren
bin/console plugin:install PerformanceABTesting --activate
```

## Erstes Experiment (2 Minuten)

### PHP Service

```php
use ShopwarePerformance\ABTesting\Service\ExperimentService;

$experimentService->create([
    'name' => 'Checkout Optimization',
    'variants' => ['control', 'optimized'],
    'traffic_split' => [50, 50],
    'performance_budget' => [
        'lcp' => 2500,
        'fid' => 100,
    ],
], $context);

$experimentService->start('checkout_optimization', $context);
```

### Template-Integration

```twig
{# checkout/index.html.twig #}
{% if experimentVariants.checkout_optimization == 'optimized' %}
    {# Optimierte Variante #}
    <div id="ajax-checkout">...</div>
{% else %}
    {# Standard #}
    {{ parent() }}
{% endif %}
```

## Nach 14 Tagen: Analyse

```bash
bin/console experiment:analyze checkout_optimization

# Output:
# ✓ SIGNIFICANT - Variant is 18% faster (p=0.003)
# Recommendation: DEPLOY to 100%
```

## Das war's!

Mehr Details in:
- README.md - Konzepte
- EXAMPLES.md - 10 Beispiele
- INSTALLATION.md - Vollständige Anleitung
