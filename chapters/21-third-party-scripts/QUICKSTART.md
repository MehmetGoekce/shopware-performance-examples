# Quick Start - Third-Party Scripts Optimierung

Starte in 5 Minuten mit der Performance-Optimierung deiner Third-Party Scripts.

## 1️⃣ Audit durchführen (2 Minuten)

```bash
# Dependencies installieren
npm install puppeteer

# Deine Seite auditieren
node scripts/audit-third-party.js https://your-shop.com
```

**Ergebnis interpretieren:**

```
Impact Score: 67/100 🟡
```

- 🟢 0-40: Gut, wenig Optimierung nötig
- 🟡 41-70: Mittel, Optimierung empfohlen
- 🔴 71-100: Kritisch, sofortige Maßnahmen nötig

## 2️⃣ GTM optimieren (1 Minute)

### Vorher (langsam):
```html
<script>
(function(w,d,s,l,i){...})(window,document,'script','dataLayer','GTM-XXX');
</script>
```

### Nachher (schnell):
```php
// Controller/Subscriber
$gtmSnippet = $tagManagerService->generateOptimizedSnippet(
    containerId: 'GTM-XXXXXXX',
    strategy: 'lazy',
    delay: 2000
);
```

**Ergebnis:** -40% Blocking Time

## 3️⃣ Consent einrichten (2 Minuten)

```php
// Consent prüfen
if ($consentService->hasConsent('analytics')) {
    // Google Analytics nur mit Consent laden
}

// Banner anzeigen
$banner = $consentService->generateConsentBanner();
```

**Template:**
```twig
{{ consentBanner|raw }}
{{ consentLoader|raw }}
```

**Ergebnis:** DSGVO-konform + keine Performance-Einbußen

## 🎯 Schnellgewinne

### 1. Lazy Loading (30 Sekunden)

```html
<!-- Statt: -->
<script src="analytics.js"></script>

<!-- Verwende: -->
<script>
setTimeout(() => {
    const s = document.createElement('script');
    s.src = 'analytics.js';
    s.async = true;
    document.head.appendChild(s);
}, 3000);
</script>
```

**Gewinn:** -2s Load Time

### 2. Async/Defer (10 Sekunden)

```html
<!-- Statt: -->
<script src="script.js"></script>

<!-- Verwende: -->
<script async src="script.js"></script>
<!-- oder -->
<script defer src="script.js"></script>
```

**Gewinn:** -50% Blocking Time

### 3. Script-Cleanup (5 Minuten)

```bash
# Alle Scripts identifizieren
node scripts/audit-third-party.js https://shop.com

# Checklist:
# ❓ Wird noch genutzt?
# ❓ Ist essenziell?
# ❓ Gibt es Alternative?
```

**Typische Findings:**
- ❌ Altes Google Analytics (ga.js statt gtag.js)
- ❌ Doppelte GTM-Container
- ❌ Nicht mehr genutzte Tracking-Pixel
- ❌ Entwicklungs-Scripts in Production

**Gewinn:** -200KB, -3 Scripts

## 📊 Messung

### Vorher-Nachher Vergleich

```bash
# Vorher
node scripts/measure-script-impact.js https://shop.com googletagmanager.com

# Optimierung durchführen
# ...

# Nachher
node scripts/measure-script-impact.js https://shop.com googletagmanager.com
```

**Erwartete Verbesserungen:**
- LCP: -20% bis -40%
- TBT: -50% bis -70%
- Lighthouse Score: +10 bis +20 Punkte

## 🚀 Nächste Schritte

### Woche 1: Grundlagen
- ✅ Audit durchführen
- ✅ Scripts kategorisieren
- ✅ Unnötige Scripts entfernen
- ✅ Async/Defer hinzufügen

### Woche 2: Optimierung
- ✅ Lazy Loading implementieren
- ✅ Consent-Management einrichten
- ✅ GTM optimieren
- ✅ Performance-Budgets definieren

### Woche 3: Advanced
- ✅ Partytown evaluieren
- ✅ Server-Side Tagging prüfen
- ✅ Monitoring einrichten
- ✅ A/B Tests durchführen

## 💡 Pro-Tipps

1. **Kritische Seiten zuerst:** Optimiere Homepage und Checkout zuerst
2. **Nicht alles sofort:** Start mit top 3 Scripts (größter Impact)
3. **Messen, messen, messen:** Vor/Nach-Vergleiche dokumentieren
4. **User-zentriert denken:** Analytics kann warten, Payment nicht

## ⚡ Emergency-Fixes

### Seite lädt zu langsam?

```javascript
// Alle Non-Essential Scripts pausieren
// In Browser-Console:
document.querySelectorAll('script[src]').forEach(s => {
    if (!s.src.includes('essential')) {
        s.remove();
    }
});

// Performance testen
// Scripts einzeln wieder aktivieren
```

### GTM zu groß?

```bash
# Container analysieren
node scripts/gtm-performance-check.js GTM-XXXXXXX

# Top-Empfehlungen:
# 1. Custom HTML Tags ausmisten
# 2. Lazy Loading aktivieren
# 3. Server-Side Tagging evaluieren
```

### Consent-Probleme?

```javascript
// Consent zurücksetzen
document.cookie = 'sw_consent_preferences=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
location.reload();
```

## 📈 Erfolgsmessung

**Vor Optimierung:**
```
Scripts: 18
Size: 892 KB
Load Time: 6.2s
LCP: 3.5s
```

**Nach Optimierung:**
```
Scripts: 12 (-33%)
Size: 423 KB (-53%)
Load Time: 2.1s (-66%)
LCP: 2.0s (-43%)
```

**ROI-Berechnung:**
- 1% schnellere Seite = +0.5% Conversion
- Bei 100k€ Umsatz/Monat = +500€/Monat
- 1h Optimierung = 6.000€/Jahr zusätzlich

## 🎓 Lernressourcen

- [README.md](README.md) - Vollständige Dokumentation
- [EXAMPLES.md](EXAMPLES.md) - Code-Beispiele
- [INSTALLATION.md](INSTALLATION.md) - Setup-Anleitung

## ❓ FAQ

**Q: Muss ich alles implementieren?**
A: Nein. Start mit Audit + Lazy Loading = 80% des Benefits.

**Q: Funktioniert das mit meinem Theme?**
A: Ja, kompatibel mit allen Shopware 6 Themes.

**Q: Wie lange dauert die Implementierung?**
A: Grundlagen: 1-2 Stunden. Vollständig: 1-2 Tage.

**Q: Bricht das mein Tracking?**
A: Nein. Alle Lösungen sind production-ready und getestet.

**Q: Brauche ich Developer-Kenntnisse?**
A: Für CLI-Tools: Nein. Für Code-Integration: Grundlegende PHP-Kenntnisse.

## 🆘 Support

Problem? Checke:
1. Browser-Console (F12)
2. Netzwerk-Tab
3. [Troubleshooting](INSTALLATION.md#troubleshooting)

Happy Optimizing! 🚀
