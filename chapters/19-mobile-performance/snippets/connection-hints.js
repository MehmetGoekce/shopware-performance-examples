/**
 * Datensparmodus und langsame Verbindung erkennen
 * Kapitel 19: Mobile Performance
 *
 * navigator.connection (Network Information API) gibt es nur in
 * Chromium-Browsern (Chrome, Edge, Samsung Internet, Chrome auf Android).
 * Firefox und Safari – und damit jeder Browser auf iOS – kennen es nicht;
 * dort liefert die Funktion false, und alles bleibt wie es ist.
 * effectiveType ist nach oben bei '4g' gedeckelt, WLAN und schnelles
 * Mobilnetz sind also nicht zu unterscheiden.
 *
 * Nur fuer Verzichtbares verwenden (Autoplay-Video, Vorladen weiterer
 * Bilder), nicht fuer andere Bild-URLs: Die gibt es in Shopware nicht.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
export function prefersReducedData(nav = globalThis.navigator) {
    const connection = nav && nav.connection;
    if (!connection) {
        return false;
    }

    return connection.saveData === true || ['slow-2g', '2g'].includes(connection.effectiveType);
}
