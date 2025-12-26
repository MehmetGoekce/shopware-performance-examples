/**
 * Service Worker for Shopware 6 Mobile Performance
 *
 * Implements various caching strategies optimized for e-commerce:
 * - Cache First: Static assets (CSS, JS, fonts)
 * - Network First: API calls, dynamic content
 * - Stale While Revalidate: Product images
 * - Network Only: Checkout, cart, account (always fresh)
 *
 * @see https://developer.chrome.com/docs/workbox/caching-strategies-overview/
 */

const CACHE_VERSION = 'v1.0.0';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `dynamic-${CACHE_VERSION}`;
const IMAGE_CACHE = `images-${CACHE_VERSION}`;

// Maximum cache sizes
const MAX_DYNAMIC_CACHE_SIZE = 50;
const MAX_IMAGE_CACHE_SIZE = 100;

// Assets to pre-cache during installation
const PRECACHE_ASSETS = [
    '/',
    '/manifest.json',
    '/offline.html',
    // Add your theme assets here
    // '/theme/css/all.min.css',
    // '/theme/js/all.min.js',
];

// Paths that should never be cached (always network)
const NETWORK_ONLY_PATHS = [
    '/checkout',
    '/cart',
    '/account',
    '/store-api/checkout',
    '/store-api/cart',
    '/api/',
    '/admin',
];

// Paths for API calls (network first)
const API_PATHS = [
    '/store-api/',
    '/sales-channel-api/',
];

// ============================================
// Installation
// ============================================

self.addEventListener('install', (event) => {
    console.log('[SW] Installing Service Worker...');

    event.waitUntil(
        caches.open(STATIC_CACHE)
            .then((cache) => {
                console.log('[SW] Pre-caching static assets');
                return cache.addAll(PRECACHE_ASSETS);
            })
            .then(() => {
                console.log('[SW] Skip waiting');
                return self.skipWaiting();
            })
            .catch((error) => {
                console.error('[SW] Pre-cache failed:', error);
            })
    );
});

// ============================================
// Activation
// ============================================

self.addEventListener('activate', (event) => {
    console.log('[SW] Activating Service Worker...');

    event.waitUntil(
        caches.keys()
            .then((cacheNames) => {
                return Promise.all(
                    cacheNames
                        .filter((name) => {
                            // Delete old versioned caches
                            return name.startsWith('static-') ||
                                   name.startsWith('dynamic-') ||
                                   name.startsWith('images-');
                        })
                        .filter((name) => {
                            return name !== STATIC_CACHE &&
                                   name !== DYNAMIC_CACHE &&
                                   name !== IMAGE_CACHE;
                        })
                        .map((name) => {
                            console.log('[SW] Deleting old cache:', name);
                            return caches.delete(name);
                        })
                );
            })
            .then(() => {
                console.log('[SW] Claiming clients');
                return self.clients.claim();
            })
    );
});

// ============================================
// Fetch Handling
// ============================================

self.addEventListener('fetch', (event) => {
    const { request } = event;
    const url = new URL(request.url);

    // Only handle same-origin requests
    if (url.origin !== location.origin) {
        return;
    }

    // Skip non-GET requests
    if (request.method !== 'GET') {
        return;
    }

    // Network Only: Checkout, Cart, Account
    if (isNetworkOnlyPath(url.pathname)) {
        return; // Let browser handle normally
    }

    // API Calls: Network First
    if (isApiPath(url.pathname)) {
        event.respondWith(networkFirst(request, DYNAMIC_CACHE));
        return;
    }

    // Static Assets: Cache First
    if (isStaticAsset(request)) {
        event.respondWith(cacheFirst(request, STATIC_CACHE));
        return;
    }

    // Images: Stale While Revalidate
    if (request.destination === 'image') {
        event.respondWith(staleWhileRevalidate(request, IMAGE_CACHE));
        return;
    }

    // HTML Pages: Network First with Offline Fallback
    if (request.mode === 'navigate') {
        event.respondWith(networkFirstWithOffline(request));
        return;
    }

    // Default: Network First
    event.respondWith(networkFirst(request, DYNAMIC_CACHE));
});

// ============================================
// Caching Strategies
// ============================================

/**
 * Cache First Strategy
 * Best for: Static assets that rarely change (CSS, JS, fonts)
 */
async function cacheFirst(request, cacheName) {
    const cachedResponse = await caches.match(request);

    if (cachedResponse) {
        return cachedResponse;
    }

    try {
        const networkResponse = await fetch(request);

        if (networkResponse.ok) {
            const cache = await caches.open(cacheName);
            cache.put(request, networkResponse.clone());
        }

        return networkResponse;
    } catch (error) {
        console.error('[SW] Cache First failed:', error);
        throw error;
    }
}

/**
 * Network First Strategy
 * Best for: API calls, dynamic content
 */
async function networkFirst(request, cacheName) {
    try {
        const networkResponse = await fetch(request);

        if (networkResponse.ok) {
            const cache = await caches.open(cacheName);
            cache.put(request, networkResponse.clone());

            // Limit cache size
            limitCacheSize(cacheName, MAX_DYNAMIC_CACHE_SIZE);
        }

        return networkResponse;
    } catch (error) {
        console.log('[SW] Network failed, trying cache:', request.url);
        const cachedResponse = await caches.match(request);

        if (cachedResponse) {
            return cachedResponse;
        }

        throw error;
    }
}

/**
 * Stale While Revalidate Strategy
 * Best for: Images, product listings (show cached, update in background)
 */
async function staleWhileRevalidate(request, cacheName) {
    const cache = await caches.open(cacheName);
    const cachedResponse = await cache.match(request);

    // Fetch in background
    const fetchPromise = fetch(request)
        .then((networkResponse) => {
            if (networkResponse.ok) {
                cache.put(request, networkResponse.clone());
                limitCacheSize(cacheName, MAX_IMAGE_CACHE_SIZE);
            }
            return networkResponse;
        })
        .catch((error) => {
            console.log('[SW] Background fetch failed:', error);
            return cachedResponse;
        });

    // Return cached immediately, or wait for network
    return cachedResponse || fetchPromise;
}

/**
 * Network First with Offline Fallback
 * Best for: HTML pages
 */
async function networkFirstWithOffline(request) {
    try {
        const networkResponse = await fetch(request);

        if (networkResponse.ok) {
            const cache = await caches.open(DYNAMIC_CACHE);
            cache.put(request, networkResponse.clone());
        }

        return networkResponse;
    } catch (error) {
        console.log('[SW] Page fetch failed, trying cache:', request.url);

        const cachedResponse = await caches.match(request);
        if (cachedResponse) {
            return cachedResponse;
        }

        // Return offline page
        return caches.match('/offline.html');
    }
}

// ============================================
// Helper Functions
// ============================================

function isNetworkOnlyPath(pathname) {
    return NETWORK_ONLY_PATHS.some((path) => pathname.startsWith(path));
}

function isApiPath(pathname) {
    return API_PATHS.some((path) => pathname.startsWith(path));
}

function isStaticAsset(request) {
    const destination = request.destination;
    return destination === 'style' ||
           destination === 'script' ||
           destination === 'font' ||
           destination === 'manifest';
}

async function limitCacheSize(cacheName, maxSize) {
    const cache = await caches.open(cacheName);
    const keys = await cache.keys();

    if (keys.length > maxSize) {
        // Delete oldest entries (FIFO)
        const toDelete = keys.slice(0, keys.length - maxSize);
        await Promise.all(toDelete.map((key) => cache.delete(key)));
    }
}

// ============================================
// Background Sync (Optional)
// ============================================

self.addEventListener('sync', (event) => {
    console.log('[SW] Background sync:', event.tag);

    if (event.tag === 'sync-wishlist') {
        event.waitUntil(syncWishlist());
    }

    if (event.tag === 'sync-cart') {
        event.waitUntil(syncCart());
    }
});

async function syncWishlist() {
    // Implement wishlist sync logic
    console.log('[SW] Syncing wishlist...');
}

async function syncCart() {
    // Implement cart sync logic
    console.log('[SW] Syncing cart...');
}

// ============================================
// Push Notifications (Optional)
// ============================================

self.addEventListener('push', (event) => {
    console.log('[SW] Push received:', event);

    if (!event.data) return;

    const data = event.data.json();

    const options = {
        body: data.body || 'Neue Nachricht',
        icon: '/icons/icon-192x192.png',
        badge: '/icons/badge-72x72.png',
        vibrate: [100, 50, 100],
        data: {
            url: data.url || '/',
        },
        actions: [
            { action: 'open', title: 'Öffnen' },
            { action: 'close', title: 'Schließen' },
        ],
    };

    event.waitUntil(
        self.registration.showNotification(data.title || 'Mein Shop', options)
    );
});

self.addEventListener('notificationclick', (event) => {
    console.log('[SW] Notification click:', event.action);

    event.notification.close();

    if (event.action === 'close') return;

    const url = event.notification.data?.url || '/';

    event.waitUntil(
        clients.matchAll({ type: 'window' })
            .then((clientList) => {
                // Focus existing window if open
                for (const client of clientList) {
                    if (client.url === url && 'focus' in client) {
                        return client.focus();
                    }
                }
                // Open new window
                if (clients.openWindow) {
                    return clients.openWindow(url);
                }
            })
    );
});
