/**
 * Tests for JSON Configuration Files
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = resolve(__dirname, '../..');

describe('PWA Manifest Validation', () => {
    const manifestPath = resolve(
        rootDir,
        'chapters/19-mobile-performance/config/manifest.json'
    );

    let manifest;

    try {
        manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    } catch (e) {
        manifest = null;
    }

    it('should have a valid JSON structure', () => {
        expect(manifest).not.toBeNull();
        expect(typeof manifest).toBe('object');
    });

    it('should have required PWA properties', () => {
        if (!manifest) return;

        expect(manifest).toHaveProperty('name');
        expect(manifest).toHaveProperty('short_name');
        expect(manifest).toHaveProperty('start_url');
        expect(manifest).toHaveProperty('display');
    });

    it('should have valid display mode', () => {
        if (!manifest) return;

        const validDisplayModes = ['fullscreen', 'standalone', 'minimal-ui', 'browser'];
        expect(validDisplayModes).toContain(manifest.display);
    });

    it('should have icons defined', () => {
        if (!manifest) return;

        expect(manifest).toHaveProperty('icons');
        expect(Array.isArray(manifest.icons)).toBe(true);
        expect(manifest.icons.length).toBeGreaterThan(0);
    });

    it('should have icons with required properties', () => {
        if (!manifest || !manifest.icons) return;

        manifest.icons.forEach((icon) => {
            expect(icon).toHaveProperty('src');
            expect(icon).toHaveProperty('sizes');
            expect(icon).toHaveProperty('type');
        });
    });

    it('should have valid theme and background colors', () => {
        if (!manifest) return;

        if (manifest.theme_color) {
            expect(manifest.theme_color).toMatch(/^#[0-9A-Fa-f]{6}$/);
        }
        if (manifest.background_color) {
            expect(manifest.background_color).toMatch(/^#[0-9A-Fa-f]{6}$/);
        }
    });
});

describe('Lighthouse Config Validation', () => {
    const configPath = resolve(
        rootDir,
        'chapters/16-shopware-themes/config/lighthouse-budget.json'
    );

    let config;

    try {
        config = JSON.parse(readFileSync(configPath, 'utf8'));
    } catch (e) {
        config = null;
    }

    it('should have a valid JSON structure', () => {
        expect(config).not.toBeNull();
    });

    it('should have budgets defined', () => {
        if (!config) return;

        expect(config).toHaveProperty('budgets');
        expect(Array.isArray(config.budgets)).toBe(true);
        expect(config.budgets.length).toBeGreaterThan(0);
    });

    it('should have valid budget structure', () => {
        if (!config || !config.budgets) return;

        config.budgets.forEach((budget) => {
            expect(budget).toHaveProperty('resourceSizes');
            expect(Array.isArray(budget.resourceSizes)).toBe(true);
        });
    });
});
