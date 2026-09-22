/**
 * Lighthouse CI für Seiten hinter dem Login — Kapitel 13
 *
 * Verwendung:
 *   SHOPWARE_TEST_EMAIL=… SHOPWARE_TEST_PASSWORD=… \
 *   LHCI_BASE_URL=https://staging.ihr-shop.ch lhci autorun --config=config/lighthouserc.auth.cjs
 *
 * Mit puppeteerScript startet LHCI Chrome über Puppeteer und ignoriert
 * settings.chromeFlags — Flags gehören dann in puppeteerLaunchOptions.args.
 *
 * Getestet mit @lhci/cli 0.15.1 (Lighthouse 12.6.1) gegen Shopware 6.6.10.6.
 */

const base = require('./lighthouserc.cjs');

const BASE_URL = (process.env.LHCI_BASE_URL || 'http://localhost').replace(/\/+$/, '');

module.exports = {
  ci: {
    ...base.ci,
    collect: {
      ...base.ci.collect,
      url: [
        `${BASE_URL}/account`,       // Kontoübersicht
        `${BASE_URL}/account/order`, // Bestellungen
      ],

      // Login vor jeder URL
      puppeteerScript: './scripts/lhci-shopware-auth.cjs',
      puppeteerLaunchOptions: {
        headless: true,
      },
    },
  },
};
