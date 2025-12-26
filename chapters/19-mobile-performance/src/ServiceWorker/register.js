/**
 * Service Worker Registration for Shopware 6
 *
 * Include this script in your theme to register the service worker.
 * Handles registration, updates, and provides utility functions.
 *
 * Usage:
 *   Import in your main.js or include as separate script:
 *   <script src="/path/to/register.js" type="module"></script>
 */

const SW_PATH = '/sw.js';
const SW_SCOPE = '/';

// ============================================
// Registration
// ============================================

export async function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) {
        console.log('[SW] Service Workers not supported');
        return null;
    }

    try {
        const registration = await navigator.serviceWorker.register(SW_PATH, {
            scope: SW_SCOPE,
        });

        console.log('[SW] Registered with scope:', registration.scope);

        // Handle updates
        registration.addEventListener('updatefound', () => {
            handleUpdateFound(registration);
        });

        // Check for updates periodically (every hour)
        setInterval(() => {
            registration.update();
        }, 60 * 60 * 1000);

        return registration;
    } catch (error) {
        console.error('[SW] Registration failed:', error);
        return null;
    }
}

// ============================================
// Update Handling
// ============================================

function handleUpdateFound(registration) {
    const newWorker = registration.installing;

    if (!newWorker) return;

    console.log('[SW] Update found, installing...');

    newWorker.addEventListener('statechange', () => {
        if (newWorker.state === 'installed') {
            if (navigator.serviceWorker.controller) {
                // New SW available, show update notification
                console.log('[SW] New version available');
                showUpdateNotification(newWorker);
            } else {
                // First install, content cached
                console.log('[SW] Content cached for offline use');
                showOfflineReadyNotification();
            }
        }
    });
}

// ============================================
// UI Notifications
// ============================================

function showUpdateNotification(newWorker) {
    // Create update banner
    const banner = document.createElement('div');
    banner.className = 'sw-update-banner';
    banner.innerHTML = `
        <div class="sw-update-content">
            <span>Eine neue Version ist verfügbar.</span>
            <button class="sw-update-btn" id="sw-update-btn">
                Aktualisieren
            </button>
            <button class="sw-update-dismiss" id="sw-dismiss-btn">
                ×
            </button>
        </div>
    `;

    // Add styles
    const style = document.createElement('style');
    style.textContent = `
        .sw-update-banner {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: #1a1a1a;
            color: white;
            padding: 12px 16px;
            z-index: 10000;
            animation: slideUp 0.3s ease;
        }

        @keyframes slideUp {
            from { transform: translateY(100%); }
            to { transform: translateY(0); }
        }

        .sw-update-content {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 16px;
            max-width: 600px;
            margin: 0 auto;
        }

        .sw-update-btn {
            background: #0070f3;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-weight: bold;
        }

        .sw-update-btn:hover {
            background: #0060df;
        }

        .sw-update-dismiss {
            background: none;
            border: none;
            color: white;
            font-size: 24px;
            cursor: pointer;
            padding: 0 8px;
        }
    `;

    document.head.appendChild(style);
    document.body.appendChild(banner);

    // Update button handler
    document.getElementById('sw-update-btn').addEventListener('click', () => {
        newWorker.postMessage({ type: 'SKIP_WAITING' });
        banner.remove();
    });

    // Dismiss button handler
    document.getElementById('sw-dismiss-btn').addEventListener('click', () => {
        banner.remove();
    });

    // Listen for controller change
    navigator.serviceWorker.addEventListener('controllerchange', () => {
        window.location.reload();
    });
}

function showOfflineReadyNotification() {
    // Create toast notification
    const toast = document.createElement('div');
    toast.className = 'sw-offline-toast';
    toast.innerHTML = `
        <span>✓ Shop ist jetzt offline verfügbar</span>
    `;

    const style = document.createElement('style');
    style.textContent = `
        .sw-offline-toast {
            position: fixed;
            bottom: 20px;
            left: 50%;
            transform: translateX(-50%);
            background: #10b981;
            color: white;
            padding: 12px 24px;
            border-radius: 8px;
            z-index: 10000;
            animation: fadeInOut 4s ease;
        }

        @keyframes fadeInOut {
            0% { opacity: 0; transform: translateX(-50%) translateY(20px); }
            15% { opacity: 1; transform: translateX(-50%) translateY(0); }
            85% { opacity: 1; transform: translateX(-50%) translateY(0); }
            100% { opacity: 0; transform: translateX(-50%) translateY(-20px); }
        }
    `;

    document.head.appendChild(style);
    document.body.appendChild(toast);

    setTimeout(() => toast.remove(), 4000);
}

// ============================================
// Utility Functions
// ============================================

/**
 * Check if app can work offline
 */
export async function isOfflineReady() {
    if (!('caches' in window)) return false;

    const cache = await caches.open('static-v1.0.0');
    const keys = await cache.keys();
    return keys.length > 0;
}

/**
 * Clear all caches (useful for debugging)
 */
export async function clearAllCaches() {
    if (!('caches' in window)) return;

    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((name) => caches.delete(name)));
    console.log('[SW] All caches cleared');
}

/**
 * Unregister service worker
 */
export async function unregisterServiceWorker() {
    if (!('serviceWorker' in navigator)) return;

    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((reg) => reg.unregister()));
    console.log('[SW] Service worker unregistered');
}

/**
 * Request notification permission
 */
export async function requestNotificationPermission() {
    if (!('Notification' in window)) {
        console.log('[SW] Notifications not supported');
        return 'denied';
    }

    const permission = await Notification.requestPermission();
    console.log('[SW] Notification permission:', permission);
    return permission;
}

// ============================================
// Auto-register on load
// ============================================

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', registerServiceWorker);
} else {
    registerServiceWorker();
}
