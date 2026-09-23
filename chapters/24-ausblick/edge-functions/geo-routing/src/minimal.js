/**
 * Kapitel 24: Geo-spezifische Waehrung auf der Edge, kurze Fassung
 * Ausblick – Neue Technologien und Trends
 *
 * Die Fassung aus dem Buch, Zeile fuer Zeile. Die ausfuehrliche Fassung
 * mit Sprache, MwSt. und Override-Cookie steht in index.js daneben.
 * Getestet in tests/JavaScript/ch24-edge-functions.test.js.
 */

// Cloudflare Worker
export default {
    async fetch(request) {
        const country = request.headers.get('CF-IPCountry') || 'DE';

        // Währung basierend auf Land
        const currency = {
            'CH': 'CHF',
            'DE': 'EUR',
            'AT': 'EUR',
            'US': 'USD'
        }[country] || 'EUR';

        // Request an Origin mit Währungs-Header (Headers kopieren, nicht spreaden)
        const headers = new Headers(request.headers);
        headers.set('X-Customer-Currency', currency);
        headers.set('X-Customer-Country', country);

        return fetch(new Request(request, { headers })); // Methode und Body bleiben
    }
};
