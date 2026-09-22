/**
 * Lighthouse CI mit Grenzen je Seitentyp — Kapitel 13
 *
 * assertMatrix ersetzt "assertions" vollständig: Beides zusammen bricht mit
 * "Cannot use assertMatrix with other options" ab. Jeder Eintrag gilt für
 * alle URLs, auf die sein Muster passt; passen mehrere, gelten alle.
 *
 * Verwendung:     LHCI_BASE_URL=https://staging.ihr-shop.ch lhci autorun --config=config/lighthouserc.matrix.cjs
 *
 * Getestet mit @lhci/cli 0.15.1 (Lighthouse 12.6.1) gegen Shopware 6.6.10.6.
 */

const base = require('./lighthouserc.cjs');

const BASE_URL = (process.env.LHCI_BASE_URL || 'http://localhost').replace(/\/+$/, '');

// An Ihren Shop anpassen; die Muster unten leiten sich daraus ab
const PRODUCT = '/Main-product/SWDEMO10001';
const PATHS = [
  '/',                         // Startseite
  '/Clothing/',                // Kategorie
  PRODUCT,                     // Produktdetail
  '/search?search=shirt',      // Suche (noindex, nicht im HTTP-Cache)
  '/checkout/cart',            // Warenkorb (noindex)
];

// URL als Regex-Muster (Punkte, Fragezeichen usw. maskiert)
const exact = (path) => '^' + (BASE_URL + path).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$';

// Gemeinsame Grenzen aus lighthouserc.cjs, ohne SEO (Suche und Warenkorb
// sind noindex und kämen nie über 0,54)
const { 'categories:seo': _seo, ...common } = base.ci.assert.assertions;

module.exports = {
  ci: {
    collect: {
      ...base.ci.collect,
      url: PATHS.map((path) => BASE_URL + path),
    },

    assert: {
      assertMatrix: [
        {
          // Alle Seiten: gemeinsame Grenzen
          matchingUrlPattern: '.*',
          aggregationMethod: 'median-run',
          assertions: common,
        },
        {
          // Startseite: strenger (erster Eindruck)
          matchingUrlPattern: exact('/'),
          aggregationMethod: 'median-run',
          assertions: {
            'largest-contentful-paint': ['error', { maxNumericValue: 2000 }],
            'first-contentful-paint': ['error', { maxNumericValue: 1500 }],
          },
        },
        {
          // Produktdetail: Bildergalerie darf nichts verschieben
          matchingUrlPattern: exact(PRODUCT),
          aggregationMethod: 'median-run',
          assertions: {
            'cumulative-layout-shift': ['error', { maxNumericValue: 0.05 }],
          },
        },
        {
          // Indexierbare Seiten: SEO prüfen
          matchingUrlPattern: '^(?!.*/(search|checkout)).*$',
          aggregationMethod: 'median-run',
          assertions: {
            'categories:seo': ['warn', { minScore: 0.9 }],
          },
        },
      ],
    },

    upload: base.ci.upload,
  },
};
