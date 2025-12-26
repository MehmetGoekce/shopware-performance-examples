# Kapitel 16: Shopware 6 Themes - Companion Code

Performance-optimierte Theme-Komponenten, SCSS-Strukturen und Build-Konfigurationen
für Shopware 6 Storefronts.

## Inhalt

### SCSS (`scss/`)

- **base.scss** - Optimierte Basis-Styles mit selektiven Bootstrap-Imports
- **overrides.scss** - Bootstrap-Variablen-Overrides (vor @Storefront)
- **critical/** - Above-the-Fold CSS für schnelles First Paint

### Templates (`templates/`)

- **base.html.twig** - Optimierte Basis mit Critical CSS und async Loading
- **optimized/** - Performance-optimierte Template-Overrides

### Source (`src/`)

- **ThemePerformanceAnalyzer.php** - Analysiert Theme-Assets auf Performance
- **AsyncPluginLoader.js** - Async Loading für JavaScript-Plugins
- **PerformancePlugin.js** - Beispiel für optimiertes Plugin

### Scripts (`scripts/`)

- **analyze-bundle.sh** - Bundle-Analyse mit source-map-explorer
- **extract-critical-css.sh** - Critical CSS Extraktion
- **build-theme.sh** - Optimierter Theme-Build

### Config (`config/`)

- **theme.json** - Optimierte Theme-Konfiguration
- **vite.config.mts** - Vite-Konfiguration für Shopware 6.7+
- **lighthouse-budget.json** - Performance-Budget für CI/CD

## Quick Start

### 1. Theme-Konfiguration anpassen

```json
// theme.json
{
  "style": [
    "app/storefront/src/scss/overrides.scss",
    "@Storefront",
    "app/storefront/src/scss/base.scss"
  ]
}
```

### 2. Bootstrap selektiv laden

```scss
// scss/base.scss
@import "~bootstrap/scss/functions";
@import "~bootstrap/scss/variables";
@import "~bootstrap/scss/mixins";

// Nur benötigte Komponenten
@import "~bootstrap/scss/grid";
@import "~bootstrap/scss/buttons";
@import "~bootstrap/scss/forms";
```

### 3. JavaScript-Plugins optimieren

```javascript
// Nicht benötigte Plugins deregistrieren
window.PluginManager.deregister('DatePicker');    // -115 KB
window.PluginManager.deregister('ImageZoom');     // -72 KB
```

### 4. Bundle analysieren

```bash
./scripts/analyze-bundle.sh
```

## Performance-Ziele

| Metrik | Vorher | Nachher | Reduktion |
|--------|--------|---------|-----------|
| JavaScript | 750 KB | 300 KB | -60% |
| CSS | 180 KB | 90 KB | -50% |
| LCP | 3.2s | 2.1s | -34% |
| FCP | 1.8s | 0.9s | -50% |

## Shopware 6.7 Vite Migration

Für Shopware 6.7+ ist die Vite-Konfiguration in `config/vite.config.mts` enthalten:

```bash
# Altes Webpack-Build ersetzen
rm src/Resources/app/storefront/webpack.config.js

# Vite-Config kopieren
cp config/vite.config.mts src/Resources/app/storefront/
```

## Bundle-Grössen (Standard vs. Optimiert)

### JavaScript

| Bibliothek | Standard | Optimiert | Aktion |
|------------|----------|-----------|--------|
| jQuery | 229 KB | 0 KB | Entfernt (SW 6.5+) |
| Bootstrap JS | 129 KB | 45 KB | Selektive Imports |
| Flatpickr | 115 KB | 0 KB | Deregistriert |
| TinySlider | 100 KB | 100 KB | Lazy Loading |
| Hammer.js | 72 KB | 0 KB | Deregistriert |
| Custom | 105 KB | 80 KB | Tree-Shaking |

### CSS

| Teil | Standard | Optimiert | Aktion |
|------|----------|-----------|--------|
| Bootstrap | 150 KB | 60 KB | Selektive Imports |
| Shopware Skin | 80 KB | 30 KB | @StorefrontBootstrap |
| Custom | 20 KB | 15 KB | Purge unused |

## Integration

### In bestehendes Theme

1. SCSS-Struktur kopieren
2. Theme.json anpassen (Reihenfolge!)
3. Templates mit sw_extends überschreiben
4. Bundle analysieren

### CI/CD

```yaml
# .github/workflows/theme-performance.yml
- name: Build Theme
  run: npm run build

- name: Analyze Bundle
  run: ./scripts/analyze-bundle.sh

- name: Lighthouse Audit
  uses: treosh/lighthouse-ci-action@v12
  with:
    budgetPath: ./config/lighthouse-budget.json
```

## Referenzen

- Kapitel 16 im Buch: "Shopware 6 Themes"
- [Shopware Theme Documentation](https://developer.shopware.com/docs/guides/plugins/themes/)
- [Bootstrap 5 Customization](https://getbootstrap.com/docs/5.3/customize/sass/)
- [Vite Configuration](https://vitejs.dev/config/)
