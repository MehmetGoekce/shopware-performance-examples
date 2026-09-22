/**
 * Workflow-Vorlagen aus Kapitel 14 (labeler) und Kapitel 15 (Wartung), MEM-315.
 *
 * actionlint prüft Syntax und Ausdrücke; hier steht, was die Vorlagen
 * inhaltlich versprechen. Das Issue-Skript lief mit einem Stub für
 * github/context, "composer audit --locked" mit Composer 2.8, die Globs mit
 * minimatch 10.2.5 (Version der labeler-Action v7.0.0).
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const chapters = resolve(dirname(fileURLToPath(import.meta.url)), '../../chapters');
const read = (path) => readFileSync(resolve(chapters, path), 'utf8');

describe('Kapitel 14: labeler', () => {
    const workflow = read('14-performance-kultur/config/labeler-workflow.yml');
    const config = read('14-performance-kultur/config/labeler.yml');

    it('läuft auf pull_request_target mit genau den nötigen Rechten', () => {
        expect(workflow).toMatch(/on:\n {2}pull_request_target:\n/);
        expect(workflow).toMatch(/permissions:\n {6}contents: read\n {6}pull-requests: write\n {4}steps:/);
        expect(workflow).toMatch(/- uses: actions\/labeler@v7\n/);
    });

    it('checkt bei pull_request_target keinen Code aus dem Pull Request aus', () => {
        expect(workflow).not.toMatch(/actions\/checkout/);
        expect(workflow).not.toMatch(/\brun:/);
    });

    it('nutzt Pfade eines Shopware-Projekts, nicht die des Shopware-Core', () => {
        expect(config).toMatch(/'custom\/\{plugins,static-plugins\}\/\*\/src\/Resources\/views\/\*\*\/\*\.twig'/);
        expect(config).toMatch(/'custom\/\{plugins,static-plugins\}\/\*\/src\/Resources\/app\/storefront\/\*\*\/\*\.\{js,ts,scss\}'/);
        expect(config).not.toMatch(/'src\/(Storefront|Core)\//);
    });

    it('markiert auch PHP-Änderungen (DAL, Subscriber) zum Review', () => {
        const review = config.split('performance-review-needed:')[1];
        expect(review).toMatch(/'custom\/\{plugins,static-plugins\}\/\*\/src\/\*\*\/\*\.php'/);
    });

    it('nutzt das Konfigurationsformat ab labeler v5', () => {
        expect(config.match(/- changed-files:\n\s+- any-glob-to-any-file:/g)).toHaveLength(2);
    });
});

describe('Kapitel 15: Wartungs-Workflow', () => {
    const workflow = read('15-langfristiger-plan/config/maintenance-workflow.yml');

    it('läuft wöchentlich und auf Knopfdruck', () => {
        expect(workflow).toMatch(/schedule:\n\s+- cron: '0 6 \* \* 1'/);
        expect(workflow).toMatch(/workflow_dispatch:/);
    });

    it('prüft composer.lock, ohne etwas zu installieren', () => {
        expect(workflow).toMatch(/run: composer audit --locked\n/);
        expect(workflow).not.toMatch(/composer (install|update|require)\b/);
    });

    it('misst mit fester LHCI-Version gegen LHCI_BASE_URL, nie mit "npx lhci"', () => {
        expect(workflow).toMatch(/npm install -g @lhci\/cli@0\.15\.1\n/);
        expect(workflow).toMatch(/LHCI_BASE_URL: \$\{\{ vars\.LHCI_BASE_URL \}\}/);
        const code = workflow.split('\n').filter((line) => !/^\s*#/.test(line));
        expect(code.filter((line) => /npx\s+lhci/.test(line))).toEqual([]);
    });

    it('lädt .lighthouseci/ wirklich hoch (versteckter Ordner) und auch nach Fehlern', () => {
        expect(workflow).toMatch(/- name: Upload reports\n\s+if: always\(\)\n\s+uses: actions\/upload-artifact@v7\n\s+with:\n\s+name: \S+\n\s+path: \.lighthouseci\/\n(\s+#.*\n)?\s+include-hidden-files: true\n/);
    });

    it('legt ein Issue an, wenn einer der beiden Jobs scheitert, und nur dieser Job darf Issues schreiben', () => {
        const job = workflow.split('  create-issue:')[1];
        expect(job).toMatch(/needs: \[dependency-audit, lighthouse-baseline\]\n\s+if: failure\(\)/);
        expect(job).toMatch(/permissions:\n\s+issues: write\n/);
        expect(job).toMatch(/uses: actions\/github-script@v9\n/);
        expect(workflow).toMatch(/^permissions:\n {2}contents: read\n/m);
        expect(workflow).not.toMatch(/write-all/);
        expect(workflow.split('  create-issue:')[0]).not.toMatch(/:\s*write\b/);
    });

    it('kommentiert ein offenes Wartungs-Issue, statt jede Woche ein neues anzulegen', () => {
        const job = workflow.split('  create-issue:')[1];
        expect(job).toMatch(/github\.rest\.issues\.listForRepo\(\{[^}]*labels: 'maintenance',\s*state: 'open',/);
        expect(job).toMatch(/github\.rest\.issues\.createComment\(/);
    });

    it('hat keinen SSH-Zugang zur Produktion', () => {
        expect(workflow).not.toMatch(/\bssh\b/);
        expect(workflow).not.toMatch(/secrets\./);
    });
});
