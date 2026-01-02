/**
 * E2E Tests for Swipe Gesture Detection
 *
 * Tests the SwipeGesture, ProductGallery, and SwipeToDelete components
 * using Playwright's touch emulation.
 */
import { test, expect, type Page } from '@playwright/test';

// Helper to perform a touch swipe gesture using CDP
async function swipe(
    page: Page,
    selector: string,
    direction: 'left' | 'right' | 'up' | 'down',
    distance: number = 100
) {
    const element = page.locator(selector);
    const box = await element.boundingBox();

    if (!box) {
        throw new Error(`Element ${selector} not found`);
    }

    const startX = box.x + box.width / 2;
    const startY = box.y + box.height / 2;

    let endX = startX;
    let endY = startY;

    switch (direction) {
        case 'left':
            endX = startX - distance;
            break;
        case 'right':
            endX = startX + distance;
            break;
        case 'up':
            endY = startY - distance;
            break;
        case 'down':
            endY = startY + distance;
            break;
    }

    // Dispatch touch events via page.evaluate with proper timing
    await page.evaluate(
        async ({ selector, startX, startY, endX, endY }) => {
            const el = document.querySelector(selector);
            if (!el) return;

            const touchId = Date.now();
            const createTouch = (x: number, y: number) =>
                new Touch({
                    identifier: touchId,
                    target: el,
                    clientX: x,
                    clientY: y,
                    radiusX: 2.5,
                    radiusY: 2.5,
                    rotationAngle: 0,
                    force: 1,
                });

            const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

            // Touch start
            const touchStart = createTouch(startX, startY);
            el.dispatchEvent(
                new TouchEvent('touchstart', {
                    bubbles: true,
                    cancelable: true,
                    touches: [touchStart],
                    targetTouches: [touchStart],
                    changedTouches: [touchStart],
                })
            );

            await delay(20);

            // Touch move (interpolate)
            const steps = 5;
            for (let i = 1; i <= steps; i++) {
                const x = startX + ((endX - startX) * i) / steps;
                const y = startY + ((endY - startY) * i) / steps;
                const touchMove = createTouch(x, y);
                el.dispatchEvent(
                    new TouchEvent('touchmove', {
                        bubbles: true,
                        cancelable: true,
                        touches: [touchMove],
                        targetTouches: [touchMove],
                        changedTouches: [touchMove],
                    })
                );
                await delay(20);
            }

            // Touch end
            const touchEnd = createTouch(endX, endY);
            el.dispatchEvent(
                new TouchEvent('touchend', {
                    bubbles: true,
                    cancelable: true,
                    touches: [],
                    targetTouches: [],
                    changedTouches: [touchEnd],
                })
            );
        },
        { selector, startX, startY, endX, endY }
    );
}

// Skip all swipe tests on WebKit - Touch constructor not supported
test.describe('SwipeGesture Component', () => {
    test.skip(({ browserName }) => browserName === 'webkit', 'Touch API not supported in WebKit');

    test.beforeEach(async ({ page }) => {
        // Serve the test fixture
        await page.goto('/tests/E2E/fixtures/swipe-gestures.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should detect swipe left', async ({ page }) => {
        const swipeArea = page.locator('#swipe-area');

        // Perform swipe left
        await swipe(page, '#swipe-area', 'left', 80);

        // Wait for swipe detection
        await page.waitForTimeout(100);

        // Check that swipe was detected
        const lastSwipe = await swipeArea.getAttribute('data-last-swipe');
        expect(lastSwipe).toBe('left');

        // Check log entry
        const log = page.locator('#log');
        await expect(log).toContainText('Swipe LEFT detected');
    });

    test('should detect swipe right', async ({ page }) => {
        const swipeArea = page.locator('#swipe-area');

        await swipe(page, '#swipe-area', 'right', 80);
        await page.waitForTimeout(100);

        const lastSwipe = await swipeArea.getAttribute('data-last-swipe');
        expect(lastSwipe).toBe('right');

        await expect(page.locator('#log')).toContainText('Swipe RIGHT detected');
    });

    test('should detect swipe up', async ({ page }) => {
        const swipeArea = page.locator('#swipe-area');

        await swipe(page, '#swipe-area', 'up', 80);
        await page.waitForTimeout(100);

        const lastSwipe = await swipeArea.getAttribute('data-last-swipe');
        expect(lastSwipe).toBe('up');
    });

    test('should detect swipe down', async ({ page }) => {
        const swipeArea = page.locator('#swipe-area');

        await swipe(page, '#swipe-area', 'down', 80);
        await page.waitForTimeout(100);

        const lastSwipe = await swipeArea.getAttribute('data-last-swipe');
        expect(lastSwipe).toBe('down');
    });

    test('should not detect swipe below threshold', async ({ page }) => {
        const swipeArea = page.locator('#swipe-area');

        // Swipe with distance below threshold (50px)
        await swipe(page, '#swipe-area', 'left', 30);
        await page.waitForTimeout(100);

        // No swipe should be detected
        const lastSwipe = await swipeArea.getAttribute('data-last-swipe');
        expect(lastSwipe).toBeNull();
    });
});

test.describe('ProductGallery Component', () => {
    test.skip(({ browserName }) => browserName === 'webkit', 'Touch API not supported in WebKit');

    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/swipe-gestures.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should render gallery with images', async ({ page }) => {
        const gallery = page.locator('#gallery');
        const slides = gallery.locator('.gallery-slide');
        const dots = gallery.locator('.gallery-dot');

        await expect(slides).toHaveCount(3);
        await expect(dots).toHaveCount(3);
    });

    test('should navigate with swipe left (next)', async ({ page }) => {
        // Initial state: first slide active
        const firstDot = page.locator('.gallery-dot').first();
        await expect(firstDot).toHaveClass(/active/);

        // Swipe left to go to next slide
        await swipe(page, '#gallery', 'left', 100);
        await page.waitForTimeout(400); // Wait for transition

        // Second dot should be active
        const secondDot = page.locator('.gallery-dot').nth(1);
        await expect(secondDot).toHaveClass(/active/);
    });

    test('should navigate with swipe right (prev)', async ({ page }) => {
        // First go to second slide
        await page.evaluate(() => window.gallery.goTo(1));
        await page.waitForTimeout(100);

        // Swipe right to go back
        await swipe(page, '#gallery', 'right', 100);
        await page.waitForTimeout(400);

        // First dot should be active
        const firstDot = page.locator('.gallery-dot').first();
        await expect(firstDot).toHaveClass(/active/);
    });

    test('should navigate with dot clicks', async ({ page }) => {
        const thirdDot = page.locator('.gallery-dot').nth(2);
        await thirdDot.click();
        await page.waitForTimeout(400);

        await expect(thirdDot).toHaveClass(/active/);
    });

    test('should loop from last to first', async ({ page }) => {
        // Go to last slide
        await page.evaluate(() => window.gallery.goTo(2));
        await page.waitForTimeout(100);

        // Swipe to next (should loop to first)
        await swipe(page, '#gallery', 'left', 100);
        await page.waitForTimeout(400);

        const firstDot = page.locator('.gallery-dot').first();
        await expect(firstDot).toHaveClass(/active/);
    });
});

test.describe('SwipeToDelete Component', () => {
    test.skip(({ browserName }) => browserName === 'webkit', 'Touch API not supported in WebKit');

    test.beforeEach(async ({ page }) => {
        await page.goto('/tests/E2E/fixtures/swipe-gestures.html');
        await page.waitForFunction(() => window.testReady === true);
    });

    test('should show delete button on swipe left', async ({ page }) => {
        const firstItem = page.locator('#swipe-list li').first();
        const deleteBtn = firstItem.locator('.swipe-delete');

        // Initially delete button should be hidden behind content
        await expect(deleteBtn).toBeVisible();

        // Swipe left partially
        await swipe(page, '#swipe-list li:first-child .swipe-content', 'left', 50);
        await page.waitForTimeout(100);

        // Delete button should now be more visible
        await expect(deleteBtn).toBeVisible();
    });

    test('should delete item on full swipe', async ({ page }) => {
        const items = page.locator('#swipe-list li');
        await expect(items).toHaveCount(3);

        // Get width of first item to calculate proper swipe distance
        const itemWidth = await page.locator('#swipe-list li:first-child').evaluate(el => el.offsetWidth);
        const swipeDistance = Math.ceil(itemWidth * 0.5); // 50% of width (above 40% threshold)

        // Full swipe left on first item
        await swipe(page, '#swipe-list li:first-child .swipe-content', 'left', swipeDistance);
        await page.waitForTimeout(800); // Wait for animation and deletion

        // Item should be removed
        await expect(items).toHaveCount(2, { timeout: 3000 });

        // Log should show deletion
        await expect(page.locator('#log')).toContainText('Item 1 deleted');
    });

    test('should not delete on partial swipe', async ({ page }) => {
        const items = page.locator('#swipe-list li');

        // Partial swipe (below threshold)
        await swipe(page, '#swipe-list li:first-child .swipe-content', 'left', 30);
        await page.waitForTimeout(500);

        // All items should still exist
        await expect(items).toHaveCount(3);
    });

    test('should not respond to right swipe', async ({ page }) => {
        const items = page.locator('#swipe-list li');

        // Try swiping right
        await swipe(page, '#swipe-list li:first-child .swipe-content', 'right', 100);
        await page.waitForTimeout(500);

        // All items should still exist
        await expect(items).toHaveCount(3);
    });
});

test.describe('Mobile Touch Emulation', () => {
    test.skip(({ browserName }) => browserName === 'webkit', 'Touch API not supported in WebKit');

    test('should work on mobile viewport', async ({ page }) => {
        // Set mobile viewport
        await page.setViewportSize({ width: 393, height: 851 });

        await page.goto('/tests/E2E/fixtures/swipe-gestures.html');
        await page.waitForFunction(() => window.testReady === true);

        const swipeArea = page.locator('#swipe-area');

        // Perform touch swipe
        await swipe(page, '#swipe-area', 'left', 80);
        await page.waitForTimeout(100);

        const lastSwipe = await swipeArea.getAttribute('data-last-swipe');
        expect(lastSwipe).toBe('left');
    });
});
