/**
 * Tests für chapters/03-core-web-vitals/scripts/cwv-diagnostics.js
 *
 * Führt die Companion-Datei selbst aus (node:vm) – mit einem
 * PerformanceObserver-Stub, der die Einträge liefert, die Chromium
 * für LCP, Layout Shifts und Events meldet. Keine nachgebaute Logik.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import vm from 'node:vm';

const __dirname = dirname(fileURLToPath(import.meta.url));
const code = readFileSync(
    resolve(__dirname, '../../chapters/03-core-web-vitals/scripts/cwv-diagnostics.js'),
    'utf8'
);

function run(entriesByType, resources = []) {
    const logs = [];
    const tables = [];
    class PerformanceObserver {
        constructor(cb) { this.cb = cb; }
        observe({ type }) {
            // Chromium ruft den Callback nur mit mindestens einem Eintrag auf
            const entries = entriesByType[type] || [];
            if (entries.length > 0) {
                this.cb({ getEntries: () => entries });
            }
        }
    }
    const context = {
        PerformanceObserver,
        performance: { getEntriesByType: () => resources },
        console: {
            log: (...a) => logs.push(a.join(' ')),
            table: rows => tables.push(rows),
        },
    };
    vm.runInNewContext(code, context);
    return { logs, tables };
}

describe('cwv-diagnostics.js', () => {
    let out;

    describe('LCP', () => {
        beforeEach(() => {
            out = run({
                'largest-contentful-paint': [
                    { startTime: 120.4, element: 'H1', url: '', size: 5000 },
                    { startTime: 812.6, element: 'IMG', url: 'https://shop.example/hero.jpg', size: 339218 },
                ],
            });
        });

        it('meldet den letzten LCP-Kandidaten', () => {
            expect(out.logs).toContain('⏱️ LCP Time: 813ms');
            expect(out.logs).toContain('🖼️ LCP URL: https://shop.example/hero.jpg');
            expect(out.logs).not.toContain('⏱️ LCP Time: 120ms');
        });
    });

    describe('CLS', () => {
        it('ignoriert Shifts direkt nach einer Eingabe', () => {
            out = run({
                'layout-shift': [
                    { value: 0.0512, hadRecentInput: false, sources: [{ node: 'DIV.banner' }] },
                    { value: 0.3, hadRecentInput: true, sources: [] },
                ],
            });
            expect(out.logs).toContain('📊 Layout Shift: 0.0512');
            expect(out.logs).toContain('  -> Element: DIV.banner');
            expect(out.logs.join('\n')).not.toContain('0.3000');
        });
    });

    describe('INP', () => {
        beforeEach(() => {
            out = run({
                event: [
                    // Hover: interactionId 0, zählt nicht für INP
                    { name: 'mouseover', duration: 312, interactionId: 0, target: 'BODY' },
                    // Interaktion 7: drei Events, das längste zählt
                    { name: 'pointerdown', duration: 304, interactionId: 7, target: 'BUTTON' },
                    { name: 'pointerup', duration: 296, interactionId: 7, target: 'BUTTON' },
                    { name: 'click', duration: 304, interactionId: 7, target: 'BUTTON' },
                    // Interaktion 8: schnell
                    { name: 'keydown', duration: 48, interactionId: 8, target: 'INPUT' },
                    // Interaktion 9: genau an der Grenze – «gut» heisst ≤ 200 ms
                    { name: 'click', duration: 200, interactionId: 9, target: 'A' },
                ],
            });
        });

        const slow = () => out.logs.filter(l => l.startsWith('🐌'));

        it('meldet eine langsame Interaktion genau einmal', () => {
            expect(slow()).toEqual(['🐌 Slow Interaction: pointerdown 304ms BUTTON']);
        });

        it('zählt Events ohne interactionId nicht', () => {
            expect(out.logs.join('\n')).not.toContain('mouseover');
        });

        it('meldet 200 ms nicht (Schwelle «gut» ist ≤ 200 ms)', () => {
            expect(out.logs.join('\n')).not.toContain('200ms');
        });
    });

    describe('Ressourcen', () => {
        it('sortiert nach Grösse und nach Dauer, je höchstens 10', () => {
            const resources = Array.from({ length: 12 }, (_, i) => ({
                name: `https://shop.example/theme/abc/js/chunk-${i}.js?v=1`,
                transferSize: (i + 1) * 1024,
                duration: 100 - i,
                initiatorType: 'script',
            }));
            out = run({}, resources);
            expect(out.tables).toHaveLength(2);
            expect(out.tables[0]).toHaveLength(10);
            expect(out.tables[0][0]).toEqual({ Name: 'chunk-11.js', KB: 12, ms: 89, Typ: 'script' });
            expect(out.tables[1][0].Name).toBe('chunk-0.js');
        });
    });
});
