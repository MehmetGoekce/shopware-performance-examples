# Kapitel 16: Shopware 6 Themes — Companion Code

Companion-Code zum Buch **«Shop-Performance in 30 Tagen»**.

Getestet gegen **Shopware 6.6.10.6** (Dockware, PHP 8.3, Node.js 20 im
Container, Node.js 22 auf dem Host für `critical`).

- **Gefahren und gemessen:** das Theme-Plugin `PerformanceTheme/` (byte-gleich
  im Testshop installiert, mit `bin/build-storefront.sh` gebaut, per
  `theme:change` zugewiesen), beide Skripte, `config/lighthouse-budget.json`
  (mit `@lhci/cli` 0.15.1 `assert` gegen den Testshop).
- **Nicht gefahren:** die GitHub-Action `treosh/lighthouse-ci-action` selbst
  und Shopware 6.7. Wo sich 6.7 unterscheidet, steht es an der Datei.

## Das Wichtigste zuerst

**Die Storefront liefert Theme-CSS und -JavaScript aus `public/theme/<prefix>/`
aus, nicht aus `public/bundles/storefront/`.** `theme:compile` legt dort
`css/all.css` und je Theme/Plugin `js/<technical-name>/` ab. Wer unter
`public/bundles/storefront/js/` misst, misst nichts — dort liegt bis 6.7.10
kein Storefront-JavaScript. Ab 6.7.11 lädt jede Seite zusätzlich das
Vite-Laufzeitmodul `public/bundles/storefront/storefront/shopware/shopware.js`;
`analyze-bundle.sh` zählt es mit, wenn es da ist.

**Die Storefront baut mit Webpack, auch in Shopware 6.7.** Die Umstellung auf
Vite in 6.7 betrifft die Administration. Ab 6.7.11 baut Vite in der Storefront
zusätzlich ein Laufzeitmodul und die neuen Komponenten — Theme- und Plugin-JS
läuft weiter über Webpack.

## Inhalt

### `PerformanceTheme/` — installierbares Theme-Plugin

| Datei | Zweck |
|---|---|
| `src/Resources/theme.json` | `overrides.scss` **vor** `@Storefront`, eigenes JS, Schalter `criticalCss` |
| `src/Resources/app/storefront/src/scss/overrides.scss` | nur Bootstrap-Variablen |
| `src/Resources/app/storefront/src/scss/base.scss` | eigene Styles nach `@Storefront`, ohne Bootstrap-Re-Import |
| `src/Resources/app/storefront/src/main.js` | Plugin asynchron registrieren |
| `src/Resources/app/storefront/src/plugin/async-slider/async-slider.plugin.js` | lädt tiny-slider erst bei Interaktion |
| `src/Resources/views/storefront/layout/meta.html.twig` | Critical CSS inline, `all.css` asynchron (übernimmt ab 6.7.11 die Komponenten-Styles des Originals) |
| `src/Resources/views/storefront/layout/header/logo.html.twig` | `sw_extends`: nur das `<img>` ersetzen |

### `scripts/`

- **`analyze-bundle.sh`** — vermisst `public/theme/<prefix>/`: Einstieg (jede
  Seite) getrennt von Chunks (nur bei Bedarf), roh und gzip, optional mit
  Budget. Mit `--stats` baut es die Storefront mit Webpack-Statistik und
  schreibt je Webpack-Compiler einen `webpack-bundle-analyzer`-Report.
- **`extract-critical-css.sh`** — Critical CSS einer Seite mit `critical` 9
  als `views/storefront/critical/critical.css.twig`.

### `config/theme-style-storefront-bootstrap.json`

`style`-Array für `@StorefrontBootstrap` statt `@Storefront` (mit dem von der
Doku verlangten `@Plugins`). In `theme.json` einsetzen, dann `theme:compile`.

### `config/lighthouse-budget.json`

Budget im Lighthouse-Format (ein **Array**). Für `treosh/lighthouse-ci-action`
(`budgetPath`) oder `lhci assert --budgetsFile`.

### `src/ThemePerformanceAnalyzer.php`

PHP-Gegenstück zu `analyze-bundle.sh` für eigene Commands oder Reports:
`analyzeThemeDirectory()` mit denselben Regeln, Grenzwerte gzip wie im
Lighthouse-Budget.

## Installation

```bash
cp -r PerformanceTheme /var/www/html/custom/plugins/
cd /var/www/html
bin/console plugin:refresh
bin/console plugin:install --activate PerformanceTheme
bin/build-storefront.sh                 # bundle:dump, JS mit Webpack, assets:install, theme:compile, cache:clear
bin/console theme:change --all PerformanceTheme
```

`bin/build-storefront.sh` braucht Node.js und die npm-Abhängigkeiten der
Storefront. Nur SCSS oder Twig geändert? Dann genügt `bin/console theme:compile`
bzw. `bin/console cache:clear`.

## Messen

```bash
# Was jede Seite lädt, aus dem Theme der gegebenen Seite
./scripts/analyze-bundle.sh --url https://shop.example.com/ --budget-js 200 --budget-css 100

# Zusammensetzung je Modul (braucht Node.js im Shopware-Verzeichnis)
SHOPWARE_ROOT=/var/www/html ./scripts/analyze-bundle.sh --stats
```

Im Analyzer-Report stehen drei Grössen: **stat** (Quelltext der Module vor
dem Minifizieren), **parsed** (ausgeliefert), **gzip** (übertragen). Beispiel
tiny-slider in 6.6.10.6: stat 100 KB, parsed 31 KB, gzip 12,6 KB (1 KB = 1024 Byte,
wie im Skript und in Lighthouse).

`analyze-bundle.sh` muss auf dem Shop-Server laufen (liest `SHOPWARE_ROOT`), und
`--url` muss eine Domain des Sales Channels sein. `--stats` ruft vorher
`bin/console bundle:dump` auf und schreibt die `dist/`-Ordner neu wie
`bin/build-storefront.sh`.

Welche Chunks eine bestimmte Seite nachlädt, sehen nur Browser-Werkzeuge
(DevTools > Netzwerk, Lighthouse).

## Critical CSS

`critical` 9 braucht Node.js ≥ 22.13 (Dockware hat Node 20). Deshalb in zwei
Schritten: auf einem Rechner mit Node 22.13+ im Companion-Checkout erzeugen,
dann aufs Theme im Shop kopieren.

```bash
# 1. Im Companion-Checkout (chapters/16-shopware-themes/), Node.js >= 22.13
npx playwright install chromium          # einmalig, für die Render-Engine
./scripts/extract-critical-css.sh https://shop.example.com/

# 2. Auf den Server kopieren, dort Cache leeren
rsync -a PerformanceTheme/src/Resources/views/storefront/critical/ \
    server:/var/www/html/custom/plugins/PerformanceTheme/src/Resources/views/storefront/critical/
bin/console cache:clear
```

Danach in der Administration unter «Inhalte > Themes > PerformanceTheme»
den Schalter «Critical CSS inline, all.css asynchron laden» einschalten.

Die Optionen `--base` und `--output` aus älteren Anleitungen gibt es in
`critical` 9 nicht mehr, und `--inline` liefert das ganze HTML statt CSS.
Das Skript schreibt ausserdem die Font-URLs auf `/theme/…` um (critical
übernimmt sie relativ, inline zeigen sie auf 404, und absolut mit dem Host,
gegen den extrahiert wurde) und schickt das Ergebnis durch `lightningcss` mit
den Browserzielen der Storefront: critical 9 schreibt `(min-width: 576px)` als
`(width>=576px)`, das Safari/iOS < 16.4 verwerfen. Startseite des Testshops:
38,5 KB, gzip 6,5 KB.

Die Datei gilt für **alle** Seiten. Aus der Startseite erzeugt, fehlt auf
Kategorie- und Produktseiten deren Above-the-fold-CSS; es kommt dort erst mit
dem asynchronen `all.css`.

## Stolperstellen (gemessen)

- `overrides.scss` **hinter** `@Storefront` wirkt nicht: Der Marker
  `$primary` kam einmal statt 91-mal im CSS an.
- `@import "~bootstrap/scss/grid"` bricht `theme:compile` ab
  (`file not found for @import`). `~vendor/bootstrap/…` kompiliert, liefert den
  Grid aber doppelt aus (+13 KB).
- `@StorefrontBootstrap` statt `@Storefront`: `all.css` −18 % roh, −10 % gzip
  (391 → 320 KB roh, 54,8 → 49,5 KB gzip). Die Doku verlangt dazu `@Plugins`
  im `style`-Array. Gemessen mit dem `style`-Array aus
  `config/theme-style-storefront-bootstrap.json` (ersetzt das in `theme.json`).
- Ein Block, den es nicht gibt (z. B. `base_head_stylesheets`), wird
  **ohne Meldung** ignoriert. Das Theme-CSS steht in `layout_head_stylesheet`
  in `layout/meta.html.twig`.
- `sw_include` ohne `ignore missing` auf eine fehlende Datei: HTTP 500 — auch
  wenn der Zweig mit dem Include nie ausgeführt wird.
- `{% sw_use %}` gibt es erst ab 6.7.0.0; in 6.6 HTTP 500 (`Unknown "sw_use" tag`).
- `import('tiny-slider')` im Theme bündelt die Bibliothek ein zweites Mal
  (eigener Webpack-Compiler je Theme/Plugin). Dasselbe gilt für
  `import Plugin from 'src/plugin-system/plugin.class'`: Der Plugin-Chunk war
  damit 7,1 KB gross, mit `window.PluginBaseClass` 0,6 KB.
- `PluginManager.deregister('DatePicker')` spart auf Start-, Kategorie- und
  Produktseite nichts: Der Chunk lädt dort ohnehin nicht.

## Referenzen

- Kapitel 16 im Buch: «Shopware 6 Themes»
- [Override Bootstrap Variables](https://developer.shopware.com/docs/guides/plugins/themes/styling/override-bootstrap-variables-in-a-theme.html)
- [Theme with Bootstrap Styling](https://developer.shopware.com/docs/guides/plugins/themes/inheritance/add-theme-inheritance-without-resources.html)
- [critical](https://github.com/addyosmani/critical)
- [webpack-bundle-analyzer](https://github.com/webpack-contrib/webpack-bundle-analyzer)
