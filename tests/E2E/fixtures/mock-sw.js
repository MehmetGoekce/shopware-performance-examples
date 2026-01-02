/**
 * Mock Service Worker for E2E Testing
 * Simplified version for test purposes
 */

const CACHE_NAME = 'test-cache-v1';
const STATIC_CACHE = 'static-test-v1';

// Install event
self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(STATIC_CACHE).then((cache) => {
            return cache.addAll([
                '/tests/E2E/fixtures/service-worker.html',
            ]);
        })
    );
    self.skipWaiting();
});

// Activate event
self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((cacheNames) => {
            return Promise.all(
                cacheNames
                    .filter((name) => name !== CACHE_NAME && name !== STATIC_CACHE)
                    .map((name) => caches.delete(name))
            );
        })
    );
    self.clients.claim();
});

// Fetch event - simple network-first strategy
self.addEventListener('fetch', (event) => {
    const url = new URL(event.request.url);

    // Skip checkout/cart/account paths
    if (url.pathname.startsWith('/checkout') ||
        url.pathname.startsWith('/cart') ||
        url.pathname.startsWith('/account')) {
        return;
    }

    event.respondWith(
        fetch(event.request)
            .then((response) => {
                // Clone and cache successful responses
                if (response.ok) {
                    const clone = response.clone();
                    caches.open(CACHE_NAME).then((cache) => {
                        cache.put(event.request, clone);
                    });
                }
                return response;
            })
            .catch(() => {
                // Fallback to cache
                return caches.match(event.request);
            })
    );
});

// Message handler
self.addEventListener('message', (event) => {
    if (event.data === 'skipWaiting') {
        self.skipWaiting();
    }
});
