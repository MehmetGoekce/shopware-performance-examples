/**
 * Shopware 6 Authentifizierung für Lighthouse CI
 *
 * Ermöglicht Performance-Tests von geschützten Bereichen:
 * - Checkout-Prozess
 * - Mein Konto
 * - Wunschliste
 *
 * Verwendung in lighthouserc.js:
 *   puppeteerScript: './scripts/lhci-shopware-auth.js'
 *
 * Umgebungsvariablen:
 *   SHOPWARE_TEST_EMAIL - Test-Account Email
 *   SHOPWARE_TEST_PASSWORD - Test-Account Passwort
 */

const SHOPWARE_TEST_EMAIL = process.env.SHOPWARE_TEST_EMAIL || 'test@example.com';
const SHOPWARE_TEST_PASSWORD = process.env.SHOPWARE_TEST_PASSWORD || 'shopware';

/**
 * Puppeteer-Script für authentifizierte Lighthouse-Tests
 *
 * @param {import('puppeteer').Browser} browser
 * @param {{url: string}} context
 */
async function setup(browser, context) {
  const page = await browser.newPage();

  // Basis-URL extrahieren
  const baseUrl = new URL(context.url).origin;

  console.log(`[Auth] Logging in to ${baseUrl}...`);

  try {
    // 1. Login-Seite aufrufen
    await page.goto(`${baseUrl}/account/login`, {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });

    // 2. Cookie-Banner akzeptieren (falls vorhanden)
    const cookieButton = await page.$('[data-cookie-permission-accept]');
    if (cookieButton) {
      await cookieButton.click();
      await page.waitForTimeout(500);
    }

    // 3. Login-Formular ausfüllen
    await page.waitForSelector('#loginMail', { timeout: 10000 });

    // Email eingeben
    await page.type('#loginMail', SHOPWARE_TEST_EMAIL, { delay: 50 });

    // Passwort eingeben
    await page.type('#loginPassword', SHOPWARE_TEST_PASSWORD, { delay: 50 });

    // 4. Login absenden
    await Promise.all([
      page.waitForNavigation({ waitUntil: 'networkidle2' }),
      page.click('button[type="submit"].login-submit'),
    ]);

    // 5. Prüfen ob Login erfolgreich
    const accountLink = await page.$('.account-menu-login');
    if (accountLink) {
      throw new Error('Login fehlgeschlagen - noch auf Login-Seite');
    }

    console.log('[Auth] Login erfolgreich');

    // 6. Optional: Produkt zum Warenkorb hinzufügen für Checkout-Tests
    if (context.url.includes('/checkout')) {
      await addProductToCart(page, baseUrl);
    }

  } catch (error) {
    console.error('[Auth] Login-Fehler:', error.message);
    // Screenshot für Debugging
    await page.screenshot({ path: '.lighthouseci/login-error.png' });
    throw error;
  }

  await page.close();
}

/**
 * Produkt zum Warenkorb hinzufügen
 */
async function addProductToCart(page, baseUrl) {
  console.log('[Auth] Adding product to cart for checkout test...');

  try {
    // Zur Produktseite navigieren
    await page.goto(`${baseUrl}/`, { waitUntil: 'networkidle2' });

    // Erstes Produkt finden und klicken
    const productLink = await page.$('.product-box .product-name');
    if (productLink) {
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'networkidle2' }),
        productLink.click(),
      ]);

      // Zum Warenkorb hinzufügen
      const addToCartBtn = await page.$('.btn-buy');
      if (addToCartBtn) {
        await addToCartBtn.click();
        await page.waitForTimeout(1000);
        console.log('[Auth] Product added to cart');
      }
    }
  } catch (error) {
    console.warn('[Auth] Could not add product to cart:', error.message);
  }
}

module.exports = setup;
