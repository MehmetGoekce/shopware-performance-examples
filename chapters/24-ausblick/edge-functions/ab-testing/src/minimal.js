/**
 * Kapitel 24: A/B-Testing auf der Edge, kurze Fassung
 * Ausblick – Neue Technologien und Trends
 *
 * Die Fassung aus dem Buch, Zeile fuer Zeile. Die ausfuehrliche Fassung
 * mit mehreren Tests und Gewichtung steht in index.js daneben.
 * Getestet in tests/JavaScript/ch24-edge-functions.test.js.
 */

// Cloudflare Worker
export default {
    async fetch(request) {
        const url = new URL(request.url);

        // Produkt-Detailseite?
        if (url.pathname.startsWith('/detail/')) {
            // Cookie zuerst lesen, sonst würfelt jeder Request neu
            const seen = request.headers.get('Cookie')?.match(/(?:^|;\s*)ab_variant=([AB])(?=;|$)/)?.[1];
            const variant = seen ?? (Math.random() < 0.5 ? 'A' : 'B');

            // Variant-Header an Origin senden. Headers ist iterierbar, aber
            // ohne eigene Properties: {...request.headers} ergibt {} und
            // verliert Cookie, User-Agent und Accept-Encoding
            const headers = new Headers(request.headers);
            headers.set('X-AB-Variant', variant);
            const modifiedRequest = new Request(request, { headers });

            const response = await fetch(modifiedRequest);

            // Cookie für konsistente Experience. Die Response als Vorlage
            // übernimmt Status und Header (sonst wird jeder 404/301 zu 200)
            const out = new Response(response.body, response);
            out.headers.append('Set-Cookie', `ab_variant=${variant}; Path=/; Max-Age=86400`);
            return out;
        }

        return fetch(request);
    }
};
