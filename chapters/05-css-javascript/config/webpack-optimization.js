/**
 * Webpack Optimization Configuration
 * Kapitel 5: CSS und JavaScript optimieren
 *
 * Erweiterte Webpack-Konfiguration für Shopware 6 Themes.
 * Aktiviert Tree Shaking, Code Splitting und Bundle-Analyse.
 *
 * Installation:
 *   npm install webpack-bundle-analyzer css-minimizer-webpack-plugin \
 *               purgecss-webpack-plugin --save-dev
 *
 * Verwendung:
 *   Diese Konfiguration in Ihr Theme webpack.config.js integrieren
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

const path = require('path');
const glob = require('glob');

// Plugins (nur installieren wenn benötigt)
let BundleAnalyzerPlugin, CssMinimizerPlugin, PurgeCSSPlugin;

try {
    BundleAnalyzerPlugin = require('webpack-bundle-analyzer').BundleAnalyzerPlugin;
} catch (e) {
    console.log('webpack-bundle-analyzer nicht installiert - Bundle-Analyse deaktiviert');
}

try {
    CssMinimizerPlugin = require('css-minimizer-webpack-plugin');
} catch (e) {
    console.log('css-minimizer-webpack-plugin nicht installiert - CSS Minimierung deaktiviert');
}

try {
    PurgeCSSPlugin = require('purgecss-webpack-plugin');
} catch (e) {
    console.log('purgecss-webpack-plugin nicht installiert - PurgeCSS deaktiviert');
}

/**
 * Shopware Theme Webpack Konfiguration
 * Merge diese Konfiguration mit der Standard-Shopware-Konfiguration
 */
module.exports = {
    // ============================================================
    // Mode
    // ============================================================
    mode: process.env.NODE_ENV || 'production',

    // ============================================================
    // Optimization
    // ============================================================
    optimization: {
        // Tree Shaking aktivieren
        usedExports: true,
        sideEffects: true,

        // Code Splitting
        splitChunks: {
            chunks: 'all',
            minSize: 20000,
            maxSize: 244000, // ~244 KB max pro Chunk
            cacheGroups: {
                // Vendor-Chunk für node_modules
                vendor: {
                    test: /[\\/]node_modules[\\/]/,
                    name: 'vendors',
                    chunks: 'all',
                    priority: 10,
                },
                // Gemeinsamer Code
                common: {
                    minChunks: 2,
                    priority: 5,
                    reuseExistingChunk: true,
                },
            },
        },

        // Runtime Chunk separieren
        runtimeChunk: 'single',

        // Minimizer
        minimizer: [
            // JavaScript Minimierung (Standard TerserPlugin)
            '...',

            // CSS Minimierung
            ...(CssMinimizerPlugin ? [
                new CssMinimizerPlugin({
                    minimizerOptions: {
                        preset: ['default', {
                            discardComments: { removeAll: true },
                            // Wichtig für Shopware: IDs nicht umbenennen
                            reduceIdents: false,
                            // z-index nicht ändern
                            zindex: false,
                        }],
                    },
                }),
            ] : []),
        ],
    },

    // ============================================================
    // Plugins
    // ============================================================
    plugins: [
        // Bundle Analyzer (nur wenn --analyze Flag gesetzt)
        ...(BundleAnalyzerPlugin && process.env.ANALYZE ? [
            new BundleAnalyzerPlugin({
                analyzerMode: 'static',
                reportFilename: 'bundle-report.html',
                openAnalyzer: true,
                generateStatsFile: true,
                statsFilename: 'bundle-stats.json',
            }),
        ] : []),

        // PurgeCSS - Entfernt ungenutztes CSS
        ...(PurgeCSSPlugin ? [
            new PurgeCSSPlugin({
                // Alle Twig-Templates durchsuchen
                paths: glob.sync(
                    path.join(__dirname, 'Resources/views/**/*.twig'),
                    { nodir: true }
                ),
                // Safelist für dynamisch generierte Klassen
                safelist: {
                    // Standard-Klassen die nicht entfernt werden dürfen
                    standard: [
                        /^modal/,
                        /^dropdown/,
                        /^offcanvas/,
                        /^alert/,
                        /^toast/,
                        /^collapse/,
                        /^fade/,
                        /^show/,
                        /^active/,
                        /^disabled/,
                    ],
                    // Deep-Match für Komponenten
                    deep: [
                        /^swiper/,
                        /^slider/,
                        /^gallery/,
                    ],
                    // Greedy-Match für JS-generierte Klassen
                    greedy: [
                        /^js-/,
                        /^is-/,
                        /^has-/,
                    ],
                },
            }),
        ] : []),
    ],

    // ============================================================
    // Performance Hints
    // ============================================================
    performance: {
        hints: 'warning',
        maxEntrypointSize: 250000, // 250 KB
        maxAssetSize: 250000,
        assetFilter: (assetFilename) => {
            // Nur JS und CSS prüfen
            return /\.(js|css)$/.test(assetFilename);
        },
    },

    // ============================================================
    // Resolve (für Tree Shaking wichtig)
    // ============================================================
    resolve: {
        // ES Modules bevorzugen für besseres Tree Shaking
        mainFields: ['module', 'main'],
        alias: {
            // Lodash durch lodash-es ersetzen für Tree Shaking
            'lodash': 'lodash-es',
        },
    },
};

/**
 * Beispiel: Integration in Shopware Theme
 *
 * // YourTheme/Resources/app/storefront/build/webpack.config.js
 *
 * const { merge } = require('webpack-merge');
 * const shopwareConfig = require('@shopware-ag/webpack-config');
 * const optimizationConfig = require('./webpack-optimization');
 *
 * module.exports = merge(shopwareConfig, optimizationConfig);
 */

/**
 * NPM Scripts für package.json
 *
 * {
 *   "scripts": {
 *     "build": "webpack --mode production",
 *     "build:analyze": "ANALYZE=true webpack --mode production",
 *     "build:dev": "webpack --mode development",
 *     "watch": "webpack --mode development --watch"
 *   }
 * }
 */
