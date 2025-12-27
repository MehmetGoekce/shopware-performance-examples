# Kapitel 21: Third-Party Scripts & Tag Management

Performance-Optimierung für Third-Party Scripts in Shopware 6.

## Übersicht

Dieses Kapitel behandelt die Performance-Optimierung von Third-Party Scripts:

- **Script-Audit**: Analyse von Third-Party Scripts auf Performance-Impact
- **Google Tag Manager**: GTM-Container optimieren und lazy loading
- **Consent Management**: Cookie-Consent ohne Performance-Einbußen
- **Script-Loading**: Async, Defer, Lazy Loading, Web Workers (Partytown)
- **Monitoring**: Performance-Impact messen und tracken

## 🎯 Lernziele

Nach diesem Kapitel können Sie:

1. Third-Party Scripts auf Performance-Impact analysieren
2. Google Tag Manager performance-optimiert implementieren
3. Consent Management ohne Performance-Verlust einrichten
4. Script-Loading-Strategien (lazy, interaction-based) umsetzen
5. Partytown für Web Worker-basiertes Script-Loading nutzen
6. Performance-Budgets für Third-Party Scripts definieren

## 📁 Struktur

```
chapters/21-third-party-scripts/
├── src/
│   ├── Service/
│   │   ├── ScriptAuditService.php          # Script-Analyse
│   │   ├── TagManagerService.php           # GTM-Optimierung
│   │   └── ConsentPerformanceService.php   # Consent-Management
│   └── Subscriber/
│       └── ScriptLoadingSubscriber.php     # Script-Injection
│
├── scripts/
│   ├── audit-third-party.js                # Script-Audit Tool
│   ├── gtm-performance-check.js            # GTM-Analyse
│   ├── partytown-setup.sh                  # Partytown Installation
│   └── measure-script-impact.js            # Impact-Messung
│
├── config/
│   ├── allowed-scripts.yaml                # Script-Whitelist
│   ├── gtm-triggers.yaml                   # GTM-Trigger Config
│   └── consent-config.yaml                 # Consent-Config
│
└── templates/
    ├── script-loader.html.twig             # Script-Loader
    └── consent-wrapper.html.twig           # Consent-Wrapper
```

## 🚀 Quick Start

### 1. Script-Audit durchführen

Analysiere alle Third-Party Scripts auf deiner Seite:

```bash
cd scripts/
npm install puppeteer
node audit-third-party.js https://your-shop.com
```

**Beispiel-Output:**
```
═══════════════════════════════════════════════════════
  THIRD-PARTY SCRIPTS AUDIT REPORT
═══════════════════════════════════════════════════════

📊 SUMMARY
  Total Scripts:     15
  Total Size:        423.5 KB
  Avg Load Time:     1,234 ms
  Unique Domains:    8

⚡ PERFORMANCE
  First Paint:       1,245 ms
  FCP:               1,567 ms
  Load Complete:     3,421 ms

📈 SCORES
  Impact Score:      62/100 🟡
  Performance Score: 71/100 🟡
  Overall Score:     67/100 🟡

💡 RECOMMENDATIONS
  1. 🔴 Use async or defer for non-critical scripts
  2. 🟡 Enable compression for all scripts
  3. 🔴 Implement lazy loading for non-critical scripts
```

### 2. GTM Performance-Check

Analysiere deinen GTM-Container:

```bash
node gtm-performance-check.js GTM-XXXXXXX
```

**Beispiel-Output:**
```
═══════════════════════════════════════════════════════
  GTM CONTAINER PERFORMANCE REPORT
═══════════════════════════════════════════════════════

📦 CONTAINER: GTM-XXXXXXX
  Size:              127.3 KB
  GZIP Enabled:      ✅
  Cache Control:     public, max-age=900

📊 CONTENT ANALYSIS
  Estimated Tags:    23
  Estimated Triggers: 18
  Custom HTML/JS:    ⚠️  Yes
  External Domains:  12

📈 SCORE
  Performance Score: 58/100 🟡

💡 RECOMMENDATIONS
  1. 🔴 Reduce number of tags (23)
  2. 🔴 Implement lazy loading
  3. 🟡 Review custom HTML/JS tags
  4. 🔴 Consider server-side tagging
```

### 3. Script-Impact messen

Miss den Performance-Impact einzelner Scripts:

```bash
node measure-script-impact.js https://your-shop.com googletagmanager.com
```

**Beispiel-Output:**
```
═══════════════════════════════════════════════════════
  SCRIPT IMPACT ANALYSIS
═══════════════════════════════════════════════════════

⚡ CORE WEB VITALS IMPACT
  LCP                2,345ms → 1,987ms  ✅ -15%
  FCP                1,234ms → 1,098ms  ✅ -11%
  TBT                  423ms →   312ms  ✅ -26%

📈 OVERALL IMPACT SCORE
  🟡 MEDIUM: 42% performance impact

💡 RECOMMENDATION: Consider lazy loading (defer until user interaction)
```

### 4. Partytown Setup (Web Worker)

Installiere Partytown für performanteres Script-Loading:

```bash
./scripts/partytown-setup.sh
```

Nach Installation Scripts in Web Worker laden:

```html
<!-- Statt normal -->
<script src="https://www.googletagmanager.com/gtm.js?id=GTM-XXX"></script>

<!-- Mit Partytown (Web Worker) -->
<script type="text/partytown" src="https://www.googletagmanager.com/gtm.js?id=GTM-XXX"></script>
```

## 💻 Code-Beispiele

### PHP: Script-Audit Service

```php
use ShopwarePerformance\ThirdPartyScripts\Service\ScriptAuditService;

// Script auditieren
$audit = $scriptAuditService->auditScript(
    url: 'https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX',
    context: 'homepage'
);

// Impact-Score prüfen
if ($audit['impact_score'] > 75) {
    // Kritischer Impact - Script blockieren oder optimieren
    $this->logger->critical('High impact script detected', [
        'url' => $audit['url'],
        'impact_score' => $audit['impact_score'],
    ]);
}

// Report generieren
$report = $scriptAuditService->generateReport([
    'gtm' => $gtmAudit,
    'facebook' => $fbAudit,
    'hotjar' => $hjAudit,
]);
```

### PHP: Tag Manager Service

```php
use ShopwarePerformance\ThirdPartyScripts\Service\TagManagerService;

// GTM Lazy-Loading Snippet
$gtmSnippet = $tagManagerService->generateOptimizedSnippet(
    containerId: 'GTM-XXXXXXX',
    strategy: 'lazy',      // lazy, immediate, interaction
    delay: 2000            // 2 Sekunden Verzögerung
);

// GTM Container-Performance analysieren
$analysis = $tagManagerService->analyzeContainerPerformance('GTM-XXXXXXX');

if ($analysis['performance_score'] < 50) {
    // Container zu groß/langsam
    foreach ($analysis['recommendations'] as $rec) {
        echo $rec['title'] . "\n";
    }
}

// Server-Side Tagging Config
$serverSideConfig = $tagManagerService->generateServerSideConfig(
    serverContainerUrl: 'https://sgtm.your-domain.com',
    containerId: 'GTM-XXXXXXX'
);
```

### PHP: Consent Performance Service

```php
use ShopwarePerformance\ThirdPartyScripts\Service\ConsentPerformanceService;

// Consent prüfen
if ($consentService->hasConsent('analytics')) {
    // Analytics-Script laden
    $gaScript = $consentService->loadConsentedScript('google-analytics', [
        'measurement_id' => 'G-XXXXXXXXXX',
    ]);
}

// Consent-Banner generieren
$banner = $consentService->generateConsentBanner([
    'position' => 'bottom',
    'style' => 'minimal',
    'categories' => ['functional', 'analytics', 'marketing'],
]);

// Consent-Loader (JavaScript)
$loader = $consentService->generateConsentLoader();
```

### Twig: Script-Loader Template

```twig
{# Lazy Loading mit 3s Verzögerung #}
{% include '@ThirdPartyScripts/script-loader.html.twig' with {
    scripts: [
        {
            url: 'https://www.googletagmanager.com/gtm.js?id=GTM-XXX',
            async: true,
            preconnect: true,
            domain: '//www.googletagmanager.com'
        }
    ],
    strategy: 'lazy',
    delay: 3000
} %}

{# Laden bei User-Interaktion #}
{% include '@ThirdPartyScripts/script-loader.html.twig' with {
    scripts: facebookPixelScripts,
    strategy: 'interaction'
} %}

{# Consent-basiertes Laden #}
{% include '@ThirdPartyScripts/script-loader.html.twig' with {
    scripts: analyticsScripts,
    strategy: 'consent',
    consentCategory: 'analytics'
} %}
```

### Twig: Consent-Wrapper

```twig
{# Script nur mit Marketing-Consent laden #}
{% include '@ThirdPartyScripts/consent-wrapper.html.twig' with {
    category: 'marketing',
    scriptUrl: 'https://connect.facebook.net/en_US/fbevents.js',
    placeholderText: 'Bitte akzeptieren Sie Marketing-Cookies um Facebook Pixel zu laden.',
    async: true,
    onload: "fbq('init', 'YOUR_PIXEL_ID'); fbq('track', 'PageView');"
} %}
```

### JavaScript: Impact-Messung

```javascript
// Script-Impact messen
const { measureScriptImpact } = require('./measure-script-impact');

const impact = await measureScriptImpact(
    'https://your-shop.com',
    'googletagmanager.com'
);

console.log('Impact Score:', impact.impact.score);
console.log('LCP Improvement:', impact.impact.webVitals.lcp.relative + '%');
```

## 🔧 Konfiguration

### allowed-scripts.yaml

Performance-Budgets für erlaubte Scripts definieren:

```yaml
allowed_scripts:
  google_tag_manager:
    name: "Google Tag Manager"
    category: analytics
    consent_required: true

    budgets:
      max_size: 100  # KB
      max_load_time: 2000  # ms
      max_blocking_time: 100  # ms

    loading:
      strategy: lazy
      delay: 2000
      async: true

    optimization:
      partytown_compatible: true
      server_side_available: true
```

### gtm-triggers.yaml

Optimierte GTM-Trigger mit Debouncing:

```yaml
scroll_triggers:
  scroll_50:
    type: scroll_depth
    depth: 50

    optimization:
      throttle: 500  # ms - Max 1 Event pro 500ms
      passive: true  # Passive Event Listener
      fire_once: true
```

### consent-config.yaml

Consent-Management Konfiguration:

```yaml
categories:
  analytics:
    name: "Analyse & Performance"
    required: false
    default_enabled: false

scripts:
  google_analytics:
    category: analytics
    loading:
      strategy: lazy
      delay: 3000
```

## 📊 Performance-Metriken

### Vorher (ohne Optimierung)

```
Total Scripts:     18
Total Size:        892 KB
Total Load Time:   6,234 ms
Total Blocking Time: 1,234 ms
LCP:               3,456 ms
```

### Nachher (mit Optimierung)

```
Total Scripts:     12 (-33%)
Total Size:        423 KB (-53%)
Total Load Time:   2,145 ms (-66%)
Total Blocking Time: 312 ms (-75%)
LCP:               1,987 ms (-42%)
```

**Verbesserungen:**
- ✅ 33% weniger Scripts
- ✅ 53% weniger Datenmenge
- ✅ 66% schnellere Ladezeit
- ✅ 75% weniger Blocking Time
- ✅ 42% besserer LCP

## 🎯 Best Practices

### 1. Script-Audit regelmäßig durchführen

```bash
# Wöchentliches Audit
0 0 * * 0 /path/to/audit-third-party.js https://shop.com --output=/var/log/audit.json
```

### 2. Performance-Budgets definieren

```yaml
global_budgets:
  max_total_size: 500  # KB
  max_script_count: 20
  max_blocking_time: 300  # ms
```

### 3. Lazy Loading für Non-Critical Scripts

```javascript
// GTM mit 3s Verzögerung laden
setTimeout(() => {
    loadGTM('GTM-XXXXXXX');
}, 3000);

// Oder bei User-Interaktion
['scroll', 'mousemove', 'touchstart'].forEach(event => {
    window.addEventListener(event, () => loadGTM('GTM-XXX'), { once: true });
});
```

### 4. Partytown für blockierende Scripts

```html
<!-- Analytics in Web Worker -->
<script type="text/partytown" src="https://www.googletagmanager.com/gtag/js"></script>
<script type="text/partytown">
    gtag('js', new Date());
    gtag('config', 'G-XXXXXXXXXX');
</script>
```

### 5. Server-Side Tagging verwenden

```yaml
google_tag_manager:
  optimization:
    server_side_available: true
    server_container_url: 'https://sgtm.your-domain.com'
```

## ⚠️ Häufige Fehler

### 1. ❌ Zu viele Third-Party Scripts

**Problem:**
```
Total Scripts: 35
Total Size: 1.2 MB
Impact Score: 92/100 🔴
```

**Lösung:**
- Audit durchführen
- Unnötige Scripts entfernen
- Scripts konsolidieren

### 2. ❌ Blocking Scripts

**Problem:**
```html
<script src="analytics.js"></script>  <!-- Blockiert Rendering! -->
```

**Lösung:**
```html
<script async src="analytics.js"></script>
<!-- Oder -->
<script defer src="analytics.js"></script>
<!-- Oder Lazy Loading -->
```

### 3. ❌ Kein Consent-Management

**Problem:**
- DSGVO-Verstoß
- Alle Scripts laden sofort

**Lösung:**
```php
if ($consentService->hasConsent('analytics')) {
    $this->loadAnalyticsScript();
}
```

### 4. ❌ GTM-Container zu groß

**Problem:**
```
Container Size: 247 KB
Estimated Tags: 42
Performance Score: 23/100 🔴
```

**Lösung:**
- Tags auditieren und entfernen
- Server-Side Tagging nutzen
- Lazy Loading implementieren

## 📚 Weiterführende Ressourcen

- [Partytown Documentation](https://partytown.builder.io/)
- [Google Tag Manager Best Practices](https://developers.google.com/tag-platform/tag-manager/best-practices)
- [Web.dev: Third-Party Scripts](https://web.dev/third-party-scripts/)
- [Chrome DevTools: Coverage Tool](https://developer.chrome.com/docs/devtools/coverage/)

## 🧪 Testing

```bash
# Scripts testen
npm test

# Performance-Impact messen
node measure-script-impact.js https://shop.com googletagmanager.com

# GTM Container analysieren
node gtm-performance-check.js GTM-XXXXXXX --detailed
```

## 📝 Autor

Mehmet Gökçe - Shop-Performance in 30 Tagen

## 📄 Lizenz

Proprietary - Nur für Buchkäufer
