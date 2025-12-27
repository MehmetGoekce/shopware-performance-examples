/**
 * Kapitel 24: INP (Interaction to Next Paint) Analyse
 * Ausblick – Neue Technologien und Trends
 *
 * Browser-Script zur Messung und Analyse von INP.
 * Führen Sie dieses Script in der Browser-Konsole aus.
 *
 * Verwendung:
 *   1. Shop-Seite öffnen
 *   2. DevTools → Console
 *   3. Script einfügen und ausführen
 *   4. Mit der Seite interagieren
 *   5. Ergebnisse werden geloggt
 */

(function() {
    'use strict';

    const interactions = [];
    const INP_THRESHOLD_GOOD = 200;      // ms
    const INP_THRESHOLD_POOR = 500;      // ms

    console.log('%c INP-Analyse gestartet', 'color: blue; font-weight: bold');
    console.log('Interagieren Sie mit der Seite (Klicks, Tippen, Tastatur)...');
    console.log('Rufen Sie analyzeINP() auf, um Ergebnisse zu sehen.');

    // PerformanceObserver für Event Timing API
    if (!('PerformanceObserver' in window)) {
        console.error('PerformanceObserver nicht unterstützt');
        return;
    }

    try {
        const observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
                // Nur User-Interaktionen (nicht Scroll)
                if (entry.name === 'pointerdown' ||
                    entry.name === 'keydown' ||
                    entry.name === 'click') {

                    const duration = entry.processingEnd - entry.startTime;

                    interactions.push({
                        type: entry.name,
                        target: entry.target?.tagName || 'unknown',
                        duration: Math.round(duration),
                        timestamp: new Date().toISOString(),
                        startTime: entry.startTime,
                        processingStart: entry.processingStart,
                        processingEnd: entry.processingEnd
                    });

                    // Live-Feedback bei langsamen Interaktionen
                    if (duration > INP_THRESHOLD_GOOD) {
                        console.warn(
                            `Langsame Interaktion: ${entry.name} auf <${entry.target?.tagName}> ` +
                            `- ${Math.round(duration)}ms`
                        );
                    }
                }
            }
        });

        observer.observe({
            type: 'event',
            buffered: true,
            durationThreshold: 16  // Mindestens 16ms
        });
    } catch (e) {
        console.error('Event Timing API nicht unterstützt:', e);
    }

    /**
     * Analysiert gesammelte Interaktionen und berechnet INP
     */
    window.analyzeINP = function() {
        if (interactions.length === 0) {
            console.log('Keine Interaktionen aufgezeichnet.');
            console.log('Bitte mit der Seite interagieren (Klicks, Tastatur).');
            return;
        }

        // INP = 98. Perzentil der Interaktionen
        const sorted = [...interactions].sort((a, b) => b.duration - a.duration);
        const p98Index = Math.floor(interactions.length * 0.98);
        const inp = sorted[Math.min(p98Index, sorted.length - 1)].duration;

        // Statistiken
        const durations = interactions.map(i => i.duration);
        const avg = durations.reduce((a, b) => a + b, 0) / durations.length;
        const max = Math.max(...durations);
        const min = Math.min(...durations);

        // Bewertung
        let rating, color;
        if (inp <= INP_THRESHOLD_GOOD) {
            rating = 'Gut';
            color = 'green';
        } else if (inp <= INP_THRESHOLD_POOR) {
            rating = 'Verbesserungswürdig';
            color = 'orange';
        } else {
            rating = 'Schlecht';
            color = 'red';
        }

        // Report
        console.log('%c\n═══════════════════════════════════════', 'color: blue');
        console.log('%c INP-ANALYSE ERGEBNISSE', 'color: blue; font-weight: bold');
        console.log('%c═══════════════════════════════════════\n', 'color: blue');

        console.log(`INP: %c${inp}ms%c (${rating})`,
            `color: ${color}; font-weight: bold`,
            'color: inherit');

        console.log(`\nStatistiken (${interactions.length} Interaktionen):`);
        console.log(`  Durchschnitt: ${Math.round(avg)}ms`);
        console.log(`  Minimum: ${min}ms`);
        console.log(`  Maximum: ${max}ms`);

        // Langsame Interaktionen
        const slow = interactions.filter(i => i.duration > INP_THRESHOLD_GOOD);
        if (slow.length > 0) {
            console.log(`\n%cLangsame Interaktionen (>${INP_THRESHOLD_GOOD}ms):`,
                'color: orange; font-weight: bold');
            slow.forEach(i => {
                console.log(`  ${i.type} auf <${i.target}>: ${i.duration}ms`);
            });
        }

        // Empfehlungen
        console.log('\n%cEmpfehlungen:', 'font-weight: bold');
        if (inp > INP_THRESHOLD_GOOD) {
            console.log('  1. Event-Handler optimieren (debounce/throttle)');
            console.log('  2. Lange Tasks aufteilen (scheduler.yield())');
            console.log('  3. JavaScript-Bundle reduzieren');
            console.log('  4. Third-Party-Scripts prüfen');
        } else {
            console.log('  ✓ INP ist gut! Weiter so.');
        }

        console.log('%c\n═══════════════════════════════════════\n', 'color: blue');

        return {
            inp,
            rating,
            count: interactions.length,
            avg: Math.round(avg),
            min,
            max,
            interactions
        };
    };

    /**
     * Exportiert Daten als JSON
     */
    window.exportINPData = function() {
        const data = window.analyzeINP();
        const json = JSON.stringify(data, null, 2);
        console.log('JSON-Export:');
        console.log(json);
        return json;
    };

    /**
     * Setzt Messungen zurück
     */
    window.resetINP = function() {
        interactions.length = 0;
        console.log('INP-Messungen zurückgesetzt.');
    };

    // Anleitung
    console.log('\nVerfügbare Befehle:');
    console.log('  analyzeINP()    - Ergebnisse anzeigen');
    console.log('  exportINPData() - Als JSON exportieren');
    console.log('  resetINP()      - Messungen zurücksetzen');

})();
