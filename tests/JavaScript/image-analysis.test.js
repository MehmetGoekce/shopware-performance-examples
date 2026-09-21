/**
 * Tests für chapters/04-image-optimization/scripts/image-analysis.js
 *
 * Führt die Companion-Datei selbst aus (node:vm) mit einem minimalen
 * DOM: document.images, devicePixelRatio, Image (echte Pixelbreite je
 * URL) und Resource-Timing-Einträgen.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import vm from 'node:vm';

const __dirname = dirname(fileURLToPath(import.meta.url));
const code = readFileSync(
    resolve(__dirname, '../../chapters/04-image-optimization/scripts/image-analysis.js'),
    'utf8'
);

async function run({ dpr, images, fileWidths, sizes = {} }) {
    const tables = [];
    class Image {
        set src(url) { this.url = url; }
        get src() { return this.url; }
        decode() { return Promise.resolve(); }
        get naturalWidth() { return fileWidths[this.url]; }
    }
    const context = {
        window: { devicePixelRatio: dpr },
        document: {
            images: images.map(i => ({
                currentSrc: i.currentSrc,
                clientWidth: i.clientWidth,
                // naturalWidth absichtlich dichtekorrigiert – darf nicht verwendet werden
                naturalWidth: i.clientWidth,
                src: 'https://shop.example/media/original.jpg?ts=1',
                getAttribute: name => (name === 'loading' ? i.loading ?? null : null),
            })),
        },
        Image,
        performance: {
            getEntriesByName: url => (sizes[url] !== undefined ? [{ encodedBodySize: sizes[url] }] : []),
        },
        console: { table: rows => tables.push(rows) },
        Number,
        Math,
    };
    vm.createContext(context);
    vm.runInContext(code, context);
    const rows = await vm.runInContext('analyzeImages()', context);
    return { rows, tables };
}

const T1920 = 'https://shop.example/thumbnail/a/b/c/1/produkt_1920x1920.jpg?ts=2';
const T800 = 'https://shop.example/thumbnail/a/b/c/1/produkt_800x800.jpg?ts=2';

describe('image-analysis.js', () => {
    it('vergleicht die echte Dateibreite mit Anzeigebreite × Pixeldichte', async () => {
        const { rows } = await run({
            dpr: 2.625,
            images: [{ currentSrc: T1920, clientWidth: 298, loading: 'lazy' }],
            fileWidths: { [T1920]: 1920 },
            sizes: { [T1920]: 435200 },
        });
        expect(rows).toEqual([{
            Datei: 'produkt_1920x1920.jpg',
            'Anzeige px': 782,
            'Datei px': 1920,
            Faktor: 2.5,
            KB: 425,
            loading: 'lazy',
        }]);
    });

    it('meldet ein passendes Bild mit Faktor 1', async () => {
        const { rows } = await run({
            dpr: 2.625,
            images: [{ currentSrc: T800, clientWidth: 298 }],
            fileWidths: { [T800]: 800 },
        });
        expect(rows[0].Faktor).toBe(1);
        expect(rows[0].loading).toBe('(kein Attribut)');
        expect(rows[0].KB).toBeNull();
    });

    it('überspringt nicht geladene und unsichtbare Bilder', async () => {
        const { rows, tables } = await run({
            dpr: 1,
            images: [
                { currentSrc: '', clientWidth: 300 },
                { currentSrc: T800, clientWidth: 0 },
                { currentSrc: T800, clientWidth: 400 },
            ],
            fileWidths: { [T800]: 800 },
        });
        expect(rows).toHaveLength(1);
        expect(rows[0].Faktor).toBe(2);
        expect(tables).toHaveLength(2); // Aufruf in der Datei + Aufruf im Test
    });
});
