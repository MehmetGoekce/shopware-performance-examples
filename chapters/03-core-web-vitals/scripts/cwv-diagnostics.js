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
// Hover-Events haben interactionId 0 und zählen nicht, Scrollen
// erfasst Event Timing gar nicht.
// Das längste Event kann nach einem kürzeren kommen (keyup nach
// keydown): gemeldet wird erst, wenn 1 s lang kein längeres nachkam.
function findSlowInteractions() {
    const longest = new Map();
    const timers = new Map();
    new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
            const id = entry.interactionId;
            if (!id) continue;
            const prev = longest.get(id);
            if (prev && prev.duration >= entry.duration) continue;
            longest.set(id, entry);
            clearTimeout(timers.get(id));
            timers.set(id, setTimeout(() => {
                const slowest = longest.get(id);
                if (slowest.duration > 200) {
                    console.log('🐌 Slow Interaction:', slowest.name, slowest.duration + 'ms', slowest.target);
                }
            }, 1000));
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

    console.log('Nach Grösse (übertragen):');
    console.table([...resources].sort((a, b) => b.transferSize - a.transferSize).slice(0, 10).map(row));
    console.log('Nach Dauer:');
    console.table([...resources].sort((a, b) => b.duration - a.duration).slice(0, 10).map(row));
}

analyzeResources();
