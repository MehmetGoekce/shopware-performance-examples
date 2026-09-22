/**
 * Lange Aufgaben aufteilen, damit Eingaben schneller eine Antwort sehen (INP)
 * Kapitel 19: Mobile Performance
 *
 * scheduler.yield() gibt dem Browser zwischendurch Gelegenheit, zu malen
 * und Eingaben zu verarbeiten, und setzt danach mit Vorrang fort.
 * Chrome/Edge ab 129, Firefox ab 142, Safari (auch jeder Browser auf iOS)
 * nicht – dort setTimeout(0) als Rueckfall. requestIdleCallback fehlt in
 * Safari ebenfalls und eignet sich nicht fuer Arbeit, auf die der Nutzer wartet.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
export function yieldToMain() {
    if (globalThis.scheduler && typeof globalThis.scheduler.yield === 'function') {
        return globalThis.scheduler.yield();
    }

    return new Promise((resolve) => {
        setTimeout(resolve, 0);
    });
}

// Beispiel: erst die sichtbare Rueckmeldung, dann die Arbeit in Portionen
export async function applyInChunks(button, items, work, chunkSize = 50) {
    button.classList.add('is-loading');
    await yieldToMain();

    for (let i = 0; i < items.length; i++) {
        work(items[i]);
        if ((i + 1) % chunkSize === 0) {
            await yieldToMain();
        }
    }

    button.classList.remove('is-loading');
}
