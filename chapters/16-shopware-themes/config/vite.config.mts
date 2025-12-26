/**
 * Vite Konfiguration für Shopware 6.7+ Themes
 *
 * Ersetzt webpack.config.js für optimierte Builds.
 *
 * Platzierung:
 *   src/Resources/app/storefront/vite.config.mts
 *
 * Vorteile gegenüber Webpack:
 *   - Build: 240s → 11s (-95%)
 *   - HMR: 2-5s → 50ms (-98%)
 *   - Bundle Size: -25% durch besseres Tree-Shaking
 */

import { defineConfig, loadEnv } from 'vite';
import { resolve } from 'path';
import { visualizer } from 'rollup-plugin-visualizer';

export default defineConfig(({ mode }) => {
  // Environment Variables laden
  const env = loadEnv(mode, process.cwd(), '');
  const isProduction = mode === 'production';
  const isAnalyze = process.env.ANALYZE === 'true';

  return {
    // Base Path für Assets
    base: '/bundles/performancetheme/',

    // Build Konfiguration
    build: {
      // Output Verzeichnis
      outDir: resolve(__dirname, '../dist/storefront'),

      // Asset Verzeichnis
      assetsDir: 'assets',

      // Source Maps nur in Development
      sourcemap: !isProduction,

      // Minimierung
      minify: isProduction ? 'terser' : false,

      terserOptions: isProduction ? {
        compress: {
          drop_console: true,
          drop_debugger: true,
          pure_funcs: ['console.log', 'console.info'],
        },
        format: {
          comments: false,
        },
      } : undefined,

      // Rollup Optionen
      rollupOptions: {
        input: {
          main: resolve(__dirname, 'src/main.ts'),
        },

        output: {
          // Chunk Naming
          chunkFileNames: isProduction
            ? 'js/[name]-[hash].js'
            : 'js/[name].js',

          entryFileNames: isProduction
            ? 'js/[name]-[hash].js'
            : 'js/[name].js',

          assetFileNames: isProduction
            ? 'assets/[name]-[hash][extname]'
            : 'assets/[name][extname]',

          // Manual Chunks für besseres Caching
          manualChunks: (id) => {
            // Node Modules splitten
            if (id.includes('node_modules')) {
              // Bootstrap separat
              if (id.includes('bootstrap')) {
                return 'vendor-bootstrap';
              }

              // Andere Vendors
              return 'vendor';
            }

            // Async-geladene Plugins
            if (id.includes('/plugin/') && id.includes('async')) {
              return 'plugins-async';
            }

            return null;
          },
        },

        // Externe Dependencies (falls nötig)
        external: [
          // Hier externe Libs die nicht gebundled werden sollen
        ],
      },

      // Chunk Size Warnungen
      chunkSizeWarningLimit: 250, // 250 KB

      // CSS Code Splitting
      cssCodeSplit: true,

      // Asset Inlining Limit
      assetsInlineLimit: 4096, // 4 KB
    },

    // CSS Konfiguration
    css: {
      devSourcemap: !isProduction,

      // PostCSS Plugins
      postcss: {
        plugins: [
          // Autoprefixer
          require('autoprefixer'),

          // CSS Nano für Production
          ...(isProduction ? [require('cssnano')({
            preset: ['default', {
              discardComments: { removeAll: true },
              normalizeWhitespace: true,
            }],
          })] : []),
        ],
      },

      // SCSS Optionen
      preprocessorOptions: {
        scss: {
          additionalData: `
            @use "sass:math";
            @import "@/scss/variables";
          `,
          includePaths: [
            resolve(__dirname, 'src/scss'),
            resolve(__dirname, 'node_modules'),
          ],
        },
      },
    },

    // Resolve Konfiguration
    resolve: {
      alias: {
        '@': resolve(__dirname, 'src'),
        '@scss': resolve(__dirname, 'src/scss'),
        '@plugin': resolve(__dirname, 'src/plugin'),

        // Shopware Plugin System
        'src/plugin-system/plugin.class': resolve(
          __dirname,
          '../../../../../../../vendor/shopware/storefront/Resources/app/storefront/src/plugin-system/plugin.class.js'
        ),
        'src/helper/dom-access.helper': resolve(
          __dirname,
          '../../../../../../../vendor/shopware/storefront/Resources/app/storefront/src/helper/dom-access.helper.js'
        ),
      },

      // Extensions
      extensions: ['.ts', '.js', '.mts', '.mjs', '.json'],
    },

    // Server Konfiguration (Development)
    server: {
      port: 9998,
      strictPort: true,
      host: true,

      // HMR Konfiguration
      hmr: {
        protocol: 'ws',
        host: 'localhost',
        port: 9998,
      },

      // Proxy für Shopware Backend
      proxy: {
        '/api': {
          target: 'http://localhost:8000',
          changeOrigin: true,
        },
      },

      // Watch Konfiguration
      watch: {
        usePolling: false,
        interval: 100,
      },
    },

    // Optimierung
    optimizeDeps: {
      // Dependencies pre-bundeln
      include: [
        'bootstrap/js/dist/modal',
        'bootstrap/js/dist/dropdown',
        'bootstrap/js/dist/collapse',
        'bootstrap/js/dist/offcanvas',
      ],

      // Dependencies ausschliessen
      exclude: [
        // Hier Libs die nicht pre-bundled werden sollen
      ],

      // ESBuild Optionen
      esbuildOptions: {
        target: 'es2020',
      },
    },

    // ESBuild Konfiguration
    esbuild: {
      target: 'es2020',
      legalComments: 'none',
    },

    // Plugins
    plugins: [
      // Bundle Visualizer (nur bei ANALYZE=true)
      ...(isAnalyze ? [
        visualizer({
          filename: 'bundle-analysis.html',
          open: true,
          gzipSize: true,
          brotliSize: true,
        }),
      ] : []),
    ],

    // Logging
    logLevel: isProduction ? 'warn' : 'info',

    // Performance
    worker: {
      format: 'es',
    },
  };
});
