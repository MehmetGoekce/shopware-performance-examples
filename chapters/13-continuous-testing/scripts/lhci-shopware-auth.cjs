/**
 * Shopware-Login vor jedem Lighthouse-Lauf — Kapitel 13
 *
 * LHCI ruft das Skript vor jeder URL mit (browser, context) auf.
 * context ist { url, options } — Cookies muss niemand übergeben:
 * Lighthouse misst im selben Browser und ist damit eingeloggt.
 *
 * Voraussetzung:  npm install --save-dev puppeteer
 *                 (@lhci/cli bringt Puppeteer nicht mit)
 * Zugangsdaten:   SHOPWARE_TEST_EMAIL, SHOPWARE_TEST_PASSWORD
 *                 (eigenes Testkonto auf Staging, nie ein echtes Kundenkonto)
 *
 * Getestet mit @lhci/cli 0.15.1 gegen Shopware 6.6.10.6.
 */

module.exports = async (browser, context) => {
  const email = process.env.SHOPWARE_TEST_EMAIL;
  const password = process.env.SHOPWARE_TEST_PASSWORD;
  if (!email || !password) {
    throw new Error('SHOPWARE_TEST_EMAIL und SHOPWARE_TEST_PASSWORD setzen');
  }

  const origin = new URL(context.url).origin;
  const page = await browser.newPage();

  // Login-Seite aufrufen. LHCI ruft das Skript vor jeder URL auf; ab der
  // zweiten ist der Browser eingeloggt, und Shopware leitet auf /account weiter.
  await page.goto(`${origin}/account/login`, { waitUntil: 'networkidle2' });
  if (!new URL(page.url()).pathname.startsWith('/account/login')) {
    await page.close();
    return;
  }

  // Zugangsdaten eingeben
  await page.type('#loginMail', email);
  await page.type('#loginPassword', password);

  // Absenden und auf die Weiterleitung warten
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle2' }),
    page.click('.login-submit button[type="submit"]'),
  ]);

  // Nach falschen Zugangsdaten bleibt Shopware auf /account/login
  if (new URL(page.url()).pathname.startsWith('/account/login')) {
    throw new Error(`Login fehlgeschlagen für ${email}`);
  }

  await page.close();
};
