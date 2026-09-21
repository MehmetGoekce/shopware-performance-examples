/**
 * Tests für chapters/05-css-javascript/scripts/coverage-analysis.js
 * und chapters/05-css-javascript/scripts/third-party-audit.js
 *
 * Führt die Companion-Dateien selbst aus (node:vm) – mit Resource-Timing-
 * Einträgen, wie Chromium sie für die Shopware-Storefront meldet
 * (Dockware 6.6.10.6). Keine nachgebaute Logik.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import vm from 'node:vm';

const __dirname = dirname(fileURLToPath(import.meta.url));
const load = name => readFileSync(
    resolve(__dirname, '../../chapters/05-css-javascript/scripts/', name),
    'utf8'
);
const coverageCode = load('coverage-analysis.js');
const thirdPartyCode = load('third-party-audit.js');

const THEME = 'https://shop.example/theme/cf8b9edb6e403de212cbc40ca597f790';

// Ein Eintrag, wie ihn performance.getEntriesByType('resource') liefert.
// Ohne Timing-Allow-Origin setzt der Browser responseStart und alle
// Grössen auf 0.
// initiatorType: 'script' für <script> (auch Webpack-Chunks), 'link' für
// Stylesheets, 'css' für Schriften aus dem CSS.
function res(name, { kb = 1, raw = kb * 3, status = 'non-blocking', tao = true, end = 100, type = 'img' } = {}) {
    return {
        name,
        initiatorType: type,
        renderBlockingStatus: status,
        responseStart: tao ? 50 : 0,
        responseEnd: end,
        duration: end - 10,
        encodedBodySize: tao ? kb * 1024 : 0,
        decodedBodySize: tao ? raw * 1024 : 0,
    };
}

function script(src, { type = '', async = false, defer = false, head = true } = {}) {
    return { src, type, async, defer, closest: sel => (sel === 'head' && head ? {} : null) };
}

// console.table wird je nach Lage 1- bis 3-mal aufgerufen
const tableWith = (out, key) => out.tables.find(t => t.length > 0 && key in t[0]);

function run(code, resources, scripts = []) {
    const logs = [];
    const tables = [];
    const context = {
        URL,
        location: { hostname: 'shop.example' },
        performance: { getEntriesByType: () => resources },
        document: { querySelectorAll: () => scripts },
        console: {
            log: (...a) => logs.push(a.join(' ')),
            table: rows => tables.push(rows),
        },
    };
    vm.runInNewContext(code, context);
    return { logs, tables };
}

// Startseite ab Werk: all.css blockiert, storefront.js mit defer,
// dazu ein Chunk der Storefront und das JavaScript eines Plugins
const storefront = [
    res(`${THEME}/css/all.css?1790010011`, { kb: 55.5, raw: 391.1, status: 'blocking', type: 'link' }),
    res(`${THEME}/js/storefront/storefront.js?1790010011`, { kb: 74.2, raw: 229.9, type: 'script' }),
    res(`${THEME}/js/storefront/storefront.cart-widget.plugin.49e687.js`, { kb: 1.3, raw: 4.1, type: 'script' }),
    res(`${THEME}/js/swag-paypal/swag-paypal.js?1790010011`, { kb: 12, raw: 40, type: 'script' }),
    res('https://shop.example/media/12/g0/96/1753443509/favicon.png', { kb: 2, type: 'link' }),
    res(`${THEME}/assets/font/Inter-Regular.woff2`, { kb: 90, type: 'css' }),
    res('https://shop.example/widgets/checkout/info', { kb: 3, type: 'fetch' }),
];

describe('coverage-analysis.js', () => {
    describe('render-blockierende Dateien', () => {
        it('meldet, was der Browser als blocking markiert', () => {
            const out = run(coverageCode, storefront);
            expect(out.logs).toContain('⚠️ 1 render-blockierende Datei(en):');
            expect(out.tables[0]).toEqual([{ Datei: 'css/all.css', KB: 56, ms: 90 }]);
        });

        it('meldet nichts, wenn all.css per preload/onload kommt', () => {
            const out = run(coverageCode, storefront.map(r => ({ ...r, renderBlockingStatus: 'non-blocking' })));
            expect(out.logs).toContain('✅ Keine render-blockierende Datei.');
        });

        it('zeigt «?» statt 0 KB bei fremden Dateien ohne Timing-Allow-Origin', () => {
            const out = run(coverageCode, [res('https://tag.example/t.js', { status: 'blocking', tao: false })]);
            expect(out.tables[0]).toEqual([{ Datei: 'tag.example/t.js', KB: '?', ms: 90 }]);
        });

        it('sagt, wenn der Browser das Feld nicht kennt (Firefox, Safari)', () => {
            const firefox = storefront.map(({ renderBlockingStatus: _status, ...r }) => r);
            const out = run(coverageCode, firefox);
            expect(out.logs[0]).toContain('meldet renderBlockingStatus nicht');
            expect(out.logs.join('\n')).not.toContain('Keine render-blockierende');
        });
    });

    describe('Bundles', () => {
        const bundles = () => tableWith(run(coverageCode, storefront), 'Bundle');

        it('fasst das JavaScript je Theme/Plugin-Verzeichnis zusammen', () => {
            expect(bundles()).toContainEqual({ Bundle: 'storefront', Dateien: 2, KB: 76, roh: 234 });
            expect(bundles()).toContainEqual({ Bundle: 'swag-paypal', Dateien: 1, KB: 12, roh: 40 });
        });

        it('führt CSS mit Dateinamen und lässt Bilder, Schriften und fetch weg', () => {
            expect(bundles()).toContainEqual({ Bundle: 'all.css', Dateien: 1, KB: 56, roh: 391 });
            expect(bundles()).toHaveLength(3);
        });

        it('sortiert nach übertragener Grösse', () => {
            expect(bundles().map(b => b.Bundle)).toEqual(['storefront', 'all.css', 'swag-paypal']);
        });

        it('trennt bekannte und unbekannte Grössen je fremdem Host', () => {
            const out = run(coverageCode, [
                res('https://www.googletagmanager.com/gtag/js?id=G-1', { tao: false, type: 'script' }),
                res('https://connect.facebook.net/en_US/fbevents.js', { kb: 30, raw: 100, type: 'script' }),
                res('https://connect.facebook.net/signals/config/1.js', { tao: false, type: 'script' }),
                res('https://www.facebook.com/tr/?id=1&ev=PageView', { tao: false }),
            ]);
            expect(tableWith(out, 'Bundle')).toEqual([
                { Bundle: 'connect.facebook.net', Dateien: 2, KB: '30 +?', roh: '100 +?' },
                { Bundle: 'www.googletagmanager.com', Dateien: 1, KB: '?', roh: '?' },
            ]);
        });
    });

    describe('Skript-Einbindung', () => {
        it('zählt defer, async und module und listet Skripte ohne beides', () => {
            const out = run(coverageCode, [], [
                script(`${THEME}/js/storefront/storefront.js`, { defer: true }),
                script('https://www.googletagmanager.com/gtm.js', { async: true }),
                script('https://tag.example/both.js', { async: true, defer: true }),
                script('/vite/runtime.js', { type: 'module' }),
                script('https://widget.example/chat.js', { head: false }),
            ]);
            expect(out.logs).toContain('Skripte: 1 defer, 2 async, 1 module, 1 ohne');
            expect(tableWith(out, 'Skript')).toEqual([{ Skript: 'https://widget.example/chat.js', Ort: 'body' }]);
        });
    });
});

describe('third-party-audit.js', () => {
    it('ignoriert den eigenen Host', () => {
        const out = run(thirdPartyCode, storefront);
        expect(out.logs).toEqual(['Keine Ressourcen von fremden Hosts.']);
    });

    it('führt eigene Subdomains als fremd', () => {
        const out = run(thirdPartyCode, [res('https://cdn.shop.example/a.js')]);
        expect(out.tables[0][0].Host).toBe('cdn.shop.example');
    });

    it('zeigt Grösse nur mit Timing-Allow-Origin, Ende und Blockieren immer', () => {
        const out = run(thirdPartyCode, [
            res('https://www.googletagmanager.com/gtag/js?id=G-1', { tao: false, end: 900 }),
            res('https://www.googletagmanager.com/gtm.js?id=GTM-1', { tao: false, status: 'blocking', end: 400 }),
            res('https://connect.facebook.net/en_US/fbevents.js', { kb: 30, end: 1200 }),
            res('https://connect.facebook.net/tr?id=1', { tao: false, end: 1300 }),
        ]);
        expect(out.tables[0]).toEqual([
            { Host: 'www.googletagmanager.com', Dateien: 2, KB: '?', blockierend: 1, 'fertig nach ms': 900 },
            { Host: 'connect.facebook.net', Dateien: 2, KB: '30 +?', blockierend: 0, 'fertig nach ms': 1300 },
        ]);
    });
});
