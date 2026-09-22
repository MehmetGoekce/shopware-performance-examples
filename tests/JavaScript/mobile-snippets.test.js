/**
 * Tests fuer die Snippets aus Kapitel 19 (yield-to-main.js, connection-hints.js).
 * Im Browser gegen Chromium, Firefox und WebKit geprueft, siehe README Kapitel 19.
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { applyInChunks, yieldToMain } from '../../chapters/19-mobile-performance/snippets/yield-to-main.js';
import { prefersReducedData } from '../../chapters/19-mobile-performance/snippets/connection-hints.js';

describe('yieldToMain', () => {
    afterEach(() => {
        delete globalThis.scheduler;
        vi.useRealTimers();
    });

    it('nutzt scheduler.yield, wenn vorhanden', async () => {
        const yieldFn = vi.fn(() => Promise.resolve('yielded'));
        globalThis.scheduler = { yield: yieldFn };
        await expect(yieldToMain()).resolves.toBe('yielded');
        expect(yieldFn).toHaveBeenCalledOnce();
    });

    it('faellt ohne scheduler.yield auf setTimeout zurueck', async () => {
        vi.useFakeTimers();
        let done = false;
        const p = yieldToMain().then(() => { done = true; });
        await Promise.resolve();
        expect(done).toBe(false);
        await vi.runAllTimersAsync();
        await p;
        expect(done).toBe(true);
    });

    it('faellt zurueck, wenn scheduler kein yield hat (aeltere Chromium-Versionen)', async () => {
        globalThis.scheduler = { postTask: () => {} };
        vi.useFakeTimers();
        const p = yieldToMain();
        await vi.runAllTimersAsync();
        await expect(p).resolves.toBeUndefined();
    });
});

describe('applyInChunks', () => {
    afterEach(() => {
        delete globalThis.scheduler;
    });

    it('setzt die Rueckmeldung vor der Arbeit und gibt je Portion ab', async () => {
        const log = [];
        globalThis.scheduler = { yield: () => { log.push('yield'); return Promise.resolve(); } };
        const classes = new Set();
        const button = { classList: { add: (c) => { classes.add(c); log.push('add'); }, remove: (c) => { classes.delete(c); log.push('remove'); } } };

        await applyInChunks(button, [1, 2, 3, 4, 5], (x) => log.push(`work${x}`), 2);

        expect(log).toEqual(['add', 'yield', 'work1', 'work2', 'yield', 'work3', 'work4', 'yield', 'work5', 'remove']);
        expect(classes.size).toBe(0);
    });
});

describe('prefersReducedData', () => {
    it('false ohne Network Information API (Firefox, Safari, iOS)', () => {
        expect(prefersReducedData({})).toBe(false);
        expect(prefersReducedData(undefined)).toBe(false);
    });

    it('true bei Datensparmodus', () => {
        expect(prefersReducedData({ connection: { saveData: true, effectiveType: '4g' } })).toBe(true);
    });

    it('true bei 2g und slow-2g, false bei 3g und 4g', () => {
        expect(prefersReducedData({ connection: { saveData: false, effectiveType: 'slow-2g' } })).toBe(true);
        expect(prefersReducedData({ connection: { saveData: false, effectiveType: '2g' } })).toBe(true);
        expect(prefersReducedData({ connection: { saveData: false, effectiveType: '3g' } })).toBe(false);
        expect(prefersReducedData({ connection: { saveData: false, effectiveType: '4g' } })).toBe(false);
    });
});
