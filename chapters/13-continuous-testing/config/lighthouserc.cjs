/**
 * Lighthouse CI für Shopware 6 — Kapitel 13
 *
 * Misst einen laufenden Shop (Staging oder Preview), nicht den Code im Runner.
 * Ein `php -S` im Runner hat keine Datenbank, keine Domain und liefert
 * CSS/JS unkomprimiert aus (storefront.js 235 statt 76 KB) — die
 * Grössen-Budgets würden dann den Server messen, nicht den Shop.
 *
 * Installation:   npm install -g @lhci/cli@0.15.1
 *                 (nie «npx lhci»: ohne installiertes @lhci/cli lädt npx das
 *                 fremde Paket «lhci», das nichts prüft und mit Exit 0 endet)
 * Verwendung:     LHCI_BASE_URL=https://staging.ihr-shop.ch lhci autorun
 *
 * Getestet mit @lhci/cli 0.15.1 (Lighthouse 12.6.1) gegen Shopware 6.6.10.6.
 *
 * @see https://github.com/GoogleChrome/lighthouse-ci/blob/v0.15.1/docs/configuration.md
 */

const BASE_URL = (process.env.LHCI_BASE_URL || 'http://localhost').replace(/\/+$/, '');

// An Ihren Shop anpassen. Kategorie und Produkt über die SEO-URL aufrufen:
// /navigation/<name> und /detail/<name> erwarten eine UUID und antworten mit 400.
const PATHS = [
  '/',                         // Startseite
  '/Clothing/',                // Kategorie (Demo-Daten)
  '/Main-product/SWDEMO10001', // Produktdetail (Demo-Daten)
];

module.exports = {
  ci: {
    collect: {
      url: PATHS.map((path) => BASE_URL + path),

      // Drei Läufe je URL; der Bericht zeigt den Median-Lauf
      numberOfRuns: 3,

      settings: {
        // Desktop: 40 ms RTT, 10 Mbit/s, keine CPU-Drosselung.
        // Für Mobil die Zeile löschen: Mobil ist die Vorgabe von Lighthouse.
        preset: 'desktop',
      },
    },

    assert: {
      // Ohne diese Zeile wertet LHCI bei Obergrenzen den besten der drei
      // Läufe ("optimistic") — ein einzelner guter Lauf lässt den Build durch.
      aggregationMethod: 'median-run',

      assertions: {
        // === CORE WEB VITALS (error = Build schlägt fehl) ===
        'largest-contentful-paint': ['error', { maxNumericValue: 2500 }],
        'cumulative-layout-shift': ['error', { maxNumericValue: 0.1 }],
        // INP misst Lighthouse im Navigationsmodus nicht; TBT ist der Labor-Ersatz
        'total-blocking-time': ['error', { maxNumericValue: 300 }],

        // === WEITERE TIMING-METRIKEN (warn) ===
        'first-contentful-paint': ['warn', { maxNumericValue: 1800 }],
        'speed-index': ['warn', { maxNumericValue: 3400 }],

        // === RESSOURCEN: übertragene Bytes (komprimiert) ===
        'resource-summary:script:size': ['error', { maxNumericValue: 300000 }],
        'resource-summary:stylesheet:size': ['warn', { maxNumericValue: 100000 }],
        'resource-summary:image:size': ['warn', { maxNumericValue: 500000 }],
        'resource-summary:font:size': ['warn', { maxNumericValue: 100000 }],
        'resource-summary:total:size': ['warn', { maxNumericValue: 1500000 }],

        // === ANZAHL REQUESTS ===
        // Shopware 6.6 ab Werk (Demo-Daten): 16 Skripte auf der Startseite,
        // 25 auf Kategorie und Produkt — bei 15 warnt es dort schon.
        'resource-summary:script:count': ['warn', { maxNumericValue: 30 }],
        'resource-summary:third-party:count': ['warn', { maxNumericValue: 10 }],

        // === LIGHTHOUSE-SCORES (0-1) ===
        'categories:performance': ['error', { minScore: 0.85 }],
        'categories:accessibility': ['warn', { minScore: 0.9 }],
        'categories:best-practices': ['warn', { minScore: 0.9 }],
        'categories:seo': ['warn', { minScore: 0.9 }],
      },
    },

    upload: {
      // Berichte und manifest.json nach .lighthouseci/ (liest der PR-Kommentar)
      target: 'filesystem',
      outputDir: '.lighthouseci',
    },
  },
};
