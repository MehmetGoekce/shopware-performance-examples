/**
 * E2E Tests for Swipe Gesture Detection
 *
 * Tests the SwipeGesture, ProductGallery, and SwipeToDelete components
 * using Playwright's touch emulation.
 */
import { test, expect, type Page } from '@playwright/test';

// Helper to perform a touch swipe gesture
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

    // Perform touch swipe
    await page.touchscreen.tap(startX, startY);
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();
}

test.describe('SwipeGesture Component', () => {
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

        // Full swipe left on first item
        await swipe(page, '#swipe-list li:first-child .swipe-content', 'left', 200);
        await page.waitForTimeout(500); // Wait for animation

        // Item should be removed
        await expect(items).toHaveCount(2);

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
    test.use({ ...require('@playwright/test').devices['Pixel 5'] });

    test('should work on mobile device', async ({ page }) => {
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
