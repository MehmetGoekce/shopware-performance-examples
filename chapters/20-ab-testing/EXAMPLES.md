# A/B Testing Beispiele - Praktische Anwendungsfälle

Dieses Dokument zeigt konkrete Beispiele für Performance-A/B-Tests in Shopware 6.

## Beispiel 1: Checkout-Optimierung

### Ziel
Checkout-Performance um 20% verbessern durch AJAX-basierte Schritte statt Full Page Reload.

### Setup

```php
// Experiment erstellen
$experimentService->create([
    'name' => 'Checkout AJAX Optimization',
    'variants' => ['control', 'ajax_checkout'],
    'traffic_split' => [50, 50],
    'performance_budget' => [
        'lcp' => 2000,
        'fid' => 50,
        'cls' => 0.05,
    ],
    'min_sample_size' => 1200,
    'duration_days' => 14,
], $context);
```

### Template-Integration

```twig
{# checkout/index.html.twig #}
{% if experimentVariants.checkout_optimization == 'ajax_checkout' %}
    {# AJAX-Variante #}
    {% include '@Storefront/storefront/page/checkout/ajax-checkout.html.twig' %}
{% else %}
    {# Standard-Variante #}
    {{ parent() }}
{% endif %}
```

### Analyse nach 14 Tagen

```bash
# CLI Analyse
bin/console experiment:analyze checkout_optimization --confidence=0.95

# Output:
# Metric: LCP
# Control: 2,450ms
# AJAX Checkout: 1,950ms (-20.4%, p=0.001) ✓ SIGNIFICANT
#
# Recommendation: DEPLOY ajax_checkout to 100%
```

### Ergebnis
- LCP: -20.4% (signifikant, p<0.001)
- FID: -35% (signifikant, p<0.001)
- CLS: -15% (signifikant, p=0.012)
- Conversion Rate: +2.8% (signifikant, p=0.004)

**Entscheidung**: Rollout zu 100%

---

## Beispiel 2: Lazy Loading Strategien

### Ziel
Beste Lazy-Loading-Strategie für Produktlistings finden.

### Setup (3 Varianten)

```yaml
# config/experiments.yaml
product_listing_lazy_loading:
  variants:
    - name: control
      description: "Eager Loading"
      traffic_percentage: 33

    - name: native_lazy
      description: "loading=lazy"
      traffic_percentage: 33

    - name: intersection_observer
      description: "IntersectionObserver + Blur Placeholder"
      traffic_percentage: 34
```

### Template

```twig
{% set lazyStrategy = experimentVariants.product_listing_lazy_loading %}

{% if lazyStrategy == 'native_lazy' %}
    <img src="{{ image.url }}" loading="lazy" alt="{{ product.name }}">

{% elseif lazyStrategy == 'intersection_observer' %}
    <img data-src="{{ image.url }}" class="lazy-load" alt="{{ product.name }}">
    <noscript><img src="{{ image.url }}" alt="{{ product.name }}"></noscript>

{% else %}
    <img src="{{ image.url }}" alt="{{ product.name }}">
{% endif %}
```

### Multi-Variant Analyse

```bash
node scripts/analyze-experiment.js product_listing_lazy_loading

# Output:
# Control:          LCP 2,850ms (baseline)
# Native Lazy:      LCP 2,450ms (-14%, p=0.023) ✓
# Intersection Obs: LCP 2,100ms (-26%, p<0.001) ✓✓
#
# Winner: Intersection Observer
```

### Ergebnis
Intersection Observer gewinnt mit 26% LCP-Verbesserung.

---

## Beispiel 3: Critical CSS Inline

### Ziel
First Contentful Paint (FCP) durch Inline Critical CSS verbessern.

### Feature Flag Setup

```php
$featureFlagService->setFlag('critical_css_inline', [
    'enabled' => true,
    'rollout_percent' => 10,  // Start mit 10%
    'performance_budget' => [
        'fcp' => 1500,
        'lcp' => 2500,
    ],
]);
```

### Template

```twig
{% if 'critical_css_inline' in featureFlags %}
    <style>
        {# Critical CSS inline #}
        {{ source('@Storefront/storefront/css/critical.css') }}
    </style>

    {# Rest async laden #}
    <link rel="preload" as="style" href="{{ asset('css/all.css') }}"
          onload="this.onload=null;this.rel='stylesheet'">
{% else %}
    <link rel="stylesheet" href="{{ asset('css/all.css') }}">
{% endif %}
```

### Gradueller Rollout

```bash
# Tag 1: 10%
bin/console feature:rollout critical_css_inline --percent=10

# Tag 3: 25% (wenn Performance OK)
bin/console feature:rollout critical_css_inline --percent=25

# Tag 7: 50%
bin/console feature:rollout critical_css_inline --percent=50

# Tag 14: 100%
bin/console feature:rollout critical_css_inline --percent=100
```

### Auto-Pause bei Budget-Überschreitung

```php
// Subscriber prüft automatisch
if ($featureFlagService->exceedsBudget('critical_css_inline', [
    'fcp' => 1800,  // Über Budget (1500)
])) {
    // Automatisch deaktiviert
    // Alert an Slack gesendet
}
```

---

## Beispiel 4: Elasticsearch Search Performance

### Ziel
Vergleich MySQL vs Elasticsearch für Produktsuche.

### Setup

```php
$experimentService->create([
    'name' => 'Search Backend Optimization',
    'variants' => ['mysql_fulltext', 'elasticsearch'],
    'traffic_split' => [50, 50],
    'performance_budget' => [
        'response_time' => 200,  // Server Response Time
        'ttfb' => 150,
    ],
], $context);
```

### Service Integration

```php
class ProductSearchService
{
    public function search(string $term, SalesChannelContext $context): SearchResult
    {
        $variant = $this->experimentService->assignVariant(
            'search_optimization',
            $context
        );

        if ($variant === 'elasticsearch') {
            return $this->elasticsearchSearch($term);
        }

        return $this->mysqlSearch($term);
    }
}
```

### Server-Side Tracking

```php
// PerformanceTrackingSubscriber misst automatisch
// Response Time, Memory, CPU pro Variante
```

### Analyse

```bash
./scripts/performance-comparison.js search_optimization --metric=response_time

# Output:
# MySQL:         Response Time 285ms
# Elasticsearch: Response Time 145ms (-49%, p<0.001) ✓
#
# Memory Usage:
# MySQL:         45MB
# Elasticsearch: 32MB (-29%)
```

---

## Beispiel 5: Mobile PWA Service Worker

### Ziel
Service Worker Impact auf Mobile Performance messen.

### Setup (nur Mobile)

```yaml
mobile_pwa_test:
  variants:
    - control
    - pwa_enabled

  targeting:
    devices:
      - mobile
      - tablet

  performance_budget:
    lcp: 2500
    fid: 100
    js_heap_size: 100  # MB
```

### Service Worker Registration

```javascript
{% if experimentVariants.mobile_pwa_test == 'pwa_enabled' %}
<script>
if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js')
        .then(reg => console.log('SW registered'))
        .catch(err => console.error('SW registration failed'));
}
</script>
{% endif %}
```

### Ergebnis

Nach 1 Woche:
- LCP: +15% (schlechter!) ❌
- FID: -20% (besser) ✓
- JS Heap: +45MB (Budget überschritten) ❌

**Entscheidung**: Experiment pausiert, Service Worker-Strategie überarbeiten.

---

## Beispiel 6: Bayesian Analysis für frühe Entscheidungen

### Wann Bayesian statt Frequentist?

- Weniger Traffic (kann früher entscheiden)
- Business-kritische Features (Risikoabschätzung wichtig)
- Kontinuierliches Monitoring (kein festes Ende)

### Beispiel

```bash
node scripts/analyze-experiment.js checkout_optimization --bayesian

# Output:
# Bayesian Analysis:
# Probability variant is best: 97.3%
# Expected loss if wrong: 12ms
# Recommendation: DEPLOY (>95% threshold)
```

### Interpretation

- 97.3% Wahrscheinlichkeit, dass Variante besser ist
- Wenn falsch, maximal 12ms Verlust
- Niedriges Risiko → Deployment empfohlen

---

## Beispiel 7: Performance Budget mit Auto-Rollback

### Setup

```yaml
# config/performance-budgets.yaml
experiments:
  new_product_slider:
    lcp: 2500
    cls: 0.1
    js_size_kb: 300

    enforcement:
      auto_rollback: true
      rollback_threshold_percent: 50  # 50% schlechter = sofort Rollback
```

### Monitoring

```php
// Automatisch überwacht durch PerformanceTrackingSubscriber

// Bei Überschreitung:
if ($metrics['lcp'] > 3750) {  // 50% über Budget
    // Automatischer Rollback
    $experimentService->pause('new_product_slider', 'Performance regression detected');

    // Alert an Team
    $slackNotifier->send("🚨 Experiment auto-rolled back: new_product_slider");
}
```

---

## Beispiel 8: Sample Size Calculator

### Vor Start: Benötigte Sample Size berechnen

```php
$analyzer = new StatisticalAnalyzer();

$requiredSamples = $analyzer->calculateRequiredSampleSize(
    expectedImprovement: 0.10,  // 10% Verbesserung erwartet
    baselineStdDev: 200,        // Aktuelle StdDev: 200ms
    power: 0.80,                // 80% Power
    alpha: 0.05                 // 95% Konfidenz
);

echo "Benötigte Sample Size pro Variante: {$requiredSamples}";
// Output: ~1570 Samples pro Variante
```

### Experiment Duration schätzen

```php
$dailyTraffic = 500;
$variants = 2;
$samplesPerVariant = 1570;

$daysNeeded = ceil(($samplesPerVariant * $variants) / $dailyTraffic);

echo "Experiment-Dauer: {$daysNeeded} Tage";
// Output: ~7 Tage
```

---

## Beispiel 9: Segmentierte Analyse

### Device-spezifische Ergebnisse

```bash
# Mobile
node scripts/export-metrics.js checkout_test \
  --device=mobile \
  --aggregate \
  --output=mobile.csv

# Desktop
node scripts/export-metrics.js checkout_test \
  --device=desktop \
  --aggregate \
  --output=desktop.csv
```

### Erkenntnis

```
Mobile:
  Control:  LCP 3,200ms
  Variant:  LCP 2,100ms (-34%) ✓✓

Desktop:
  Control:  LCP 1,800ms
  Variant:  LCP 1,850ms (+3%, not significant)
```

**Strategie**: Nur auf Mobile ausrollen, Desktop behält Standard.

---

## Beispiel 10: Conversion-Tracking

### Conversion als Performance-Metrik

```php
// Bei Bestellung
$experimentService->trackConversion(
    experimentKey: 'checkout_optimization',
    variant: $variant,
    conversionType: 'order_completed',
    conversionValue: $order->getTotalPrice()
);
```

### Analyse

```sql
SELECT
    variant,
    COUNT(*) as orders,
    AVG(conversion_value) as avg_order_value,
    AVG(time_to_conversion) as avg_time_seconds
FROM experiment_conversions
WHERE experiment_key = 'checkout_optimization'
GROUP BY variant;
```

### Korrelation: Performance vs Conversion

```
Faster LCP (-20%) → Higher Conversion Rate (+2.8%)
Faster Checkout → Higher AOV (+€3.50)
```

---

## Best Practices aus den Beispielen

1. **Immer Control-Gruppe**: Mindestens 20% Traffic für Baseline
2. **Sample Size vor Start berechnen**: Keine Zeit verschwenden
3. **Performance Budgets setzen**: Auto-Pause bei Überschreitung
4. **Device-Segmentierung**: Mobile ≠ Desktop
5. **Business-Metriken tracken**: Performance + Conversion
6. **Gradueller Rollout**: 10% → 25% → 50% → 100%
7. **Bayesian für wenig Traffic**: Frühere Entscheidungen möglich
8. **Auto-Rollback bei Regression**: Schutz vor versehentlichen Deployments

## Zusammenfassung

Diese Beispiele zeigen:
- Wie man A/B Tests für Performance durchführt
- Wann statistische Signifikanz erreicht ist
- Wie man automatisch pausiert/rollbackt
- Wie man Business-Impact misst

**Wichtigste Regel**: Nie ohne Performance-Budget testen. Ein A/B Test darf die Performance nicht verschlechtern.
