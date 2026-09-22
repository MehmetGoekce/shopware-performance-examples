/**
 * Tests fuer chapters/12-real-user-monitoring/RumMonitoring/src/Resources/public/rum-payload.js
 *
 * Die Attributions-Felder stammen aus web-vitals 6.2.2 (dist/modules/types/*.d.ts).
 * In web-vitals 4 hiess das LCP-Ziel "element", in 3 das INP-Ziel "eventTarget" -
 * genau diese Namen standen in der alten Kapitelfassung und lieferten "unknown".
 */
import { describe, it, expect } from 'vitest';
import {
    attributionTarget,
    buildPayload,
    isSampled,
} from '../../chapters/12-real-user-monitoring/RumMonitoring/src/Resources/public/rum-payload.js';

const metric = (name, attribution) => ({
    name,
    value: 1234.5,
    rating: 'needs-improvement',
    navigationType: 'navigate',
    attribution,
});

describe('attributionTarget', () => {
    it('liest das Ziel je Metrik aus dem Feld, das web-vitals 5/6 dafuer nutzt', () => {
        expect(attributionTarget(metric('LCP', { target: 'img.hero' }))).toBe('img.hero');
        expect(attributionTarget(metric('INP', { interactionTarget: 'button.buy' }))).toBe('button.buy');
        expect(attributionTarget(metric('CLS', { largestShiftTarget: 'div.banner' }))).toBe('div.banner');
    });

    it('nimmt keine Feldnamen aus aelteren Versionen', () => {
        expect(attributionTarget(metric('LCP', { element: 'img.hero' }))).toBeNull();
        expect(attributionTarget(metric('INP', { eventTarget: 'button.buy' }))).toBeNull();
    });

    it('liefert null ohne Attribution und fuer FCP/TTFB', () => {
        expect(attributionTarget(metric('LCP', undefined))).toBeNull();
        expect(attributionTarget(metric('FCP', { target: 'x' }))).toBeNull();
        expect(attributionTarget(metric('TTFB', {}))).toBeNull();
    });
});

describe('buildPayload', () => {
    it('schickt nur die Felder, die der Controller erwartet', () => {
        const payload = buildPayload(
            { ...metric('LCP', { target: 'img.hero' }), entries: [{ big: 'x' }], id: 'v6-123' },
            'frontend.detail.page',
            '/Main-product/SWDEMO10001',
            390,
        );

        expect(payload).toEqual({
            name: 'LCP',
            value: 1234.5,
            rating: 'needs-improvement',
            navigationType: 'navigate',
            route: 'frontend.detail.page',
            path: '/Main-product/SWDEMO10001',
            target: 'img.hero',
            device: 'mobile',
        });
    });

    it('trennt mobile und desktop an 768 px', () => {
        expect(buildPayload(metric('FCP'), 'r', '/', 767).device).toBe('mobile');
        expect(buildPayload(metric('FCP'), 'r', '/', 768).device).toBe('desktop');
    });
});

describe('isSampled', () => {
    it('nimmt bei Rate 1 jeden Aufruf und bei 0 keinen', () => {
        expect(isSampled('1', 0.9999)).toBe(true);
        expect(isSampled('0', 0)).toBe(false);
    });

    it('vergleicht strikt kleiner', () => {
        expect(isSampled('0.1', 0.0999)).toBe(true);
        expect(isSampled('0.1', 0.1)).toBe(false);
    });

    it('sampelt nicht bei fehlender oder kaputter Rate', () => {
        expect(isSampled(undefined, 0)).toBe(false);
        expect(isSampled('abc', 0)).toBe(false);
    });
});
