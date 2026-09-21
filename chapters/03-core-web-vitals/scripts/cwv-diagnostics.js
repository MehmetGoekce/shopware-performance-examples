/**
 * Core Web Vitals Diagnose-Snippets
 * Kapitel 3: Core Web Vitals messen und optimieren
 *
 * Verwendung: Chrome DevTools → Console, eine Funktion samt Aufruf
 * einfügen (oder die ganze Datei – dann laufen alle vier).
 * Getestet in Chromium gegen Shopware 6.6.10.6.
 *
 * Die Werte sind Labor-Werte dieses einen Aufrufs. Was Google bewertet,
 * ist das 75. Perzentil echter Besuche (Search Console, PageSpeed
 * Insights «Felddaten»).
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// ============================================================
// 1. LCP-Element finden
// ============================================================

function findLCPElement() {
    new PerformanceObserver((list) => {
        const entries = list.getEntries();
        const lastEntry = entries[entries.length - 1];
        console.log('🎯 LCP Element:', lastEntry.element);
        console.log('⏱️ LCP Time:', Math.round(lastEntry.startTime) + 'ms');
        console.log('🖼️ LCP URL:', lastEntry.url || '(kein Bild)');
        console.log('📐 LCP Size:', lastEntry.size);
    }).observe({ type: 'largest-contentful-paint', buffered: true });
}

findLCPElement();


// ============================================================
// 2. Layout Shifts (CLS) finden
// ============================================================

// Meldet jeden Shift ohne vorherige Eingabe. Bleibt die Konsole
// stumm, gab es bisher keinen Shift.
function findLayoutShifts() {
    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            if (!entry.hadRecentInput) {
                console.log('📊 Layout Shift:', entry.value.toFixed(4));
                entry.sources?.forEach(source => {
                    console.log('  -> Element:', source.node);
                });
            }
        }
    }).observe({ type: 'layout-shift', buffered: true });
}

findLayoutShifts();


// ============================================================
// 3. Langsame Interaktionen (INP) finden
// ============================================================

// Ein Tap erzeugt mehrere Events (pointerdown, pointerup, click …).
// Für INP zählt je Interaktion (interactionId > 0) das längste davon;
// Hover- und Scroll-Events haben interactionId 0 und zählen nicht.
function findSlowInteractions() {
    const longest = new Map();
    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            if (!entry.interactionId) continue;
            const prev = longest.get(entry.interactionId);
            if (prev && prev.duration >= entry.duration) continue;
            longest.set(entry.interactionId, entry);
            if (entry.duration > 200) {
                console.log('🐌 Slow Interaction:', entry.name, entry.duration + 'ms', entry.target);
            }
        }
    }).observe({ type: 'event', buffered: true, durationThreshold: 16 });
}

findSlowInteractions();


// ============================================================
// 4. Grösste und langsamste Ressourcen
// ============================================================

// transferSize ist bei Drittanbietern ohne Timing-Allow-Origin 0,
// bei Treffern aus dem Browser-Cache ebenfalls.
function analyzeResources() {
    const resources = performance.getEntriesByType('resource');
    const row = r => ({
        Name: r.name.split('/').pop().split('?')[0].substring(0, 40),
        KB: Math.round(r.transferSize / 1024),
        ms: Math.round(r.duration),
        Typ: r.initiatorType,
    });

    console.table([...resources].sort((a, b) => b.transferSize - a.transferSize).slice(0, 10).map(row));
    console.table([...resources].sort((a, b) => b.duration - a.duration).slice(0, 10).map(row));
}

analyzeResources();
