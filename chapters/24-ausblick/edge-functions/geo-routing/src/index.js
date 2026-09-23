/**
 * Kapitel 24: Geo-basiertes Routing auf der Edge
 * Ausblick – Neue Technologien und Trends
 *
 * Cloudflare Worker für länderspezifische Anpassungen. Der Origin muss die
 * Header auswerten und in seinen Cache-Key aufnehmen (Kapitel 20), sonst
 * liefert der HTTP-Cache die zuerst gecachte Währung an alle:
 * - Währung basierend auf Land
 * - Sprach-Redirect
 * - Regionale Preise
 *
 * Deployment:
 *   wrangler deploy
 */

// Konfiguration: Land → Einstellungen
const GEO_CONFIG = {
    // DACH-Region
    'CH': {
        currency: 'CHF',
        language: 'de-CH',
        priceMultiplier: 1.0,
        vatRate: 0.081
    },
    'DE': {
        currency: 'EUR',
        language: 'de-DE',
        priceMultiplier: 1.0,
        vatRate: 0.19
    },
    'AT': {
        currency: 'EUR',
        language: 'de-AT',
        priceMultiplier: 1.0,
        vatRate: 0.20
    },
    // Weitere Länder
    'US': {
        currency: 'USD',
        language: 'en-US',
        priceMultiplier: 1.1,  // Aufschlag für US
        vatRate: 0
    },
    'GB': {
        currency: 'GBP',
        language: 'en-GB',
        priceMultiplier: 0.85,
        vatRate: 0.20
    },
    // Default
    'DEFAULT': {
        currency: 'EUR',
        language: 'en',
        priceMultiplier: 1.0,
        vatRate: 0.19
    }
};

export default {
    async fetch(request, env, ctx) {
        // Geo-Informationen von Cloudflare
        const country = request.cf?.country || 'DEFAULT';
        const city = request.cf?.city || 'Unknown';
        const continent = request.cf?.continent || 'EU';

        // Cookie prüfen: Nutzer hat manuell Land gewählt? Dann gilt dessen
        // Konfiguration. GEO_CONFIG nie verändern: Ein Worker-Isolate bedient
        // viele Requests, eine Änderung gälte für alle folgenden Besucher.
        const cookies = parseCookies(request.headers.get('Cookie') || '');
        const overrideCountry = cookies['geo_override'];
        const config = (overrideCountry && GEO_CONFIG[overrideCountry])
            || GEO_CONFIG[country]
            || GEO_CONFIG['DEFAULT'];

        // Request an Origin mit Geo-Headern. Headers kopieren und mit set()
        // ersetzen: Ein angehängtes Paar ([...request.headers, [...]]) würde
        // einen vom Client geschickten X-Price-Multiplier: 0.01 nur ergänzen
        // ("0.01, 1", in PHP (float) = 0.01). Der Origin darf Preise trotzdem
        // nie allein aus diesen Headern ableiten
        const headers = new Headers(request.headers);
        headers.set('X-Customer-Country', country);
        // Headers nehmen nur Latin-1 (ByteString), "Łódź" würfe einen TypeError
        headers.set('X-Customer-City', encodeURIComponent(city));
        headers.set('X-Customer-Continent', continent);
        headers.set('X-Customer-Currency', config.currency);
        headers.set('X-Customer-Language', config.language);
        headers.set('X-Customer-VAT-Rate', config.vatRate.toString());
        headers.set('X-Price-Multiplier', config.priceMultiplier.toString());
        const modifiedRequest = new Request(request, { headers });

        const response = await fetch(modifiedRequest);

        // Response mit Geo-Info-Header für Debugging
        const newResponse = new Response(response.body, response);
        newResponse.headers.set('X-Geo-Country', country);
        newResponse.headers.set('X-Geo-Currency', config.currency);

        return newResponse;
    }
};

/**
 * Parst Cookie-Header
 */
function parseCookies(cookieHeader) {
    const cookies = {};
    if (!cookieHeader) return cookies;

    cookieHeader.split(';').forEach(cookie => {
        const [name, ...rest] = cookie.trim().split('=');
        const value = rest.join('=');
        if (name && value) {
            cookies[name] = value;
        }
    });
    return cookies;
}
