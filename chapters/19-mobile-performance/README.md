# Kapitel 19: Mobile Performance

Code-Beispiele für Woche 5 der 30-Tage-Roadmap. Getestet gegen Shopware 6.6.10.6 (Dockware, prod) mit Chromium und Lighthouse 13.5; die Snippets zusätzlich in WebKit.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `MobilePerformance/` | Plugin: Eingabefelder mit 16 px, Service Worker, Web App Manifest |
| `MobilePerformance/src/Resources/app/storefront/src/scss/base.scss` | `.form-control`/`.form-select` auf 1rem (Shopware 6.6: 14 px) |
| `MobilePerformance/src/Resources/sw/sw.js` | Service Worker: statische Theme-Dateien aus dem Cache, Offline-Seite, Navigation Preload |
| `MobilePerformance/src/Controller/ServiceWorkerController.php` | liefert `sw.js` unter `/sw.js` aus (Scope = ganze Storefront) |
| `MobilePerformance/src/Resources/views/storefront/base.html.twig` | registriert den Service Worker nach dem `load`-Event |
| `MobilePerformance/src/Resources/views/storefront/layout/meta.html.twig` | bindet das Manifest ein |
| `MobilePerformance/src/Resources/public/manifest.json` | Web App Manifest mit Beispiel-Icons |
| `scripts/lighthouse-mobile.sh` | Lighthouse mobil, mehrere Läufe, Median und Spanne |
| `snippets/yield-to-main.js` | Lange Aufgaben aufteilen (INP), mit Rückfall ohne `scheduler.yield` |
| `snippets/connection-hints.js` | Datensparmodus/langsame Verbindung erkennen (nur Chromium) |
| `snippets/art-direction.html` | `<picture>` mit anderem Motiv auf dem Handy, `width`/`height` je `<source>` |

## Installation des Plugins

```bash
cp -r MobilePerformance <shopware>/custom/plugins/
cd <shopware>
bin/console plugin:refresh
bin/console plugin:install --activate MobilePerformance
bin/console assets:install
bin/console theme:compile
bin/console cache:clear
```

Im Manifest Name, Farben und Icons durch die eigenen ersetzen. Liegt der Shop in einem Unterordner, `start_url` und `scope` anpassen.

## Was gemessen wurde

Test-Shop, Demo-Daten, Chromium:

| Prüfung | Ergebnis |
|---------|----------|
| Schriftgrösse der Formularfelder, ab Werk / mit Plugin | 14 px / 16 px |
| Touch-Ziele unter 24 × 24 px (390 px Breite, Start, Kategorie, Produkt, Login) | nur Skip-Link, Breadcrumb- und Textlinks, Checkbox mit Label |
| `/sw.js` | 200, `application/javascript`, `Cache-Control: no-cache, private` (Shopware ergänzt `private`, die Storefront-Route startet eine Session) |
| Service Worker | Scope `/`, aktiv, Navigation Preload an |
| Cache nach drei Seitenaufrufen | 28 Einträge, alle unter `/theme/` oder `/bundles/`, keine HTML-Seite |
| Offline: Seitenaufruf / CSS | Offline-Seite / CSS aus dem Cache |
| Manifest | keine Fehler, keine Installability-Fehler (Chromium, `Page.getAppManifest`) |
| `lighthouse-mobile.sh`, Startseite, 5 Läufe | Score 89 (89–90), LCP 2924 ms (2882–2932), TBT 196 ms (172–209), CLS 0,075 |

Die Lighthouse-Werte sind eine Simulation (Lantern) auf einer Maschine mit weiteren Containern, nur als Beispiel für die Ausgabe.

## Tests

- `tests/Shell/lighthouse-mobile.bats` – Aufruf je Lauf (Stub protokolliert die Argumente), Median/Spanne bei gerader und ungerader Laufzahl, INP nicht als Messwert; braucht `jq`.
- `tests/JavaScript/mobile-snippets.test.js` – `yieldToMain` mit und ohne `scheduler.yield`, Reihenfolge Rückmeldung → Arbeit, `prefersReducedData`.
- `tests/E2E/mobile-snippets.spec.ts` – dieselben Snippets in Chromium, Pixel 5 und iPhone 12 (WebKit).
- `tests/JavaScript/config-validation.test.js` – Manifest: Pflichtfelder, ein `purpose` je Icon, Icon-Dateien vorhanden.
- Plugin im Dockware-Shop (6.6.10.6): siehe Tabelle oben.

## Weiter in anderen Kapiteln

- Core Web Vitals messen, LCP-Bild vorladen (`imagesrcset`): Kapitel 3 und 4
- Bildgrössen je Media-Ordner, `sizes` im Listing: Kapitel 4
- Felddaten (INP) mit RUM: Kapitel 12

## Quellen

- [web.dev: Core Web Vitals Schwellenwerte](https://web.dev/articles/defining-core-web-vitals-thresholds)
- [MDN: Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)
- [MDN: scheduler.yield()](https://developer.mozilla.org/en-US/docs/Web/API/Scheduler/yield)
- [MDN: Network Information API](https://developer.mozilla.org/en-US/docs/Web/API/Network_Information_API)
- [web.dev: Maskable icons](https://web.dev/articles/maskable-icon)
