/**
 * Keine GitHub Actions mehr, die auf node20 oder älter laufen (MEM-315).
 *
 * Geprüft wird jede Zeile "uses: <action>@<major>" in allen YAML- und
 * Markdown-Dateien des Repos: die eigene CI (.github/workflows/test.yml)
 * und alle Vorlagen, die ein Leser ins Shop-Repository kopiert.
 *
 * Grenzen aus der action.yml des jeweiligen Tags ("runs.using"), 2026-09-22:
 * checkout, setup-node: node24 ab v5 · cache: ab v5 · github-script: ab v8 ·
 * upload-artifact: ab v6 (v5 noch node20) · slack-github-action: ab v4.
 * bats-core/bats-action (auch 4.0.0) nutzt intern actions/cache@v4.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'fs';
import { resolve, dirname, relative, join } from 'path';
import { fileURLToPath } from 'url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SKIP = new Set(['node_modules', '.git', 'vendor', 'coverage', 'playwright-report', '.phpunit.cache']);

function files(dir) {
    return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const path = join(dir, entry.name);
        if (entry.isDirectory()) {
            return SKIP.has(entry.name) ? [] : files(path);
        }
        return /\.(ya?ml|md)$/.test(entry.name) ? [path] : [];
    });
}

const OUTDATED = [
    /uses:\s*actions\/(checkout|setup-node|cache)@v[1-4]\b/,
    /uses:\s*actions\/github-script@v[1-7]\b/,
    /uses:\s*actions\/upload-artifact@v[1-5]\b/,
    /uses:\s*slackapi\/slack-github-action@v[1-3]\b/,
    /uses:\s*bats-core\/bats-action@/,
];

function findings(text, file) {
    return text.split('\n').flatMap((line, i) =>
        OUTDATED.some((re) => re.test(line)) ? [`${file}:${i + 1}: ${line.trim()}`] : []
    );
}

describe('GitHub Actions (MEM-315)', () => {
    const all = files(root);

    it('findet die eigene CI und die Kapitel-Workflows', () => {
        const names = all.map((f) => relative(root, f));
        expect(names).toContain('.github/workflows/test.yml');
        expect(names).toContain('chapters/03-core-web-vitals/.github/workflows/lighthouse.yml');
        expect(names).toContain('chapters/13-continuous-testing/.github/workflows/lighthouse-ci.yml');
        expect(names).toContain('chapters/21-third-party-scripts/EXAMPLES.md');
    });

    it('nutzt nirgends einen Major, der auf node20 oder älter läuft', () => {
        const hits = all.flatMap((f) => findings(readFileSync(f, 'utf8'), relative(root, f)));
        expect(hits).toEqual([]);
    });

    it('erkennt die alten Majors (Gegenprobe)', () => {
        const sample = [
            '- uses: actions/checkout@v4',
            '  uses: actions/setup-node@v3',
            '  uses: actions/cache@v4',
            '  uses: actions/github-script@v7',
            '  uses: actions/upload-artifact@v5',
            '  uses: slackapi/slack-github-action@v1',
            '  uses: bats-core/bats-action@2.0.0',
            '- uses: actions/checkout@v7',
            '  uses: actions/github-script@v9',
            '  uses: actions/upload-artifact@v7',
            '  uses: actions/cache@v6',
        ].join('\n');
        expect(findings(sample, 'x')).toHaveLength(7);
    });
});
