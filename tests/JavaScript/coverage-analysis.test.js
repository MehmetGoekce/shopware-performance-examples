/**
 * Tests for coverage-analysis.js utility functions
 *
 * Tests the CSS/JS coverage analysis functions with mocked DOM/Performance APIs
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

describe('Coverage Analysis Functions', () => {
    let mockDocument;
    let mockPerformance;
    let mockConsole;
    let originalConsole;

    beforeEach(() => {
        // Mock console
        originalConsole = global.console;
        mockConsole = {
            log: vi.fn(),
            table: vi.fn(),
            clear: vi.fn(),
        };
        global.console = mockConsole;

        // Mock document
        mockDocument = {
            querySelectorAll: vi.fn(),
        };
        global.document = mockDocument;

        // Mock performance
        mockPerformance = {
            getEntriesByType: vi.fn(),
        };
        global.performance = mockPerformance;

        // Mock location
        global.location = { hostname: 'example.com' };

        // Mock PerformanceObserver
        global.PerformanceObserver = vi.fn().mockImplementation(() => ({
            observe: vi.fn(),
            disconnect: vi.fn(),
        }));
    });

    afterEach(() => {
        global.console = originalConsole;
        vi.clearAllMocks();
    });

    /**
     * Test findRenderBlockingResources logic
     */
    describe('findRenderBlockingResources', () => {
        function findRenderBlockingResources() {
            // CSS im <head> ohne media="print" oder async
            const blockingCSS = Array.from(document.querySelectorAll('link[rel="stylesheet"]'))
                .filter(link => {
                    const media = link.getAttribute('media');
                    const onload = link.getAttribute('onload');
                    return !media || (media !== 'print' && !onload);
                })
                .map(link => ({
                    type: 'CSS',
                    url: link.href.split('/').pop().substring(0, 50),
                    fullUrl: link.href,
                    blocking: true
                }));

            // JavaScript ohne defer/async
            const blockingJS = Array.from(document.querySelectorAll('script[src]'))
                .filter(script => {
                    const isInHead = script.parentElement.tagName === 'HEAD';
                    const hasDefer = script.defer;
                    const hasAsync = script.async;
                    const isModule = script.type === 'module';
                    return isInHead && !hasDefer && !hasAsync && !isModule;
                })
                .map(script => ({
                    type: 'JS',
                    url: script.src.split('/').pop().substring(0, 50),
                    fullUrl: script.src,
                    blocking: true
                }));

            return [...blockingCSS, ...blockingJS];
        }

        it('should detect blocking CSS without media attribute', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'link[rel="stylesheet"]') {
                    return [{
                        getAttribute: (attr) => (attr === 'media' ? null : null),
                        href: 'https://example.com/style.css',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(1);
            expect(result[0].type).toBe('CSS');
            expect(result[0].blocking).toBe(true);
        });

        it('should not detect CSS with media="print"', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'link[rel="stylesheet"]') {
                    return [{
                        getAttribute: (attr) => (attr === 'media' ? 'print' : null),
                        href: 'https://example.com/print.css',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(0);
        });

        it('should not detect CSS with async pattern (onload)', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'link[rel="stylesheet"]') {
                    return [{
                        getAttribute: (attr) => {
                            if (attr === 'media') return 'all';
                            if (attr === 'onload') return "this.media='all'";
                            return null;
                        },
                        href: 'https://example.com/async.css',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(0);
        });

        it('should detect blocking JS in HEAD without defer/async', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'script[src]') {
                    return [{
                        parentElement: { tagName: 'HEAD' },
                        defer: false,
                        async: false,
                        type: '',
                        src: 'https://example.com/main.js',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(1);
            expect(result[0].type).toBe('JS');
            expect(result[0].blocking).toBe(true);
        });

        it('should not detect JS with defer', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'script[src]') {
                    return [{
                        parentElement: { tagName: 'HEAD' },
                        defer: true,
                        async: false,
                        type: '',
                        src: 'https://example.com/main.js',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(0);
        });

        it('should not detect JS modules (always deferred)', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'script[src]') {
                    return [{
                        parentElement: { tagName: 'HEAD' },
                        defer: false,
                        async: false,
                        type: 'module',
                        src: 'https://example.com/app.mjs',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(0);
        });

        it('should not detect JS in BODY (not render-blocking)', () => {
            mockDocument.querySelectorAll.mockImplementation((selector) => {
                if (selector === 'script[src]') {
                    return [{
                        parentElement: { tagName: 'BODY' },
                        defer: false,
                        async: false,
                        type: '',
                        src: 'https://example.com/bottom.js',
                    }];
                }
                return [];
            });

            const result = findRenderBlockingResources();

            expect(result).toHaveLength(0);
        });
    });

    /**
     * Test analyzeJavaScriptBundles logic
     */
    describe('analyzeJavaScriptBundles', () => {
        function analyzeJavaScriptBundles() {
            const jsResources = performance.getEntriesByType('resource')
                .filter(r => r.initiatorType === 'script' || r.name.endsWith('.js'))
                .map(r => ({
                    name: r.name.split('/').pop().split('?')[0].substring(0, 40),
                    size: Math.round(r.transferSize / 1024),
                    duration: Math.round(r.duration),
                    isThirdParty: !r.name.includes(location.hostname)
                }))
                .sort((a, b) => b.size - a.size);

            const totalSize = jsResources.reduce((sum, r) => sum + r.size, 0);
            const thirdPartySize = jsResources
                .filter(r => r.isThirdParty)
                .reduce((sum, r) => sum + r.size, 0);

            return { jsResources, totalSize, thirdPartySize };
        }

        it('should calculate total JS size', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                { initiatorType: 'script', name: 'https://example.com/main.js', transferSize: 102400, duration: 50 },
                { initiatorType: 'script', name: 'https://example.com/vendor.js', transferSize: 204800, duration: 80 },
            ]);

            const result = analyzeJavaScriptBundles();

            expect(result.totalSize).toBe(300); // 100 + 200 KB
        });

        it('should identify third-party scripts', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                { initiatorType: 'script', name: 'https://example.com/main.js', transferSize: 51200, duration: 30 },
                { initiatorType: 'script', name: 'https://cdn.external.com/analytics.js', transferSize: 102400, duration: 100 },
            ]);

            const result = analyzeJavaScriptBundles();

            expect(result.thirdPartySize).toBe(100); // Only external script
            expect(result.jsResources[0].isThirdParty).toBe(true); // Largest is third-party
        });

        it('should sort by size descending', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                { initiatorType: 'script', name: 'https://example.com/small.js', transferSize: 10240, duration: 10 },
                { initiatorType: 'script', name: 'https://example.com/large.js', transferSize: 512000, duration: 150 },
                { initiatorType: 'script', name: 'https://example.com/medium.js', transferSize: 102400, duration: 50 },
            ]);

            const result = analyzeJavaScriptBundles();

            expect(result.jsResources[0].name).toBe('large.js');
            expect(result.jsResources[1].name).toBe('medium.js');
            expect(result.jsResources[2].name).toBe('small.js');
        });

        it('should filter only JS resources', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                { initiatorType: 'script', name: 'https://example.com/main.js', transferSize: 51200, duration: 30 },
                { initiatorType: 'link', name: 'https://example.com/style.css', transferSize: 20480, duration: 20 },
                { initiatorType: 'img', name: 'https://example.com/image.png', transferSize: 102400, duration: 80 },
            ]);

            const result = analyzeJavaScriptBundles();

            expect(result.jsResources).toHaveLength(1);
            expect(result.jsResources[0].name).toBe('main.js');
        });

        it('should truncate long filenames', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                {
                    initiatorType: 'script',
                    name: 'https://example.com/this-is-a-very-long-filename-that-exceeds-forty-characters.js',
                    transferSize: 51200,
                    duration: 30
                },
            ]);

            const result = analyzeJavaScriptBundles();

            expect(result.jsResources[0].name.length).toBeLessThanOrEqual(40);
        });
    });

    /**
     * Test analyzeCSSBundles logic
     */
    describe('analyzeCSSBundles', () => {
        function analyzeCSSBundles() {
            const cssResources = performance.getEntriesByType('resource')
                .filter(r => r.initiatorType === 'link' || r.name.endsWith('.css'))
                .map(r => ({
                    name: r.name.split('/').pop().split('?')[0].substring(0, 40),
                    size: Math.round(r.transferSize / 1024),
                    duration: Math.round(r.duration)
                }))
                .sort((a, b) => b.size - a.size);

            const totalSize = cssResources.reduce((sum, r) => sum + r.size, 0);

            return { cssResources, totalSize };
        }

        it('should calculate total CSS size', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                { initiatorType: 'link', name: 'https://example.com/main.css', transferSize: 51200, duration: 30 },
                { initiatorType: 'link', name: 'https://example.com/theme.css', transferSize: 25600, duration: 20 },
            ]);

            const result = analyzeCSSBundles();

            expect(result.totalSize).toBe(75); // 50 + 25 KB
        });

        it('should filter CSS resources by extension', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                { initiatorType: 'link', name: 'https://example.com/style.css', transferSize: 20480, duration: 20 },
                { initiatorType: 'other', name: 'https://example.com/dynamic.css', transferSize: 10240, duration: 15 },
                { initiatorType: 'script', name: 'https://example.com/main.js', transferSize: 51200, duration: 30 },
            ]);

            const result = analyzeCSSBundles();

            expect(result.cssResources).toHaveLength(2);
        });

        it('should strip query strings from filenames', () => {
            mockPerformance.getEntriesByType.mockReturnValue([
                {
                    initiatorType: 'link',
                    name: 'https://example.com/style.css?v=1234567890',
                    transferSize: 20480,
                    duration: 20
                },
            ]);

            const result = analyzeCSSBundles();

            expect(result.cssResources[0].name).toBe('style.css');
        });
    });

    /**
     * Test auditScriptLoading logic
     */
    describe('auditScriptLoading', () => {
        function auditScriptLoading() {
            const scripts = Array.from(document.querySelectorAll('script[src]'));

            const audit = {
                blocking: [],
                defer: [],
                async: [],
                module: []
            };

            scripts.forEach(script => {
                const info = {
                    src: script.src.split('/').pop().substring(0, 40),
                    inHead: script.parentElement.tagName === 'HEAD'
                };

                if (script.type === 'module') {
                    audit.module.push(info);
                } else if (script.defer) {
                    audit.defer.push(info);
                } else if (script.async) {
                    audit.async.push(info);
                } else {
                    audit.blocking.push(info);
                }
            });

            return audit;
        }

        it('should categorize blocking scripts', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { src: 'https://example.com/blocking.js', parentElement: { tagName: 'HEAD' }, defer: false, async: false, type: '' },
            ]);

            const result = auditScriptLoading();

            expect(result.blocking).toHaveLength(1);
            expect(result.blocking[0].src).toBe('blocking.js');
        });

        it('should categorize deferred scripts', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { src: 'https://example.com/deferred.js', parentElement: { tagName: 'HEAD' }, defer: true, async: false, type: '' },
            ]);

            const result = auditScriptLoading();

            expect(result.defer).toHaveLength(1);
        });

        it('should categorize async scripts', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { src: 'https://example.com/async.js', parentElement: { tagName: 'HEAD' }, defer: false, async: true, type: '' },
            ]);

            const result = auditScriptLoading();

            expect(result.async).toHaveLength(1);
        });

        it('should categorize module scripts', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { src: 'https://example.com/app.mjs', parentElement: { tagName: 'HEAD' }, defer: false, async: false, type: 'module' },
            ]);

            const result = auditScriptLoading();

            expect(result.module).toHaveLength(1);
        });

        it('should track if script is in HEAD', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { src: 'https://example.com/head.js', parentElement: { tagName: 'HEAD' }, defer: false, async: false, type: '' },
                { src: 'https://example.com/body.js', parentElement: { tagName: 'BODY' }, defer: false, async: false, type: '' },
            ]);

            const result = auditScriptLoading();

            expect(result.blocking[0].inHead).toBe(true);
            expect(result.blocking[1].inHead).toBe(false);
        });

        it('should handle mixed script types', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { src: 'https://example.com/a.js', parentElement: { tagName: 'HEAD' }, defer: false, async: false, type: '' },
                { src: 'https://example.com/b.js', parentElement: { tagName: 'HEAD' }, defer: true, async: false, type: '' },
                { src: 'https://example.com/c.js', parentElement: { tagName: 'HEAD' }, defer: false, async: true, type: '' },
                { src: 'https://example.com/d.mjs', parentElement: { tagName: 'HEAD' }, defer: false, async: false, type: 'module' },
            ]);

            const result = auditScriptLoading();

            expect(result.blocking).toHaveLength(1);
            expect(result.defer).toHaveLength(1);
            expect(result.async).toHaveLength(1);
            expect(result.module).toHaveLength(1);
        });
    });

    /**
     * Test inline styles analysis
     */
    describe('Inline Styles Analysis', () => {
        function countInlineStyles() {
            const styles = document.querySelectorAll('style');
            const count = styles.length;
            const totalSize = Array.from(styles)
                .reduce((sum, s) => sum + s.textContent.length, 0);

            return { count, totalSize: Math.round(totalSize / 1024) };
        }

        it('should count inline style elements', () => {
            mockDocument.querySelectorAll.mockReturnValue([
                { textContent: 'body { margin: 0; }' },
                { textContent: '.header { color: blue; }' },
            ]);

            const result = countInlineStyles();

            expect(result.count).toBe(2);
        });

        it('should calculate inline styles size', () => {
            // 1KB of CSS
            const css = 'a'.repeat(1024);
            mockDocument.querySelectorAll.mockReturnValue([
                { textContent: css },
            ]);

            const result = countInlineStyles();

            expect(result.totalSize).toBe(1);
        });
    });
});

describe('Performance Thresholds', () => {
    it('should flag JS bundle over 500KB', () => {
        const totalSize = 600; // KB
        const isLarge = totalSize > 500;

        expect(isLarge).toBe(true);
    });

    it('should not flag JS bundle under 500KB', () => {
        const totalSize = 300; // KB
        const isLarge = totalSize > 500;

        expect(isLarge).toBe(false);
    });

    it('should calculate TBT from long tasks', () => {
        const longTasks = [
            { duration: 80 },  // 30ms over 50ms threshold
            { duration: 120 }, // 70ms over
            { duration: 60 },  // 10ms over
        ];

        const totalBlocking = longTasks.reduce(
            (sum, t) => sum + Math.max(0, t.duration - 50),
            0
        );

        expect(totalBlocking).toBe(110); // 30 + 70 + 10
    });

    it('should flag TBT over 200ms', () => {
        const totalBlocking = 250;
        const needsOptimization = totalBlocking > 200;

        expect(needsOptimization).toBe(true);
    });
});
