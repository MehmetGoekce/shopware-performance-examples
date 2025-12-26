/**
 * Real User Monitoring (RUM) Tracker
 *
 * Integriert web-vitals Library und sendet Metriken an Analytics.
 *
 * Installation:
 *   1. npm install web-vitals
 *   2. In Shopware Theme einbinden (siehe README)
 *
 * Oder als ES Module von CDN:
 *   <script type="module" src="rum-tracker.js"></script>
 */

// Import von CDN (für schnellen Start ohne Build-Prozess)
import {
    onCLS,
    onINP,
    onLCP,
    onFCP,
    onTTFB
} from 'https://unpkg.com/web-vitals@4/dist/web-vitals.attribution.js?module';

// =============================================================================
// Konfiguration
// =============================================================================

const CONFIG = {
    // Eigener RUM-Endpoint (optional)
    endpoint: '/api/rum',

    // Google Analytics 4 Event-Namen
    ga4: {
        enabled: typeof gtag !== 'undefined',
        eventName: 'web_vitals'
    },

    // Debug-Modus
    debug: false,

    // Sampling Rate (1 = 100%, 0.1 = 10%)
    samplingRate: 1,

    // Zusätzliche Dimensionen
    dimensions: {
        pageType: true,
        deviceType: true,
        connection: true,
        returningUser: true
    }
};

// =============================================================================
// Hilfsfunktionen
// =============================================================================

/**
 * Erkennt den Seitentyp basierend auf URL
 */
function detectPageType() {
    const path = window.location.pathname;

    if (path === '/' || path === '') return 'home';
    if (path.includes('/detail/')) return 'product';
    if (path.includes('/navigation/')) return 'category';
    if (path.includes('/search')) return 'search';
    if (path.includes('/checkout')) return 'checkout';
    if (path.includes('/account')) return 'account';
    if (path.includes('/wishlist')) return 'wishlist';

    return 'other';
}

/**
 * Erkennt den Gerätetyp
 */
function detectDeviceType() {
    const ua = navigator.userAgent;

    if (/Mobile|Android|iPhone|iPad|iPod/i.test(ua)) {
        if (/iPad/i.test(ua) || (navigator.maxTouchPoints > 1 && /Mac/i.test(ua))) {
            return 'tablet';
        }
        return 'mobile';
    }

    return 'desktop';
}

/**
 * Ermittelt die Verbindungsqualität
 */
function getConnectionType() {
    const connection = navigator.connection ||
                       navigator.mozConnection ||
                       navigator.webkitConnection;

    if (!connection) return 'unknown';

    return connection.effectiveType || 'unknown';
}

/**
 * Prüft ob Nutzer wiederkehrend ist
 */
function isReturningUser() {
    const key = 'rum_returning';
    const isReturning = localStorage.getItem(key) === 'true';
    localStorage.setItem(key, 'true');
    return isReturning;
}

/**
 * Sampling-Check
 */
function shouldSample() {
    return Math.random() < CONFIG.samplingRate;
}

// =============================================================================
// Daten senden
// =============================================================================

/**
 * Sendet Metriken an alle konfigurierten Ziele
 */
function sendToAnalytics(metric) {
    // Sampling
    if (!shouldSample()) {
        return;
    }

    // Basis-Daten
    const data = {
        // Core metric data
        name: metric.name,
        value: metric.value,
        rating: metric.rating,
        delta: metric.delta,
        id: metric.id,
        navigationType: metric.navigationType,

        // Page info
        page: window.location.pathname,
        url: window.location.href,

        // Timestamp
        timestamp: Date.now()
    };

    // Zusätzliche Dimensionen
    if (CONFIG.dimensions.pageType) {
        data.page_type = detectPageType();
    }
    if (CONFIG.dimensions.deviceType) {
        data.device_type = detectDeviceType();
    }
    if (CONFIG.dimensions.connection) {
        data.connection = getConnectionType();
    }
    if (CONFIG.dimensions.returningUser) {
        data.returning_user = isReturningUser();
    }

    // Attribution-Daten (für Debugging)
    if (metric.attribution) {
        data.attribution = extractAttribution(metric);
    }

    // Debug-Log
    if (CONFIG.debug) {
        console.log('[RUM]', metric.name, data);
    }

    // An Google Analytics 4 senden
    if (CONFIG.ga4.enabled) {
        sendToGA4(metric, data);
    }

    // An eigenen Endpoint senden
    if (CONFIG.endpoint) {
        sendToEndpoint(data);
    }
}

/**
 * Extrahiert relevante Attribution-Daten
 */
function extractAttribution(metric) {
    const attr = metric.attribution;

    switch (metric.name) {
        case 'LCP':
            return {
                element: attr.element || 'unknown',
                url: attr.url || null,
                timeToFirstByte: attr.timeToFirstByte,
                resourceLoadDelay: attr.resourceLoadDelay,
                resourceLoadTime: attr.resourceLoadTime,
                elementRenderDelay: attr.elementRenderDelay
            };

        case 'INP':
            return {
                eventTarget: attr.eventTarget || 'unknown',
                eventType: attr.eventType,
                inputDelay: attr.inputDelay,
                processingDuration: attr.processingDuration,
                presentationDelay: attr.presentationDelay
            };

        case 'CLS':
            return {
                largestShiftTarget: attr.largestShiftTarget || 'unknown',
                largestShiftValue: attr.largestShiftValue,
                largestShiftTime: attr.largestShiftTime
            };

        default:
            return {};
    }
}

/**
 * Sendet an Google Analytics 4
 */
function sendToGA4(metric, data) {
    try {
        gtag('event', metric.name, {
            // Wert (CLS * 1000 für bessere Lesbarkeit)
            value: Math.round(metric.name === 'CLS' ? metric.value * 1000 : metric.value),

            // Standard-Parameter
            metric_id: metric.id,
            metric_rating: metric.rating,
            metric_delta: Math.round(metric.delta),

            // Custom dimensions
            page_type: data.page_type,
            device_type: data.device_type,
            connection_type: data.connection,

            // Debug-Info
            debug_target: data.attribution?.element ||
                          data.attribution?.eventTarget ||
                          data.attribution?.largestShiftTarget ||
                          'unknown'
        });
    } catch (e) {
        console.error('[RUM] GA4 Error:', e);
    }
}

/**
 * Sendet an eigenen Endpoint via sendBeacon
 */
function sendToEndpoint(data) {
    try {
        // sendBeacon ist zuverlässiger bei Page Unload
        if (navigator.sendBeacon) {
            navigator.sendBeacon(CONFIG.endpoint, JSON.stringify(data));
        } else {
            // Fallback für ältere Browser
            fetch(CONFIG.endpoint, {
                method: 'POST',
                body: JSON.stringify(data),
                headers: {
                    'Content-Type': 'application/json'
                },
                keepalive: true
            });
        }
    } catch (e) {
        console.error('[RUM] Endpoint Error:', e);
    }
}

// =============================================================================
// Metriken registrieren
// =============================================================================

// Core Web Vitals (für Google Ranking relevant)
onCLS(sendToAnalytics);
onINP(sendToAnalytics);
onLCP(sendToAnalytics);

// Zusätzliche Metriken (empfohlen)
onFCP(sendToAnalytics);
onTTFB(sendToAnalytics);

// Initialisierung bestätigen
if (CONFIG.debug) {
    console.log('[RUM] Web Vitals Monitoring aktiv', {
        ga4: CONFIG.ga4.enabled,
        endpoint: CONFIG.endpoint,
        samplingRate: CONFIG.samplingRate
    });
}

// =============================================================================
// Export für erweiterte Nutzung
// =============================================================================

export { sendToAnalytics, CONFIG };
