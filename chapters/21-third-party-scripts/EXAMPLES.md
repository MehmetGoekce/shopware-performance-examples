# Third-Party Scripts - Code-Beispiele

Praxisnahe Beispiele für Third-Party Script Performance-Optimierung in Shopware 6.

## Inhaltsverzeichnis

1. [Script-Audit](#1-script-audit)
2. [Google Tag Manager](#2-google-tag-manager)
3. [Consent Management](#3-consent-management)
4. [Lazy Loading](#4-lazy-loading)
5. [Partytown (Web Workers)](#5-partytown-web-workers)
6. [Server-Side Tagging](#6-server-side-tagging)

---

## 1. Script-Audit

### 1.1 Einzelnes Script analysieren

```php
use ShopwarePerformance\ThirdPartyScripts\Service\ScriptAuditService;

// Script auditieren
$audit = $scriptAuditService->auditScript(
    url: 'https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX',
    context: 'homepage',
    useCache: false  // Fresh audit
);

// Ergebnis prüfen
echo "Impact Score: {$audit['impact_score']}/100\n";
echo "Risk Level: {$audit['risk_level']}\n";
echo "Size: {$audit['size']['human']}\n";
echo "Load Time: {$audit['load_time']['ms']}ms\n";

// Performance-Hints ausgeben
foreach ($audit['performance_hints'] as $hint) {
    echo "- {$hint}\n";
}
```

**Output:**
```
Impact Score: 67/100
Risk Level: medium
Size: 127.3 KB
Load Time: 1,234ms
- Enable GZIP compression for this script
- Load time (1234ms) exceeds recommended limit (2000ms)
```

### 1.2 Mehrere Scripts parallel auditieren

```php
$scripts = [
    'https://www.googletagmanager.com/gtm.js?id=GTM-XXX',
    'https://www.google-analytics.com/analytics.js',
    'https://connect.facebook.net/en_US/fbevents.js',
    'https://static.hotjar.com/c/hotjar-123456.js',
];

$audits = $scriptAuditService->auditMultiple($scripts, 'homepage');

// Report generieren
$report = $scriptAuditService->generateReport($audits);

echo "Total Scripts: {$report['summary']['total_scripts']}\n";
echo "Total Size: {$report['summary']['total_size']['human']}\n";
echo "Average Impact: {$report['summary']['average_impact_score']}/100\n";

// Risk-Verteilung
foreach ($report['risk_distribution'] as $risk => $count) {
    echo "{$risk}: {$count}\n";
}
```

### 1.3 CLI-Tool verwenden

```bash
# Homepage auditieren
node scripts/audit-third-party.js https://your-shop.com

# JSON-Output
node scripts/audit-third-party.js https://your-shop.com --json

# In Datei speichern
node scripts/audit-third-party.js https://your-shop.com --output=audit-report.json

# Mehrere Seiten
for page in home product cart checkout; do
    node scripts/audit-third-party.js https://shop.com/$page --output=audit-$page.json
done
```

---

## 2. Google Tag Manager

### 2.1 GTM mit Lazy Loading

```php
use ShopwarePerformance\ThirdPartyScripts\Service\TagManagerService;

// Lazy Loading mit 3s Verzögerung
$gtmSnippet = $tagManagerService->generateOptimizedSnippet(
    containerId: 'GTM-XXXXXXX',
    strategy: 'lazy',
    delay: 3000
);

// In Template einbinden
$parameters['gtmSnippet'] = $gtmSnippet;
```

**Template (base.html.twig):**
```twig
<head>
    {# Data Layer Init #}
    {{ dataLayerInit|raw }}

    {# GTM Lazy Loading #}
    {{ gtmSnippet|raw }}
</head>
```

### 2.2 GTM mit User-Interaktion laden

```php
$gtmSnippet = $tagManagerService->generateOptimizedSnippet(
    containerId: 'GTM-XXXXXXX',
    strategy: 'interaction',
    triggers: ['scroll', 'mousemove', 'touchstart', 'click']
);
```

**Verhalten:**
- GTM lädt erst bei erstem User-Event
- Reduziert Initial Load Time
- Gut für Performance-Score

### 2.3 Data Layer Events

```php
// E-Commerce Event
$tagManagerService->pushEvent('purchase', [
    'transaction_id' => $order->getOrderNumber(),
    'value' => $order->getAmountTotal(),
    'currency' => $order->getCurrency()->getIsoCode(),
    'items' => $this->mapOrderItems($order),
]);

// Custom Event
$tagManagerService->pushEvent('newsletter_signup', [
    'location' => 'footer',
    'source' => 'homepage',
]);
```

### 2.4 GTM Performance-Check

```bash
# Container analysieren
node scripts/gtm-performance-check.js GTM-XXXXXXX

# Detaillierte Analyse
node scripts/gtm-performance-check.js GTM-XXXXXXX --detailed

# JSON-Output
node scripts/gtm-performance-check.js GTM-XXXXXXX --json > gtm-analysis.json
```

**Empfohlene Checks:**
- ✅ Container-Größe < 100 KB
- ✅ Anzahl Tags < 20
- ✅ GZIP aktiviert
- ✅ Cache-Headers konfiguriert

### 2.5 Server-Side Tagging

```php
// Server-Side Config generieren
$serverConfig = $tagManagerService->generateServerSideConfig(
    serverContainerUrl: 'https://sgtm.your-domain.com',
    containerId: 'GTM-XXXXXXX'
);

echo "Client Container: {$serverConfig['client_container_id']}\n";
echo "Server Container: {$serverConfig['server_container_url']}\n";
echo "Transport URL: {$serverConfig['transport_url']}\n";

// Snippet einbinden
$parameters['gtmServerSnippet'] = $serverConfig['snippet'];
```

**Vorteile Server-Side Tagging:**
- 🚀 Weniger Client-Load
- 🔒 Besserer Datenschutz
- 📊 Genaueres Tracking
- ⚡ Bessere Performance

---

## 3. Consent Management

### 3.1 Consent-Status prüfen

```php
use ShopwarePerformance\ThirdPartyScripts\Service\ConsentPerformanceService;

// Analytics-Consent prüfen
if ($consentService->hasConsent('analytics')) {
    // Google Analytics laden
    $gaScript = $consentService->loadConsentedScript('google-analytics', [
        'measurement_id' => 'G-XXXXXXXXXX',
    ]);

    $parameters['gaScript'] = $gaScript;
}

// Marketing-Consent prüfen
if ($consentService->hasConsent('marketing')) {
    // Facebook Pixel laden
    $fbScript = $consentService->loadConsentedScript('facebook-pixel', [
        'pixel_id' => 'XXXXXXXXXXXXXXX',
    ]);

    $parameters['fbScript'] = $fbScript;
}
```

### 3.2 Consent-Banner einbinden

```php
// Banner generieren
$banner = $consentService->generateConsentBanner([
    'position' => 'bottom',
    'style' => 'minimal',
    'categories' => ['functional', 'analytics', 'marketing'],
]);

$parameters['consentBanner'] = $banner;
```

**Template:**
```twig
{# Consent-Banner #}
{{ consentBanner|raw }}

{# Consent-Loader (lädt Scripts nach Consent) #}
{{ consentLoader|raw }}
```

### 3.3 Custom Consent-Script registrieren

```php
// Script registrieren
$consentService->registerScript('custom-tracking', [
    'category' => 'analytics',
    'url' => 'https://cdn.example.com/tracking.js',
    'async' => true,
    'autoload' => true,
    'onload' => "window.trackingInit();",
]);

// Laden wenn Consent vorhanden
$script = $consentService->loadConsentedScript('custom-tracking');
```

### 3.4 Consent-Wrapper in Template

```twig
{# Facebook Pixel mit Consent-Check #}
{% include '@ThirdPartyScripts/consent-wrapper.html.twig' with {
    category: 'marketing',
    scriptUrl: 'https://connect.facebook.net/en_US/fbevents.js',
    placeholderText: 'Bitte akzeptieren Sie Marketing-Cookies.',
    async: true,
    onload: "fbq('init', 'YOUR_PIXEL_ID'); fbq('track', 'PageView');"
} %}

{# YouTube Video mit Consent #}
{% include '@ThirdPartyScripts/consent-wrapper.html.twig' with {
    category: 'marketing',
    placeholderHtml: '<div class="video-placeholder">
        <p>YouTube-Video</p>
        <button onclick="openConsentSettings()">Cookies akzeptieren</button>
    </div>',
    inlineScript: 'loadYouTubePlayer("VIDEO_ID");'
} %}
```

### 3.5 Consent speichern

```php
use Symfony\Component\HttpFoundation\Response;

public function saveConsent(Request $request, ConsentPerformanceService $consentService): Response
{
    $consents = [
        'essential' => true,  // Immer true
        'functional' => $request->request->getBoolean('functional'),
        'analytics' => $request->request->getBoolean('analytics'),
        'marketing' => $request->request->getBoolean('marketing'),
    ];

    // Cookie generieren
    $cookie = $consentService->saveConsent($consents);

    // Response mit Cookie
    $response = new JsonResponse(['success' => true]);
    $response->headers->setCookie($cookie);

    // Consent-Änderung tracken
    $consentService->trackConsentChange('analytics', $consents['analytics']);

    return $response;
}
```

---

## 4. Lazy Loading

### 4.1 Script mit Verzögerung laden

```twig
{% include '@ThirdPartyScripts/script-loader.html.twig' with {
    scripts: [
        {
            url: 'https://static.hotjar.com/c/hotjar-123456.js',
            async: true,
            preconnect: true,
            domain: '//static.hotjar.com'
        }
    ],
    strategy: 'lazy',
    delay: 5000  {# 5 Sekunden #}
} %}
```

### 4.2 Script bei Interaktion laden

```twig
{% include '@ThirdPartyScripts/script-loader.html.twig' with {
    scripts: facebookPixelScripts,
    strategy: 'interaction',
    {# Lädt bei scroll, mousemove, touchstart #}
} %}
```

### 4.3 Route-spezifisches Loading

```php
use ShopwarePerformance\ThirdPartyScripts\Subscriber\ScriptLoadingSubscriber;

class MyScriptSubscriber
{
    public function __construct(
        private ScriptLoadingSubscriber $scriptLoader
    ) {}

    public function onStorefrontRender(StorefrontRenderEvent $event): void
    {
        $route = $event->getRequest()->attributes->get('_route');

        // Homepage: Nur essentials
        if ($route === 'frontend.home.page') {
            $this->scriptLoader->configureRouteScripts('frontend.home.page', [
                'gtm' => ['strategy' => 'lazy', 'delay' => 3000],
            ]);
        }

        // Checkout: Alle laden (Conversion-Tracking)
        if (str_starts_with($route, 'frontend.checkout.')) {
            $this->scriptLoader->configureRouteScripts($route, [
                'gtm' => ['strategy' => 'immediate'],
                'facebook_pixel' => ['strategy' => 'immediate'],
            ]);
        }
    }
}
```

### 4.4 JavaScript Lazy Loading

```javascript
// Generic lazy loader
function lazyLoadScript(url, delay = 0) {
    setTimeout(() => {
        const script = document.createElement('script');
        script.async = true;
        script.src = url;
        document.head.appendChild(script);
    }, delay);
}

// Mit User-Interaktion
function loadOnInteraction(url, events = ['scroll', 'mousemove', 'touchstart']) {
    let loaded = false;

    function load() {
        if (loaded) return;
        loaded = true;

        const script = document.createElement('script');
        script.async = true;
        script.src = url;
        document.head.appendChild(script);

        // Event-Listener entfernen
        events.forEach(event => {
            window.removeEventListener(event, load);
        });
    }

    events.forEach(event => {
        window.addEventListener(event, load, { once: true, passive: true });
    });
}

// Verwendung
lazyLoadScript('https://www.googletagmanager.com/gtm.js?id=GTM-XXX', 2000);
loadOnInteraction('https://connect.facebook.net/en_US/fbevents.js');
```

---

## 5. Partytown (Web Workers)

### 5.1 Partytown installieren

```bash
# Setup-Script ausführen
./scripts/partytown-setup.sh

# Manuelle Installation
npm install @builder.io/partytown
cp -r node_modules/@builder.io/partytown/lib public/~partytown/
```

### 5.2 Partytown in Base-Template

```twig
{# templates/base.html.twig #}
<head>
    {# Partytown Config #}
    <script src="/partytown-config.js"></script>

    {# Partytown Library #}
    <script src="/~partytown/partytown.js"></script>

    {# ... rest of head ... #}
</head>
```

### 5.3 Google Analytics mit Partytown

```twig
{# Standard (Main Thread) - LANGSAM #}
<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXX"></script>
<script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-XXXXXXXXXX');
</script>

{# Mit Partytown (Web Worker) - SCHNELL #}
<script type="text/partytown" async src="https://www.googletagmanager.com/gtag/js?id=G-XXX"></script>
<script type="text/partytown">
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-XXXXXXXXXX');
</script>
```

### 5.4 GTM mit Partytown

```twig
{% include '@Storefront/storefront/partytown/google-tag-manager.html.twig' with {
    containerId: 'GTM-XXXXXXX'
} %}
```

**Inhalt des Templates:**
```twig
<script type="text/partytown">
    (function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
    new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
    j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
    'https://www.googletagmanager.com/gtm.js?id='+i+dl;j.type='text/partytown';
    f.parentNode.insertBefore(j,f);
    })(window,document,'script','dataLayer','{{ containerId }}');
</script>
```

### 5.5 Facebook Pixel mit Partytown

```twig
{% include '@Storefront/storefront/partytown/facebook-pixel.html.twig' with {
    pixelId: 'XXXXXXXXXXXXXXX'
} %}
```

### 5.6 Partytown Config anpassen

```javascript
// public/partytown-config.js
partytown = {
    forward: [
        'dataLayer.push',
        'gtag',
        'fbq',
        'hj',  // Hotjar
    ],

    resolveUrl: function(url, location, type) {
        // Custom URL-Handling
        if (url.hostname.includes('your-cdn.com')) {
            return new URL('/proxy/' + url.pathname, location);
        }
        return url;
    },

    debug: false,  // Production: false
};
```

---

## 6. Server-Side Tagging

### 6.1 Server-Container Setup

1. **Google Cloud Run Deploy:**
```bash
# Tag Manager Server Container
gcloud run deploy gtm-server \
    --image gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable \
    --region europe-west1
```

2. **Custom Domain:**
```bash
# Domain mapping
gcloud run domain-mappings create \
    --service gtm-server \
    --domain sgtm.your-shop.com
```

### 6.2 Client-Side Config

```php
// Server-Side Snippet generieren
$serverSnippet = $tagManagerService->generateServerSideSnippet(
    serverUrl: 'https://sgtm.your-shop.com',
    containerId: 'GTM-XXXXXXX'
);
```

**Template:**
```twig
{# Server-Side GTM #}
{{ serverSnippet|raw }}
```

### 6.3 Server-Side Events

```php
// Event an Server-Container senden
$client = new GuzzleHttp\Client();

$response = $client->post('https://sgtm.your-shop.com/g/collect', [
    'json' => [
        'client_id' => $customerId,
        'events' => [[
            'name' => 'purchase',
            'params' => [
                'transaction_id' => $order->getOrderNumber(),
                'value' => $order->getAmountTotal(),
                'currency' => 'EUR',
                'items' => $items,
            ],
        ]],
    ],
]);
```

### 6.4 Vorteile Server-Side

**Performance:**
- ✅ -60% Client-Side JavaScript
- ✅ -40% Network Requests
- ✅ +35% Lighthouse Score

**Privacy:**
- ✅ First-Party Cookies
- ✅ Bessere GDPR-Compliance
- ✅ Ad-Blocker umgehen

**Accuracy:**
- ✅ Genaueres Tracking
- ✅ Keine Browser-Limitationen

---

## 7. Performance-Messung

### 7.1 Script-Impact messen

```bash
# Einzelnes Script
node scripts/measure-script-impact.js \
    https://your-shop.com \
    googletagmanager.com

# Mehrere Scripts
for script in googletagmanager.com facebook.net hotjar.com; do
    node scripts/measure-script-impact.js \
        https://shop.com $script \
        --json > impact-$script.json
done
```

### 7.2 Performance-Monitoring

```php
use Psr\Log\LoggerInterface;

class PerformanceMonitor
{
    public function __construct(
        private LoggerInterface $logger,
        private ScriptAuditService $auditService
    ) {}

    public function checkPerformance(): void
    {
        $scripts = $this->getAllThirdPartyScripts();
        $audits = $this->auditService->auditMultiple($scripts);
        $report = $this->auditService->generateReport($audits);

        // Performance-Regression erkennen
        $currentScore = $report['summary']['average_impact_score'];
        $previousScore = $this->getPreviousScore();

        if ($currentScore > $previousScore * 1.15) {
            $this->logger->critical('Performance regression detected', [
                'current_score' => $currentScore,
                'previous_score' => $previousScore,
                'regression' => (($currentScore / $previousScore) - 1) * 100 . '%',
            ]);

            // Alert senden
            $this->sendPerformanceAlert($report);
        }
    }
}
```

### 7.3 Automated Testing

```yaml
# .github/workflows/performance.yml
name: Third-Party Scripts Performance

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Wöchentlich

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm install

      - name: Run script audit
        run: |
          node scripts/audit-third-party.js https://shop.com --json > audit.json

      - name: Check performance budget
        run: |
          node scripts/check-budget.js audit.json

      - name: Upload report
        uses: actions/upload-artifact@v3
        with:
          name: audit-report
          path: audit.json
```

---

## Zusammenfassung

Diese Beispiele zeigen:

✅ **Script-Audit**: Performance-Impact messen
✅ **GTM-Optimierung**: Lazy Loading, Server-Side
✅ **Consent**: DSGVO-konform ohne Performance-Verlust
✅ **Lazy Loading**: Scripts verzögert laden
✅ **Partytown**: Web Workers für Third-Party Scripts
✅ **Monitoring**: Kontinuierliche Performance-Überwachung

**Ergebnis:** -40% bis -60% Performance-Impact bei Third-Party Scripts!
