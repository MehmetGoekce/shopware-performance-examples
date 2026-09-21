/**
 * Tests für chapters/03-core-web-vitals/lighthouserc.json und das
 * Workflow-Beispiel .github/workflows/lighthouse.yml
 *
 * Lighthouse CI meldet eine Zusicherung auf ein unbekanntes Audit nur
 * als Warnung – die Prüfung fällt dann still weg. Deshalb wird jede
 * Audit-ID gegen die Liste der Lighthouse-Version gehalten, die
 * @lhci/cli 0.15.1 mitbringt (12.6.1).
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const chapter = resolve(__dirname, '../../chapters/03-core-web-vitals');
const rc = JSON.parse(readFileSync(resolve(chapter, 'lighthouserc.json'), 'utf8'));
const known = new Set(
    JSON.parse(readFileSync(resolve(__dirname, 'fixtures/lighthouse-12.6.1-audits.json'), 'utf8')).audits
);
const workflow = readFileSync(resolve(chapter, '.github/workflows/lighthouse.yml'), 'utf8');

describe('lighthouserc.json (Kapitel 3)', () => {
    const assertions = rc.ci.assert.assertions;

    it('kennt jedes Audit, auf das es sich beruft', () => {
        const unknown = Object.keys(assertions)
            .filter(id => !id.startsWith('categories:'))
            .filter(id => !known.has(id));
        expect(unknown).toEqual([]);
    });

    it('misst mobil (kein Desktop-Preset)', () => {
        const settings = rc.ci.collect.settings || {};
        expect(settings.preset).toBeUndefined();
        expect(settings.formFactor ?? 'mobile').toBe('mobile');
    });

    it('lässt ein lazy geladenes LCP-Bild scheitern', () => {
        expect(assertions['lcp-lazy-loaded']).toEqual(['error', { minScore: 1 }]);
    });

    it('hält die Schwellen aus dem Kapitel ein', () => {
        expect(assertions['cumulative-layout-shift'][1].maxNumericValue).toBe(0.1);
        expect(assertions['largest-contentful-paint'][1].maxNumericValue).toBe(2500);
    });

    it('lädt Berichte nicht öffentlich hoch', () => {
        expect(rc.ci.upload.target).not.toBe('temporary-public-storage');
    });
});

describe('lighthouse.yml (Kapitel 3)', () => {
    it('nutzt treosh/lighthouse-ci-action v12 mit der Kapitel-Konfiguration', () => {
        expect(workflow).toMatch(/uses: treosh\/lighthouse-ci-action@v12\n/);
        expect(workflow).toMatch(/configPath: \.\/lighthouserc\.json\n/);
    });

    it('lädt nicht öffentlich hoch', () => {
        expect(workflow).not.toMatch(/temporaryPublicStorage:\s*true/);
    });
});
