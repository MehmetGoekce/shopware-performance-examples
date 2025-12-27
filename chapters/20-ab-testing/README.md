# Kapitel 20: A/B Testing & Performance-Experimente

## Überblick

Dieses Kapitel zeigt, wie Sie A/B Tests durchführen und dabei den Performance-Impact präzise messen. Ein schlecht implementierter A/B Test kann die Performance um 20-30% verschlechtern - lernen Sie, wie Sie das vermeiden.

## Lernziele

- Performance-Impact von A/B Tests messen
- Feature Flags mit Performance-Budgets kombinieren
- Statistische Signifikanz für Performance-Metriken berechnen
- A/B Testing in Shopware 6 integrieren
- Experiment-Tracking ohne Performance-Overhead

## Struktur

```
20-ab-testing/
├── src/
│   ├── Service/
│   │   ├── ExperimentService.php          # Zentrale Experiment-Verwaltung
│   │   ├── PerformanceVariantCollector.php # Metriken pro Variante
│   │   ├── StatisticalAnalyzer.php        # Signifikanz-Berechnung
│   │   └── FeatureFlagService.php         # Feature Flag Integration
│   ├── Subscriber/
│   │   ├── ExperimentSubscriber.php       # Shopware Event Integration
│   │   └── PerformanceTrackingSubscriber.php # Performance Tracking
│   ├── Entity/
│   │   ├── ExperimentEntity.php           # Experiment-Datenmodell
│   │   └── ExperimentVariantEntity.php    # Varianten-Datenmodell
│   └── Migration/
│       └── Migration1234567890Experiment.php # Datenbank-Schema
├── scripts/
│   ├── analyze-experiment.js              # Statistische Auswertung
│   ├── significance-calculator.sh         # CLI Signifikanz-Test
│   ├── export-metrics.js                  # Metriken exportieren
│   └── performance-comparison.js          # Varianten vergleichen
├── config/
│   ├── experiments.yaml                   # Experiment-Definitionen
│   ├── performance-budgets.yaml           # Performance-Limits
│   └── feature-flags.yaml                 # Feature Flag Config
├── templates/
│   ├── experiment-control.html.twig       # Control Variante
│   └── experiment-variant.html.twig       # Test Variante
└── tests/
    ├── ExperimentServiceTest.php
    └── StatisticalAnalyzerTest.php
```

## Kern-Konzepte

### 1. Performance-bewusstes A/B Testing

```yaml
# config/experiments.yaml
checkout_optimization:
  name: "Checkout Performance Test"
  variants:
    - control
    - optimized_ajax
  performance_budget:
    lcp_max: 2500
    fid_max: 100
    cls_max: 0.1
  traffic_split: 50/50
  min_sample_size: 1000
```

### 2. Statistische Signifikanz

```php
$analyzer = new StatisticalAnalyzer();
$result = $analyzer->calculateSignificance(
    controlMetrics: [2100, 2050, 2200],
    variantMetrics: [1800, 1750, 1900],
    confidenceLevel: 0.95
);

if ($result->isSignificant()) {
    echo "Winner: {$result->getWinner()}";
    echo "Improvement: {$result->getImprovement()}%";
}
```

### 3. Feature Flags mit Performance-Limits

```php
$featureFlags = new FeatureFlagService();

if ($featureFlags->isEnabled('new_product_listing', $context)) {
    // Neue Variante mit Performance-Monitoring
    return $this->renderOptimizedListing();
}

return $this->renderStandardListing();
```

## Installation

### 1. Datenbank-Migration

```bash
bin/console database:migrate --all Performance
```

### 2. Cache leeren

```bash
bin/console cache:clear
```

### 3. Experiment starten

```bash
php bin/console experiment:start checkout_optimization
```

## Verwendung

### Experiment erstellen

```php
$experimentService = $container->get(ExperimentService::class);

$experiment = $experimentService->create([
    'name' => 'Product Image Lazy Loading',
    'variants' => ['control', 'lazy_native', 'lazy_intersection'],
    'traffic_split' => [33, 33, 34],
    'performance_budget' => [
        'lcp' => 2500,
        'cls' => 0.1
    ],
    'duration_days' => 14
]);
```

### Variante zuweisen

```php
// Im Subscriber
$variant = $experimentService->assignVariant(
    experimentId: 'product_image_test',
    context: $salesChannelContext
);

// Template-Variable setzen
$page->assign('experimentVariant', $variant);
```

### Performance messen

```javascript
// Im Frontend
window.experimentTracker = {
  trackLCP(entry) {
    const variant = document.body.dataset.experimentVariant;

    fetch('/api/experiment/metric', {
      method: 'POST',
      body: JSON.stringify({
        experiment: 'product_image_test',
        variant: variant,
        metric: 'lcp',
        value: entry.renderTime
      })
    });
  }
};

new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    if (entry.entryType === 'largest-contentful-paint') {
      window.experimentTracker.trackLCP(entry);
    }
  }
}).observe({ entryTypes: ['largest-contentful-paint'] });
```

### Ergebnisse analysieren

```bash
# Statistischer Vergleich
./scripts/analyze-experiment.js product_image_test

# Output:
# Experiment: Product Image Lazy Loading
# Duration: 14 days
# Samples: Control=1250, Lazy Native=1230, Lazy Intersection=1245
#
# LCP Results:
# Control:           2,450ms (baseline)
# Lazy Native:       2,100ms (-14.3%, p=0.003 ✓)
# Lazy Intersection: 1,950ms (-20.4%, p=0.001 ✓)
#
# Winner: Lazy Intersection Observer
# Recommendation: Deploy to 100% traffic
```

## Performance-Fallstricke vermeiden

### 1. Client-Side Overhead minimieren

```javascript
// SCHLECHT: Schwere A/B Test Library (50KB+)
import { Optimizely } from 'optimizely-sdk';

// GUT: Lightweight Feature Flags (2KB)
const variant = document.cookie
  .split('; ')
  .find(row => row.startsWith('exp_variant='))
  ?.split('=')[1] || 'control';
```

### 2. Server-Side Assignment

```php
// Variante im Backend zuweisen, nicht im Frontend
class ExperimentSubscriber implements EventSubscriberInterface
{
    public function onPageLoaded(PageLoadedEvent $event): void
    {
        $variant = $this->experimentService->getVariant(
            'checkout_test',
            $event->getSalesChannelContext()
        );

        // Cookie für Frontend setzen
        $event->getResponse()->headers->setCookie(
            Cookie::create('exp_variant', $variant)
                ->withHttpOnly(false) // Frontend braucht Zugriff
                ->withSameSite('strict')
        );

        $event->getPage()->assign('variant', $variant);
    }
}
```

### 3. Performance-Budget überwachen

```bash
# Automatische Alerts bei Budget-Überschreitung
./scripts/significance-calculator.sh \
  --experiment checkout_test \
  --metric lcp \
  --budget 2500 \
  --alert-webhook https://slack.com/webhook/...
```

## Best Practices

1. **Immer Control-Gruppe**: Mindestens 20% Traffic für Baseline
2. **Sample Size Calculator**: Vor Start berechnen
3. **Performance-First**: Budget-Überschreitung = Auto-Stop
4. **Statistische Geduld**: Nicht zu früh beenden (min. 7 Tage)
5. **Segmentierung**: Mobile vs Desktop separat testen
6. **Monitoring**: Real User Monitoring parallel laufen lassen

## Metriken

### Core Web Vitals pro Variante

```sql
SELECT
    variant,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lcp) as p75_lcp,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY fid) as p75_fid,
    AVG(cls) as avg_cls,
    COUNT(*) as samples
FROM experiment_metrics
WHERE experiment_id = 'checkout_test'
    AND created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
GROUP BY variant;
```

### Business Impact

```javascript
// Korrelation: Performance vs Conversion
const analysis = await analyzeExperiment({
  experiment: 'checkout_test',
  metrics: ['lcp', 'fid', 'cls'],
  businessMetrics: ['conversion_rate', 'revenue_per_session'],
  correlation: true
});

// Output:
// LCP Improvement: -15% → Conversion +2.3% (r=0.87, p<0.001)
// Revenue per Session: +€0.45 (statistically significant)
```

## Tools & Integration

### Split.io Integration

```php
// config/packages/splitio.yaml
splitio:
    api_key: '%env(SPLITIO_API_KEY)%'
    performance_tracking: true

// Service
class SplitIoExperimentService
{
    public function getVariant(string $feature, Context $context): string
    {
        $client = $this->splitFactory->client();

        return $client->getTreatment(
            $context->getCustomerId(),
            $feature,
            ['deviceType' => $this->getDeviceType()]
        );
    }
}
```

### LaunchDarkly Integration

```yaml
# config/launchdarkly.yaml
launchdarkly:
  sdk_key: '%env(LAUNCHDARKLY_SDK_KEY)%'
  features:
    optimized_search:
      variations:
        - elasticsearch_standard
        - elasticsearch_optimized
      performance_budget:
        response_time: 200ms
```

## Troubleshooting

### Problem: Varianten ungleich verteilt

```bash
# Check Distribution
./scripts/analyze-experiment.js checkout_test --check-distribution

# Expected: 50/50
# Actual: 65/35
# Reason: Cookie-based assignment + returning users
# Fix: Use hashed user ID for deterministic assignment
```

### Problem: Performance-Regression nicht erkannt

```php
// Automatisches Monitoring einbauen
class PerformanceGuardSubscriber
{
    public function onMetricCollected(MetricCollectedEvent $event): void
    {
        if ($event->getValue() > $event->getBudget()) {
            $this->experimentService->pauseExperiment(
                $event->getExperimentId(),
                reason: "Performance budget exceeded"
            );

            $this->alertService->send(
                "Experiment {$event->getExperimentId()} auto-paused"
            );
        }
    }
}
```

## Weiterführende Ressourcen

- [Bayesian A/B Testing Calculator](https://www.abtestguide.com/bayesian/)
- [Google Optimize Sunset - Alternativen](https://developers.google.com/optimize)
- [Shopware Plugin: Performance Experiments](https://github.com/shopware/experiments)
- [Statistical Power Analysis](https://www.statsig.com/calculator)

## Zusammenfassung

A/B Testing ist essenziell für datengetriebene Performance-Optimierung. Mit den Tools und Patterns aus diesem Kapitel können Sie:

- Performance-Impact präzise messen
- Statistically significant Entscheidungen treffen
- Feature Flags ohne Performance-Overhead nutzen
- Experimente sicher in Production laufen lassen

**Wichtigste Regel**: Ein A/B Test darf niemals die Performance verschlechtern. Überwachen Sie kontinuierlich und stoppen Sie automatisch bei Budget-Überschreitungen.
