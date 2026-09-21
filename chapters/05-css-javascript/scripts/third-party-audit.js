/**
 * Drittanbieter-Übersicht für die DevTools-Console
 * Kapitel 5: CSS und JavaScript optimieren
 *
 * Verwendung: Chrome DevTools → Console, Datei einfügen. Am besten
 * einige Sekunden nach dem Laden und nach der Cookie-Zustimmung, sonst
 * fehlt alles, was erst danach nachlädt.
 * Getestet in Chromium gegen Shopware 6.6.10.6.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// Alle Ressourcen fremder Hosts, je Host zusammengefasst. «Fremd» heisst
// hier: anderer Hostname als die Seite. Eine eigene Subdomain (CDN,
// Medien-Server) erscheint also ebenfalls.
//
// Ohne Timing-Allow-Origin-Header gibt der Browser für fremde Dateien
// keine Grösse heraus (0) – der Wert wäre falsch, deshalb «?». Die
// Grösse steht dann im Network-Tab. Dauer und Ende sind immer lesbar.
function auditThirdParty() {
    const hosts = {};

    for (const r of performance.getEntriesByType('resource')) {
        const host = new URL(r.name).hostname;
        if (host === location.hostname) {
            continue;
        }

        const entry = hosts[host] ??= { files: 0, bytes: 0, unknown: 0, blocking: 0, end: 0 };
        entry.files++;
        if (r.responseStart === 0) {
            entry.unknown++;
        } else {
            entry.bytes += r.encodedBodySize;
        }
        if (r.renderBlockingStatus === 'blocking') {
            entry.blocking++;
        }
        entry.end = Math.max(entry.end, r.responseEnd);
    }

    // «+?» = dazu Dateien unbekannter Grösse
    const kb = e => (e.unknown > 0 ? `${Math.round(e.bytes / 1024)} +?` : Math.round(e.bytes / 1024));
    const rows = Object.entries(hosts)
        .map(([host, e]) => ({
            Host: host,
            Dateien: e.files,
            KB: e.unknown === e.files ? '?' : kb(e),
            blockierend: e.blocking,
            'fertig nach ms': Math.round(e.end),
        }))
        .sort((a, b) => b.Dateien - a.Dateien);

    if (rows.length === 0) {
        console.log('Keine Ressourcen von fremden Hosts.');
    } else {
        console.table(rows);
    }
    return rows;
}

auditThirdParty();
