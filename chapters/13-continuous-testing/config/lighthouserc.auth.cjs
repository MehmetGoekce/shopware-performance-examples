/**
 * Lighthouse CI für Seiten hinter dem Login — Kapitel 13
 *
 * Verwendung:
 *   SHOPWARE_TEST_EMAIL=… SHOPWARE_TEST_PASSWORD=… \
 *   LHCI_BASE_URL=https://staging.ihr-shop.ch lhci autorun --config=config/lighthouserc.auth.cjs
 *
 * Mit puppeteerScript startet LHCI Chrome über das puppeteer-core, das
 * Lighthouse mitbringt (kein eigenes Paket nötig), und ignoriert
 * settings.chromeFlags — Flags gehören dann in puppeteerLaunchOptions.args.
 * Chrome muss auffindbar sein; sonst CHROME_PATH setzen.
 * puppeteerScript gilt relativ zum Arbeitsverzeichnis, nicht zu dieser Datei.
 *
 * Getestet mit @lhci/cli 0.15.1 (Lighthouse 12.6.1) gegen Shopware 6.6.10.6.
 */

const base = require('./lighthouserc.cjs');

// Konto-Seiten sind noindex: SEO würde bei jedem Lauf warnen (0,54)
const { 'categories:seo': _seo, ...assertions } = base.ci.assert.assertions;

const BASE_URL = (process.env.LHCI_BASE_URL || 'http://localhost').replace(/\/+$/, '');

module.exports = {
  ci: {
    ...base.ci,
    assert: { ...base.ci.assert, assertions },
    collect: {
      ...base.ci.collect,
      url: [
        `${BASE_URL}/account`,       // Kontoübersicht
        `${BASE_URL}/account/order`, // Bestellungen
      ],

      // Login vor jeder URL
      puppeteerScript: './scripts/lhci-shopware-auth.cjs',
      // Als root (z. B. im GitLab-Job): args: ['--no-sandbox']
      puppeteerLaunchOptions: {},
    },
  },
};
