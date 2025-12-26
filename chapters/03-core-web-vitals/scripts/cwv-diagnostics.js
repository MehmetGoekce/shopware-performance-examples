/**
 * Core Web Vitals Diagnose-Snippets
 * Kapitel 3: Core Web Vitals messen und optimieren
 *
 * Verwendung: Kopieren Sie diese Snippets in die Chrome DevTools Console
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// ============================================================
// 1. LCP-Element finden
// ============================================================

/**
 * Identifiziert das Largest Contentful Paint Element
 * Zeigt Element, Zeit und Größe an
 */
function findLCPElement() {
    new PerformanceObserver((list) => {
        const entries = list.getEntries();
        const lastEntry = entries[entries.length - 1];

        console.log('%c🎯 LCP Analyse', 'font-size: 16px; font-weight: bold; color: #4CAF50;');
        console.log('Element:', lastEntry.element);
        console.log('Zeit:', Math.round(lastEntry.startTime) + 'ms');
        console.log('Größe:', lastEntry.size + ' px²');
        console.log('URL:', lastEntry.url || '(kein Bild)');

        // Visuelles Highlighting
        if (lastEntry.element) {
            lastEntry.element.style.outline = '4px solid #4CAF50';
            lastEntry.element.style.outlineOffset = '2px';
            console.log('%c↑ Element wurde grün markiert', 'color: #4CAF50;');
        }
    }).observe({ type: 'largest-contentful-paint', buffered: true });
}

// Ausführen:
findLCPElement();


// ============================================================
// 2. Layout Shifts (CLS) finden
// ============================================================

/**
 * Identifiziert alle Layout Shifts und deren Ursachen
 * Filtert Shifts durch User-Input heraus
 */
function findLayoutShifts() {
    let clsScore = 0;
    const shifts = [];

    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            // Nur unerwartete Shifts (nicht durch User-Input)
            if (!entry.hadRecentInput) {
                clsScore += entry.value;
                shifts.push({
                    score: entry.value.toFixed(4),
                    elements: entry.sources?.map(s => s.node) || []
                });

                console.log('%c📊 Layout Shift detected', 'color: #FF9800; font-weight: bold;');
                console.log('Score:', entry.value.toFixed(4));
                console.log('Gesamt CLS:', clsScore.toFixed(4));

                entry.sources?.forEach((source, i) => {
                    console.log(`  Element ${i + 1}:`, source.node);
                    if (source.node) {
                        source.node.style.outline = '3px dashed #FF9800';
                    }
                });
            }
        }
    }).observe({ type: 'layout-shift', buffered: true });

    // Nach 5 Sekunden Zusammenfassung
    setTimeout(() => {
        console.log('%c📊 CLS Zusammenfassung', 'font-size: 16px; font-weight: bold; color: #FF9800;');
        console.log('Gesamt CLS:', clsScore.toFixed(4));
        console.log('Bewertung:', clsScore < 0.1 ? '✅ Gut' : clsScore < 0.25 ? '⚠️ Verbesserungswürdig' : '❌ Schlecht');
        console.log('Shifts gefunden:', shifts.length);
    }, 5000);
}

// Ausführen:
findLayoutShifts();


// ============================================================
// 3. Langsame Interaktionen (INP) finden
// ============================================================

/**
 * Überwacht alle Interaktionen und meldet langsame (> 200ms)
 */
function findSlowInteractions() {
    const interactions = [];

    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            if (entry.duration > 200) {
                interactions.push({
                    name: entry.name,
                    duration: entry.duration,
                    target: entry.target
                });

                console.log('%c🐌 Langsame Interaktion!', 'color: #F44336; font-weight: bold;');
                console.log('Event:', entry.name);
                console.log('Dauer:', entry.duration + 'ms');
                console.log('Ziel:', entry.target);
                console.log('Bewertung:', entry.duration < 200 ? '✅ Gut' : entry.duration < 500 ? '⚠️ Verbesserungswürdig' : '❌ Schlecht');

                if (entry.target) {
                    entry.target.style.outline = '3px solid #F44336';
                }
            }
        }
    }).observe({ type: 'event', buffered: true, durationThreshold: 16 });

    console.log('%c👆 Interagieren Sie mit der Seite...', 'color: #2196F3; font-style: italic;');
    console.log('Langsame Interaktionen (> 200ms) werden gemeldet.');
}

// Ausführen:
findSlowInteractions();


// ============================================================
// 4. Alle Core Web Vitals auf einmal
// ============================================================

/**
 * Komplette CWV-Analyse in einem Snippet
 */
function analyzeAllCWV() {
    console.log('%c🔍 Core Web Vitals Analyse gestartet...', 'font-size: 18px; font-weight: bold; color: #2196F3;');
    console.log('Warten Sie 5 Sekunden für vollständige Ergebnisse.');
    console.log('');

    let lcpValue = 0;
    let clsValue = 0;
    let inpValue = 0;
    let lcpElement = null;

    // LCP
    new PerformanceObserver((list) => {
        const entries = list.getEntries();
        const lastEntry = entries[entries.length - 1];
        lcpValue = lastEntry.startTime;
        lcpElement = lastEntry.element;
    }).observe({ type: 'largest-contentful-paint', buffered: true });

    // CLS
    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            if (!entry.hadRecentInput) {
                clsValue += entry.value;
            }
        }
    }).observe({ type: 'layout-shift', buffered: true });

    // INP (approximiert durch längste Interaktion)
    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            if (entry.duration > inpValue) {
                inpValue = entry.duration;
            }
        }
    }).observe({ type: 'event', buffered: true, durationThreshold: 16 });

    // Ergebnis nach 5 Sekunden
    setTimeout(() => {
        console.log('%c📊 CORE WEB VITALS REPORT', 'font-size: 20px; font-weight: bold; color: #4CAF50;');
        console.log('═══════════════════════════════════════');

        // LCP
        const lcpStatus = lcpValue < 2500 ? '✅' : lcpValue < 4000 ? '⚠️' : '❌';
        console.log(`${lcpStatus} LCP: ${Math.round(lcpValue)}ms (Ziel: < 2500ms)`);
        console.log('   Element:', lcpElement);

        // CLS
        const clsStatus = clsValue < 0.1 ? '✅' : clsValue < 0.25 ? '⚠️' : '❌';
        console.log(`${clsStatus} CLS: ${clsValue.toFixed(4)} (Ziel: < 0.1)`);

        // INP
        const inpStatus = inpValue < 200 ? '✅' : inpValue < 500 ? '⚠️' : '❌';
        console.log(`${inpStatus} INP: ${Math.round(inpValue)}ms (Ziel: < 200ms)`);

        console.log('═══════════════════════════════════════');
        console.log('💡 Tipp: Interagieren Sie mit der Seite für genauere INP-Werte.');
    }, 5000);
}

// Ausführen:
analyzeAllCWV();


// ============================================================
// 5. Ressourcen-Timing analysieren
// ============================================================

/**
 * Zeigt die größten und langsamsten Ressourcen
 */
function analyzeResources() {
    const resources = performance.getEntriesByType('resource');

    // Nach Größe sortieren
    const bySize = [...resources]
        .filter(r => r.transferSize > 0)
        .sort((a, b) => b.transferSize - a.transferSize)
        .slice(0, 10);

    // Nach Dauer sortieren
    const byDuration = [...resources]
        .sort((a, b) => b.duration - a.duration)
        .slice(0, 10);

    console.log('%c📦 TOP 10 GRÖßTE RESSOURCEN', 'font-size: 16px; font-weight: bold; color: #9C27B0;');
    console.table(bySize.map(r => ({
        Name: r.name.split('/').pop().substring(0, 40),
        Größe: Math.round(r.transferSize / 1024) + ' KB',
        Dauer: Math.round(r.duration) + 'ms',
        Typ: r.initiatorType
    })));

    console.log('%c⏱️ TOP 10 LANGSAMSTE RESSOURCEN', 'font-size: 16px; font-weight: bold; color: #E91E63;');
    console.table(byDuration.map(r => ({
        Name: r.name.split('/').pop().substring(0, 40),
        Dauer: Math.round(r.duration) + 'ms',
        Größe: Math.round(r.transferSize / 1024) + ' KB',
        Typ: r.initiatorType
    })));
}

// Ausführen:
analyzeResources();
