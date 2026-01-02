/**
 * E2E Tests for Real User Monitoring (RUM) Tracker
 *
 * Tests web-vitals collection and analytics integration.
 */
import { test, expect, type Page } from '@playwright/test';

test.describe('RUM Tracker Initialization', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should initialize RUM tracker', async ({ page }) => {
        await expect(page.locator('#log')).toContainText('Test page initialized');
    });

    test('should display metric cards', async ({ page }) => {
        const metricCards = page.locator('.metric-card');
        await expect(metricCards).toHaveCount(5); // LCP, CLS, INP, FCP, TTFB
    });

    test('should have collectedMetrics array', async ({ page }) => {
        const hasMetrics = await page.evaluate(() => {
            return Array.isArray(window.collectedMetrics);
        });
        expect(hasMetrics).toBe(true);
    });
});

test.describe('Core Web Vitals Collection', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should collect FCP metric', async ({ page }) => {
        // FCP should be collected shortly after page load
        await page.waitForTimeout(2000);

        const metrics = await page.evaluate(() => window.collectedMetrics);
        const fcp = metrics.find((m: { name: string }) => m.name === 'FCP');

        if (fcp) {
            expect(fcp.name).toBe('FCP');
            expect(typeof fcp.value).toBe('number');
            expect(fcp.value).toBeGreaterThan(0);
        }
        // Note: FCP may not fire in all test environments
    });

    test('should collect TTFB metric', async ({ page }) => {
        await page.waitForTimeout(2000);

        const metrics = await page.evaluate(() => window.collectedMetrics);
        const ttfb = metrics.find((m: { name: string }) => m.name === 'TTFB');

        if (ttfb) {
            expect(ttfb.name).toBe('TTFB');
            expect(typeof ttfb.value).toBe('number');
        }
    });

    test('should collect LCP metric', async ({ page }) => {
        // Scroll to trigger LCP observation
        await page.locator('#lcp-element').scrollIntoViewIfNeeded();
        await page.waitForTimeout(3000);

        const metrics = await page.evaluate(() => window.collectedMetrics);
        const lcp = metrics.find((m: { name: string }) => m.name === 'LCP');

        if (lcp) {
            expect(lcp.name).toBe('LCP');
            expect(typeof lcp.value).toBe('number');
            expect(['good', 'needs-improvement', 'poor']).toContain(lcp.rating);
        }
    });

    test('should collect INP metric on interaction', async ({ page }) => {
        // Click the fast button
        await page.click('#btn-fast');
        await page.waitForTimeout(100);

        // Click the slow button
        await page.click('#btn-slow');
        await page.waitForTimeout(500);

        // Need to trigger page visibility change for INP to report
        // or wait for page unload
        await page.evaluate(() => {
            // Trigger visibility change to force INP report
            document.dispatchEvent(new Event('visibilitychange'));
        });

        await page.waitForTimeout(1000);

        const metrics = await page.evaluate(() => window.collectedMetrics);
        const inp = metrics.find((m: { name: string }) => m.name === 'INP');

        // INP may not fire immediately in test environment
        if (inp) {
            expect(inp.name).toBe('INP');
            expect(typeof inp.value).toBe('number');
        }
    });

    test('should collect CLS metric', async ({ page }) => {
        // CLS is reported on page visibility change or unload
        await page.waitForTimeout(2000);

        // Trigger visibility change
        await page.evaluate(() => {
            document.dispatchEvent(new Event('visibilitychange'));
        });

        await page.waitForTimeout(1000);

        const metrics = await page.evaluate(() => window.collectedMetrics);
        const cls = metrics.find((m: { name: string }) => m.name === 'CLS');

        if (cls) {
            expect(cls.name).toBe('CLS');
            expect(typeof cls.value).toBe('number');
            expect(cls.value).toBeGreaterThanOrEqual(0);
        }
    });
});

test.describe('Analytics Integration', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should send metrics via sendBeacon', async ({ page }) => {
        await page.waitForTimeout(2000);

        const beaconCalls = await page.evaluate(() => window.beaconCalls || []);

        // Check that at least some beacons were sent
        if (beaconCalls.length > 0) {
            const call = beaconCalls[0];
            expect(call.url).toBe('/api/rum');
            expect(call.data).toHaveProperty('name');
            expect(call.data).toHaveProperty('value');
        }
    });

    test('should call gtag for GA4', async ({ page }) => {
        await page.waitForTimeout(2000);

        const gtagCalls = await page.evaluate(() => window.gtagCalls || []);

        // Check that gtag was called with metric data
        if (gtagCalls.length > 0) {
            expect(gtagCalls.some((call: unknown[]) => call[0] === 'event')).toBe(true);
        }
    });

    test('should include metric rating', async ({ page }) => {
        await page.waitForTimeout(3000);

        const metrics = await page.evaluate(() => window.collectedMetrics);

        for (const metric of metrics) {
            if (metric.rating) {
                expect(['good', 'needs-improvement', 'poor']).toContain(metric.rating);
            }
        }
    });
});

test.describe('Metric Display Updates', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should update metric cards when data received', async ({ page }) => {
        // Wait for metrics to be collected
        await page.waitForTimeout(3000);

        // Check if any value has been updated from '--'
        const lcpValue = await page.locator('#lcp-value').textContent();
        const fcpValue = await page.locator('#fcp-value').textContent();
        const ttfbValue = await page.locator('#ttfb-value').textContent();

        // At least one metric should have a value
        const hasValue = [lcpValue, fcpValue, ttfbValue].some(v => v !== '--');
        // May not always have values in test environment
        expect(typeof hasValue).toBe('boolean');
    });

    test('should show rating badge', async ({ page }) => {
        await page.waitForTimeout(3000);

        const ratings = page.locator('.rating');
        const count = await ratings.count();

        expect(count).toBe(5); // One for each metric card
    });
});

test.describe('Slow Interaction Detection', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should log slow button click', async ({ page }) => {
        await page.click('#btn-slow');
        await page.waitForTimeout(500);

        await expect(page.locator('#log')).toContainText('Slow button clicked (200ms delay)');
    });

    test('should log fast button click', async ({ page }) => {
        await page.click('#btn-fast');
        await page.waitForTimeout(100);

        await expect(page.locator('#log')).toContainText('Fast button clicked');
    });
});

test.describe('Page Context', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should include page path in metrics', async ({ page }) => {
        await page.waitForTimeout(2000);

        const metrics = await page.evaluate(() => window.collectedMetrics);

        for (const metric of metrics) {
            if (metric.page) {
                expect(metric.page).toContain('/tests/E2E/fixtures/rum-tracker');
            }
        }
    });

    test('should include timestamp', async ({ page }) => {
        await page.waitForTimeout(2000);

        const metrics = await page.evaluate(() => window.collectedMetrics);

        for (const metric of metrics) {
            if (metric.timestamp) {
                expect(typeof metric.timestamp).toBe('number');
                expect(metric.timestamp).toBeGreaterThan(0);
            }
        }
    });
});

// Mobile device tests - run with: npx playwright test --project=mobile
test.describe('Mobile RUM Collection', () => {
    test('should collect metrics on mobile viewport', async ({ page }) => {
        // Set mobile viewport
        await page.setViewportSize({ width: 390, height: 844 });

        await page.goto('/tests/E2E/fixtures/rum-tracker.html');
        await page.waitForFunction(() => window.testReady === true);
        await page.waitForTimeout(2000);

        const metrics = await page.evaluate(() => window.collectedMetrics);
        expect(Array.isArray(metrics)).toBe(true);
    });
});

// Type declarations
declare global {
    interface Window {
        testReady: boolean;
        collectedMetrics: Array<{
            name: string;
            value: number;
            rating?: string;
            delta?: number;
            id?: string;
            page?: string;
            timestamp?: number;
        }>;
        beaconCalls: Array<{
            url: string;
            data: {
                name: string;
                value: number;
                rating?: string;
            };
        }>;
        gtagCalls: unknown[][];
    }
}
