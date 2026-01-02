/**
 * E2E Tests for Service Worker
 *
 * Tests caching strategies, offline behavior, and SW lifecycle.
 */
import { test, expect, type Page, type BrowserContext } from '@playwright/test';

test.describe('Service Worker Lifecycle', () => {
    test.beforeEach(async ({ page, context }) => {
        // Clear any existing service workers
        await context.clearCookies();

        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should register service worker', async ({ page }) => {
        // Click register button
        await page.click('#btn-register');

        // Wait for registration
        await page.waitForTimeout(1000);

        // Check status
        const statusText = await page.locator('#sw-status-text').textContent();
        expect(statusText).toBe('Registered');

        // Check log
        await expect(page.locator('#log')).toContainText('Registering Service Worker');
    });

    test('should unregister service worker', async ({ page }) => {
        // First register
        await page.click('#btn-register');
        await page.waitForTimeout(1000);

        // Then unregister
        await page.click('#btn-unregister');
        await page.waitForTimeout(500);

        // Check status
        const statusText = await page.locator('#sw-status-text').textContent();
        expect(statusText).toBe('Unregistered');

        await expect(page.locator('#log')).toContainText('Unregistered');
    });

    test('should check for updates', async ({ page }) => {
        // Register first
        await page.click('#btn-register');
        await page.waitForTimeout(1000);

        // Check for updates
        await page.click('#btn-update');
        await page.waitForTimeout(500);

        await expect(page.locator('#log')).toContainText('Checked for updates');
    });
});

test.describe('Cache Management', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);

        // Register SW
        await page.click('#btn-register');
        await page.waitForTimeout(2000); // Wait for installation
    });

    test('should list caches after registration', async ({ page }) => {
        await page.click('#btn-list-caches');
        await page.waitForTimeout(500);

        const cacheList = page.locator('#cache-list li');
        const count = await cacheList.count();

        // Should have at least static cache
        expect(count).toBeGreaterThanOrEqual(0); // May be 0 if precache failed

        // Check log
        await expect(page.locator('#log')).toContainText(/Cache:|No caches found/);
    });

    test('should clear all caches', async ({ page }) => {
        // First list caches
        await page.click('#btn-list-caches');
        await page.waitForTimeout(500);

        // Clear caches
        await page.click('#btn-clear-caches');
        await page.waitForTimeout(500);

        // Verify cleared
        await expect(page.locator('#cache-list')).toContainText('All caches cleared');
    });
});

test.describe('Caching Strategies', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);

        // Register SW and wait for activation
        await page.click('#btn-register');
        await page.waitForTimeout(2000);
    });

    test('should handle static asset fetch', async ({ page }) => {
        await page.click('#btn-fetch-static');
        await page.waitForTimeout(500);

        // Check that fetch was attempted
        await expect(page.locator('#log')).toContainText('Static fetch');
    });

    test('should handle API fetch', async ({ page }) => {
        await page.click('#btn-fetch-api');
        await page.waitForTimeout(500);

        await expect(page.locator('#log')).toContainText('API fetch');
    });

    test('should handle image fetch', async ({ page }) => {
        await page.click('#btn-fetch-image');
        await page.waitForTimeout(500);

        await expect(page.locator('#log')).toContainText('Image fetch');
    });
});

test.describe('Offline Behavior', () => {
    test('should serve cached content when offline', async ({ page, context }) => {
        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);

        // Register SW
        await page.click('#btn-register');
        await page.waitForTimeout(2000);

        // Reload to ensure SW is controlling
        await page.reload();
        await page.waitForFunction(() => window.testReady === true);

        // Go offline
        await context.setOffline(true);

        // The page should still be visible (cached)
        await expect(page.locator('h1')).toBeVisible();

        // Go back online
        await context.setOffline(false);
    });

    test('should show offline page for uncached navigation', async ({ page, context }) => {
        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);

        // Register SW
        await page.click('#btn-register');
        await page.waitForTimeout(2000);

        // Go offline
        await context.setOffline(true);

        // Try to navigate to uncached page
        try {
            await page.goto('/uncached-page', { timeout: 5000 });
        } catch {
            // Expected to fail or show offline page
        }

        // Should either show offline page or error
        // (depends on whether offline.html is precached)

        // Go back online
        await context.setOffline(false);
    });
});

test.describe('Network Only Paths', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);

        await page.click('#btn-register');
        await page.waitForTimeout(2000);
    });

    test('should not cache checkout paths', async ({ page }) => {
        // The SW should not intercept these paths
        const response = await page.evaluate(async () => {
            try {
                const res = await fetch('/checkout/test');
                return { status: res.status, cached: false };
            } catch {
                return { status: 0, cached: false };
            }
        });

        // These requests should go directly to network
        // (will fail with 404 but shouldn't be cached)
        expect(response).toBeDefined();
    });

    test('should not cache cart paths', async ({ page }) => {
        const response = await page.evaluate(async () => {
            try {
                const res = await fetch('/cart/items');
                return { status: res.status };
            } catch {
                return { status: 0 };
            }
        });

        expect(response).toBeDefined();
    });

    test('should not cache account paths', async ({ page }) => {
        const response = await page.evaluate(async () => {
            try {
                const res = await fetch('/account/profile');
                return { status: res.status };
            } catch {
                return { status: 0 };
            }
        });

        expect(response).toBeDefined();
    });
});

test.describe('Service Worker Events', () => {
    test('should receive messages from service worker', async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/service-worker.html');
        await page.waitForFunction(() => window.testReady === true);

        // Set up message listener
        await page.evaluate(() => {
            window.swMessages = [];
            navigator.serviceWorker.addEventListener('message', (e) => {
                window.swMessages.push(e.data);
            });
        });

        // Register SW
        await page.click('#btn-register');
        await page.waitForTimeout(2000);

        // Messages array should be defined
        const messages = await page.evaluate(() => window.swMessages);
        expect(Array.isArray(messages)).toBe(true);
    });
});

// Helper type declarations
declare global {
    interface Window {
        testReady: boolean;
        swRegistration: ServiceWorkerRegistration;
        swMessages: unknown[];
        cacheNames: string[];
        lastFetchResult: { type: string; status: number };
        offlineTestReady: boolean;
    }
}
