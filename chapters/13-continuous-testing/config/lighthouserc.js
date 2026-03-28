/**
 * Lighthouse CI Konfiguration für Shopware 6
 *
 * Installation:
 *   npm install -g @lhci/cli
 *
 * Verwendung:
 *   lhci autorun
 *
 * Dokumentation:
 *   https://github.com/GoogleChrome/lighthouse-ci/blob/main/docs/configuration.md
 */

module.exports = {
  ci: {
    collect: {
      // Anzahl der Test-Durchläufe pro URL (Median wird verwendet)
      numberOfRuns: 3,

      // URLs zum Testen (an Ihren Shop anpassen)
      url: [
        'https://ihr-shop.de/',
        'https://ihr-shop.de/kategorie/bestseller/',
        'https://ihr-shop.de/detail/beispiel-produkt/',
      ],

      // Shopware Storefront starten (falls lokal)
      // startServerCommand: 'php -S localhost:8000 -t public/',
      // startServerReadyPattern: 'Development Server',

      // Chrome-Einstellungen
      settings: {
        // Mobile-First (wie Google)
        preset: 'desktop', // oder 'perf' für Mobile-Simulation

        // Throttling für realistische Bedingungen
        throttling: {
          cpuSlowdownMultiplier: 4,
          downloadThroughputKbps: 1600,
          uploadThroughputKbps: 750,
          rttMs: 150,
        },

        // Kategorien aktivieren
        onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],

        // Skip-Audits (optional, für schnellere Tests)
        skipAudits: [
          'uses-http2',           // Oft CDN-abhängig
          'is-on-https',          // Staging meist ohne SSL
        ],
      },
    },

    assert: {
      // Performance Budget als Assertions
      assertions: {
        // Core Web Vitals (p75 Schwellenwerte)
        'largest-contentful-paint': ['warn', { maxNumericValue: 2500 }],
        'cumulative-layout-shift': ['error', { maxNumericValue: 0.1 }],
        'interactive': ['warn', { maxNumericValue: 3800 }],
        'total-blocking-time': ['warn', { maxNumericValue: 300 }],

        // Lighthouse Scores (0-1 Skala)
        'categories:performance': ['error', { minScore: 0.75 }],
        'categories:accessibility': ['warn', { minScore: 0.9 }],
        'categories:best-practices': ['warn', { minScore: 0.9 }],
        'categories:seo': ['warn', { minScore: 0.9 }],

        // Resource Budgets
        'resource-summary:script:size': ['error', { maxNumericValue: 307200 }],  // 300KB
        'resource-summary:stylesheet:size': ['warn', { maxNumericValue: 102400 }], // 100KB
        'resource-summary:image:size': ['warn', { maxNumericValue: 512000 }],     // 500KB
        'resource-summary:total:size': ['warn', { maxNumericValue: 2097152 }],    // 2MB

        // Request Counts
        'resource-summary:script:count': ['warn', { maxNumericValue: 15 }],
        'resource-summary:third-party:count': ['warn', { maxNumericValue: 10 }],
      },
    },

    upload: {
      // LHCI Server (optional)
      // target: 'lhci',
      // serverBaseUrl: 'https://lhci.ihr-server.de',
      // token: process.env.LHCI_TOKEN,

      // Temporär: Lokaler HTML-Report
      target: 'temporary-public-storage',
    },
  },
};
