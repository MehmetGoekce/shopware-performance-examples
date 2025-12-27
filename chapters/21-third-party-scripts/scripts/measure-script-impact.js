#!/usr/bin/env node

/**
 * Script Impact Measurement Tool
 *
 * Misst den Performance-Impact einzelner Third-Party Scripts durch:
 * - A/B Vergleich (mit/ohne Script)
 * - Core Web Vitals Messung
 * - Blocking Time Analyse
 * - Netzwerk-Impact
 *
 * Usage:
 *   node measure-script-impact.js https://shop.example.com https://script-to-test.js
 *   node measure-script-impact.js https://shop.example.com --all
 *   node measure-script-impact.js https://shop.example.com --script="googletagmanager.com"
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */

const puppeteer = require('puppeteer');

// Configuration
const CONFIG = {
    runs: 5, // Anzahl Messungen für Durchschnitt
    viewport: { width: 1920, height: 1080 },
    throttling: {
        cpu: 4, // 4x slowdown für realistic testing
        network: {
            offline: false,
            downloadThroughput: (1.6 * 1024 * 1024) / 8, // 1.6 Mbps
            uploadThroughput: (750 * 1024) / 8, // 750 Kbps
            latency: 40, // 40ms RTT
        },
    },
};

/**
 * Measure page performance with/without specific script
 */
async function measureScriptImpact(url, scriptPattern, options = {}) {
    console.log(`🔬 Measuring impact of script: ${scriptPattern}`);
    console.log(`   URL: ${url}\n`);

    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    try {
        // 1. Baseline measurement (with all scripts)
        console.log('📊 Baseline measurement (all scripts)...');
        const baselineMetrics = await measurePerformance(browser, url, null, options);

        // 2. Measurement without target script
        console.log(`📊 Measurement without ${scriptPattern}...\n`);
        const blockedMetrics = await measurePerformance(browser, url, scriptPattern, options);

        // 3. Calculate impact
        const impact = calculateImpact(baselineMetrics, blockedMetrics);

        // 4. Generate report
        const report = {
            url: url,
            script: scriptPattern,
            timestamp: new Date().toISOString(),
            runs: CONFIG.runs,
            baseline: baselineMetrics,
            blocked: blockedMetrics,
            impact: impact,
        };

        // Output
        if (options.json) {
            console.log(JSON.stringify(report, null, 2));
        } else {
            printImpactReport(report);
        }

        return report;

    } finally {
        await browser.close();
    }
}

/**
 * Measure page performance multiple times
 */
async function measurePerformance(browser, url, blockPattern, options) {
    const measurements = [];

    for (let i = 0; i < CONFIG.runs; i++) {
        const page = await browser.newPage();

        try {
            // Setup
            await page.setViewport(CONFIG.viewport);

            // CPU throttling
            const client = await page.target().createCDPSession();
            await client.send('Emulation.setCPUThrottlingRate', { rate: CONFIG.throttling.cpu });

            // Network throttling
            if (options.throttle !== false) {
                await page.emulateNetworkConditions(CONFIG.throttling.network);
            }

            // Block specific script if pattern provided
            if (blockPattern) {
                await page.setRequestInterception(true);
                page.on('request', (request) => {
                    if (request.resourceType() === 'script' && request.url().includes(blockPattern)) {
                        request.abort();
                    } else {
                        request.continue();
                    }
                });
            }

            // Collect metrics
            const metrics = await collectMetrics(page, url);
            measurements.push(metrics);

            console.log(`  Run ${i + 1}/${CONFIG.runs} complete`);

        } finally {
            await page.close();
        }
    }

    // Average results
    return averageMetrics(measurements);
}

/**
 * Collect all relevant metrics
 */
async function collectMetrics(page, url) {
    const startTime = Date.now();

    // Navigate
    await page.goto(url, {
        waitUntil: 'networkidle2',
        timeout: 60000,
    });

    // Wait for page to settle
    await page.waitForTimeout(2000);

    const navigationTime = Date.now() - startTime;

    // Core Web Vitals
    const webVitals = await page.evaluate(() => {
        return new Promise((resolve) => {
            const vitals = {
                lcp: 0,
                fid: 0,
                cls: 0,
                fcp: 0,
                ttfb: 0,
            };

            // Largest Contentful Paint
            const lcpObserver = new PerformanceObserver((list) => {
                const entries = list.getEntries();
                const lastEntry = entries[entries.length - 1];
                vitals.lcp = lastEntry.renderTime || lastEntry.loadTime;
            });
            lcpObserver.observe({ type: 'largest-contentful-paint', buffered: true });

            // Cumulative Layout Shift
            const clsObserver = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                    if (!entry.hadRecentInput) {
                        vitals.cls += entry.value;
                    }
                }
            });
            clsObserver.observe({ type: 'layout-shift', buffered: true });

            // Navigation Timing
            const navTiming = performance.getEntriesByType('navigation')[0];
            if (navTiming) {
                vitals.ttfb = navTiming.responseStart - navTiming.requestStart;
            }

            // Paint Timing
            const paintTiming = performance.getEntriesByType('paint');
            const fcpEntry = paintTiming.find(entry => entry.name === 'first-contentful-paint');
            if (fcpEntry) {
                vitals.fcp = fcpEntry.startTime;
            }

            setTimeout(() => resolve(vitals), 1000);
        });
    });

    // JavaScript metrics
    const jsMetrics = await page.metrics();

    // Network metrics
    const networkMetrics = await page.evaluate(() => {
        const resources = performance.getEntriesByType('resource');

        let totalSize = 0;
        let totalDuration = 0;
        let scriptCount = 0;
        let scriptSize = 0;

        resources.forEach(resource => {
            totalDuration += resource.duration;
            if (resource.transferSize) {
                totalSize += resource.transferSize;
            }

            if (resource.initiatorType === 'script') {
                scriptCount++;
                if (resource.transferSize) {
                    scriptSize += resource.transferSize;
                }
            }
        });

        return {
            totalRequests: resources.length,
            totalSize: totalSize,
            totalDuration: totalDuration,
            scriptCount: scriptCount,
            scriptSize: scriptSize,
        };
    });

    // Long Tasks
    const longTasks = await page.evaluate(() => {
        return new Promise((resolve) => {
            const tasks = [];
            const observer = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                    tasks.push({
                        duration: entry.duration,
                        startTime: entry.startTime,
                    });
                }
            });

            try {
                observer.observe({ type: 'longtask', buffered: true });
                setTimeout(() => resolve(tasks), 1000);
            } catch (e) {
                // longtask API not available
                resolve([]);
            }
        });
    });

    const totalBlockingTime = longTasks.reduce((sum, task) => {
        // Only count tasks > 50ms, and only the portion > 50ms
        return sum + Math.max(0, task.duration - 50);
    }, 0);

    return {
        navigationTime,
        webVitals,
        jsMetrics: {
            heapSize: jsMetrics.JSHeapUsedSize,
            eventListeners: jsMetrics.JSEventListeners,
            documents: jsMetrics.Documents,
            nodes: jsMetrics.Nodes,
            scriptDuration: jsMetrics.ScriptDuration,
            taskDuration: jsMetrics.TaskDuration,
        },
        networkMetrics,
        longTasks: {
            count: longTasks.length,
            totalBlockingTime: totalBlockingTime,
        },
    };
}

/**
 * Average multiple measurements
 */
function averageMetrics(measurements) {
    const count = measurements.length;

    const avg = {
        navigationTime: 0,
        webVitals: {
            lcp: 0,
            fid: 0,
            cls: 0,
            fcp: 0,
            ttfb: 0,
        },
        jsMetrics: {
            heapSize: 0,
            eventListeners: 0,
            documents: 0,
            nodes: 0,
            scriptDuration: 0,
            taskDuration: 0,
        },
        networkMetrics: {
            totalRequests: 0,
            totalSize: 0,
            totalDuration: 0,
            scriptCount: 0,
            scriptSize: 0,
        },
        longTasks: {
            count: 0,
            totalBlockingTime: 0,
        },
    };

    measurements.forEach(m => {
        avg.navigationTime += m.navigationTime;

        Object.keys(avg.webVitals).forEach(key => {
            avg.webVitals[key] += m.webVitals[key];
        });

        Object.keys(avg.jsMetrics).forEach(key => {
            avg.jsMetrics[key] += m.jsMetrics[key];
        });

        Object.keys(avg.networkMetrics).forEach(key => {
            avg.networkMetrics[key] += m.networkMetrics[key];
        });

        avg.longTasks.count += m.longTasks.count;
        avg.longTasks.totalBlockingTime += m.longTasks.totalBlockingTime;
    });

    // Divide by count
    avg.navigationTime = Math.round(avg.navigationTime / count);

    Object.keys(avg.webVitals).forEach(key => {
        avg.webVitals[key] = Math.round((avg.webVitals[key] / count) * 10) / 10;
    });

    Object.keys(avg.jsMetrics).forEach(key => {
        avg.jsMetrics[key] = Math.round(avg.jsMetrics[key] / count);
    });

    Object.keys(avg.networkMetrics).forEach(key => {
        avg.networkMetrics[key] = Math.round(avg.networkMetrics[key] / count);
    });

    avg.longTasks.count = Math.round(avg.longTasks.count / count);
    avg.longTasks.totalBlockingTime = Math.round(avg.longTasks.totalBlockingTime / count);

    return avg;
}

/**
 * Calculate impact (improvement when script is blocked)
 */
function calculateImpact(baseline, blocked) {
    const impact = {};

    // Navigation time improvement
    impact.navigationTime = {
        absolute: baseline.navigationTime - blocked.navigationTime,
        relative: calculatePercentage(baseline.navigationTime, blocked.navigationTime),
    };

    // Web Vitals improvements
    impact.webVitals = {};
    Object.keys(baseline.webVitals).forEach(key => {
        impact.webVitals[key] = {
            absolute: baseline.webVitals[key] - blocked.webVitals[key],
            relative: calculatePercentage(baseline.webVitals[key], blocked.webVitals[key]),
        };
    });

    // JS metrics improvements
    impact.jsMetrics = {};
    Object.keys(baseline.jsMetrics).forEach(key => {
        impact.jsMetrics[key] = {
            absolute: baseline.jsMetrics[key] - blocked.jsMetrics[key],
            relative: calculatePercentage(baseline.jsMetrics[key], blocked.jsMetrics[key]),
        };
    });

    // Network improvements
    impact.networkMetrics = {};
    Object.keys(baseline.networkMetrics).forEach(key => {
        impact.networkMetrics[key] = {
            absolute: baseline.networkMetrics[key] - blocked.networkMetrics[key],
            relative: calculatePercentage(baseline.networkMetrics[key], blocked.networkMetrics[key]),
        };
    });

    // Blocking time improvement
    impact.totalBlockingTime = {
        absolute: baseline.longTasks.totalBlockingTime - blocked.longTasks.totalBlockingTime,
        relative: calculatePercentage(baseline.longTasks.totalBlockingTime, blocked.longTasks.totalBlockingTime),
    };

    // Overall impact score (0-100)
    impact.score = calculateImpactScore(impact);

    return impact;
}

/**
 * Calculate percentage difference
 */
function calculatePercentage(before, after) {
    if (before === 0) return 0;
    return Math.round(((before - after) / before) * 100);
}

/**
 * Calculate overall impact score
 */
function calculateImpactScore(impact) {
    let score = 0;
    let weight = 0;

    // LCP weight: 30%
    if (impact.webVitals.lcp.relative > 0) {
        score += impact.webVitals.lcp.relative * 0.3;
        weight += 0.3;
    }

    // FCP weight: 20%
    if (impact.webVitals.fcp.relative > 0) {
        score += impact.webVitals.fcp.relative * 0.2;
        weight += 0.2;
    }

    // TBT weight: 30%
    if (impact.totalBlockingTime.relative > 0) {
        score += impact.totalBlockingTime.relative * 0.3;
        weight += 0.3;
    }

    // Network size weight: 20%
    if (impact.networkMetrics.scriptSize.relative > 0) {
        score += impact.networkMetrics.scriptSize.relative * 0.2;
        weight += 0.2;
    }

    return weight > 0 ? Math.round(score / weight) : 0;
}

/**
 * Print impact report
 */
function printImpactReport(report) {
    console.log('═══════════════════════════════════════════════════════');
    console.log('  SCRIPT IMPACT ANALYSIS');
    console.log('═══════════════════════════════════════════════════════\n');

    console.log(`🎯 Script: ${report.script}`);
    console.log(`📍 URL:    ${report.url}`);
    console.log(`🔄 Runs:   ${report.runs}\n`);

    console.log('⚡ CORE WEB VITALS IMPACT');
    console.log('─────────────────────────────────────────────────────');
    printMetricComparison('LCP', report.baseline.webVitals.lcp, report.blocked.webVitals.lcp, 'ms');
    printMetricComparison('FCP', report.baseline.webVitals.fcp, report.blocked.webVitals.fcp, 'ms');
    printMetricComparison('CLS', report.baseline.webVitals.cls, report.blocked.webVitals.cls, '');
    printMetricComparison('TTFB', report.baseline.webVitals.ttfb, report.blocked.webVitals.ttfb, 'ms');
    console.log();

    console.log('🚫 BLOCKING TIME');
    console.log('─────────────────────────────────────────────────────');
    printMetricComparison('Total Blocking Time',
        report.baseline.longTasks.totalBlockingTime,
        report.blocked.longTasks.totalBlockingTime,
        'ms'
    );
    console.log();

    console.log('📊 NETWORK IMPACT');
    console.log('─────────────────────────────────────────────────────');
    printMetricComparison('Script Count',
        report.baseline.networkMetrics.scriptCount,
        report.blocked.networkMetrics.scriptCount,
        ''
    );
    printMetricComparison('Script Size',
        formatBytes(report.baseline.networkMetrics.scriptSize),
        formatBytes(report.blocked.networkMetrics.scriptSize),
        ''
    );
    printMetricComparison('Total Requests',
        report.baseline.networkMetrics.totalRequests,
        report.blocked.networkMetrics.totalRequests,
        ''
    );
    console.log();

    console.log('💾 JAVASCRIPT HEAP');
    console.log('─────────────────────────────────────────────────────');
    printMetricComparison('Heap Size',
        formatBytes(report.baseline.jsMetrics.heapSize),
        formatBytes(report.blocked.jsMetrics.heapSize),
        ''
    );
    console.log();

    console.log('📈 OVERALL IMPACT SCORE');
    console.log('─────────────────────────────────────────────────────');
    const score = report.impact.score;
    const emoji = score > 50 ? '🔴 HIGH' : score > 20 ? '🟡 MEDIUM' : '🟢 LOW';
    console.log(`  ${emoji}: ${score}% performance impact\n`);

    if (score > 50) {
        console.log('💡 RECOMMENDATION: This script has HIGH impact. Consider:');
        console.log('   • Lazy loading (defer until user interaction)');
        console.log('   • Moving to Web Worker (Partytown)');
        console.log('   • Server-side alternative');
        console.log('   • Removing if not critical\n');
    } else if (score > 20) {
        console.log('💡 RECOMMENDATION: This script has MEDIUM impact. Consider:');
        console.log('   • Async/defer loading');
        console.log('   • Lazy loading for non-critical pages\n');
    }

    console.log('═══════════════════════════════════════════════════════\n');
}

/**
 * Print metric comparison
 */
function printMetricComparison(label, baseline, blocked, unit) {
    const improvement = typeof baseline === 'number'
        ? baseline - blocked
        : 0;

    const percent = typeof baseline === 'number' && baseline > 0
        ? Math.round(((baseline - blocked) / baseline) * 100)
        : 0;

    const emoji = improvement > 0 ? '✅' : improvement < 0 ? '⚠️ ' : '➖';
    const sign = improvement > 0 ? '-' : improvement < 0 ? '+' : ' ';

    console.log(`  ${label.padEnd(20)} ${String(baseline).padStart(10)}${unit} → ${String(blocked).padStart(10)}${unit}  ${emoji} ${sign}${Math.abs(percent)}%`);
}

/**
 * Format bytes
 */
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

// CLI
if (require.main === module) {
    const args = process.argv.slice(2);

    if (args.length < 2 || args[0] === '--help') {
        console.log(`
Usage: node measure-script-impact.js <url> <script-pattern> [options]

Arguments:
  url              URL to test
  script-pattern   Pattern to match script URL (e.g., "googletagmanager.com")

Options:
  --json           Output as JSON
  --no-throttle    Disable CPU/network throttling

Examples:
  node measure-script-impact.js https://shop.example.com googletagmanager.com
  node measure-script-impact.js https://shop.example.com facebook.net --json
  node measure-script-impact.js https://shop.example.com hotjar.com --no-throttle
        `);
        process.exit(0);
    }

    const url = args[0];
    const scriptPattern = args[1];
    const options = {
        json: args.includes('--json'),
        throttle: !args.includes('--no-throttle'),
    };

    measureScriptImpact(url, scriptPattern, options)
        .then(() => process.exit(0))
        .catch(err => {
            console.error(err);
            process.exit(1);
        });
}

module.exports = { measureScriptImpact };
