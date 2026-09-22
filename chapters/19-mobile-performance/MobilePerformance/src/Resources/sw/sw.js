/**
 * Service Worker: statische Theme-Dateien aus dem Cache, Offline-Seite
 * Kapitel 19: Mobile Performance
 *
 * Bewusst klein gehalten:
 *   - Nur GET-Anfragen derselben Domain.
 *   - Dateien unter /theme/ und /bundles/ (Versionsparameter oder Hash in
 *     der URL): Cache First. Neue Theme-Versionen haben neue URLs.
 *   - Seitenaufrufe (navigate): immer aus dem Netz, nur ohne Verbindung
 *     die Offline-Seite. Keine HTML-Seite landet im Cache, also auch keine
 *     Preise, Warenkoerbe oder Kundendaten.
 *   - Alles andere (Store-API, Warenkorb, Konto, Medien) geht am Service
 *     Worker vorbei direkt ins Netz.
 *
 * Ausgeliefert ueber die Route /sw.js (Controller im Plugin), damit der
 * Scope die ganze Storefront umfasst.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
const CACHE = 'mobile-static-v1';
const MAX_ENTRIES = 100;
const BASE = new URL(self.registration.scope).pathname;
const STATIC_PREFIXES = [BASE + 'theme/', BASE + 'bundles/'];

const OFFLINE_HTML = '<!doctype html><html lang="de"><head><meta charset="utf-8">'
    + '<meta name="viewport" content="width=device-width, initial-scale=1">'
    + '<title>Offline</title></head><body style="font-family:sans-serif;padding:2rem">'
    + '<h1>Keine Verbindung</h1><p>Bitte prüfen Sie Ihre Internetverbindung und laden Sie die Seite neu.</p>'
    + '</body></html>';

self.addEventListener('install', () => {
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil((async () => {
        // Navigation Preload: der Seitenaufruf startet parallel zum Hochfahren des Service Workers
        if (self.registration.navigationPreload) {
            await self.registration.navigationPreload.enable();
        }
        const keys = await caches.keys();
        await Promise.all(keys
            .filter((key) => key.startsWith('mobile-static-') && key !== CACHE)
            .map((key) => caches.delete(key)));
        await self.clients.claim();
    })());
});

self.addEventListener('fetch', (event) => {
    const request = event.request;
    if (request.method !== 'GET') {
        return;
    }

    const url = new URL(request.url);
    if (url.origin !== self.location.origin) {
        return;
    }

    if (request.mode === 'navigate') {
        event.respondWith(networkWithOfflinePage(event));
        return;
    }

    if (STATIC_PREFIXES.some((prefix) => url.pathname.startsWith(prefix))) {
        event.respondWith(cacheFirst(request));
    }
});

async function networkWithOfflinePage(event) {
    try {
        const preloaded = await event.preloadResponse;
        return preloaded || await fetch(event.request);
    } catch {
        return new Response(OFFLINE_HTML, {
            headers: { 'Content-Type': 'text/html; charset=utf-8' },
        });
    }
}

async function cacheFirst(request) {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request);
    if (cached) {
        return cached;
    }

    const response = await fetch(request);
    if (response.ok) {
        await cache.put(request, response.clone());
        await trim(cache);
    }
    return response;
}

async function trim(cache) {
    const keys = await cache.keys();
    for (let i = 0; i < keys.length - MAX_ENTRIES; i++) {
        await cache.delete(keys[i]);
    }
}
