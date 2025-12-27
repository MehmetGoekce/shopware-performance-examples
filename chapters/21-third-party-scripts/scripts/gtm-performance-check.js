#!/usr/bin/env node

/**
 * Google Tag Manager Performance Checker
 *
 * Analysiert GTM-Container auf Performance-Probleme:
 * - Container-Größe
 * - Anzahl Tags/Trigger/Variablen
 * - Blocking vs. Non-Blocking Tags
 * - Performance-Impact
 *
 * Usage:
 *   node gtm-performance-check.js GTM-XXXXXXX
 *   node gtm-performance-check.js GTM-XXXXXXX --detailed
 *   node gtm-performance-check.js GTM-XXXXXXX --json
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */

const puppeteer = require('puppeteer');
const https = require('https');

// Configuration
const CONFIG = {
    gtmBaseUrl: 'https://www.googletagmanager.com/gtm.js',
    testUrl: 'https://example.com', // Fallback test page
    thresholds: {
        containerSize: 100 * 1024, // 100 KB
        estimatedTags: 20,
        loadTime: 2000, // 2 seconds
    },
};

/**
 * Main GTM performance check
 */
async function checkGTMPerformance(containerId, options = {}) {
    console.log(`🔍 Analyzing GTM Container: ${containerId}\n`);

    try {
        // 1. Fetch container and analyze size
        const containerAnalysis = await analyzeContainer(containerId);

        // 2. Test loading performance in browser
        const performanceAnalysis = await testContainerPerformance(containerId, options.testUrl);

        // 3. Analyze container content
        const contentAnalysis = await analyzeContainerContent(containerAnalysis.content);

        // 4. Generate report
        const report = {
            containerId: containerId,
            timestamp: new Date().toISOString(),
            container: containerAnalysis,
            performance: performanceAnalysis,
            content: contentAnalysis,
            score: calculateScore(containerAnalysis, performanceAnalysis, contentAnalysis),
            recommendations: generateRecommendations(containerAnalysis, performanceAnalysis, contentAnalysis),
        };

        // Output
        if (options.json) {
            console.log(JSON.stringify(report, null, 2));
        } else {
            printReport(report, options.detailed);
        }

        return report;

    } catch (error) {
        console.error('❌ Analysis failed:', error.message);
        throw error;
    }
}

/**
 * Analyze GTM container file
 */
async function analyzeContainer(containerId) {
    const url = `${CONFIG.gtmBaseUrl}?id=${containerId}`;

    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let data = '';

            res.on('data', (chunk) => {
                data += chunk;
            });

            res.on('end', () => {
                const size = Buffer.byteLength(data, 'utf8');
                const gzipEnabled = res.headers['content-encoding'] === 'gzip';
                const cacheControl = res.headers['cache-control'] || 'none';

                resolve({
                    url: url,
                    size: size,
                    sizeFormatted: formatBytes(size),
                    gzipEnabled: gzipEnabled,
                    cacheControl: cacheControl,
                    content: data,
                    status: res.statusCode,
                });
            });

        }).on('error', (err) => {
            reject(new Error(`Failed to fetch container: ${err.message}`));
        });
    });
}

/**
 * Test container loading performance
 */
async function testContainerPerformance(containerId, testUrl = null) {
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    try {
        const page = await browser.newPage();

        // Inject GTM snippet
        const gtmUrl = `${CONFIG.gtmBaseUrl}?id=${containerId}`;
        let gtmLoadTime = 0;
        let gtmSize = 0;

        page.on('response', async (response) => {
            if (response.url() === gtmUrl) {
                const timing = response.timing();
                gtmLoadTime = timing.receiveHeadersEnd;
                gtmSize = parseInt(response.headers()['content-length'] || '0', 10);
            }
        });

        // Navigate to test page with GTM
        await page.setContent(`
            <!DOCTYPE html>
            <html>
            <head>
                <script>
                window.dataLayer = window.dataLayer || [];
                </script>
            </head>
            <body>
                <h1>GTM Performance Test</h1>
                <script>
                (function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
                new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
                j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
                'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);
                })(window,document,'script','dataLayer','${containerId}');
                </script>
            </body>
            </html>
        `);

        // Wait for GTM to load
        await page.waitForTimeout(3000);

        // Collect performance metrics
        const metrics = await page.evaluate(() => {
            const gtmScript = document.querySelector('script[src*="googletagmanager.com/gtm.js"]');
            const dataLayerSize = window.dataLayer ? window.dataLayer.length : 0;

            // Get GTM performance entry
            const perfEntries = performance.getEntriesByType('resource');
            const gtmEntry = perfEntries.find(e => e.name.includes('googletagmanager.com/gtm.js'));

            return {
                dataLayerSize: dataLayerSize,
                scriptLoaded: !!gtmScript,
                timing: gtmEntry ? {
                    dns: gtmEntry.domainLookupEnd - gtmEntry.domainLookupStart,
                    tcp: gtmEntry.connectEnd - gtmEntry.connectStart,
                    request: gtmEntry.responseStart - gtmEntry.requestStart,
                    response: gtmEntry.responseEnd - gtmEntry.responseStart,
                    total: gtmEntry.duration,
                } : null,
            };
        });

        return {
            loadTime: gtmLoadTime || (metrics.timing?.total || 0),
            size: gtmSize,
            dataLayerSize: metrics.dataLayerSize,
            scriptLoaded: metrics.scriptLoaded,
            timing: metrics.timing,
        };

    } finally {
        await browser.close();
    }
}

/**
 * Analyze container content
 */
function analyzeContainerContent(content) {
    const analysis = {
        estimatedTags: 0,
        estimatedTriggers: 0,
        estimatedVariables: 0,
        hasCustomHTML: false,
        hasCustomJS: false,
        hasImageTags: false,
        externalDomains: new Set(),
        potentialIssues: [],
    };

    // Estimate tags (heuristic based on common patterns)
    const tagPatterns = [
        /\.sendto\(/g,
        /\.track\(/g,
        /\.push\(/g,
        /new\s+Image\(/g,
        /fbq\(/g,
        /gtag\(/g,
    ];

    tagPatterns.forEach(pattern => {
        const matches = content.match(pattern);
        if (matches) {
            analysis.estimatedTags += matches.length;
        }
    });

    // Estimate triggers
    const triggerPatterns = [
        /addEventListener/g,
        /\.on\(/g,
    ];

    triggerPatterns.forEach(pattern => {
        const matches = content.match(pattern);
        if (matches) {
            analysis.estimatedTriggers += matches.length;
        }
    });

    // Check for custom HTML/JS
    analysis.hasCustomHTML = content.includes('customScripts') || content.includes('innerHTML');
    analysis.hasCustomJS = content.includes('eval(') || content.includes('Function(');

    // Check for image tags (tracking pixels)
    analysis.hasImageTags = content.includes('new Image') || content.includes('<img');

    // Extract external domains
    const urlPattern = /https?:\/\/([a-zA-Z0-9.-]+)/g;
    let match;
    while ((match = urlPattern.exec(content)) !== null) {
        const domain = match[1];
        if (!domain.includes('googletagmanager.com') && !domain.includes('google-analytics.com')) {
            analysis.externalDomains.add(domain);
        }
    }

    // Detect potential issues
    if (content.includes('document.write')) {
        analysis.potentialIssues.push({
            type: 'blocking',
            severity: 'high',
            message: 'Container uses document.write() which blocks rendering',
        });
    }

    if (content.includes('eval(')) {
        analysis.potentialIssues.push({
            type: 'security',
            severity: 'medium',
            message: 'Container uses eval() which is a security risk',
        });
    }

    if (analysis.hasCustomHTML || analysis.hasCustomJS) {
        analysis.potentialIssues.push({
            type: 'custom_code',
            severity: 'medium',
            message: 'Container includes custom HTML/JS tags',
        });
    }

    if (analysis.externalDomains.size > 10) {
        analysis.potentialIssues.push({
            type: 'third_party',
            severity: 'high',
            message: `Container loads scripts from ${analysis.externalDomains.size} external domains`,
        });
    }

    analysis.externalDomains = Array.from(analysis.externalDomains);

    return analysis;
}

/**
 * Calculate performance score (0-100)
 */
function calculateScore(container, performance, content) {
    let score = 100;

    // Container size penalty
    if (container.size > CONFIG.thresholds.containerSize * 2) {
        score -= 30;
    } else if (container.size > CONFIG.thresholds.containerSize) {
        score -= 15;
    }

    // Load time penalty
    if (performance.loadTime > CONFIG.thresholds.loadTime * 2) {
        score -= 20;
    } else if (performance.loadTime > CONFIG.thresholds.loadTime) {
        score -= 10;
    }

    // Tag count penalty
    if (content.estimatedTags > 30) {
        score -= 20;
    } else if (content.estimatedTags > 20) {
        score -= 10;
    }

    // Issue penalties
    const highIssues = content.potentialIssues.filter(i => i.severity === 'high').length;
    const mediumIssues = content.potentialIssues.filter(i => i.severity === 'medium').length;

    score -= highIssues * 15;
    score -= mediumIssues * 5;

    // Compression bonus
    if (container.gzipEnabled) {
        score += 5;
    }

    return Math.max(0, Math.min(100, score));
}

/**
 * Generate optimization recommendations
 */
function generateRecommendations(container, performance, content) {
    const recommendations = [];

    // Size recommendations
    if (container.size > CONFIG.thresholds.containerSize) {
        recommendations.push({
            priority: 'high',
            category: 'size',
            title: 'Reduce container size',
            description: `Container size (${container.sizeFormatted}) exceeds recommended limit. Remove unused tags and consolidate similar tags.`,
        });
    }

    // Tag count
    if (content.estimatedTags > CONFIG.thresholds.estimatedTags) {
        recommendations.push({
            priority: 'high',
            category: 'optimization',
            title: 'Reduce number of tags',
            description: `Estimated ${content.estimatedTags} tags. Audit and remove unnecessary tags. Consider tag consolidation.`,
        });
    }

    // Loading strategy
    if (performance.loadTime > 1000) {
        recommendations.push({
            priority: 'high',
            category: 'loading',
            title: 'Implement lazy loading',
            description: 'Use lazy loading strategy to defer GTM loading by 2-3 seconds or until user interaction.',
        });
    }

    // Custom code
    if (content.hasCustomHTML || content.hasCustomJS) {
        recommendations.push({
            priority: 'medium',
            category: 'custom_code',
            title: 'Review custom HTML/JS tags',
            description: 'Custom code can impact performance. Review and optimize custom tags.',
        });
    }

    // Blocking code
    const blockingIssues = content.potentialIssues.filter(i => i.type === 'blocking');
    if (blockingIssues.length > 0) {
        recommendations.push({
            priority: 'high',
            category: 'blocking',
            title: 'Remove blocking code',
            description: 'Container contains render-blocking code (document.write). Refactor to non-blocking alternatives.',
        });
    }

    // External domains
    if (content.externalDomains.length > 10) {
        recommendations.push({
            priority: 'medium',
            category: 'third_party',
            title: 'Reduce external dependencies',
            description: `Container loads from ${content.externalDomains.length} external domains. Consolidate or remove unnecessary integrations.`,
        });
    }

    // Server-side tagging
    if (content.estimatedTags > 15 || container.size > 150 * 1024) {
        recommendations.push({
            priority: 'high',
            category: 'architecture',
            title: 'Consider server-side tagging',
            description: 'Move tags to server-side GTM to reduce client-side load and improve performance.',
        });
    }

    return recommendations;
}

/**
 * Print human-readable report
 */
function printReport(report, detailed = false) {
    console.log('═══════════════════════════════════════════════════════');
    console.log('  GTM CONTAINER PERFORMANCE REPORT');
    console.log('═══════════════════════════════════════════════════════\n');

    console.log(`📦 CONTAINER: ${report.containerId}`);
    console.log('─────────────────────────────────────────────────────');
    console.log(`  Size:              ${report.container.sizeFormatted}`);
    console.log(`  GZIP Enabled:      ${report.container.gzipEnabled ? '✅' : '❌'}`);
    console.log(`  Cache Control:     ${report.container.cacheControl}\n`);

    console.log('⚡ PERFORMANCE');
    console.log('─────────────────────────────────────────────────────');
    console.log(`  Load Time:         ${Math.round(report.performance.loadTime)}ms`);
    console.log(`  Data Layer Size:   ${report.performance.dataLayerSize} events`);
    console.log(`  Script Loaded:     ${report.performance.scriptLoaded ? '✅' : '❌'}\n`);

    if (detailed && report.performance.timing) {
        console.log('  Timing Breakdown:');
        console.log(`    DNS Lookup:      ${Math.round(report.performance.timing.dns)}ms`);
        console.log(`    TCP Connect:     ${Math.round(report.performance.timing.tcp)}ms`);
        console.log(`    Request:         ${Math.round(report.performance.timing.request)}ms`);
        console.log(`    Response:        ${Math.round(report.performance.timing.response)}ms`);
        console.log(`    Total:           ${Math.round(report.performance.timing.total)}ms\n`);
    }

    console.log('📊 CONTENT ANALYSIS');
    console.log('─────────────────────────────────────────────────────');
    console.log(`  Estimated Tags:    ${report.content.estimatedTags}`);
    console.log(`  Estimated Triggers: ${report.content.estimatedTriggers}`);
    console.log(`  Custom HTML/JS:    ${report.content.hasCustomHTML || report.content.hasCustomJS ? '⚠️  Yes' : '✅ No'}`);
    console.log(`  External Domains:  ${report.content.externalDomains.length}\n`);

    if (detailed && report.content.externalDomains.length > 0) {
        console.log('  External Domains:');
        report.content.externalDomains.slice(0, 10).forEach(domain => {
            console.log(`    • ${domain}`);
        });
        if (report.content.externalDomains.length > 10) {
            console.log(`    ... and ${report.content.externalDomains.length - 10} more`);
        }
        console.log();
    }

    console.log('📈 SCORE');
    console.log('─────────────────────────────────────────────────────');
    console.log(`  Performance Score: ${report.score}/100 ${getScoreEmoji(report.score)}\n`);

    if (report.content.potentialIssues.length > 0) {
        console.log('⚠️  POTENTIAL ISSUES');
        console.log('─────────────────────────────────────────────────────');
        report.content.potentialIssues.forEach(issue => {
            const severityEmoji = issue.severity === 'high' ? '🔴' : '🟡';
            console.log(`  ${severityEmoji} ${issue.message}`);
        });
        console.log();
    }

    if (report.recommendations.length > 0) {
        console.log('💡 RECOMMENDATIONS');
        console.log('─────────────────────────────────────────────────────');
        report.recommendations.forEach((rec, i) => {
            const priorityEmoji = rec.priority === 'high' ? '🔴' : '🟡';
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

// CLI
if (require.main === module) {
    const args = process.argv.slice(2);

    if (args.length === 0 || args[0] === '--help') {
        console.log(`
Usage: node gtm-performance-check.js <GTM-ID> [options]

Options:
  --detailed          Show detailed analysis
  --json              Output as JSON
  --test-url=<url>    Custom test URL
  --help              Show this help

Examples:
  node gtm-performance-check.js GTM-XXXXXXX
  node gtm-performance-check.js GTM-XXXXXXX --detailed
  node gtm-performance-check.js GTM-XXXXXXX --json
        `);
        process.exit(0);
    }

    const containerId = args[0];
    const options = {
        detailed: args.includes('--detailed'),
        json: args.includes('--json'),
        testUrl: args.find(arg => arg.startsWith('--test-url='))?.split('=')[1],
    };

    checkGTMPerformance(containerId, options)
        .then(() => process.exit(0))
        .catch(err => {
            console.error(err);
            process.exit(1);
        });
}

module.exports = { checkGTMPerformance };
