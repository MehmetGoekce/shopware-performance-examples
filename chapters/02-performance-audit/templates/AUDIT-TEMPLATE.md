# Performance Audit: [Shop-Name]

**Datum:** [YYYY-MM-DD]
**Auditor:** [Name]
**Shopware Version:** [z.B. 6.5.8.0]
**PHP Version:** [z.B. 8.2.15]
**Hosting:** [Provider/Setup]

---

## 1. Executive Summary

| Dimension | Score | Status |
|-----------|-------|--------|
| Server Response (TTFB) | [X]ms | ✅/⚠️/❌ |
| Render (LCP) | [X]s | ✅/⚠️/❌ |
| Render (FCP) | [X]s | ✅/⚠️/❌ |
| Interaktivität (INP) | [X]ms | ✅/⚠️/❌ |
| Stabilität (CLS) | [X] | ✅/⚠️/❌ |
| Ressourcen | [X]MB | ✅/⚠️/❌ |
| Caching | [X]% Hit Rate | ✅/⚠️/❌ |
| Infrastruktur | [X]/10 | ✅/⚠️/❌ |

**Gesamtbewertung:** [Schlecht/Akzeptabel/Gut/Exzellent]

**Lighthouse Score (Mobile):** [X]/100

---

## 2. Getestete URLs

### Homepage (/)

| Metrik | Wert | Status |
|--------|------|--------|
| PageSpeed Score (Mobile) | [X]/100 | |
| LCP | [X]s | |
| FCP | [X]s | |
| INP | [X]ms | |
| CLS | [X] | |
| TTFB | [X]ms | |
| Total Page Weight | [X]MB | |
| Requests | [X] | |

**LCP Element:** [z.B. Hero Image, h1 Text]

**Opportunities:**
1. [Opportunity 1]
2. [Opportunity 2]
3. [Opportunity 3]

### Top-Kategorie (/kategorie/[name]/)

| Metrik | Wert | Status |
|--------|------|--------|
| PageSpeed Score (Mobile) | [X]/100 | |
| LCP | [X]s | |
| FCP | [X]s | |
| INP | [X]ms | |
| CLS | [X] | |
| TTFB | [X]ms | |
| Total Page Weight | [X]MB | |
| Requests | [X] | |

### Produktseite (/produkt/[bestseller]/)

| Metrik | Wert | Status |
|--------|------|--------|
| PageSpeed Score (Mobile) | [X]/100 | |
| LCP | [X]s | |
| FCP | [X]s | |
| INP | [X]ms | |
| CLS | [X] | |
| TTFB | [X]ms | |
| Total Page Weight | [X]MB | |
| Requests | [X] | |

### Warenkorb (/checkout/cart/)

| Metrik | Wert | Status |
|--------|------|--------|
| PageSpeed Score (Mobile) | [X]/100 | |
| LCP | [X]s | |
| INP | [X]ms | |
| TTFB | [X]ms | |

### Checkout (/checkout/confirm/)

| Metrik | Wert | Status |
|--------|------|--------|
| PageSpeed Score (Mobile) | [X]/100 | |
| LCP | [X]s | |
| INP | [X]ms | |
| TTFB | [X]ms | |

---

## 3. Infrastruktur-Check

### Server-Konfiguration

| Check | Status | Wert |
|-------|--------|------|
| PHP Version | ✅/⚠️/❌ | [Version] |
| PHP OPcache | ✅/⚠️/❌ | [aktiviert/deaktiviert] |
| JIT Compiler | ✅/⚠️/❌ | [aktiviert/deaktiviert] |
| Memory Limit | ✅/⚠️/❌ | [MB] |

### Datenbank

| Check | Status | Wert |
|-------|--------|------|
| MySQL/MariaDB Version | ✅/⚠️/❌ | [Version] |
| InnoDB Buffer Pool | ✅/⚠️/❌ | [GB] |
| Slow Query Log | ✅/⚠️/❌ | [aktiviert/deaktiviert] |

### Caching

| Check | Status | Wert |
|-------|--------|------|
| HTTP-Cache | ✅/⚠️/❌ | [aktiviert/deaktiviert] |
| Redis | ✅/⚠️/❌ | [installiert/nicht installiert] |
| Redis für Sessions | ✅/⚠️/❌ | [ja/nein] |
| Varnish | ✅/⚠️/❌ | [installiert/nicht installiert] |

### Services

| Check | Status | Wert |
|-------|--------|------|
| Elasticsearch | ✅/⚠️/❌ | [Health Status] |
| CLI Worker | ✅/⚠️/❌ | [X] Prozesse |
| Message Queue | ✅/⚠️/❌ | [X] Jobs pending |

### Plugins

| Check | Status | Wert |
|-------|--------|------|
| Aktive Plugins | ✅/⚠️/❌ | [Anzahl] |
| Ungenutzte Plugins | ⚠️ | [Anzahl] |

---

## 4. Identifizierte Probleme

### Kritisch (P1 - sofort beheben)

1. **[Problem-Titel]**
   - Beschreibung: [Details]
   - Impact: [Geschätzter Performance-Gewinn]
   - Aufwand: [Stunden]
   - Betroffene URLs: [URLs]

2. **[Problem-Titel]**
   - Beschreibung: [Details]
   - Impact: [Geschätzter Performance-Gewinn]
   - Aufwand: [Stunden]

### Hoch (P2 - diese Woche)

1. **[Problem-Titel]**
   - Beschreibung: [Details]
   - Impact: [Geschätzter Performance-Gewinn]
   - Aufwand: [Stunden]

### Mittel (P3 - diesen Monat)

1. **[Problem-Titel]**
   - Beschreibung: [Details]
   - Impact: [Geschätzter Performance-Gewinn]
   - Aufwand: [Stunden]

### Niedrig (P4 - Backlog)

1. **[Problem-Titel]**
   - Beschreibung: [Details]

---

## 5. Empfohlene Maßnahmen

| # | Maßnahme | Impact | Aufwand | Priorität |
|---|----------|--------|---------|-----------|
| 1 | [Maßnahme] | [Hoch/Mittel/Niedrig] | [X]h | P1 |
| 2 | [Maßnahme] | [Hoch/Mittel/Niedrig] | [X]h | P1 |
| 3 | [Maßnahme] | [Hoch/Mittel/Niedrig] | [X]h | P2 |
| 4 | [Maßnahme] | [Hoch/Mittel/Niedrig] | [X]h | P2 |
| 5 | [Maßnahme] | [Hoch/Mittel/Niedrig] | [X]h | P3 |

### Quick Wins (hoher Impact, niedriger Aufwand)

1. [Quick Win 1]
2. [Quick Win 2]
3. [Quick Win 3]

---

## 6. Ressourcen-Analyse

### Größte Ressourcen (Top 10)

| # | Datei | Größe | Typ |
|---|-------|-------|-----|
| 1 | [Datei] | [KB/MB] | [JS/CSS/Image] |
| 2 | [Datei] | [KB/MB] | [JS/CSS/Image] |
| 3 | [Datei] | [KB/MB] | [JS/CSS/Image] |

### JavaScript Coverage

| Datei | Größe | Unused | Unused % |
|-------|-------|--------|----------|
| [app.js] | [KB] | [KB] | [%] |
| [vendor.js] | [KB] | [KB] | [%] |

### Third-Party Scripts

| Script | Größe | Blocking | Empfehlung |
|--------|-------|----------|------------|
| [Google Analytics] | [KB] | [Ja/Nein] | [Behalten/Entfernen/Optimieren] |
| [Facebook Pixel] | [KB] | [Ja/Nein] | [Behalten/Entfernen/Optimieren] |

---

## 7. Nächste Schritte

### Diese Woche

- [ ] [Maßnahme 1]
- [ ] [Maßnahme 2]
- [ ] [Maßnahme 3]

### Dieser Monat

- [ ] [Maßnahme 4]
- [ ] [Maßnahme 5]

### Re-Audit

- [ ] Re-Audit nach Optimierung: [Datum]
- [ ] Ziel-Score: [X]/100

---

## 8. Anhang

### Verwendete Tools

- PageSpeed Insights (Mobile)
- Chrome DevTools (Lighthouse, Network, Performance)
- WebPageTest.org
- Frosh Tools Plugin
- [Weitere Tools]

### Screenshots

[Screenshots hier einfügen oder als separate Dateien referenzieren]

### Raw Data

[Links zu exportierten Lighthouse-Reports, HAR-Files, etc.]

---

*Audit erstellt mit dem Audit-Template aus "Shop-Performance in 30 Tagen"*
*https://github.com/MehmetGoekce/shopware-performance-examples*
