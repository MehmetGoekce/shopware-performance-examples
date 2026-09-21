# Kapitel 5: CSS und JavaScript optimieren

Code-Beispiele für Tag 5-7 der 30-Tage-Roadmap. Getestet gegen Shopware 6.6.10.6 (Dockware, prod) mit Chromium.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/coverage-analysis.js` | DevTools-Snippets: render-blockierende Dateien, JavaScript und CSS je Theme/Plugin, Einbindung der Skripte (`defer`/`async`) |
| `scripts/third-party-audit.js` | DevTools-Snippet: Ressourcen fremder Hosts, je Host zusammengefasst |

## Verwendung

Chrome DevTools (F12) → Console, den Inhalt einer Datei einfügen, Enter. `renderBlockingStatus` kennt nur Chromium (Chrome, Edge); Firefox und Safari melden es nicht.

Wie viel einer Datei ungenutzt ist, zeigt der Coverage-Tab (Drei-Punkte-Menü → More tools → Coverage, dann neu laden). Ein Skript in der Console kommt an diese Daten nicht heran.

Fremde Dateien ohne `Timing-Allow-Origin`-Header erscheinen mit «?» statt einer Grösse: Der Browser gibt ihre Grösse nicht heraus. Die Grösse steht dann im Network-Tab.

Die Werte gelten für diesen einen Aufruf in Ihrem Browser (Labordaten).

## Was ab Werk gemessen wurde

Startseite, Shopware 6.6.10.6, Demo-Daten, Chromium mobil, ohne Drosselung, beim Laden ohne Interaktion:

| Datei | übertragen | entpackt | beim Laden ungenutzt |
|-------|-----------|----------|----------------------|
| `all.css` (einzige render-blockierende Datei) | 55 KB | 391 KB | 96 % |
| JavaScript (16 Dateien, alle `defer` bzw. nachgeladen) | 100 KB | 309 KB | 65 % |

## Weiter in anderen Kapiteln

- Critical CSS, `@StorefrontBootstrap`, asynchrone Plugins, Bundle-Analyse: Kapitel 16 (`chapters/16-shopware-themes/`)
- Chat-Widget erst bei Interaktion laden: Kapitel 3 (`chapters/03-core-web-vitals/src/Resources/views/storefront/base.html.twig`)
- Tracking und Consent: Kapitel 21

## Quellen

- [Web Almanac 2024 - JavaScript](https://almanac.httparchive.org/en/2024/javascript)
- [MDN - PerformanceResourceTiming.renderBlockingStatus](https://developer.mozilla.org/en-US/docs/Web/API/PerformanceResourceTiming/renderBlockingStatus)
- [MDN - Timing-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Timing-Allow-Origin)
- [Chrome for Developers - Coverage](https://developer.chrome.com/docs/devtools/coverage)
