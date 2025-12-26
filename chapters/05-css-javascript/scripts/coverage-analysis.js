/**
 * CSS/JS Coverage-Analyse für DevTools Console
 * Kapitel 5: CSS und JavaScript optimieren
 *
 * Verwendung:
 * 1. Chrome DevTools öffnen (F12)
 * 2. More Tools → Coverage
 * 3. Seite neu laden
 * 4. Dieses Script in Console ausführen für detaillierte Analyse
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// ============================================================
// 1. Render-Blocking Resources identifizieren
// ============================================================

/**
 * Findet alle render-blocking CSS und JavaScript Ressourcen
 */
function findRenderBlockingResources() {
    console.log('%c🚫 RENDER-BLOCKING ANALYSE', 'font-size: 16px; font-weight: bold; color: #F44336;');

    // CSS im <head> ohne media="print" oder async
    const blockingCSS = Array.from(document.querySelectorAll('link[rel="stylesheet"]'))
        .filter(link => {
            const media = link.getAttribute('media');
            const onload = link.getAttribute('onload');
            // Blocking wenn: kein media="print" und kein async-Pattern
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

    const allBlocking = [...blockingCSS, ...blockingJS];

    if (allBlocking.length === 0) {
        console.log('%c✅ Keine render-blocking Ressourcen gefunden!', 'color: #4CAF50;');
    } else {
        console.log(`%c⚠️ ${allBlocking.length} render-blocking Ressourcen gefunden:`, 'color: #FF9800;');
        console.table(allBlocking);

        console.log('\n%c💡 Empfehlungen:', 'font-weight: bold;');
        if (blockingCSS.length > 0) {
            console.log('  CSS: Critical CSS inline, Rest mit preload/onload laden');
        }
        if (blockingJS.length > 0) {
            console.log('  JS: defer oder async Attribut hinzufügen');
        }
    }

    return allBlocking;
}

// Ausführen:
findRenderBlockingResources();


// ============================================================
// 2. JavaScript Bundle Analyse
// ============================================================

/**
 * Analysiert geladene JavaScript-Ressourcen
 */
function analyzeJavaScriptBundles() {
    console.log('%c📦 JAVASCRIPT BUNDLE ANALYSE', 'font-size: 16px; font-weight: bold; color: #2196F3;');

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

    console.log(`\nGesamt: ${totalSize} KB JavaScript`);
    console.log(`Davon Third-Party: ${thirdPartySize} KB (${Math.round(thirdPartySize/totalSize*100)}%)`);

    console.log('\n%cTop 10 größte Bundles:', 'font-weight: bold;');
    console.table(jsResources.slice(0, 10).map(r => ({
        Name: r.name,
        'Größe (KB)': r.size,
        'Dauer (ms)': r.duration,
        'Third-Party': r.isThirdParty ? '⚠️ Ja' : 'Nein'
    })));

    // Empfehlungen basierend auf Größe
    if (totalSize > 500) {
        console.log('%c\n⚠️ JavaScript Bundle ist groß (>500 KB)', 'color: #FF9800; font-weight: bold;');
        console.log('💡 Empfehlungen:');
        console.log('  - Code Splitting implementieren');
        console.log('  - Große Libraries ersetzen (moment.js → day.js)');
        console.log('  - Tree Shaking prüfen');
    }

    return jsResources;
}

// Ausführen:
analyzeJavaScriptBundles();


// ============================================================
// 3. CSS Analyse
// ============================================================

/**
 * Analysiert geladene CSS-Ressourcen
 */
function analyzeCSSBundles() {
    console.log('%c🎨 CSS ANALYSE', 'font-size: 16px; font-weight: bold; color: #9C27B0;');

    const cssResources = performance.getEntriesByType('resource')
        .filter(r => r.initiatorType === 'link' || r.name.endsWith('.css'))
        .map(r => ({
            name: r.name.split('/').pop().split('?')[0].substring(0, 40),
            size: Math.round(r.transferSize / 1024),
            duration: Math.round(r.duration)
        }))
        .sort((a, b) => b.size - a.size);

    const totalSize = cssResources.reduce((sum, r) => sum + r.size, 0);

    console.log(`\nGesamt: ${totalSize} KB CSS`);

    console.table(cssResources.map(r => ({
        Name: r.name,
        'Größe (KB)': r.size,
        'Dauer (ms)': r.duration
    })));

    // Inline Styles zählen
    const inlineStyles = document.querySelectorAll('style').length;
    const inlineStylesSize = Array.from(document.querySelectorAll('style'))
        .reduce((sum, s) => sum + s.textContent.length, 0);

    console.log(`\nInline <style> Elemente: ${inlineStyles}`);
    console.log(`Inline CSS Größe: ~${Math.round(inlineStylesSize/1024)} KB`);

    return cssResources;
}

// Ausführen:
analyzeCSSBundles();


// ============================================================
// 4. Main Thread Blocking Analysis
// ============================================================

/**
 * Analysiert Long Tasks die den Main Thread blockieren
 */
function analyzeMainThreadBlocking() {
    console.log('%c⏱️ MAIN THREAD BLOCKING', 'font-size: 16px; font-weight: bold; color: #E91E63;');

    // Long Tasks Observer
    const longTasks = [];

    const observer = new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            longTasks.push({
                name: entry.name,
                duration: Math.round(entry.duration),
                startTime: Math.round(entry.startTime),
                blocking: Math.round(entry.duration - 50) // Zeit über 50ms
            });
        }
    });

    observer.observe({ type: 'longtask', buffered: true });

    // Nach 3 Sekunden Ergebnis zeigen
    setTimeout(() => {
        observer.disconnect();

        if (longTasks.length === 0) {
            console.log('%c✅ Keine Long Tasks gefunden!', 'color: #4CAF50;');
        } else {
            const totalBlocking = longTasks.reduce((sum, t) => sum + t.blocking, 0);

            console.log(`\n⚠️ ${longTasks.length} Long Tasks gefunden`);
            console.log(`Gesamt Blocking Time: ${totalBlocking}ms`);

            console.table(longTasks.map(t => ({
                'Start (ms)': t.startTime,
                'Dauer (ms)': t.duration,
                'Blocking (ms)': t.blocking
            })));

            if (totalBlocking > 200) {
                console.log('%c\n❌ TBT > 200ms - Optimierung nötig!', 'color: #F44336; font-weight: bold;');
            }
        }
    }, 3000);

    console.log('Sammle Long Tasks für 3 Sekunden...');
}

// Ausführen:
analyzeMainThreadBlocking();


// ============================================================
// 5. Script Loading Attributes Audit
// ============================================================

/**
 * Prüft wie Scripts geladen werden (defer, async, module)
 */
function auditScriptLoading() {
    console.log('%c📜 SCRIPT LOADING AUDIT', 'font-size: 16px; font-weight: bold; color: #00BCD4;');

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

    console.log('\n%cScript Loading Übersicht:', 'font-weight: bold;');
    console.log(`  ❌ Blocking (kein defer/async): ${audit.blocking.length}`);
    console.log(`  ✅ defer: ${audit.defer.length}`);
    console.log(`  ⚠️ async: ${audit.async.length}`);
    console.log(`  ✅ module: ${audit.module.length}`);

    if (audit.blocking.length > 0) {
        console.log('\n%c❌ Blocking Scripts (sollten defer haben):', 'color: #F44336;');
        audit.blocking.forEach(s => console.log(`  - ${s.src} ${s.inHead ? '(im HEAD!)' : ''}`));
    }

    return audit;
}

// Ausführen:
auditScriptLoading();


// ============================================================
// 6. Vollständige Analyse
// ============================================================

/**
 * Führt alle Analysen aus
 */
function fullCSSJSAudit() {
    console.clear();
    console.log('%c🔍 VOLLSTÄNDIGE CSS/JS ANALYSE', 'font-size: 20px; font-weight: bold; color: #4CAF50;');
    console.log('═══════════════════════════════════════════════════════\n');

    findRenderBlockingResources();
    console.log('\n');

    analyzeJavaScriptBundles();
    console.log('\n');

    analyzeCSSBundles();
    console.log('\n');

    auditScriptLoading();
    console.log('\n');

    analyzeMainThreadBlocking();

    console.log('\n═══════════════════════════════════════════════════════');
    console.log('%c📊 Analyse läuft... Long Task Ergebnisse in 3s', 'color: #4CAF50;');
}

// Für vollständige Analyse:
// fullCSSJSAudit();
