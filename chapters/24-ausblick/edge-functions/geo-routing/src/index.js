/**
 * Kapitel 24: Geo-basiertes Routing auf der Edge
 * Ausblick – Neue Technologien und Trends
 *
 * Cloudflare Worker für länderspezifische Anpassungen:
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

        // Konfiguration für dieses Land
        const config = GEO_CONFIG[country] || GEO_CONFIG['DEFAULT'];

        // Cookie prüfen: Nutzer hat manuell Land gewählt?
        const cookies = parseCookies(request.headers.get('Cookie') || '');
        const overrideCountry = cookies['geo_override'];

        if (overrideCountry && GEO_CONFIG[overrideCountry]) {
            // Manuelle Auswahl respektieren
            Object.assign(config, GEO_CONFIG[overrideCountry]);
        }

        // Request an Origin mit Geo-Headern
        const modifiedRequest = new Request(request, {
            headers: new Headers([
                ...request.headers,
                ['X-Customer-Country', country],
                ['X-Customer-City', city],
                ['X-Customer-Continent', continent],
                ['X-Customer-Currency', config.currency],
                ['X-Customer-Language', config.language],
                ['X-Customer-VAT-Rate', config.vatRate.toString()],
                ['X-Price-Multiplier', config.priceMultiplier.toString()]
            ])
        });

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
        const [name, value] = cookie.trim().split('=');
        if (name && value) {
            cookies[name] = value;
        }
    });
    return cookies;
}
