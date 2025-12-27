#!/usr/bin/env node

/**
 * Third-Party Script Audit Tool
 *
 * Analysiert alle Third-Party Scripts auf einer Seite und erstellt
 * Performance-Report mit Empfehlungen.
 *
 * Usage:
 *   node audit-third-party.js https://shop.example.com
 *   node audit-third-party.js https://shop.example.com --json
 *   node audit-third-party.js https://shop.example.com --output=report.json
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

// Configuration
const CONFIG = {
    userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 },
    timeout: 30000,
    thresholds: {
        maxScriptSize: 100 * 1024, // 100 KB
        maxLoadTime: 2000, // 2 seconds
        maxScriptsTotal: 20,
    },
};

/**
 * Main audit function
 */
async function auditThirdPartyScripts(url, options = {}) {
    console.log(`🔍 Auditing Third-Party Scripts: ${url}\n`);

    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    try {
        const page = await browser.newPage();
        await page.setUserAgent(CONFIG.userAgent);
        await page.setViewport(CONFIG.viewport);

        // Collect network requests
        const scripts = [];
        const requestMap = new Map();

        page.on('request', (request) => {
            if (request.resourceType() === 'script') {
                requestMap.set(request.url(), {
                    url: request.url(),
                    startTime: Date.now(),
                });
            }
        });

        page.on('response', async (response) => {
            if (response.request().resourceType() === 'script') {
                const url = response.url();
                const requestData = requestMap.get(url);

                if (requestData) {
                    const headers = response.headers();
                    const size = parseInt(headers['content-length'] || '0', 10);
                    const loadTime = Date.now() - requestData.startTime;

                    // Determine if third-party
                    const pageUrl = new URL(page.url());
                    const scriptUrl = new URL(url);
                    const isThirdParty = scriptUrl.hostname !== pageUrl.hostname;

                    if (isThirdParty) {
                        scripts.push({
                            url,
                            domain: scriptUrl.hostname,
                            size,
                            loadTime,
                            status: response.status(),
                            cached: headers['x-cache'] === 'HIT' || headers['cf-cache-status'] === 'HIT',
                            compression: headers['content-encoding'] || 'none',
                            cacheControl: headers['cache-control'] || 'none',
                            timing: await getResourceTiming(page, url),
                        });
                    }
                }
            }
        });

        // Navigate and wait
        await page.goto(url, {
            waitUntil: 'networkidle2',
            timeout: CONFIG.timeout,
        });

        // Wait additional time for lazy-loaded scripts
        await page.waitForTimeout(3000);

        // Analyze loaded scripts
        const scriptAnalysis = await analyzeScripts(page);

        // Collect performance metrics
        const metrics = await page.metrics();
        const performance = await page.evaluate(() => {
            const nav = performance.getEntriesByType('navigation')[0];
            const paint = performance.getEntriesByType('paint');

            return {
                domContentLoaded: nav.domContentLoadedEventEnd - nav.domContentLoadedEventStart,
                loadComplete: nav.loadEventEnd - nav.loadEventStart,
                firstPaint: paint.find(p => p.name === 'first-paint')?.startTime || 0,
                firstContentfulPaint: paint.find(p => p.name === 'first-contentful-paint')?.startTime || 0,
            };
        });

        // Generate report
        const report = generateReport(scripts, scriptAnalysis, metrics, performance);

        // Output
        if (options.json || options.output) {
            const output = JSON.stringify(report, null, 2);

            if (options.output) {
                fs.writeFileSync(options.output, output);
                console.log(`\n✅ Report saved to: ${options.output}`);
            } else {
                console.log(output);
            }
        } else {
            printReport(report);
        }

        return report;

    } catch (error) {
        console.error('❌ Audit failed:', error.message);
        throw error;
    } finally {
        await browser.close();
    }
}

/**
 * Get Resource Timing for script
 */
async function getResourceTiming(page, url) {
    return page.evaluate((scriptUrl) => {
        const entries = performance.getEntriesByType('resource');
        const entry = entries.find(e => e.name === scriptUrl);

        if (!entry) return null;

        return {
            dns: entry.domainLookupEnd - entry.domainLookupStart,
            tcp: entry.connectEnd - entry.connectStart,
            request: entry.responseStart - entry.requestStart,
            response: entry.responseEnd - entry.responseStart,
            total: entry.duration,
        };
    }, url);
}

/**
 * Analyze script content and behavior
 */
async function analyzeScripts(page) {
    return page.evaluate(() => {
        const scripts = Array.from(document.querySelectorAll('script[src]'));

        return scripts.map(script => ({
            url: script.src,
            async: script.async,
            defer: script.defer,
            type: script.type || 'text/javascript',
            position: script.parentElement.tagName.toLowerCase(),
        }));
    });
}

/**
 * Generate audit report
 */
function generateReport(scripts, scriptAnalysis, metrics, performance) {
    const totalSize = scripts.reduce((sum, s) => sum + s.size, 0);
    const totalLoadTime = scripts.reduce((sum, s) => sum + s.loadTime, 0);
    const avgLoadTime = scripts.length > 0 ? totalLoadTime / scripts.length : 0;

    // Categorize scripts by domain
    const byDomain = scripts.reduce((acc, script) => {
        if (!acc[script.domain]) {
            acc[script.domain] = [];
        }
        acc[script.domain].push(script);
        return acc;
    }, {});

    // Identify issues
    const issues = [];

    scripts.forEach(script => {
        if (script.size > CONFIG.thresholds.maxScriptSize) {
            issues.push({
                type: 'size',
                severity: 'high',
                script: script.url,
                message: `Script size (${formatBytes(script.size)}) exceeds threshold (${formatBytes(CONFIG.thresholds.maxScriptSize)})`,
            });
        }

        if (script.loadTime > CONFIG.thresholds.maxLoadTime) {
            issues.push({
                type: 'load_time',
                severity: 'medium',
                script: script.url,
                message: `Load time (${script.loadTime}ms) exceeds threshold (${CONFIG.thresholds.maxLoadTime}ms)`,
            });
        }

        if (script.compression === 'none') {
            issues.push({
                type: 'compression',
                severity: 'medium',
                script: script.url,
                message: 'Script is not compressed (GZIP/Brotli)',
            });
        }

        if (script.cacheControl === 'none' || script.cacheControl.includes('no-cache')) {
            issues.push({
                type: 'caching',
                severity: 'low',
                script: script.url,
                message: 'Script has no cache headers',
            });
        }
    });

    if (scripts.length > CONFIG.thresholds.maxScriptsTotal) {
        issues.push({
            type: 'count',
            severity: 'high',
            message: `Too many third-party scripts (${scripts.length}). Consider consolidation.`,
        });
    }

    // Calculate scores
    const impactScore = calculateImpactScore(scripts, issues);
    const performanceScore = calculatePerformanceScore(performance, totalSize);

    // Recommendations
    const recommendations = generateRecommendations(scripts, issues, scriptAnalysis);

    return {
        url: scripts.length > 0 ? new URL(scripts[0].url).origin : 'unknown',
        timestamp: new Date().toISOString(),
        summary: {
            totalScripts: scripts.length,
            totalSize: totalSize,
            totalSizeFormatted: formatBytes(totalSize),
            avgLoadTime: Math.round(avgLoadTime),
            domains: Object.keys(byDomain).length,
        },
        performance: {
            domContentLoaded: Math.round(performance.domContentLoaded),
            loadComplete: Math.round(performance.loadComplete),
            firstPaint: Math.round(performance.firstPaint),
            firstContentfulPaint: Math.round(performance.firstContentfulPaint),
        },
        metrics: {
            jsHeapSize: metrics.JSHeapUsedSize,
            jsEventListeners: metrics.JSEventListeners,
            documents: metrics.Documents,
            nodes: metrics.Nodes,
        },
        scripts: scripts.sort((a, b) => b.size - a.size), // Sort by size descending
        byDomain: byDomain,
        scriptAnalysis: scriptAnalysis,
        issues: issues,
        scores: {
            impact: impactScore,
            performance: performanceScore,
            overall: Math.round((impactScore + performanceScore) / 2),
        },
        recommendations: recommendations,
    };
}

/**
 * Calculate impact score (0-100, higher = better)
 */
function calculateImpactScore(scripts, issues) {
    let score = 100;

    // Size penalty
    const totalSize = scripts.reduce((sum, s) => sum + s.size, 0);
    if (totalSize > 500 * 1024) {
        score -= 30;
    } else if (totalSize > 250 * 1024) {
        score -= 15;
    }

    // Count penalty
    if (scripts.length > 30) {
        score -= 20;
    } else if (scripts.length > 20) {
        score -= 10;
    }

    // Issue penalties
    const highIssues = issues.filter(i => i.severity === 'high').length;
    const mediumIssues = issues.filter(i => i.severity === 'medium').length;

    score -= highIssues * 10;
    score -= mediumIssues * 5;

    return Math.max(0, Math.min(100, score));
}

/**
 * Calculate performance score (0-100, higher = better)
 */
function calculatePerformanceScore(performance, totalSize) {
    let score = 100;

    // FCP penalty
    if (performance.firstContentfulPaint > 2500) {
        score -= 30;
    } else if (performance.firstContentfulPaint > 1800) {
        score -= 15;
    }

    // Load complete penalty
    if (performance.loadComplete > 5000) {
        score -= 20;
    } else if (performance.loadComplete > 3000) {
        score -= 10;
    }

    return Math.max(0, Math.min(100, score));
}

/**
 * Generate recommendations
 */
function generateRecommendations(scripts, issues, scriptAnalysis) {
    const recommendations = [];

    // Async/defer recommendations
    const blockingScripts = scriptAnalysis.filter(s => !s.async && !s.defer);
    if (blockingScripts.length > 0) {
        recommendations.push({
            priority: 'high',
            category: 'loading',
            title: 'Use async or defer for non-critical scripts',
            description: `${blockingScripts.length} scripts are blocking rendering. Add async or defer attributes.`,
            scripts: blockingScripts.map(s => s.url),
        });
    }

    // Compression
    const uncompressed = scripts.filter(s => s.compression === 'none');
    if (uncompressed.length > 0) {
        recommendations.push({
            priority: 'medium',
            category: 'compression',
            title: 'Enable compression for all scripts',
            description: `${uncompressed.length} scripts are not compressed. Enable GZIP or Brotli.`,
            scripts: uncompressed.map(s => s.url),
        });
    }

    // Caching
    const uncached = scripts.filter(s => s.cacheControl === 'none' || s.cacheControl.includes('no-cache'));
    if (uncached.length > 0) {
        recommendations.push({
            priority: 'medium',
            category: 'caching',
            title: 'Configure cache headers',
            description: `${uncached.length} scripts have no cache headers. Add Cache-Control and Expires headers.`,
            scripts: uncached.slice(0, 5).map(s => s.url),
        });
    }

    // Lazy loading
    if (scripts.length > 15) {
        recommendations.push({
            priority: 'high',
            category: 'optimization',
            title: 'Implement lazy loading for non-critical scripts',
            description: 'Use lazy loading strategy to defer non-critical scripts (GTM, analytics, etc.)',
        });
    }

    // Consolidation
    const domains = new Set(scripts.map(s => s.domain));
    if (domains.size > 10) {
        recommendations.push({
            priority: 'medium',
            category: 'optimization',
            title: 'Reduce number of third-party domains',
            description: `${domains.size} different domains detected. Consider consolidating or removing unused scripts.`,
        });
    }

    return recommendations;
}

/**
 * Print human-readable report
 */
function printReport(report) {
    console.log('═══════════════════════════════════════════════════════');
    console.log('  THIRD-PARTY SCRIPTS AUDIT REPORT');
    console.log('═══════════════════════════════════════════════════════\n');

    console.log('📊 SUMMARY');
    console.log('─────────────────────────────────────────────────────');
    console.log(`  Total Scripts:     ${report.summary.totalScripts}`);
    console.log(`  Total Size:        ${report.summary.totalSizeFormatted}`);
    console.log(`  Avg Load Time:     ${report.summary.avgLoadTime}ms`);
    console.log(`  Unique Domains:    ${report.summary.domains}\n`);

    console.log('⚡ PERFORMANCE');
    console.log('─────────────────────────────────────────────────────');
    console.log(`  First Paint:       ${report.performance.firstPaint}ms`);
    console.log(`  FCP:               ${report.performance.firstContentfulPaint}ms`);
    console.log(`  DOM Content:       ${report.performance.domContentLoaded}ms`);
    console.log(`  Load Complete:     ${report.performance.loadComplete}ms\n`);

    console.log('📈 SCORES');
    console.log('─────────────────────────────────────────────────────');
    console.log(`  Impact Score:      ${report.scores.impact}/100 ${getScoreEmoji(report.scores.impact)}`);
    console.log(`  Performance Score: ${report.scores.performance}/100 ${getScoreEmoji(report.scores.performance)}`);
    console.log(`  Overall Score:     ${report.scores.overall}/100 ${getScoreEmoji(report.scores.overall)}\n`);

    if (report.issues.length > 0) {
        console.log('⚠️  ISSUES');
        console.log('─────────────────────────────────────────────────────');
        const grouped = groupBy(report.issues, 'type');
        Object.entries(grouped).forEach(([type, issues]) => {
            console.log(`  ${type.toUpperCase()}: ${issues.length} issue(s)`);
            issues.slice(0, 3).forEach(issue => {
                console.log(`    • ${issue.message}`);
            });
        });
        console.log();
    }

    if (report.recommendations.length > 0) {
        console.log('💡 RECOMMENDATIONS');
        console.log('─────────────────────────────────────────────────────');
        report.recommendations.forEach((rec, i) => {
            const priorityEmoji = rec.priority === 'high' ? '🔴' : rec.priority === 'medium' ? '🟡' : '🟢';
            console.log(`  ${i + 1}. ${priorityEmoji} ${rec.title}`);
            console.log(`     ${rec.description}\n`);
        });
    }

    console.log('═══════════════════════════════════════════════════════\n');
}

/**
 * Utility: Format bytes
 */
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

/**
 * Utility: Get score emoji
 */
function getScoreEmoji(score) {
    if (score >= 80) return '🟢';
    if (score >= 50) return '🟡';
    return '🔴';
}

/**
 * Utility: Group by key
 */
function groupBy(array, key) {
    return array.reduce((acc, item) => {
        const group = item[key];
        if (!acc[group]) acc[group] = [];
        acc[group].push(item);
        return acc;
    }, {});
}

// CLI
if (require.main === module) {
    const args = process.argv.slice(2);

    if (args.length === 0 || args[0] === '--help') {
        console.log(`
Usage: node audit-third-party.js <url> [options]

Options:
  --json              Output as JSON
  --output=<file>     Save report to file
  --help              Show this help

Examples:
  node audit-third-party.js https://shop.example.com
  node audit-third-party.js https://shop.example.com --json
  node audit-third-party.js https://shop.example.com --output=report.json
        `);
        process.exit(0);
    }

    const url = args[0];
    const options = {
        json: args.includes('--json'),
        output: args.find(arg => arg.startsWith('--output='))?.split('=')[1],
    };

    auditThirdPartyScripts(url, options)
        .then(() => process.exit(0))
        .catch(err => {
            console.error(err);
            process.exit(1);
        });
}

module.exports = { auditThirdPartyScripts };
