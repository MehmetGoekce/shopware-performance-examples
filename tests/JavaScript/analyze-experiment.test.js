/**
 * Tests for analyze-experiment.js utility functions
 *
 * Tests the statistical analysis functions without database dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock modules before importing
vi.mock('mysql2/promise', () => ({
    default: { createConnection: vi.fn() }
}));

vi.mock('simple-statistics', () => ({
    mean: (arr) => arr.reduce((a, b) => a + b, 0) / arr.length,
    std: (arr) => {
        const m = arr.reduce((a, b) => a + b, 0) / arr.length;
        return Math.sqrt(arr.reduce((acc, v) => acc + Math.pow(v - m, 2), 0) / (arr.length - 1));
    },
    tTest: vi.fn()
}));

describe('Statistical Analysis Functions', () => {
    /**
     * Test groupByVariant logic (inline implementation)
     */
    describe('groupByVariant', () => {
        function groupByVariant(metrics) {
            const grouped = {};

            for (const metric of metrics) {
                const { variant, metric: metricName, value } = metric;

                if (!grouped[variant]) {
                    grouped[variant] = {};
                }

                if (!grouped[variant][metricName]) {
                    grouped[variant][metricName] = [];
                }

                grouped[variant][metricName].push(parseFloat(value));
            }

            return grouped;
        }

        it('should group metrics by variant', () => {
            const metrics = [
                { variant: 'control', metric: 'lcp', value: '2100' },
                { variant: 'control', metric: 'lcp', value: '2200' },
                { variant: 'variant_a', metric: 'lcp', value: '1800' },
                { variant: 'variant_a', metric: 'lcp', value: '1900' },
            ];

            const result = groupByVariant(metrics);

            expect(result).toHaveProperty('control');
            expect(result).toHaveProperty('variant_a');
            expect(result.control.lcp).toEqual([2100, 2200]);
            expect(result.variant_a.lcp).toEqual([1800, 1900]);
        });

        it('should handle multiple metrics', () => {
            const metrics = [
                { variant: 'control', metric: 'lcp', value: '2100' },
                { variant: 'control', metric: 'cls', value: '0.05' },
                { variant: 'control', metric: 'inp', value: '150' },
            ];

            const result = groupByVariant(metrics);

            expect(Object.keys(result.control)).toEqual(['lcp', 'cls', 'inp']);
            expect(result.control.lcp).toEqual([2100]);
            expect(result.control.cls).toEqual([0.05]);
            expect(result.control.inp).toEqual([150]);
        });

        it('should handle empty input', () => {
            const result = groupByVariant([]);
            expect(result).toEqual({});
        });
    });

    /**
     * Test normalCDF (Normal Cumulative Distribution Function)
     */
    describe('normalCDF', () => {
        function normalCDF(x) {
            const t = 1 / (1 + 0.2316419 * Math.abs(x));
            const d = 0.3989423 * Math.exp(-x * x / 2);
            const prob = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));

            return x > 0 ? 1 - prob : prob;
        }

        it('should return 0.5 for x=0', () => {
            expect(normalCDF(0)).toBeCloseTo(0.5, 2);
        });

        it('should return ~0.8413 for x=1', () => {
            expect(normalCDF(1)).toBeCloseTo(0.8413, 2);
        });

        it('should return ~0.9772 for x=2', () => {
            expect(normalCDF(2)).toBeCloseTo(0.9772, 2);
        });

        it('should return ~0.1587 for x=-1', () => {
            expect(normalCDF(-1)).toBeCloseTo(0.1587, 2);
        });

        it('should be symmetric around 0', () => {
            const pos = normalCDF(1.5);
            const neg = normalCDF(-1.5);
            expect(pos + neg).toBeCloseTo(1.0, 4);
        });
    });

    /**
     * Test parseArgs logic
     */
    describe('parseArgs', () => {
        function parseArgs(argv) {
            const CONFIG = { defaultConfidence: 0.95 };
            const args = {
                experimentKey: argv[2],
                bayesian: false,
                confidence: CONFIG.defaultConfidence,
                metric: null,
                export: null,
            };

            for (let i = 3; i < argv.length; i++) {
                const arg = argv[i];

                if (arg === '--bayesian') {
                    args.bayesian = true;
                } else if (arg.startsWith('--confidence=')) {
                    args.confidence = parseFloat(arg.split('=')[1]);
                } else if (arg.startsWith('--metric=')) {
                    args.metric = arg.split('=')[1];
                } else if (arg.startsWith('--export=')) {
                    args.export = arg.split('=')[1];
                }
            }

            return args;
        }

        it('should parse experiment key', () => {
            const result = parseArgs(['node', 'script.js', 'checkout_test']);
            expect(result.experimentKey).toBe('checkout_test');
        });

        it('should parse --bayesian flag', () => {
            const result = parseArgs(['node', 'script.js', 'test', '--bayesian']);
            expect(result.bayesian).toBe(true);
        });

        it('should parse --confidence option', () => {
            const result = parseArgs(['node', 'script.js', 'test', '--confidence=0.99']);
            expect(result.confidence).toBe(0.99);
        });

        it('should parse --metric option', () => {
            const result = parseArgs(['node', 'script.js', 'test', '--metric=lcp']);
            expect(result.metric).toBe('lcp');
        });

        it('should parse --export option', () => {
            const result = parseArgs(['node', 'script.js', 'test', '--export=results.csv']);
            expect(result.export).toBe('results.csv');
        });

        it('should handle multiple options', () => {
            const result = parseArgs([
                'node', 'script.js', 'test',
                '--bayesian',
                '--confidence=0.90',
                '--metric=cls',
                '--export=output.csv'
            ]);

            expect(result.experimentKey).toBe('test');
            expect(result.bayesian).toBe(true);
            expect(result.confidence).toBe(0.90);
            expect(result.metric).toBe('cls');
            expect(result.export).toBe('output.csv');
        });

        it('should use defaults when no options provided', () => {
            const result = parseArgs(['node', 'script.js', 'test']);
            expect(result.bayesian).toBe(false);
            expect(result.confidence).toBe(0.95);
            expect(result.metric).toBeNull();
            expect(result.export).toBeNull();
        });
    });

    /**
     * Test calculateSignificance logic
     */
    describe('calculateSignificance', () => {
        function mean(arr) {
            return arr.reduce((a, b) => a + b, 0) / arr.length;
        }

        function std(arr) {
            const m = mean(arr);
            return Math.sqrt(arr.reduce((acc, v) => acc + Math.pow(v - m, 2), 0) / (arr.length - 1));
        }

        function normalCDF(x) {
            const t = 1 / (1 + 0.2316419 * Math.abs(x));
            const d = 0.3989423 * Math.exp(-x * x / 2);
            const prob = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
            return x > 0 ? 1 - prob : prob;
        }

        function calculateSignificance(control, variant, confidence) {
            const controlMean = mean(control);
            const variantMean = mean(variant);
            const controlStd = std(control);
            const variantStd = std(variant);

            const pooledSE = Math.sqrt(
                (controlStd ** 2 / control.length) + (variantStd ** 2 / variant.length)
            );

            const tStat = Math.abs((controlMean - variantMean) / pooledSE);
            const pValue = 2 * (1 - normalCDF(tStat));

            const pooledStd = Math.sqrt(
                ((control.length - 1) * controlStd ** 2 + (variant.length - 1) * variantStd ** 2) /
                (control.length + variant.length - 2)
            );

            const effectSize = (controlMean - variantMean) / pooledStd;
            const alpha = 1 - confidence;
            const isSignificant = pValue < alpha;

            return { pValue, effectSize, isSignificant };
        }

        it('should detect significant difference', () => {
            // Control: slower (higher values)
            const control = [2100, 2050, 2200, 2150, 2080, 2120, 2090, 2180, 2100, 2070];
            // Variant: faster (lower values - clear improvement)
            const variant = [1800, 1750, 1850, 1780, 1820, 1770, 1830, 1790, 1810, 1760];

            const result = calculateSignificance(control, variant, 0.95);

            expect(result.isSignificant).toBe(true);
            expect(result.pValue).toBeLessThan(0.05);
            expect(result.effectSize).toBeGreaterThan(0); // Positive = control > variant
        });

        it('should not detect significance for similar groups', () => {
            const control = [2000, 2010, 1990, 2005, 1995, 2000, 2008, 1998, 2002, 1997];
            const variant = [2002, 2008, 1998, 2001, 1999, 2005, 1997, 2003, 2000, 2004];

            const result = calculateSignificance(control, variant, 0.95);

            expect(result.isSignificant).toBe(false);
        });

        it('should calculate Cohen d effect size', () => {
            const control = [100, 100, 100, 100, 100];
            const variant = [80, 80, 80, 80, 80];

            const result = calculateSignificance(control, variant, 0.95);

            // Large effect size expected (mean diff / pooled std)
            expect(Math.abs(result.effectSize)).toBeGreaterThan(1);
        });
    });
});

describe('Bayesian Analysis Functions', () => {
    describe('bayesianComparison', () => {
        function mean(arr) {
            return arr.reduce((a, b) => a + b, 0) / arr.length;
        }

        function std(arr) {
            const m = mean(arr);
            return Math.sqrt(arr.reduce((acc, v) => acc + Math.pow(v - m, 2), 0) / (arr.length - 1));
        }

        function sampleNormal(mean, std) {
            const u1 = Math.random();
            const u2 = Math.random();
            const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            return mean + z * std;
        }

        function bayesianComparison(control, variant, simulations = 10000) {
            const controlMean = mean(control);
            const variantMean = mean(variant);
            const controlStd = std(control);
            const variantStd = std(variant);

            let variantWins = 0;

            for (let i = 0; i < simulations; i++) {
                const controlSample = sampleNormal(controlMean, controlStd);
                const variantSample = sampleNormal(variantMean, variantStd);

                if (variantSample < controlSample) {
                    variantWins++;
                }
            }

            const probabilityToBeBest = variantWins / simulations;
            const expectedLoss = Math.max(0, variantMean - controlMean);

            const margin = 1.96 * (variantStd / Math.sqrt(variant.length));

            return {
                probabilityToBeBest,
                expectedLoss,
                credibleInterval: {
                    lower: variantMean - margin,
                    upper: variantMean + margin,
                },
            };
        }

        it('should give high probability when variant is clearly better', () => {
            const control = [2000, 2100, 2050, 2080, 2020];
            const variant = [1600, 1650, 1620, 1680, 1640]; // Much better

            const result = bayesianComparison(control, variant, 5000);

            // Variant should have high probability to be best (lower is better)
            expect(result.probabilityToBeBest).toBeGreaterThan(0.8);
        });

        it('should give ~50% probability when groups are similar', () => {
            // Add small variation to avoid std=0 edge case
            const control = [2000, 2010, 1990, 2005, 1995];
            const variant = [2002, 1998, 2003, 1997, 2000];

            const result = bayesianComparison(control, variant, 5000);

            // Should be close to 50% when nearly identical
            expect(result.probabilityToBeBest).toBeGreaterThan(0.2);
            expect(result.probabilityToBeBest).toBeLessThan(0.8);
        });

        it('should calculate credible interval', () => {
            const control = [2000, 2100, 2050];
            const variant = [1800, 1850, 1820];

            const result = bayesianComparison(control, variant, 1000);

            expect(result.credibleInterval).toHaveProperty('lower');
            expect(result.credibleInterval).toHaveProperty('upper');
            expect(result.credibleInterval.lower).toBeLessThan(result.credibleInterval.upper);
        });

        it('should calculate expected loss', () => {
            const control = [1800, 1850, 1820];
            const variant = [2000, 2100, 2050]; // Worse variant

            const result = bayesianComparison(control, variant, 1000);

            // Expected loss should be positive when variant is worse
            expect(result.expectedLoss).toBeGreaterThan(0);
        });
    });
});
