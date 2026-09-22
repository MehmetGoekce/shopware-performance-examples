/**
 * Baut aus einer web-vitals-Metrik den Beacon fuer POST /rum.
 *
 * Eigene Datei ohne Browser-Globals, damit die Tests (Vitest) sie ohne DOM laden.
 * Die Attributions-Felder gelten fuer web-vitals 5 und 6; in 4 hiess das
 * LCP-Ziel noch "element" statt "target".
 */

/**
 * Das DOM-Element, das die Metrik verursacht hat, als CSS-Selektor.
 *
 * @param {{name: string, attribution?: object}} metric
 * @returns {string|null}
 */
export function attributionTarget(metric) {
    const attribution = metric.attribution || {};

    switch (metric.name) {
        case 'LCP':
            return attribution.target ?? null;
        case 'INP':
            return attribution.interactionTarget ?? null;
        case 'CLS':
            return attribution.largestShiftTarget ?? null;
        default:
            return null;
    }
}

/**
 * @param {{name: string, value: number, rating: string, navigationType: string, attribution?: object}} metric
 * @param {string} route         Shopware-Route der Seite, z. B. frontend.detail.page
 * @param {string} path          location.pathname
 * @param {number} viewportWidth window.innerWidth
 * @returns {object}
 */
export function buildPayload(metric, route, path, viewportWidth) {
    return {
        name: metric.name,
        value: metric.value,
        rating: metric.rating,
        navigationType: metric.navigationType,
        route,
        path,
        target: attributionTarget(metric),
        // Bootstrap-Grenze md (768 px) statt User-Agent-Raten
        device: viewportWidth < 768 ? 'mobile' : 'desktop',
    };
}

/**
 * Einmal je Seitenaufruf wuerfeln: ganz oder gar nicht, damit die Metriken
 * eines Aufrufs zusammenbleiben.
 *
 * @param {string|undefined} rate  Wert aus data-rum-sample-rate
 * @param {number} random          Math.random()
 * @returns {boolean}
 */
export function isSampled(rate, random) {
    const value = Number(rate);

    return Number.isFinite(value) && random < value;
}
