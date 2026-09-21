/**
 * Bild-Analyse für die DevTools-Console
 * Kapitel 4: Bildoptimierung
 *
 * Verwendung: Seite laden, bis zum Ende scrollen (lazy Bilder laden
 * erst dann), Datei in die Console einfügen.
 * Getestet in Chromium gegen Shopware 6.6.10.6.
 *
 * Pro geladenem Bild: welche Datei der Browser aus dem srcset gewählt
 * hat, wie viele Pixel die Anzeige braucht (CSS-Breite × Pixeldichte),
 * wie breit die Datei wirklich ist, und das Verhältnis. Faktor über
 * 1,5 heisst: zu grosse Datei für diesen Platz.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

async function analyzeImages() {
    const dpr = window.devicePixelRatio;
    const rows = [];

    for (const img of document.images) {
        // Noch nicht geladene (lazy) oder unsichtbare Bilder überspringen
        if (!img.currentSrc || img.clientWidth === 0) continue;

        // naturalWidth ist bei srcset dichtekorrigiert und img.src ist
        // bei sw_thumbnails immer das Original. Die echte Pixelbreite der
        // geladenen Datei liefert ein eigenes Image-Objekt.
        const probe = new Image();
        probe.src = img.currentSrc;
        await probe.decode().catch(() => {});

        const needed = Math.round(img.clientWidth * dpr);
        const entry = performance.getEntriesByName(img.currentSrc)[0];

        rows.push({
            Datei: img.currentSrc.split('/').pop().split('?')[0].substring(0, 40),
            'Anzeige px': needed,
            'Datei px': probe.naturalWidth,
            Faktor: Number((probe.naturalWidth / needed).toFixed(1)),
            // 0 bei fremden Domains ohne Timing-Allow-Origin
            KB: entry ? Math.round(entry.encodedBodySize / 1024) : null,
            loading: img.getAttribute('loading') || '(kein Attribut)',
        });
    }

    console.table(rows);
    return rows;
}

analyzeImages();
