import js from '@eslint/js';

// Common browser globals
const browserGlobals = {
    window: 'readonly',
    document: 'readonly',
    navigator: 'readonly',
    location: 'readonly',
    console: 'readonly',
    setTimeout: 'readonly',
    setInterval: 'readonly',
    clearTimeout: 'readonly',
    clearInterval: 'readonly',
    requestAnimationFrame: 'readonly',
    cancelAnimationFrame: 'readonly',
    requestIdleCallback: 'readonly',
    cancelIdleCallback: 'readonly',
    fetch: 'readonly',
    URL: 'readonly',
    URLSearchParams: 'readonly',
    FormData: 'readonly',
    Headers: 'readonly',
    Response: 'readonly',
    Request: 'readonly',
    Blob: 'readonly',
    File: 'readonly',
    FileReader: 'readonly',
    AbortController: 'readonly',
    CustomEvent: 'readonly',
    Event: 'readonly',
    MutationObserver: 'readonly',
    IntersectionObserver: 'readonly',
    ResizeObserver: 'readonly',
    PerformanceObserver: 'readonly',
    performance: 'readonly',
    Node: 'readonly',
    Notification: 'readonly',
    ServiceWorkerRegistration: 'readonly',
    PushManager: 'readonly',
    localStorage: 'readonly',
    sessionStorage: 'readonly',
    indexedDB: 'readonly',
    caches: 'readonly',
    crypto: 'readonly',
    TextEncoder: 'readonly',
    TextDecoder: 'readonly',
    structuredClone: 'readonly',
    queueMicrotask: 'readonly',
    btoa: 'readonly',
    atob: 'readonly',
    // Third-party globals
    gtag: 'readonly',
    dataLayer: 'readonly',
    ga: 'readonly',
};

// Node.js globals
const nodeGlobals = {
    process: 'readonly',
    console: 'readonly',
    Buffer: 'readonly',
    __dirname: 'readonly',
    __filename: 'readonly',
    module: 'readonly',
    require: 'readonly',
    exports: 'readonly',
    setTimeout: 'readonly',
    setInterval: 'readonly',
    clearTimeout: 'readonly',
    clearInterval: 'readonly',
    setImmediate: 'readonly',
    clearImmediate: 'readonly',
    URL: 'readonly',
    URLSearchParams: 'readonly',
    TextEncoder: 'readonly',
    TextDecoder: 'readonly',
    fetch: 'readonly',
    AbortController: 'readonly',
};

// Service Worker globals
const swGlobals = {
    self: 'readonly',
    caches: 'readonly',
    fetch: 'readonly',
    clients: 'readonly',
    registration: 'readonly',
    skipWaiting: 'readonly',
    location: 'readonly',
    URL: 'readonly',
    Request: 'readonly',
    Response: 'readonly',
    Headers: 'readonly',
    console: 'readonly',
    Promise: 'readonly',
    addEventListener: 'readonly',
};

export default [
    // Base recommended config
    js.configs.recommended,

    // Global settings for all files
    {
        languageOptions: {
            ecmaVersion: 2022,
            sourceType: 'module',
            // Provide all globals - most files are browser or mixed
            globals: {
                ...browserGlobals,
                ...nodeGlobals,
            }
        },
        rules: {
            // Relaxed for book examples
            'no-unused-vars': ['warn', {
                argsIgnorePattern: '^_',
                varsIgnorePattern: '^_',
                caughtErrorsIgnorePattern: '^_'
            }],
            'no-console': 'off',
            'no-empty': 'warn',
        }
    },

    // Service Worker files
    {
        files: ['chapters/**/ServiceWorker/**/*.js'],
        languageOptions: {
            globals: swGlobals
        }
    },

    // Edge Functions
    {
        files: ['chapters/**/edge-functions/**/*.js'],
        languageOptions: {
            globals: {
                addEventListener: 'readonly',
                Response: 'readonly',
                Request: 'readonly',
                Headers: 'readonly',
                URL: 'readonly',
                fetch: 'readonly',
                crypto: 'readonly',
                TextEncoder: 'readonly',
                console: 'readonly',
            }
        }
    },

    // CommonJS config files
    {
        files: ['chapters/**/config/*.js'],
        languageOptions: {
            sourceType: 'commonjs',
        }
    },

    // Test files
    {
        files: ['tests/**/*.js'],
        languageOptions: {
            globals: {
                describe: 'readonly',
                it: 'readonly',
                test: 'readonly',
                expect: 'readonly',
                beforeEach: 'readonly',
                afterEach: 'readonly',
                beforeAll: 'readonly',
                afterAll: 'readonly',
                vi: 'readonly',
            }
        }
    },

    // Ignore patterns
    {
        ignores: [
            'node_modules/**',
            'vendor/**',
            'coverage/**',
            'dist/**',
            '**/*.min.js',
        ]
    }
];
