/**
 * Keine GitHub Actions mehr, die auf node20 oder älter laufen, und kein
 * Node.js unter 22 in den Vorlagen (MEM-315).
 *
 * Geprüft wird jede Zeile "uses: <action>@<ref>" in allen YAML- und
 * Markdown-Dateien des Repos: die eigene CI (.github/workflows/test.yml)
 * und alle Vorlagen, die ein Leser ins Shop-Repository kopiert.
 *
 * Jede Action muss in NODE24_FROM stehen. Eine neue Action scheitert, bis
 * ihr erster node24-Major nachgetragen ist ("runs.using" in der action.yml
 * des Tags, per gh api 'repos/<action>/contents/action.yml?ref=<tag>').
 * Stand 2026-09-22.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'fs';
import { resolve, dirname, relative, join } from 'path';
import { fileURLToPath } from 'url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SKIP = new Set(['node_modules', '.git', 'vendor', 'coverage', 'playwright-report', '.phpunit.cache']);

/** Erster Major mit "using: node24" (bzw. composite ohne node20-Actions: 0) */
const NODE24_FROM = {
    'actions/checkout': 5,
    'actions/setup-node': 5,
    'actions/cache': 5,
    'actions/github-script': 8,
    'actions/upload-artifact': 6, // v5 laeuft noch auf node20
    'actions/download-artifact': 7, // v6 laeuft noch auf node20
    'actions/labeler': 6,
    'actions/setup-python': 6,
    'shivammathur/setup-php': 2, // v2 ist ein mitlaufender Tag, heute node24
    'treosh/lighthouse-ci-action': 12,
    'slackapi/slack-github-action': 4,
    'ludeeus/action-shellcheck': 0, // composite, ohne weitere Actions
};

/** Composite-Actions, die intern node20-Actions aufrufen */
const BANNED = new Set(['bats-core/bats-action']); // auch 4.0.0: actions/cache@v4

const MIN_NODE = 22; // Node 20 ist seit 2026-04-30 EOL

function files(dir) {
    return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const path = join(dir, entry.name);
        if (entry.isDirectory()) {
            return SKIP.has(entry.name) ? [] : files(path);
        }
        return /\.(ya?ml|md)$/.test(entry.name) ? [path] : [];
    });
}

/**
 * Liefert für eine Zeile den Fehler oder null.
 */
export function checkLine(line) {
    const uses = line.match(/^\s*(?:-\s*)?uses:\s*["']?([^"'\s#]+)["']?\s*(?:#\s*(\S+))?/);
    if (uses) {
        const [, value, comment] = uses;
        if (value.startsWith('./') || value.startsWith('docker://')) {
            return null;
        }
        const [path, ref = ''] = value.toLowerCase().split('@');
        const action = path.split('/').slice(0, 2).join('/');
        if (BANNED.has(action)) {
            return `${action} nutzt intern node20-Actions`;
        }
        if (!(action in NODE24_FROM)) {
            return `${action} fehlt in NODE24_FROM`;
        }
        if (NODE24_FROM[action] === 0) {
            return null;
        }
        // SHA-Pin: die Version steht im Kommentar dahinter ("# v7.0.1")
        const version = /^[0-9a-f]{40}$/.test(ref) ? (comment ?? '') : ref;
        const major = version.match(/^v?(\d+)/);
        if (!major) {
            return `${action}@${ref}: keine Major-Version erkennbar`;
        }
        return Number(major[1]) < NODE24_FROM[action]
            ? `${action}@${ref} läuft auf node20 oder älter (node24 ab v${NODE24_FROM[action]})`
            : null;
    }

    const node = line.match(/node-version:\s*["']?(\d+)|image:\s*["']?node:(\d+)|FROM\s+node:(\d+)/);
    if (node) {
        const major = Number(node[1] ?? node[2] ?? node[3]);
        return major < MIN_NODE ? `Node.js ${major} (mindestens ${MIN_NODE})` : null;
    }

    return null;
}

function findings(text, file) {
    return text.split('\n').flatMap((line, i) => {
        const error = checkLine(line);
        return error ? [`${file}:${i + 1}: ${error}`] : [];
    });
}

describe('GitHub Actions und Node.js (MEM-315)', () => {
    const all = files(root);

    it('findet die eigene CI und die Kapitel-Workflows', () => {
        const names = all.map((f) => relative(root, f));
        expect(names).toContain('.github/workflows/test.yml');
        expect(names).toContain('chapters/03-core-web-vitals/.github/workflows/lighthouse.yml');
        expect(names).toContain('chapters/13-continuous-testing/.github/workflows/lighthouse-ci.yml');
        expect(names.some((n) => n.endsWith('.md'))).toBe(true);
    });

    it('nutzt nirgends einen Major, der auf node20 oder älter läuft, und kein Node.js unter 22', () => {
        const hits = all.flatMap((f) => findings(readFileSync(f, 'utf8'), relative(root, f)));
        expect(hits).toEqual([]);
    });

    it.each([
        '- uses: actions/checkout@v4',
        '  uses: "actions/checkout@v4"',
        "  uses: 'actions/checkout@v4'",
        '  uses: Actions/Checkout@v4',
        '  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2',
        '  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683',
        '  uses: actions/cache/restore@v4',
        '  uses: actions/upload-artifact@v5',
        '  uses: actions/download-artifact@v6',
        '  uses: actions/labeler@v5',
        '  uses: actions/github-script@v7',
        '  uses: treosh/lighthouse-ci-action@v11',
        '  uses: bats-core/bats-action@4.0.0',
        '  uses: some/unknown-action@v9',
        "  node-version: '20'",
        '  node-version: 18',
        '  image: node:20-slim',
    ])('schlägt an: %s', (line) => {
        expect(checkLine(line)).not.toBeNull();
    });

    it.each([
        '- uses: actions/checkout@v7',
        '  uses: "actions/checkout@v7.0.1"',
        '  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v7.0.1',
        '  uses: actions/cache/save@v6',
        '  uses: actions/upload-artifact@v7',
        '  uses: actions/github-script@v10',
        '  uses: shivammathur/setup-php@v2',
        '  uses: ludeeus/action-shellcheck@master',
        '  uses: ./.github/actions/local',
        '  uses: docker://alpine:3',
        "  node-version: '22'",
        '  node-version: 24',
        '  image: node:22-bookworm-slim',
    ])('lässt durch: %s', (line) => {
        expect(checkLine(line)).toBeNull();
    });
});
