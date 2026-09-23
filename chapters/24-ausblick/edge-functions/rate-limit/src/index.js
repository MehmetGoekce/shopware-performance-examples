/**
 * Kapitel 24: Anfragen je IP begrenzen (Rate Limiting Binding)
 * Ausblick – Neue Technologien und Trends
 *
 * Die Fassung aus dem Buch, Zeile fuer Zeile.
 * Das Binding braucht Wrangler 4.36.0 oder neuer, siehe wrangler.toml.example.
 * Getestet in tests/JavaScript/ch24-edge-functions.test.js.
 */

// Edge: Anfragen je IP begrenzen (Rate Limiting Binding, wrangler.toml:
// [[ratelimits]] name = "RATE_LIMITER", namespace_id = "1001",
// simple = { limit = 100, period = 60 })
export default {
    async fetch(request, env) {
        const ip = request.headers.get('CF-Connecting-IP');

        // Kein Zähler in KV: KV nimmt je Key höchstens einen Schreibvorgang
        // pro Sekunde an, ein Zähler je IP scheitert genau beim Bot. Das
        // Binding zählt je Cloudflare-Standort und bewusst ungenau; für ein
        // verbindliches Limit die Rate-Limiting-Regeln von Cloudflare nutzen
        const { success } = await env.RATE_LIMITER.limit({ key: ip });
        if (!success) {
            return new Response('Rate limit exceeded', { status: 429 });
        }

        return fetch(request);
    }
};
