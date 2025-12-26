/**
 * Bildgrößen-Analyse für DevTools Console
 * Kapitel 4: Bildoptimierung
 *
 * Verwendung: Kopieren Sie diesen Code in die Chrome DevTools Console (F12)
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// ============================================================
// 1. Alle Bilder analysieren
// ============================================================

/**
 * Analysiert alle Bilder auf der Seite
 * Zeigt: gerenderte Größe, natürliche Größe, ob überdimensioniert
 */
function analyzeAllImages() {
    const images = document.querySelectorAll('img');
    const results = [];

    images.forEach((img, index) => {
        const rendered = {
            width: img.clientWidth,
            height: img.clientHeight
        };
        const natural = {
            width: img.naturalWidth,
            height: img.naturalHeight
        };

        // Überdimensioniert wenn natürliche Größe > 2x gerenderte Größe
        const isOversized = natural.width > rendered.width * 2;

        // Geschätzte Verschwendung in Bytes (grobe Schätzung)
        const wastedPixels = isOversized
            ? (natural.width * natural.height) - (rendered.width * rendered.height * 4)
            : 0;

        results.push({
            index: index + 1,
            src: img.src.split('/').pop().substring(0, 40),
            rendered: `${rendered.width}×${rendered.height}`,
            natural: `${natural.width}×${natural.height}`,
            oversized: isOversized ? '⚠️ JA' : '✅ Nein',
            loading: img.loading || 'auto',
            fetchpriority: img.fetchPriority || 'auto'
        });

        // Visuelles Highlighting für überdimensionierte Bilder
        if (isOversized) {
            img.style.outline = '3px solid #FF9800';
            img.style.outlineOffset = '2px';
        }
    });

    console.log('%c📊 BILDANALYSE', 'font-size: 16px; font-weight: bold; color: #4CAF50;');
    console.log(`${images.length} Bilder gefunden\n`);
    console.table(results);

    const oversizedCount = results.filter(r => r.oversized.includes('JA')).length;
    if (oversizedCount > 0) {
        console.log(`%c⚠️ ${oversizedCount} überdimensionierte Bilder gefunden (orange markiert)`, 'color: #FF9800; font-weight: bold;');
    } else {
        console.log('%c✅ Keine überdimensionierten Bilder gefunden', 'color: #4CAF50;');
    }

    return results;
}

// Ausführen:
analyzeAllImages();


// ============================================================
// 2. LCP-Bild identifizieren
// ============================================================

/**
 * Findet das LCP-Element und prüft ob es korrekt konfiguriert ist
 */
function checkLCPImage() {
    new PerformanceObserver((list) => {
        const entries = list.getEntries();
        const lastEntry = entries[entries.length - 1];

        console.log('%c🎯 LCP-ELEMENT ANALYSE', 'font-size: 16px; font-weight: bold; color: #2196F3;');

        if (lastEntry.element && lastEntry.element.tagName === 'IMG') {
            const img = lastEntry.element;

            console.log('Element:', img);
            console.log('LCP-Zeit:', Math.round(lastEntry.startTime) + 'ms');
            console.log('');

            // Prüfungen
            const checks = {
                'loading="eager"': img.loading === 'eager' || !img.loading,
                'fetchpriority="high"': img.fetchPriority === 'high',
                'Hat width/height': img.hasAttribute('width') && img.hasAttribute('height'),
                'Nicht lazy loaded': img.loading !== 'lazy'
            };

            console.log('%c🔍 Konfigurationsprüfung:', 'font-weight: bold;');
            Object.entries(checks).forEach(([check, passed]) => {
                console.log(`  ${passed ? '✅' : '❌'} ${check}`);
            });

            // Empfehlungen
            if (!checks['fetchpriority="high"']) {
                console.log('%c\n💡 Empfehlung: Fügen Sie fetchpriority="high" zum LCP-Bild hinzu', 'color: #FF9800;');
            }
            if (checks['loading="eager"'] === false) {
                console.log('%c💡 Empfehlung: Entfernen Sie loading="lazy" vom LCP-Bild', 'color: #FF9800;');
            }

            // Visuelles Highlighting
            img.style.outline = '4px solid #2196F3';
            img.style.outlineOffset = '2px';
            console.log('%c\n↑ LCP-Bild wurde blau markiert', 'color: #2196F3;');

        } else {
            console.log('LCP-Element ist kein Bild:', lastEntry.element);
            console.log('LCP-Zeit:', Math.round(lastEntry.startTime) + 'ms');
        }
    }).observe({ type: 'largest-contentful-paint', buffered: true });
}

// Ausführen:
checkLCPImage();


// ============================================================
// 3. Lazy Loading Audit
// ============================================================

/**
 * Prüft welche Bilder lazy/eager geladen werden
 */
function auditLazyLoading() {
    const images = document.querySelectorAll('img');
    const viewportHeight = window.innerHeight;

    const results = {
        aboveFold: { eager: [], lazy: [], auto: [] },
        belowFold: { eager: [], lazy: [], auto: [] }
    };

    images.forEach((img) => {
        const rect = img.getBoundingClientRect();
        const isAboveFold = rect.top < viewportHeight;
        const loading = img.loading || 'auto';
        const category = isAboveFold ? 'aboveFold' : 'belowFold';

        results[category][loading].push({
            src: img.src.split('/').pop().substring(0, 30),
            top: Math.round(rect.top)
        });
    });

    console.log('%c📋 LAZY LOADING AUDIT', 'font-size: 16px; font-weight: bold; color: #9C27B0;');

    console.log('\n%cAbove-the-fold Bilder:', 'font-weight: bold;');
    console.log(`  ✅ eager: ${results.aboveFold.eager.length}`);
    console.log(`  ⚠️ lazy: ${results.aboveFold.lazy.length} (sollte 0 sein!)`);
    console.log(`  ℹ️ auto: ${results.aboveFold.auto.length}`);

    console.log('\n%cBelow-the-fold Bilder:', 'font-weight: bold;');
    console.log(`  ℹ️ eager: ${results.belowFold.eager.length}`);
    console.log(`  ✅ lazy: ${results.belowFold.lazy.length}`);
    console.log(`  ℹ️ auto: ${results.belowFold.auto.length}`);

    if (results.aboveFold.lazy.length > 0) {
        console.log('%c\n⚠️ PROBLEM: Lazy-loaded Bilder above-the-fold gefunden!', 'color: #F44336; font-weight: bold;');
        console.log('Diese Bilder verzögern den LCP:');
        results.aboveFold.lazy.forEach(img => {
            console.log(`  - ${img.src} (top: ${img.top}px)`);
        });
    }

    return results;
}

// Ausführen:
auditLazyLoading();


// ============================================================
// 4. Bildformat-Analyse
// ============================================================

/**
 * Analysiert welche Bildformate verwendet werden
 */
function analyzeImageFormats() {
    const images = document.querySelectorAll('img');
    const formats = {};
    let totalSize = 0;

    images.forEach((img) => {
        const url = img.src || img.currentSrc;
        const extension = url.split('.').pop().split('?')[0].toLowerCase();

        if (!formats[extension]) {
            formats[extension] = { count: 0, urls: [] };
        }
        formats[extension].count++;
        formats[extension].urls.push(url.split('/').pop().substring(0, 30));
    });

    console.log('%c🖼️ BILDFORMAT-ANALYSE', 'font-size: 16px; font-weight: bold; color: #E91E63;');
    console.table(Object.entries(formats).map(([format, data]) => ({
        Format: format.toUpperCase(),
        Anzahl: data.count,
        Prozent: Math.round((data.count / images.length) * 100) + '%'
    })));

    // Empfehlungen
    if (formats['jpg'] || formats['jpeg'] || formats['png']) {
        const legacyCount = (formats['jpg']?.count || 0) +
                          (formats['jpeg']?.count || 0) +
                          (formats['png']?.count || 0);

        if (legacyCount > 0 && !formats['webp'] && !formats['avif']) {
            console.log('%c\n💡 Empfehlung: Aktivieren Sie WebP für ~30% kleinere Dateien', 'color: #FF9800;');
            console.log('   → FroshPlatformThumbnailProcessor installieren');
        }
    }

    if (formats['webp']) {
        console.log('%c\n✅ WebP wird verwendet - gut!', 'color: #4CAF50;');
    }

    if (formats['avif']) {
        console.log('%c✅ AVIF wird verwendet - optimal!', 'color: #4CAF50;');
    }

    return formats;
}

// Ausführen:
analyzeImageFormats();


// ============================================================
// 5. Komplette Bildanalyse
// ============================================================

/**
 * Führt alle Analysen auf einmal aus
 */
function fullImageAudit() {
    console.clear();
    console.log('%c🔍 VOLLSTÄNDIGE BILDANALYSE', 'font-size: 20px; font-weight: bold; color: #4CAF50;');
    console.log('═══════════════════════════════════════════════════════\n');

    analyzeAllImages();
    console.log('\n');

    analyzeImageFormats();
    console.log('\n');

    auditLazyLoading();
    console.log('\n');

    checkLCPImage();

    console.log('\n═══════════════════════════════════════════════════════');
    console.log('%c📊 Analyse abgeschlossen', 'font-size: 14px; color: #4CAF50;');
}

// Für vollständige Analyse ausführen:
// fullImageAudit();
