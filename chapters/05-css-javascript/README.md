# Kapitel 5: CSS und JavaScript optimieren

Code-Beispiele und Tools für Tag 5-7 der 30-Tage-Roadmap.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/coverage-analysis.js` | DevTools-Snippet für CSS/JS Coverage |
| `scripts/third-party-audit.js` | Third-Party Scripts analysieren |
| `scripts/generate-critical.js` | Critical CSS generieren (Node.js) |
| `templates/meta-defer.html.twig` | JavaScript mit defer laden |
| `templates/critical-css.html.twig` | Critical CSS inline Template |
| `config/webpack-optimization.js` | Webpack-Konfiguration für Optimierung |

## Verwendung

### Coverage-Analyse (DevTools)

```javascript
// Chrome DevTools Console (F12)
// Kopieren Sie den Inhalt von scripts/coverage-analysis.js
```

### Critical CSS generieren

```bash
# Abhängigkeiten installieren
npm install critical --save-dev

# Critical CSS generieren
node scripts/generate-critical.js https://ihr-shop.ch
```

### Webpack Bundle Analyzer

```bash
npm install webpack-bundle-analyzer --save-dev
npm run build -- --analyze
```

## Lighthouse-Metriken

| Metrik | Ziel | Gewichtung |
|--------|------|------------|
| TBT | < 200ms | 30% |
| TTI | < 3.8s | - |
| Speed Index | < 3.4s | 10% |

## Quick Wins Checkliste

### CSS
- [ ] Coverage-Analyse durchgeführt (Ziel: <40% ungenutzt)
- [ ] Critical CSS extrahiert und inline
- [ ] Rest-CSS async geladen
- [ ] `font-display: swap` für Web Fonts

### JavaScript
- [ ] Bundle-Analyse durchgeführt
- [ ] Alle Scripts mit `defer` oder `async`
- [ ] Code Splitting für nicht-kritische Features
- [ ] Tree Shaking aktiviert

### Third-Party
- [ ] Alle externen Scripts aufgelistet
- [ ] GTM delayed loading (2s nach load)
- [ ] Chat-Widget lazy (on-demand)
- [ ] Unnötige Scripts entfernt

## Statistiken (Web Almanac 2024)

- Mediane Mobile-Seite: **558 KB JavaScript**
- Davon **44% ungenutzt** während Page Load
- TBT macht **30%** des Lighthouse Scores aus

## Quellen

- [Web Almanac 2024 - JavaScript](https://almanac.httparchive.org/en/2024/javascript)
- [web.dev - Total Blocking Time](https://web.dev/articles/tbt)
- [web.dev - Render-Blocking Resources](https://web.dev/articles/render-blocking-resources)
- [web.dev - Extract Critical CSS](https://web.dev/articles/extract-critical-css)
