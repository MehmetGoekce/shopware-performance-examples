/**
 * Kapitel 24: Anfragen je IP begrenzen (Rate Limiting Binding)
 * Ausblick – Neue Technologien und Trends
 *
 * Die Fassung aus dem Buch, Zeile fuer Zeile.
 * Das Binding braucht Wrangler 4.36.0 oder neuer, siehe wrangler.toml.example.
 * Getestet in tests/JavaScript/ch24-edge-functions.test.js.
 */

// Edge: teure Routen (Suche, Login) je IP bremsen, nicht Assets.
// Rate Limiting Binding, Konfiguration im Companion: rate-limit/wrangler.toml.example
export default {
    async fetch(request, env) {
        const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';

        // Kein Zähler in KV: KV nimmt je Key höchstens einen Schreibvorgang
        // pro Sekunde an. Cloudflare rät von IPs als Key ab (Mobilfunk und
        // Proxys teilen sie), anonyme Bots haben aber keine andere Kennung:
        // Limit grosszügig wählen. Genau zählt weder Binding noch WAF-Regel
        const { success } = await env.RATE_LIMITER.limit({ key: ip });
        if (!success) {
            return new Response('Rate limit exceeded', { status: 429 });
        }

        return fetch(request);
    }
};
