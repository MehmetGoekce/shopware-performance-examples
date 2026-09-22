import { test, expect } from '@playwright/test';

/**
 * Kapitel 19: yield-to-main.js und connection-hints.js im echten Browser.
 * Laeuft in allen Projekten der playwright.config.ts (Chromium, Pixel 5,
 * iPhone 12 = WebKit): WebKit hat weder scheduler.yield noch
 * navigator.connection, dort muss der Rueckfall greifen.
 */
test.describe('Kapitel 19 Snippets', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/mobile-snippets.html');
        await page.waitForFunction(() => (window as any).snippetsReady === true);
    });

    test('yieldToMain loest auf, mit oder ohne scheduler.yield', async ({ page, browserName }) => {
        const result = await page.evaluate(async () => {
            const hasYield = typeof (globalThis as any).scheduler?.yield === 'function';
            await (window as any).snippets.yieldToMain();
            return { hasYield, resolved: true };
        });

        expect(result.resolved).toBe(true);
        if (browserName === 'webkit') {
            expect(result.hasYield).toBe(false);
        }
    });

    test('applyInChunks: Ladezustand steht vor der ersten Arbeit, danach weg', async ({ page }) => {
        const result = await page.evaluate(async () => {
            const button = document.getElementById('filter')!;
            const seen: boolean[] = [];
            await (window as any).snippets.applyInChunks(
                button,
                Array.from({ length: 120 }, (_, i) => i),
                () => seen.push(button.classList.contains('is-loading')),
                50,
            );
            return { all: seen.every(Boolean), count: seen.length, after: button.classList.contains('is-loading') };
        });

        expect(result).toEqual({ all: true, count: 120, after: false });
    });

    test('prefersReducedData ist ohne Network Information API false', async ({ page, browserName }) => {
        const result = await page.evaluate(() => ({
            hasConnection: 'connection' in navigator,
            reduced: (window as any).snippets.prefersReducedData(),
        }));

        if (browserName === 'webkit') {
            expect(result.hasConnection).toBe(false);
        }
        expect(result.reduced).toBe(false);
    });
});
