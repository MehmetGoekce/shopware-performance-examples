/**
 * Tests für chapters/13-continuous-testing/ (Lighthouse CI)
 *
 * Die Konfigurationen liefen gegen Shopware 6.6.10.6 mit @lhci/cli 0.15.1;
 * diese Tests halten fest, was dabei schiefging:
 * - assertMatrix neben assertions bricht ab
 * - ohne aggregationMethod zählt der beste von drei Läufen
 * - "npx lhci" ohne installiertes @lhci/cli lädt ein fremdes Paket (Exit 0)
 * - context.setCookies gibt es im puppeteerScript nicht
 * - ab der zweiten URL ist der Browser schon eingeloggt
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const __dirname = dirname(fileURLToPath(import.meta.url));
const chapter = resolve(__dirname, '../../chapters/13-continuous-testing');
const require = createRequire(import.meta.url);
const known = new Set(
    JSON.parse(readFileSync(resolve(__dirname, 'fixtures/lighthouse-12.6.1-audits.json'), 'utf8')).audits
);

const read = (file) => readFileSync(resolve(chapter, file), 'utf8');

/** Lädt eine .cjs-Konfiguration frisch, damit LHCI_BASE_URL greift. */
function load(file, baseUrl) {
    const env = process.env.LHCI_BASE_URL;
    if (baseUrl === undefined) delete process.env.LHCI_BASE_URL;
    else process.env.LHCI_BASE_URL = baseUrl;
    for (const key of Object.keys(require.cache)) {
        if (key.startsWith(chapter)) delete require.cache[key];
    }
    try {
        return require(resolve(chapter, file));
    } finally {
        if (env === undefined) delete process.env.LHCI_BASE_URL;
        else process.env.LHCI_BASE_URL = env;
    }
}

/** Audit-IDs ohne "categories:", "resource-summary:…" auf die Audit-ID gekürzt. */
function unknownAudits(assertions) {
    return Object.keys(assertions)
        .filter((id) => !id.startsWith('categories:'))
        .map((id) => id.split(':')[0])
        .filter((id) => !known.has(id));
}

describe('config/lighthouserc.cjs', () => {
    const rc = load('config/lighthouserc.cjs', 'https://staging.example.ch/');

    it('kennt jedes Audit, auf das es sich beruft', () => {
        expect(unknownAudits(rc.ci.assert.assertions)).toEqual([]);
    });

    it('baut die URLs aus LHCI_BASE_URL, ohne doppelten Slash', () => {
        expect(rc.ci.collect.url[0]).toBe('https://staging.example.ch/');
        expect(rc.ci.collect.url.every((u) => u.startsWith('https://staging.example.ch/'))).toBe(true);
        expect(rc.ci.collect.url.some((u) => u.includes('.ch//'))).toBe(false);
    });

    it('fällt ohne LHCI_BASE_URL auf http://localhost zurück', () => {
        expect(load('config/lighthouserc.cjs').ci.collect.url[0]).toBe('http://localhost/');
    });

    it('nutzt SEO-URLs statt /navigation/<name> und /detail/<name> (400)', () => {
        expect(rc.ci.collect.url.filter((u) => /\/(navigation|detail)\//.test(u))).toEqual([]);
    });

    it('wertet den Median-Lauf, nicht den besten', () => {
        expect(rc.ci.assert.aggregationMethod).toBe('median-run');
    });

    it('kennt nur Presets, die es gibt', () => {
        expect(['desktop', 'perf', 'experimental', undefined]).toContain(rc.ci.collect.settings.preset);
    });

    it('schreibt manifest.json für den PR-Kommentar (filesystem)', () => {
        expect(rc.ci.upload).toEqual({ target: 'filesystem', outputDir: '.lighthouseci' });
    });

    it('lässt die Kern-Metriken den Build brechen', () => {
        const a = rc.ci.assert.assertions;
        expect(a['largest-contentful-paint']).toEqual(['error', { maxNumericValue: 2500 }]);
        expect(a['cumulative-layout-shift']).toEqual(['error', { maxNumericValue: 0.1 }]);
        expect(a['total-blocking-time']).toEqual(['error', { maxNumericValue: 300 }]);
        expect(a['resource-summary:script:size']).toEqual(['error', { maxNumericValue: 300000 }]);
    });
});

describe('config/lighthouserc.matrix.cjs', () => {
    const rc = load('config/lighthouserc.matrix.cjs', 'https://staging.example.ch');
    const matrix = rc.ci.assert.assertMatrix;
    const urls = rc.ci.collect.url;
    const assertionsFor = (url) => matrix
        .filter((entry) => new RegExp(entry.matchingUrlPattern).test(url))
        .flatMap((entry) => Object.keys(entry.assertions));

    it('setzt neben assertMatrix nichts anderes (LHCI bricht sonst ab)', () => {
        expect(Object.keys(rc.ci.assert)).toEqual(['assertMatrix']);
    });

    it('kennt jedes Audit, auf das es sich beruft', () => {
        expect(matrix.flatMap((entry) => unknownAudits(entry.assertions))).toEqual([]);
    });

    it('wertet in jedem Eintrag den Median-Lauf', () => {
        expect(matrix.map((entry) => entry.aggregationMethod)).toEqual(matrix.map(() => 'median-run'));
    });

    it('prüft SEO nur auf indexierbaren Seiten', () => {
        const seo = urls.filter((url) => assertionsFor(url).includes('categories:seo'));
        expect(seo).toEqual(urls.filter((url) => !/\/(search|checkout)/.test(url)));
        expect(seo.length).toBe(3);
    });

    it('prüft auf jeder URL die Kern-Metriken', () => {
        for (const url of urls) {
            expect(assertionsFor(url)).toEqual(expect.arrayContaining([
                'largest-contentful-paint', 'cumulative-layout-shift', 'total-blocking-time',
            ]));
        }
    });

    it('trifft mit dem Startseiten-Muster nur die Startseite', () => {
        const home = matrix.find((entry) => entry.assertions['first-contentful-paint']?.[0] === 'error');
        expect(urls.filter((url) => new RegExp(home.matchingUrlPattern).test(url)))
            .toEqual(['https://staging.example.ch/']);
    });
});

describe('config/lighthouserc.auth.cjs + scripts/lhci-shopware-auth.cjs', () => {
    const rc = load('config/lighthouserc.auth.cjs', 'https://staging.example.ch');

    it('verweist auf ein Skript, das es gibt (Pfad relativ zum Kapitelordner)', () => {
        expect(existsSync(resolve(chapter, rc.ci.collect.puppeteerScript))).toBe(true);
    });

    it('übernimmt Budgets und Upload aus lighthouserc.cjs', () => {
        const base = load('config/lighthouserc.cjs');
        expect(rc.ci.assert).toEqual(base.ci.assert);
        expect(rc.ci.upload).toEqual(base.ci.upload);
    });

    describe('Login-Skript', () => {
        let env;
        beforeEach(() => {
            env = { ...process.env };
            process.env.SHOPWARE_TEST_EMAIL = 'test@example.com';
            process.env.SHOPWARE_TEST_PASSWORD = 'geheim';
        });
        afterEach(() => { process.env = env; });

        /** Browser-Stub: protokolliert Aufrufe, URL nach goto/Submit wählbar. */
        function browserStub({ afterGoto, afterSubmit }) {
            const calls = [];
            let url = 'about:blank';
            const page = {
                goto: async (u) => { calls.push(['goto', u]); url = afterGoto ?? u; },
                url: () => url,
                type: async (sel, text) => { calls.push(['type', sel, text]); },
                click: async (sel) => { calls.push(['click', sel]); url = afterSubmit; },
                waitForNavigation: async () => { calls.push(['waitForNavigation']); },
                close: async () => { calls.push(['close']); },
            };
            return { calls, browser: { newPage: async () => page } };
        }
        const script = () => load('scripts/lhci-shopware-auth.cjs');
        const context = { url: 'https://staging.example.ch/account/order', options: {} };

        it('meldet sich mit den Selektoren der Storefront an', async () => {
            const { calls, browser } = browserStub({ afterSubmit: 'https://staging.example.ch/account' });
            await script()(browser, context);
            expect(calls).toEqual([
                ['goto', 'https://staging.example.ch/account/login'],
                ['type', '#loginMail', 'test@example.com'],
                ['type', '#loginPassword', 'geheim'],
                ['waitForNavigation'],
                ['click', '.login-submit button[type="submit"]'],
                ['close'],
            ]);
        });

        it('tippt nichts, wenn der Browser schon eingeloggt ist (zweite URL)', async () => {
            const { calls, browser } = browserStub({ afterGoto: 'https://staging.example.ch/account' });
            await script()(browser, context);
            expect(calls.map((c) => c[0])).toEqual(['goto', 'close']);
        });

        it('bricht ab, wenn Shopware auf der Login-Seite bleibt', async () => {
            const { browser } = browserStub({ afterSubmit: 'https://staging.example.ch/account/login' });
            await expect(script()(browser, context)).rejects.toThrow('Login fehlgeschlagen');
        });

        it('bricht ohne Zugangsdaten ab, bevor es den Browser anfasst', async () => {
            delete process.env.SHOPWARE_TEST_PASSWORD;
            const { calls, browser } = browserStub({});
            await expect(script()(browser, context)).rejects.toThrow('SHOPWARE_TEST_PASSWORD');
            expect(calls).toEqual([]);
        });

        it('kennt kein context.setCookies (gibt es in LHCI nicht)', () => {
            expect(read('scripts/lhci-shopware-auth.cjs')).not.toMatch(/setCookies/);
        });
    });
});

describe('config/budget.json', () => {
    const budgets = JSON.parse(read('config/budget.json'));

    it('ist ein Array (LHCI lehnt ein Objekt ab)', () => {
        expect(Array.isArray(budgets)).toBe(true);
    });

    it('kennt jede Metrik', () => {
        const metrics = budgets.flatMap((b) => (b.timings || []).map((t) => t.metric));
        expect(metrics.filter((m) => !known.has(m))).toEqual([]);
    });
});

describe('Workflows, GitLab, Compose', () => {
    const files = {
        pr: read('.github/workflows/lighthouse-ci.yml'),
        staging: read('.github/workflows/lighthouse-staging.yml'),
        gitlab: read('gitlab/gitlab-ci.yml'),
    };

    it('ruft nie "npx lhci" auf (fremdes npm-Paket, Exit 0)', () => {
        // Kommentarzeilen (#, *, //) dürfen davor warnen
        const code = [...Object.values(files), read('config/lighthouserc.cjs')].join('\n')
            .split('\n').filter((line) => !/^\s*(#|\*|\/\/)/.test(line));
        expect(code.filter((line) => /npx\s+lhci/.test(line))).toEqual([]);
    });

    it('installiert überall dieselbe LHCI-Version', () => {
        for (const text of Object.values(files)) {
            expect(text).toMatch(/npm install -g @lhci\/cli@0\.15\.1\n/);
        }
    });

    it('nutzt keine Actions mehr, die auf node20 laufen', () => {
        const all = files.pr + files.staging;
        expect(all).not.toMatch(/actions\/(checkout|setup-node)@v[1-4]\b/);
        expect(all).not.toMatch(/actions\/github-script@v[1-7]\b/);
        expect(all).not.toMatch(/actions\/upload-artifact@v[1-5]\b/);
        expect(all).not.toMatch(/slackapi\/slack-github-action@v[1-3]\b/);
    });

    it('gibt dem Token nur die Rechte, die der Kommentar braucht', () => {
        expect(files.pr).toMatch(/permissions:\n {2}contents: read\n {2}pull-requests: write\n/);
    });

    it('kommentiert auch nach einer Regression', () => {
        expect(files.pr).toMatch(/- name: Comment PR with results\n\s+if: always\(\)\n/);
    });

    it('misst nach dem Deployment die URL der Umgebung, nicht den Log-Link', () => {
        expect(files.staging).toMatch(/LHCI_BASE_URL: \$\{\{ github\.event\.deployment_status\.environment_url \}\}/);
        expect(files.staging).not.toMatch(/deployment_status\.target_url/);
    });

    it('GitLab: rules statt only, Chrome ohne Sandbox als root', () => {
        expect(files.gitlab).toMatch(/\n {2}rules:\n/);
        expect(files.gitlab).not.toMatch(/\n {2}only:/);
        expect(files.gitlab).toMatch(/lhci autorun --collect\.settings\.chromeFlags="--no-sandbox"/);
    });

    it('Compose: gepinntes Image, Passwort Pflicht, kein version-Schlüssel', () => {
        const compose = read('docker/docker-compose.yml');
        expect(compose).toMatch(/image: patrickhulce\/lhci-server:0\.15\.1\n/);
        expect(compose).toMatch(/LHCI_BASIC_AUTH__PASSWORD: \$\{LHCI_PASSWORD:\?/);
        expect(compose).not.toMatch(/^version:/m);
    });
});
