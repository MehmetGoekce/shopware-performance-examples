# Kapitel 3: Core Web Vitals messen und optimieren

Code-Beispiele und Tools für Tag 1-2 der 30-Tage-Roadmap.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/cwv-diagnostics.js` | JavaScript-Snippets für DevTools-Console |
| `templates/lcp-priority.html.twig` | Twig-Template für LCP-Bildpriorisierung |
| `templates/font-preload.html.twig` | Font-Preloading Template |
| `templates/third-party-lazy.html.twig` | Lazy Loading für Third-Party Scripts |
| `.github/workflows/lighthouse.yml` | GitHub Actions für automatisierte Tests |
| `lighthouserc.json` | Lighthouse CI Konfiguration |

## Verwendung

### DevTools-Diagnose

Öffnen Sie Chrome DevTools (F12) → Console und fügen Sie die Snippets ein:

```javascript
// LCP-Element finden
// Kopieren Sie den Inhalt von scripts/cwv-diagnostics.js
```

### Lighthouse CI

```bash
# Lokal testen
npm install -g @lhci/cli
lhci autorun --config=lighthouserc.json

# Oder via GitHub Actions (automatisch bei Push)
```

## Core Web Vitals Zielwerte

| Metrik | Gut | Verbesserungswürdig | Schlecht |
|--------|-----|---------------------|----------|
| LCP | < 2,5s | 2,5-4,0s | > 4,0s |
| INP | < 200ms | 200-500ms | > 500ms |
| CLS | < 0,1 | 0,1-0,25 | > 0,25 |

## Quick Wins Checkliste

- [ ] `fetchpriority="high"` für LCP-Bilder
- [ ] Alle Bilder haben `width` und `height`
- [ ] `font-display: swap` für Web Fonts
- [ ] Third-Party Scripts verzögert laden
- [ ] Google Fonts mit Preconnect oder selbst gehostet

## Statistiken (Web Almanac 2024)

- 73% mobile / 83% desktop: LCP-Element ist ein Bild
- 59% mobile / 72% desktop: Haben gutes LCP
- 16% der Seiten laden LCP-Bild lazy (Anti-Pattern!)

## Quellen

- [Web Almanac 2024 - Performance](https://almanac.httparchive.org/en/2024/performance)
- [LCP (web.dev)](https://web.dev/articles/lcp)
- [INP (web.dev)](https://web.dev/articles/inp)
- [CLS (web.dev)](https://web.dev/articles/cls)
