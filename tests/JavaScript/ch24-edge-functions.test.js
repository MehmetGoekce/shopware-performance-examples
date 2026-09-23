/**
 * Kapitel 24: Edge Functions (Cloudflare Worker), MEM-317.
 *
 * Node 22 bringt Request, Response und Headers nach WHATWG Fetch mit, wie
 * workerd. fetch() ist ein Stub, der den Request an den Origin festhält.
 * request.cf setzt nur Cloudflare, hier per defineProperty.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest';
import abFull from '../../chapters/24-ausblick/edge-functions/ab-testing/src/index.js';
import abBook from '../../chapters/24-ausblick/edge-functions/ab-testing/src/minimal.js';
import geoFull from '../../chapters/24-ausblick/edge-functions/geo-routing/src/index.js';
import geoBook from '../../chapters/24-ausblick/edge-functions/geo-routing/src/minimal.js';
import rateLimit from '../../chapters/24-ausblick/edge-functions/rate-limit/src/index.js';

let origin;

beforeEach(() => {
    origin = [];
    vi.stubGlobal('fetch', vi.fn(async (input, init) => {
        const req = input instanceof Request ? new Request(input, init) : new Request(input, init);
        origin.push({ req, body: req.body ? await req.text() : null });
        return new Response('origin', { status: 404, headers: { 'X-Origin': '1' } });
    }));
});

const request = (path, { headers = {}, cf, method = 'GET', body } = {}) => {
    const req = new Request(`https://shop.example${path}`, { method, headers, body });
    if (cf) {
        Object.defineProperty(req, 'cf', { value: cf });
    }
    return req;
};

const browserHeaders = { Cookie: 'sw-session=abc', 'User-Agent': 'UA/1', 'Accept-Encoding': 'br' };

describe('Kapitel 24: A/B-Test, Fassung aus dem Buch (minimal.js)', () => {
    it('reicht Cookie, User-Agent und Accept-Encoding weiter und setzt X-AB-Variant', async () => {
        await abBook.fetch(request('/detail/42', { headers: browserHeaders }));

        const sent = origin[0].req.headers;
        expect(sent.get('cookie')).toBe('sw-session=abc');
        expect(sent.get('user-agent')).toBe('UA/1');
        expect(sent.get('accept-encoding')).toBe('br');
        expect(['A', 'B']).toContain(sent.get('x-ab-variant'));
    });

    it('behält Status und Header des Origin (404 bleibt 404)', async () => {
        const res = await abBook.fetch(request('/detail/42'));

        expect(res.status).toBe(404);
        expect(res.headers.get('x-origin')).toBe('1');
        expect(res.headers.get('set-cookie')).toMatch(/^ab_variant=[AB]; Path=\/; Max-Age=86400$/);
    });

    it('nimmt die Variante aus dem Cookie, statt neu zu würfeln', async () => {
        for (let i = 0; i < 20; i++) {
            await abBook.fetch(request('/detail/42', { headers: { Cookie: 'ab_variant=B' } }));
        }

        expect(origin.map((o) => o.req.headers.get('x-ab-variant'))).toEqual(Array(20).fill('B'));
    });

    it('liest nur das eigene Cookie, nicht my_ab_variant oder ab_variant=Ax', async () => {
        // Math.random() = 0 würfelt A; ein fälschlich gelesenes Cookie ergäbe B
        vi.spyOn(Math, 'random').mockReturnValue(0);
        for (const cookie of ['my_ab_variant=B', 'ab_variant=Bx', 'x=1; ab_variant=B; y=2']) {
            await abBook.fetch(request('/detail/42', { headers: { Cookie: cookie } }));
        }
        vi.restoreAllMocks();
        const res = await abBook.fetch(request('/detail/42', { headers: { Cookie: 'x=1; ab_variant=A; y=2' } }));

        expect(origin.map((o) => o.req.headers.get('x-ab-variant')).slice(0, 3)).toEqual(['A', 'A', 'B']);
        expect(origin[3].req.headers.get('x-ab-variant')).toBe('A');
        expect(res.status).toBe(404);
    });

    it('lässt andere Pfade unverändert durch', async () => {
        const res = await abBook.fetch(request('/checkout/cart'));

        expect(origin[0].req.headers.get('x-ab-variant')).toBeNull();
        expect(res.headers.get('set-cookie')).toBeNull();
    });
});

describe('Kapitel 24: A/B-Test, ausführliche Fassung (index.js)', () => {
    it('kopiert alle Header (Objekt-Spread ergäbe {})', async () => {
        expect({ ...new Headers(browserHeaders) }).toEqual({});

        await abFull.fetch(request('/detail/42', { headers: browserHeaders }));

        const sent = origin[0].req.headers;
        expect(sent.get('cookie')).toBe('sw-session=abc');
        expect(sent.get('user-agent')).toBe('UA/1');
        expect(sent.get('accept-encoding')).toBe('br');
        expect(Object.keys(JSON.parse(sent.get('x-ab-tests')))).toEqual(['product-page']);
    });

    it('ersetzt einen vom Client geschickten X-AB-Tests, statt ihn zu ergänzen', async () => {
        await abFull.fetch(request('/detail/42', { headers: { 'X-AB-Tests': '{"product-page":"x"}', Cookie: 'ab_product_page=control' } }));

        expect(JSON.parse(origin[0].req.headers.get('x-ab-tests'))).toEqual({ 'product-page': 'control' });
    });

    it('übernimmt aus dem Cookie nur bekannte Varianten', async () => {
        await abFull.fetch(request('/detail/42', { headers: { Cookie: 'ab_product_page=evil' } }));

        expect(['control', 'new-layout']).toContain(JSON.parse(origin[0].req.headers.get('x-ab-tests'))['product-page']);
    });

    it('setzt ein Cookie nur bei neuer Zuweisung und behält den Status', async () => {
        const fresh = await abFull.fetch(request('/detail/42'));
        const known = await abFull.fetch(request('/detail/42', { headers: { Cookie: 'ab_product_page=control' } }));

        expect(fresh.status).toBe(404);
        expect(fresh.headers.get('set-cookie')).toMatch(/^ab_product_page=(control|new-layout); Path=\/; Max-Age=2592000; SameSite=Lax$/);
        expect(known.headers.get('set-cookie')).toBeNull();
        expect(JSON.parse(origin[1].req.headers.get('x-ab-tests'))).toEqual({ 'product-page': 'control' });
    });
});

describe('Kapitel 24: Geo-Währung, Fassung aus dem Buch (minimal.js)', () => {
    it('setzt Währung nach CF-IPCountry und behält die übrigen Header', async () => {
        await geoBook.fetch(request('/', { headers: { ...browserHeaders, 'CF-IPCountry': 'CH' } }));

        const sent = origin[0].req.headers;
        expect(sent.get('x-customer-currency')).toBe('CHF');
        expect(sent.get('x-customer-country')).toBe('CH');
        expect(sent.get('cookie')).toBe('sw-session=abc');
    });

    it('behält Methode und Body (ein POST bleibt ein POST)', async () => {
        await geoBook.fetch(request('/checkout/order', { method: 'POST', body: 'tos=on' }));

        expect(origin[0].req.method).toBe('POST');
        expect(origin[0].body).toBe('tos=on');
    });

    it('ist ein Cloudflare-Worker-Modul (export default { fetch })', () => {
        expect(typeof geoBook.fetch).toBe('function');
        expect(typeof abBook.fetch).toBe('function');
    });

    it('fällt ohne Land auf DE/EUR zurück, unbekannte Länder auf EUR', async () => {
        await geoBook.fetch(request('/'));
        await geoBook.fetch(request('/', { headers: { 'CF-IPCountry': 'JP' } }));

        expect(origin.map((o) => o.req.headers.get('x-customer-currency'))).toEqual(['EUR', 'EUR']);
        expect(origin[0].req.headers.get('x-customer-country')).toBe('DE');
    });
});

describe('Kapitel 24: Geo-Routing, ausführliche Fassung (index.js)', () => {
    it('ein geo_override-Cookie gilt nur für seinen Request, nicht für die folgenden', async () => {
        await geoFull.fetch(request('/', { cf: { country: 'DE' } }));
        await geoFull.fetch(request('/', { cf: { country: 'DE' }, headers: { Cookie: 'geo_override=US' } }));
        await geoFull.fetch(request('/', { cf: { country: 'DE' } }));

        expect(origin.map((o) => o.req.headers.get('x-customer-currency'))).toEqual(['EUR', 'USD', 'EUR']);
        expect(origin[2].req.headers.get('x-customer-vat-rate')).toBe('0.19');
    });

    it('überschreibt vom Client geschickte Preis- und Währungs-Header', async () => {
        await geoFull.fetch(request('/', { cf: { country: 'CH' }, headers: { 'X-Price-Multiplier': '0.01', 'X-Customer-Currency': 'USD' } }));

        expect(origin[0].req.headers.get('x-price-multiplier')).toBe('1');
        expect(origin[0].req.headers.get('x-customer-currency')).toBe('CHF');
    });

    it('unbekanntes Land und ungültiger Override nehmen DEFAULT', async () => {
        await geoFull.fetch(request('/', { cf: { country: 'JP' }, headers: { Cookie: 'geo_override=XX' } }));

        expect(origin[0].req.headers.get('x-customer-language')).toBe('en');
    });

    it('kodiert Städtenamen ausserhalb von Latin-1, statt mit TypeError abzubrechen', async () => {
        await geoFull.fetch(request('/', { cf: { country: 'DE', city: 'Łódź' } }));

        expect(decodeURIComponent(origin[0].req.headers.get('x-customer-city'))).toBe('Łódź');
    });

    it('behält Status, Header und Cookie des Browsers', async () => {
        const res = await geoFull.fetch(request('/', { cf: { country: 'CH' }, headers: browserHeaders }));

        expect(res.status).toBe(404);
        expect(res.headers.get('x-geo-currency')).toBe('CHF');
        expect(origin[0].req.headers.get('cookie')).toBe('sw-session=abc');
    });
});

describe('Kapitel 24: Rate Limit (Buchfassung, Rate Limiting Binding)', () => {
    const env = (allowed) => {
        const calls = [];
        return { calls, RATE_LIMITER: { limit: async (opts) => { calls.push(opts); return { success: allowed }; } } };
    };

    it('fragt das Binding je IP und antwortet mit 429, ohne den Origin zu fragen', async () => {
        const e = env(false);
        const res = await rateLimit.fetch(request('/', { headers: { 'CF-Connecting-IP': '203.0.113.7' } }), e);

        expect(e.calls).toEqual([{ key: '203.0.113.7' }]);
        expect(res.status).toBe(429);
        expect(origin).toHaveLength(0);
    });

    it('reicht erlaubte Requests unverändert weiter', async () => {
        const res = await rateLimit.fetch(request('/', { headers: { 'CF-Connecting-IP': '203.0.113.7' } }), env(true));

        expect(origin).toHaveLength(1);
        expect(res.status).toBe(404);
    });
});
