/**
 * Real User Monitoring fuer die Shopware-Storefront (Kapitel 12).
 *
 * Eingebunden ueber views/storefront/layout/meta.html.twig. web-vitals liegt
 * als Datei daneben: feste Version, kein Dritt-CDN, keine Besucher-IP bei
 * einem fremden Anbieter.
 *
 * Jede Metrik geht einzeln per sendBeacon an POST /rum. web-vitals meldet LCP,
 * CLS und INP erst, wenn die Seite in den Hintergrund geht - genau dann, wenn
 * ein normaler fetch() abgebrochen wuerde.
 */
import { onCLS, onFCP, onINP, onLCP, onTTFB } from './web-vitals.attribution.js';
import { buildPayload, isSampled } from './rum-payload.js';

const script = document.querySelector('script[data-rum-endpoint]');

if (script && isSampled(script.dataset.rumSampleRate, Math.random())) {
    const send = (metric) => {
        const body = JSON.stringify(
            buildPayload(metric, script.dataset.rumRoute, location.pathname, window.innerWidth)
        );

        // sendBeacon liefert false, wenn der Browser die Warteschlange voll hat
        if (!navigator.sendBeacon(script.dataset.rumEndpoint, body)) {
            fetch(script.dataset.rumEndpoint, { method: 'POST', body, keepalive: true }).catch(() => {});
        }
    };

    onLCP(send);
    onINP(send);
    onCLS(send);
    onFCP(send);
    onTTFB(send);
}
