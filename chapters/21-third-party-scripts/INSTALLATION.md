# Installation - Third-Party Scripts & Tag Management

Vollständige Installationsanleitung für Shopware 6.

## Voraussetzungen

- Shopware 6.5+ (getestet mit 6.5.8, 6.6.x)
- PHP 8.2+
- Node.js 18+
- Composer 2+
- npm 9+

## Installation

### 1. Code-Dateien kopieren

```bash
# Shopware-Root Verzeichnis
cd /var/www/shopware

# Plugin/Extension-Verzeichnis erstellen
mkdir -p custom/plugins/ThirdPartyScripts

# Dateien kopieren
cp -r chapters/21-third-party-scripts/src/* \
      custom/plugins/ThirdPartyScripts/src/

cp -r chapters/21-third-party-scripts/templates/* \
      custom/plugins/ThirdPartyScripts/Resources/views/
```

### 2. Services registrieren

**services.xml** erstellen:

```xml
<?xml version="1.0" ?>
<container xmlns="http://symfony.com/schema/dic/services"
           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="http://symfony.com/schema/dic/services
           http://symfony.com/schema/dic/services/services-1.0.xsd">

    <services>
        <!-- Script Audit Service -->
        <service id="ShopwarePerformance\ThirdPartyScripts\Service\ScriptAuditService">
            <argument type="service" id="http_client"/>
            <argument type="service" id="logger"/>
            <argument>%kernel.cache_dir%/script-audit</argument>
        </service>

        <!-- Tag Manager Service -->
        <service id="ShopwarePerformance\ThirdPartyScripts\Service\TagManagerService">
            <argument type="service" id="logger"/>
            <argument type="service" id="cache.adapter.filesystem"/>
            <argument>%kernel.debug%</argument>
        </service>

        <!-- Consent Performance Service -->
        <service id="ShopwarePerformance\ThirdPartyScripts\Service\ConsentPerformanceService">
            <argument type="service" id="request_stack"/>
            <argument type="service" id="logger"/>
            <argument>%consent_config%</argument>
        </service>

        <!-- Script Loading Subscriber -->
        <service id="ShopwarePerformance\ThirdPartyScripts\Subscriber\ScriptLoadingSubscriber">
            <argument type="service"
                      id="ShopwarePerformance\ThirdPartyScripts\Service\TagManagerService"/>
            <argument type="service"
                      id="ShopwarePerformance\ThirdPartyScripts\Service\ConsentPerformanceService"/>
            <argument type="service" id="logger"/>
            <argument>%env(GTM_CONTAINER_ID)%</argument>
            <argument>%env(bool:GTM_ENABLE)%</argument>
            <argument>%env(bool:CONSENT_ENABLE)%</argument>
            <tag name="kernel.event_subscriber"/>
        </service>
    </services>

    <parameters>
        <parameter key="consent_config" type="collection">
            <!-- Wird aus config/consent-config.yaml geladen -->
        </parameter>
    </parameters>
</container>
```

### 3. Environment-Konfiguration

```bash
# .env kopieren
cp chapters/21-third-party-scripts/.env.example .env.local

# Anpassen
nano .env.local
```

**.env.local:**
```bash
# Google Tag Manager
GTM_CONTAINER_ID=GTM-XXXXXXX
GTM_ENABLE=true
GTM_STRATEGY=lazy
GTM_DELAY=2000

# Consent
CONSENT_ENABLE=true

# Performance Budgets
BUDGET_MAX_TOTAL_SIZE=500
BUDGET_MAX_SCRIPT_COUNT=20
```

### 4. Config-Dateien

```bash
# Config-Verzeichnis
mkdir -p config/packages/third_party_scripts

# Configs kopieren
cp chapters/21-third-party-scripts/config/*.yaml \
   config/packages/third_party_scripts/
```

### 5. Node.js Dependencies

```bash
# package.json kopieren oder mergen
cp chapters/21-third-party-scripts/package.json .

# Dependencies installieren
npm install
```

### 6. Shopware Cache leeren

```bash
# Caches leeren
bin/console cache:clear

# Container neu bauen (falls nötig)
rm -rf var/cache/*
bin/console cache:warmup
```

### 7. Theme anpassen

**themes/YourTheme/Resources/views/storefront/base.html.twig:**

```twig
{% extends '@Storefront/storefront/base.html.twig' %}

{% block base_head %}
    {{ parent() }}

    {# Consent-Banner (wenn aktiviert) #}
    {% if consentBanner is defined %}
        {{ consentBanner|raw }}
    {% endif %}

    {# Consent-Loader #}
    {% if consentLoader is defined %}
        {{ consentLoader|raw }}
    {% endif %}

    {# Data Layer Initialization #}
    {% if dataLayerInit is defined %}
        {{ dataLayerInit|raw }}
    {% endif %}

    {# Google Tag Manager (optimiert) #}
    {% if gtmSnippet is defined %}
        {{ gtmSnippet|raw }}
    {% endif %}
{% endblock %}

{% block base_body_script %}
    {{ parent() }}

    {# Debug Info (nur mit ?debug_scripts=1) #}
    {% if scriptDebugInfo is defined %}
        {{ scriptDebugInfo|raw }}
    {% endif %}
{% endblock %}
```

### 8. Theme neu bauen

```bash
# Storefront neu bauen
bin/build-storefront.sh

# Oder manuell
npm --prefix vendor/shopware/storefront/Resources/app/storefront run build
```

## Partytown-Installation (Optional)

Für Web Worker-basiertes Script-Loading:

```bash
# Setup-Script ausführen
cd chapters/21-third-party-scripts
./scripts/partytown-setup.sh

# Oder manuell
npm install @builder.io/partytown
mkdir -p public/~partytown
cp -r node_modules/@builder.io/partytown/lib/* public/~partytown/
```

**Theme anpassen:**
```twig
{# base.html.twig #}
<head>
    {# Partytown Config #}
    <script src="/partytown-config.js"></script>

    {# Partytown Library #}
    <script src="/~partytown/partytown.js"></script>
</head>
```

**Scripts mit Partytown:**
```html
<!-- Statt: -->
<script src="analytics.js"></script>

<!-- Verwende: -->
<script type="text/partytown" src="analytics.js"></script>
```

## Verification

### 1. Services prüfen

```bash
# Service-Container prüfen
bin/console debug:container ScriptAuditService
bin/console debug:container TagManagerService
bin/console debug:container ConsentPerformanceService
```

### 2. Event-Subscriber prüfen

```bash
bin/console debug:event-subscriber ScriptLoadingSubscriber
```

### 3. Templates prüfen

```bash
# Template-Pfade
bin/console debug:twig @ThirdPartyScripts/script-loader.html.twig
```

### 4. Funktionstest

```bash
# Homepage aufrufen
curl -I https://your-shop.com

# GTM-Snippet prüfen (sollte lazy loading zeigen)
curl https://your-shop.com | grep -i "gtm"

# Consent-Cookie prüfen
curl -I https://your-shop.com | grep -i "consent"
```

### 5. Performance-Test

```bash
# Script-Audit
node scripts/audit-third-party.js https://your-shop.com

# GTM-Check
node scripts/gtm-performance-check.js GTM-XXXXXXX

# Impact-Messung
node scripts/measure-script-impact.js https://your-shop.com googletagmanager.com
```

## Troubleshooting

### Services nicht gefunden

```bash
# Cache leeren
bin/console cache:clear

# Composer dumpen
composer dump-autoload
```

### Templates nicht gefunden

```bash
# Template-Cache löschen
rm -rf var/cache/*/twig

# Theme neu bauen
bin/build-storefront.sh
```

### GTM lädt nicht

1. **Container-ID prüfen:**
```bash
echo $GTM_CONTAINER_ID
```

2. **Browser-Console prüfen:**
```javascript
console.log(window.dataLayer);
```

3. **Netzwerk-Tab prüfen:**
- Suche nach `gtm.js`
- Prüfe Ladezeit und Status

### Consent-Banner erscheint nicht

1. **Service prüfen:**
```bash
bin/console debug:container ConsentPerformanceService
```

2. **Template prüfen:**
```bash
# Suche nach consentBanner Variable
grep -r "consentBanner" themes/
```

3. **Cookie prüfen:**
```javascript
// Browser-Console
document.cookie.split(';').find(c => c.includes('consent'));
```

### Partytown funktioniert nicht

1. **Dateien prüfen:**
```bash
ls -la public/~partytown/
```

2. **Config prüfen:**
```bash
cat public/partytown-config.js
```

3. **Browser-Console prüfen:**
```
Partytown-Fehler werden als "Partytown" prefix angezeigt
```

4. **Debug-Modus aktivieren:**
```javascript
// partytown-config.js
partytown = {
    debug: true,
    logCalls: true,
};
```

## Deinstallation

```bash
# Services deaktivieren
# In services.xml alle Third-Party Services auskommentieren

# Partytown entfernen
./scripts/partytown-setup.sh --uninstall

# Node-Modules entfernen
npm uninstall puppeteer

# Dateien entfernen
rm -rf custom/plugins/ThirdPartyScripts
rm -rf config/packages/third_party_scripts

# Cache leeren
bin/console cache:clear
```

## Updates

```bash
# Code aktualisieren
cd chapters/21-third-party-scripts
git pull

# Dateien neu kopieren
cp -r src/* /var/www/shopware/custom/plugins/ThirdPartyScripts/src/

# Dependencies aktualisieren
npm install

# Cache leeren
bin/console cache:clear
bin/build-storefront.sh
```

## Performance-Monitoring

### Automatisiertes Audit (Cronjob)

```bash
# /etc/cron.d/third-party-audit
0 0 * * 0 cd /var/www/shopware && node scripts/audit-third-party.js https://shop.com --output=/var/log/audit.json
```

### Alerts einrichten

**config/packages/monolog.yaml:**
```yaml
monolog:
    handlers:
        third_party_scripts:
            type: stream
            path: "%kernel.logs_dir%/third_party_scripts.log"
            level: warning
            channels: ["third_party_scripts"]
```

## Support

Bei Problemen:

1. Log-Dateien prüfen: `var/log/prod.log`
2. Browser-Console prüfen
3. Netzwerk-Tab prüfen
4. Debug-Modus aktivieren: `APP_ENV=dev`

## Nächste Schritte

Nach erfolgreicher Installation:

1. ✅ Script-Audit durchführen
2. ✅ Performance-Budgets definieren
3. ✅ GTM-Container optimieren
4. ✅ Consent-Management testen
5. ✅ Partytown evaluieren
6. ✅ Monitoring einrichten

Siehe [EXAMPLES.md](EXAMPLES.md) für Code-Beispiele.
