/**
 * Kapitel 24: A/B-Testing auf der Edge
 * Ausblick – Neue Technologien und Trends
 *
 * Cloudflare Worker für A/B-Testing ohne Origin-Last.
 * Varianten-Zuweisung erfolgt auf der Edge (< 1ms).
 *
 * Deployment:
 *   npm install -g wrangler
 *   wrangler deploy
 */

// A/B-Test-Konfiguration
const AB_TESTS = {
    // Produktseiten-Test
    'product-page': {
        variants: ['control', 'new-layout'],
        weights: [50, 50],  // 50/50 Split
        paths: ['/detail/'],
        cookie: 'ab_product_page',
        duration: 30 * 24 * 60 * 60  // 30 Tage
    },
    // Checkout-Button-Test
    'checkout-button': {
        variants: ['green', 'orange'],
        weights: [50, 50],
        paths: ['/checkout/'],
        cookie: 'ab_checkout_button',
        duration: 7 * 24 * 60 * 60  // 7 Tage
    }
};

/**
 * Haupthandler für eingehende Requests
 */
export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);
        const cookies = parseCookies(request.headers.get('Cookie') || '');

        // Aktive Tests für diesen Pfad finden
        const activeTests = findActiveTests(url.pathname);

        if (activeTests.length === 0) {
            // Kein A/B-Test aktiv - direkt weiterleiten
            return fetch(request);
        }

        // Varianten für alle aktiven Tests ermitteln
        const assignments = {};
        const newCookies = [];

        for (const testName of activeTests) {
            const test = AB_TESTS[testName];
            let variant = cookies[test.cookie];

            if (!variant) {
                // Neue Zuweisung basierend auf Gewichtung
                variant = assignVariant(test.variants, test.weights);
                newCookies.push({
                    name: test.cookie,
                    value: variant,
                    maxAge: test.duration
                });
            }

            assignments[testName] = variant;
        }

        // Request an Origin mit Varianten-Headern
        const modifiedRequest = new Request(request, {
            headers: new Headers([
                ...request.headers,
                ['X-AB-Tests', JSON.stringify(assignments)]
            ])
        });

        // Origin-Response holen
        const response = await fetch(modifiedRequest);

        // Cookies für neue Zuweisungen setzen
        if (newCookies.length > 0) {
            const newResponse = new Response(response.body, response);
            for (const cookie of newCookies) {
                newResponse.headers.append(
                    'Set-Cookie',
                    `${cookie.name}=${cookie.value}; Path=/; Max-Age=${cookie.maxAge}; SameSite=Lax`
                );
            }
            return newResponse;
        }

        return response;
    }
};

/**
 * Findet aktive Tests für einen Pfad
 */
function findActiveTests(pathname) {
    const tests = [];
    for (const [name, config] of Object.entries(AB_TESTS)) {
        if (config.paths.some(path => pathname.startsWith(path))) {
            tests.push(name);
        }
    }
    return tests;
}

/**
 * Weist Variante basierend auf Gewichtung zu
 */
function assignVariant(variants, weights) {
    const totalWeight = weights.reduce((a, b) => a + b, 0);
    const random = Math.random() * totalWeight;

    let cumulative = 0;
    for (let i = 0; i < variants.length; i++) {
        cumulative += weights[i];
        if (random < cumulative) {
            return variants[i];
        }
    }
    return variants[0];
}

/**
 * Parst Cookie-Header
 */
function parseCookies(cookieHeader) {
    const cookies = {};
    if (!cookieHeader) return cookies;

    cookieHeader.split(';').forEach(cookie => {
        const [name, value] = cookie.trim().split('=');
        if (name && value) {
            cookies[name] = value;
        }
    });
    return cookies;
}
