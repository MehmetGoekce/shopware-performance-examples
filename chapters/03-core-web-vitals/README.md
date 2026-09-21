# Kapitel 3: Core Web Vitals messen und optimieren

Code-Beispiele für Tag 1-2 der 30-Tage-Roadmap. Getestet gegen Shopware 6.6.10.6 (Dockware, prod) mit Chromium.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/cwv-diagnostics.js` | Snippets für die DevTools-Console: LCP-Element, Layout Shifts, langsame Interaktionen (INP), grösste Ressourcen |
| `src/Resources/views/storefront/element/cms-element-image.html.twig` | Bild(er) im ersten Block der ersten CMS-Sektion mit `loading="eager"` + `fetchpriority="high"`, alle anderen bleiben lazy |
| `src/Resources/views/storefront/layout/meta.html.twig` | Preload der Inter-Datei, die das Storefront-CSS nutzt |
| `src/Resources/views/storefront/base.html.twig` | Drittanbieter-Skript (z. B. Chat) erst bei Interaktion oder nach 5 s laden |
| `lighthouserc.json` | Lighthouse-CI-Konfiguration (mobil) |
| `.github/workflows/lighthouse.yml` | GitHub-Actions-Workflow für Lighthouse CI |

Die drei Twig-Dateien sind Overrides je eines Storefront-Templates. Sie gehören in Ihr Theme oder Plugin unter denselben Pfad (`src/Resources/views/storefront/…`), danach `bin/console cache:clear`. Sie sind unabhängig voneinander.

**Zusammen mit Kapitel 16:** Das Critical-CSS-Theme aus Kapitel 16 überschreibt ebenfalls `layout/meta.html.twig` und dort denselben Block `layout_head_stylesheet`, im eingeschalteten Zweig ohne `parent()`. Im selben Theme ersetzt die eine Datei die andere; liegt dieses Override in einem Plugin, fällt der Font-Preload weg, sobald `criticalCss` an ist. Wer beides will, führt die Blöcke in einer Datei zusammen und setzt den Preload vor die Bedingung.

## Verwendung

### DevTools-Diagnose

Chrome DevTools (F12) → Console, eine Funktion aus `scripts/cwv-diagnostics.js` samt Aufruf einfügen. Die Werte gelten für diesen einen Aufruf in Ihrem Browser (Labordaten). Was Google bewertet, ist das 75. Perzentil echter Besuche über 28 Tage.

### Lighthouse CI

```bash
npm install -g @lhci/cli@0.15.1
lhci autorun --config=lighthouserc.json --collect.url=https://ihr-shop.ch/
```

`@lhci/cli` 0.15.1 bringt Lighthouse 12.6.1 mit, nicht die Version der aktuellen DevTools. Die Konfiguration misst mobil und bricht ab, wenn das LCP-Bild lazy geladen wird (`lcp-lazy-loaded`) oder CLS über 0,1 liegt; LCP und TBT sind nur Warnungen, weil die simulierte Drosselung von Lighthouse sie stark streuen lässt. Berichte landen lokal (`lhci autorun`) in `./lhci-reports`; der GitHub-Workflow legt sie als Actions-Artefakt `lighthouse-results` ab (`uploadArtifacts: true`). Beides ist nicht öffentlich.

## Core Web Vitals Zielwerte

| Metrik | Gut | Verbesserungswürdig | Schlecht |
|--------|-----|---------------------|----------|
| LCP | ≤ 2,5 s | > 2,5 s bis 4,0 s | > 4,0 s |
| INP | ≤ 200 ms | > 200 ms bis 500 ms | > 500 ms |
| CLS | ≤ 0,1 | > 0,1 bis 0,25 | > 0,25 |

Bewertet wird jeweils das 75. Perzentil der Seitenaufrufe.

## Statistiken (Web Almanac 2024)

- 73 % mobil / 83 % Desktop: Das LCP-Element ist ein Bild
- 59 % mobil / 74 % Desktop: gutes LCP
- 16 % der mobilen Seiten mit Bild als LCP laden dieses Bild lazy

## Quellen

- [Web Almanac 2024 - Performance](https://almanac.httparchive.org/en/2024/performance)
- [LCP (web.dev)](https://web.dev/articles/lcp)
- [INP (web.dev)](https://web.dev/articles/inp)
- [CLS (web.dev)](https://web.dev/articles/cls)
