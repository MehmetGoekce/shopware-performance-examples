/**
 * CSS/JS-Übersicht für die DevTools-Console
 * Kapitel 5: CSS und JavaScript optimieren
 *
 * Verwendung: Chrome DevTools → Console, die ganze Datei einfügen
 * (dann laufen alle drei) oder eine Funktion samt Aufruf.
 * Getestet in Chromium gegen Shopware 6.6.10.6.
 *
 * Wie viel einer Datei ungenutzt ist, zeigt nur der Coverage-Tab
 * (Drei-Punkte-Menü → More tools → Coverage, dann neu laden). An diese
 * Daten kommt ein Skript in der Console nicht heran.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// ============================================================
// 1. Render-blockierende Dateien
// ============================================================

// Chromium meldet je Ressource, ob sie das erste Rendern aufgehalten
// hat (renderBlockingStatus, ab Chrome 107). Das ist die Sicht des
// Browsers, keine Vermutung aus den Attributen im HTML.
function findRenderBlocking() {
    const resources = performance.getEntriesByType('resource');
    if (resources.length > 0 && resources[0].renderBlockingStatus === undefined) {
        console.log('Dieser Browser meldet renderBlockingStatus nicht. In Chrome oder Edge ausführen.');
        return [];
    }

    const blocking = resources.filter(r => r.renderBlockingStatus === 'blocking');
    if (blocking.length === 0) {
        console.log('✅ Keine render-blockierende Datei.');
    } else {
        console.log(`⚠️ ${blocking.length} render-blockierende Datei(en):`);
        console.table(blocking.map(r => {
            const url = new URL(r.name);
            const own = url.hostname === location.hostname;
            return {
                Datei: own ? url.pathname.split('/').slice(-2).join('/') : url.hostname + url.pathname,
                // ohne Timing-Allow-Origin gibt der Browser keine Grösse heraus
                KB: r.responseStart === 0 ? '?' : Math.round(r.encodedBodySize / 1024),
                ms: Math.round(r.duration),
            };
        }));
    }
    return blocking;
}

findRenderBlocking();


// ============================================================
// 2. JavaScript und CSS je Bundle
// ============================================================

// Shopware legt das JavaScript jedes Themes und Plugins unter
// /theme/<id>/js/<technischer-name>/ ab. Die Gruppe «storefront» ist
// Shopware selbst, jede weitere ein Theme oder Plugin. CSS erscheint
// mit dem Dateinamen (all.css), fremde Hosts mit ihrem Hostnamen.
// KB = übertragen (komprimiert), roh = entpackt. Bei fremden Hosts ohne
// Timing-Allow-Origin meldet der Browser für beides 0, daher «?».
function analyzeBundles() {
    const groups = {};

    for (const r of performance.getEntriesByType('resource')) {
        const url = new URL(r.name);
        // gtag lädt von /gtag/js, ohne Endung: am Auslöser erkennen
        const isJs = r.initiatorType === 'script' || url.pathname.endsWith('.js');
        const isCss = url.pathname.endsWith('.css');
        if (!isJs && !isCss) {
            continue;
        }

        const bundle = url.pathname.match(/\/js\/([^/]+)\//);
        let name = url.hostname;
        if (url.hostname === location.hostname) {
            name = isCss ? url.pathname.split('/').pop() : (bundle ? bundle[1] : url.pathname);
        }

        const group = groups[name] ??= { Bundle: name, Dateien: 0, KB: 0, roh: 0, unbekannt: 0 };
        group.Dateien++;
        if (r.responseStart === 0) {
            group.unbekannt++;
        } else {
            group.KB += r.encodedBodySize / 1024;
            group.roh += r.decodedBodySize / 1024;
        }
    }

    // «?» = Grösse unbekannt, «+?» = dazu Dateien unbekannter Grösse
    const show = (g, kb) => {
        if (g.unbekannt === g.Dateien) {
            return '?';
        }
        return g.unbekannt > 0 ? `${Math.round(kb)} +?` : Math.round(kb);
    };
    const rows = Object.values(groups)
        .sort((a, b) => b.KB - a.KB)
        .map(g => ({ Bundle: g.Bundle, Dateien: g.Dateien, KB: show(g, g.KB), roh: show(g, g.roh) }));

    console.table(rows);
    return rows;
}

analyzeBundles();


// ============================================================
// 3. Wie die Skripte eingebunden sind
// ============================================================

// Ohne defer/async hält ein Skript den HTML-Parser an. Shopware bindet
// sein eigenes JavaScript seit 6.5 mit defer ein; was hier auftaucht,
// kommt meist aus einem Plugin, dem Theme oder einem Tag-Snippet.
function auditScriptLoading() {
    const counts = { defer: 0, async: 0, module: 0, ohne: 0 };
    const withoutDefer = [];

    for (const script of document.querySelectorAll('script[src]')) {
        if (script.type === 'module') {
            counts.module++;
        } else if (script.async) {
            counts.async++;
        } else if (script.defer) {
            counts.defer++;
        } else {
            counts.ohne++;
            withoutDefer.push({
                Skript: script.src,
                Ort: script.closest('head') ? 'head' : 'body',
            });
        }
    }

    console.log(`Skripte: ${counts.defer} defer, ${counts.async} async, ${counts.module} module, ${counts.ohne} ohne`);
    if (withoutDefer.length > 0) {
        console.table(withoutDefer);
    }
    return { counts, withoutDefer };
}

auditScriptLoading();
