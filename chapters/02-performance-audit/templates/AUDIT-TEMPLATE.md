# Performance Audit: [Shop-Name]

**Datum:** [YYYY-MM-DD]
**Auditor:** [Name]
**Shopware Version:** [z.B. 6.6.10.6]
**PHP Version (FPM):** [z.B. 8.3.23] (`php -v` zeigt nur die CLI)
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

**Lighthouse Score (Mobile):** [X]/100 (Lighthouse-Version: [z.B. 13.5])

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

**Insights (Lighthouse 13):**
1. [Insight 1]
2. [Insight 2]
3. [Insight 3]

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

### Checkout (/checkout/register/)

Als Gast leitet `/checkout/confirm` auf `/checkout/register` um - PageSpeed Insights misst also
diese Seite. `/checkout/confirm` selbst nur in DevTools mit gefülltem Warenkorb messen.

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
| PHP OPcache (FPM, nicht `php -i`) | ✅/⚠️/❌ | [aktiviert/deaktiviert] |
| JIT Compiler | - | [an/aus] (Kapitel 9 lässt JIT begründet aus) |
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
| Elasticsearch/OpenSearch | ✅/⚠️/❌ | [Health Status oder «MySQL-Suche»] |
| CLI Worker | ✅/⚠️/❌ | [X] Prozesse |
| Message Queue | ✅/⚠️/❌ | [X] Jobs pending |

### Plugins

| Check | Status | Wert |
|-------|--------|------|
| Aktive Plugins | - | [Anzahl] (keine belegte Obergrenze; Kosten je Plugin: Kapitel 17) |
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

## 5. Empfohlene Massnahmen

| # | Massnahme | Impact | Aufwand | Priorität |
|---|----------|--------|---------|-----------|
| 1 | [Massnahme] | [Hoch/Mittel/Niedrig] | [X]h | P1 |
| 2 | [Massnahme] | [Hoch/Mittel/Niedrig] | [X]h | P1 |
| 3 | [Massnahme] | [Hoch/Mittel/Niedrig] | [X]h | P2 |
| 4 | [Massnahme] | [Hoch/Mittel/Niedrig] | [X]h | P2 |
| 5 | [Massnahme] | [Hoch/Mittel/Niedrig] | [X]h | P3 |

### Quick Wins (hoher Impact, niedriger Aufwand)

1. [Quick Win 1]
2. [Quick Win 2]
3. [Quick Win 3]

---

## 6. Ressourcen-Analyse

### Grösste Ressourcen (Top 10)

| # | Datei | Grösse | Typ |
|---|-------|-------|-----|
| 1 | [Datei] | [KB/MB] | [JS/CSS/Image] |
| 2 | [Datei] | [KB/MB] | [JS/CSS/Image] |
| 3 | [Datei] | [KB/MB] | [JS/CSS/Image] |

### JavaScript Coverage

| Datei | Grösse | Unused | Unused % |
|-------|-------|--------|----------|
| [storefront.js] | [KB] | [KB] | [%] |
| [Plugin-/Drittanbieter-Bundle] | [KB] | [KB] | [%] |

### Third-Party Scripts

| Script | Grösse | Blocking | Empfehlung |
|--------|-------|----------|------------|
| [Google Analytics] | [KB] | [Ja/Nein] | [Behalten/Entfernen/Optimieren] |
| [Facebook Pixel] | [KB] | [Ja/Nein] | [Behalten/Entfernen/Optimieren] |

---

## 7. Nächste Schritte

### Diese Woche

- [ ] [Massnahme 1]
- [ ] [Massnahme 2]
- [ ] [Massnahme 3]

### Dieser Monat

- [ ] [Massnahme 4]
- [ ] [Massnahme 5]

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
