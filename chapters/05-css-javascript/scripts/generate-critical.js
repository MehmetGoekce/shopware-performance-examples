/**
 * Critical CSS Generator
 * Kapitel 5: CSS und JavaScript optimieren
 *
 * Generiert Critical CSS für Above-the-Fold Inhalte.
 *
 * Installation:
 *   npm install critical --save-dev
 *
 * Verwendung:
 *   node scripts/generate-critical.js https://ihr-shop.ch
 *   node scripts/generate-critical.js https://ihr-shop.ch --pages /kategorie /produkt/beispiel
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

const critical = require('critical');
const path = require('path');
const fs = require('fs');

// Konfiguration
const CONFIG = {
    // Output-Verzeichnis für generiertes CSS
    outputDir: './critical-css',

    // Viewport-Größen (Desktop + Mobile)
    dimensions: [
        { width: 375, height: 667 },   // Mobile
        { width: 1366, height: 768 },  // Desktop
    ],

    // Critical CSS Optionen
    options: {
        inline: false,
        minify: true,
        extract: true,
        timeout: 30000,
        // Penthouse-spezifische Optionen
        penthouse: {
            blockJSRequests: false,
            renderWaitTime: 500,
            timeout: 30000,
        }
    }
};

// Standard-Seiten für einen Shop
const DEFAULT_PAGES = [
    { name: 'home', path: '/' },
    { name: 'category', path: '/kategorie' },
    { name: 'product', path: '/produkt/beispiel' },
    { name: 'cart', path: '/checkout/cart' },
];

/**
 * Generiert Critical CSS für eine URL
 */
async function generateCriticalCSS(baseUrl, pagePath, pageName) {
    const url = new URL(pagePath, baseUrl).toString();
    const outputFile = path.join(CONFIG.outputDir, `critical-${pageName}.css`);

    console.log(`\n🔄 Generiere Critical CSS für: ${url}`);

    try {
        const { css, uncritical } = await critical.generate({
            src: url,
            dimensions: CONFIG.dimensions,
            ...CONFIG.options,
        });

        // Critical CSS speichern
        fs.writeFileSync(outputFile, css);
        console.log(`✅ Critical CSS: ${outputFile} (${Math.round(css.length / 1024)} KB)`);

        // Uncritical CSS speichern (optional)
        if (uncritical) {
            const uncriticalFile = path.join(CONFIG.outputDir, `uncritical-${pageName}.css`);
            fs.writeFileSync(uncriticalFile, uncritical);
            console.log(`📦 Uncritical CSS: ${uncriticalFile} (${Math.round(uncritical.length / 1024)} KB)`);
        }

        return { css, uncritical };

    } catch (error) {
        console.error(`❌ Fehler bei ${url}:`, error.message);
        return null;
    }
}

/**
 * Kombiniert Critical CSS von mehreren Seiten
 */
function combineCriticalCSS(cssFiles) {
    const combined = new Set();

    cssFiles.forEach(file => {
        if (fs.existsSync(file)) {
            const css = fs.readFileSync(file, 'utf-8');
            // CSS-Regeln extrahieren (vereinfacht)
            const rules = css.split('}').filter(r => r.trim());
            rules.forEach(rule => combined.add(rule.trim() + '}'));
        }
    });

    return Array.from(combined).join('\n');
}

/**
 * Hauptfunktion
 */
async function main() {
    const args = process.argv.slice(2);

    if (args.length === 0) {
        console.log(`
📄 Critical CSS Generator
========================

Verwendung:
  node generate-critical.js <base-url> [optionen]

Beispiele:
  node generate-critical.js https://ihr-shop.ch
  node generate-critical.js https://ihr-shop.ch --pages / /kategorie /produkt/test

Optionen:
  --pages <pfade>  Spezifische Seiten zum Analysieren
  --combine        Kombiniert alle Critical CSS in eine Datei

Output:
  ./critical-css/critical-*.css
        `);
        process.exit(0);
    }

    const baseUrl = args[0];
    console.log(`\n🚀 Critical CSS Generator`);
    console.log(`📍 Base URL: ${baseUrl}`);
    console.log(`📂 Output: ${CONFIG.outputDir}`);

    // Output-Verzeichnis erstellen
    if (!fs.existsSync(CONFIG.outputDir)) {
        fs.mkdirSync(CONFIG.outputDir, { recursive: true });
    }

    // Seiten bestimmen
    let pages = DEFAULT_PAGES;
    const pagesIndex = args.indexOf('--pages');
    if (pagesIndex !== -1) {
        pages = args.slice(pagesIndex + 1)
            .filter(p => !p.startsWith('--'))
            .map((p, i) => ({ name: `page-${i}`, path: p }));
    }

    console.log(`\n📋 Seiten zu analysieren:`);
    pages.forEach(p => console.log(`   - ${p.path}`));

    // Critical CSS für jede Seite generieren
    const results = [];
    for (const page of pages) {
        const result = await generateCriticalCSS(baseUrl, page.path, page.name);
        if (result) {
            results.push({ page, ...result });
        }
    }

    // Optional: Kombinieren
    if (args.includes('--combine') && results.length > 0) {
        console.log('\n🔗 Kombiniere Critical CSS...');
        const cssFiles = pages.map(p =>
            path.join(CONFIG.outputDir, `critical-${p.name}.css`)
        );
        const combined = combineCriticalCSS(cssFiles);
        const combinedFile = path.join(CONFIG.outputDir, 'critical-combined.css');
        fs.writeFileSync(combinedFile, combined);
        console.log(`✅ Kombiniert: ${combinedFile} (${Math.round(combined.length / 1024)} KB)`);
    }

    // Zusammenfassung
    console.log('\n' + '═'.repeat(50));
    console.log('📊 ZUSAMMENFASSUNG');
    console.log('═'.repeat(50));
    console.log(`✅ Erfolgreich: ${results.length}/${pages.length} Seiten`);
    console.log(`📂 Output: ${path.resolve(CONFIG.outputDir)}`);
    console.log('\n💡 Nächste Schritte:');
    console.log('   1. Critical CSS in <head> inline einbinden');
    console.log('   2. Rest-CSS mit preload/onload laden');
    console.log('   3. Mit Lighthouse testen');
}

// Script ausführen
main().catch(console.error);
