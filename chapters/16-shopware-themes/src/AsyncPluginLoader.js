/**
 * Async Plugin Loader für Shopware 6
 *
 * Lädt JavaScript-Plugins erst bei Bedarf, um den initialen
 * Bundle-Size zu reduzieren.
 *
 * Verwendung:
 *   import { asyncLoad, asyncLoadOnVisible, asyncLoadOnInteraction } from './AsyncPluginLoader';
 *
 *   // Bei Viewport-Eintritt laden
 *   asyncLoadOnVisible('[data-slider]', () => import('./plugins/slider'));
 *
 *   // Bei Interaktion laden
 *   asyncLoadOnInteraction('[data-datepicker]', 'focus', () => import('flatpickr'));
 */

/**
 * Basis-Funktion für async Import
 * @param {Function} importFn - Dynamic import function
 * @returns {Promise} - Resolved module
 */
export async function asyncLoad(importFn) {
  try {
    const module = await importFn();
    return module.default || module;
  } catch (error) {
    console.error('[AsyncPluginLoader] Failed to load module:', error);
    throw error;
  }
}

/**
 * Lädt Plugin wenn Element im Viewport sichtbar wird
 * @param {string} selector - CSS Selector für Elemente
 * @param {Function} importFn - Dynamic import function
 * @param {Object} options - IntersectionObserver options
 */
export function asyncLoadOnVisible(selector, importFn, options = {}) {
  const elements = document.querySelectorAll(selector);

  if (elements.length === 0) {
    return;
  }

  const defaultOptions = {
    root: null,
    rootMargin: '100px', // Etwas früher laden
    threshold: 0.1
  };

  const observerOptions = { ...defaultOptions, ...options };
  let loaded = false;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting && !loaded) {
        loaded = true;

        asyncLoad(importFn)
          .then((Plugin) => {
            // Plugin für alle Elemente initialisieren
            elements.forEach((el) => {
              if (typeof Plugin === 'function') {
                new Plugin(el);
              } else if (Plugin.init) {
                Plugin.init(el);
              }
            });

            // Observer stoppen
            observer.disconnect();
          })
          .catch((err) => {
            console.error('[AsyncPluginLoader] Visible load failed:', err);
          });
      }
    });
  }, observerOptions);

  // Alle Elemente beobachten
  elements.forEach((el) => observer.observe(el));
}

/**
 * Lädt Plugin bei User-Interaktion
 * @param {string} selector - CSS Selector
 * @param {string} event - Event type (click, focus, mouseenter, etc.)
 * @param {Function} importFn - Dynamic import function
 * @param {Object} options - Additional options
 */
export function asyncLoadOnInteraction(selector, event, importFn, options = {}) {
  const elements = document.querySelectorAll(selector);

  if (elements.length === 0) {
    return;
  }

  const defaultOptions = {
    once: true, // Nach erstem Load Event-Listener entfernen
    preloadOnIdle: false // Bei Idle-Time vorladen
  };

  const config = { ...defaultOptions, ...options };
  let loaded = false;
  let Plugin = null;

  const loadAndInit = async (targetElement) => {
    if (!loaded) {
      loaded = true;

      try {
        Plugin = await asyncLoad(importFn);
      } catch (err) {
        console.error('[AsyncPluginLoader] Interaction load failed:', err);
        return;
      }
    }

    // Plugin initialisieren
    if (Plugin) {
      if (typeof Plugin === 'function') {
        new Plugin(targetElement);
      } else if (Plugin.init) {
        Plugin.init(targetElement);
      }
    }
  };

  elements.forEach((el) => {
    el.addEventListener(event, function handler() {
      loadAndInit(el);

      if (config.once) {
        el.removeEventListener(event, handler);
      }
    });
  });

  // Optional: Bei Idle-Time vorladen
  if (config.preloadOnIdle && 'requestIdleCallback' in window) {
    requestIdleCallback(() => {
      if (!loaded) {
        asyncLoad(importFn)
          .then((module) => {
            Plugin = module;
            loaded = true;
          })
          .catch(() => {
            // Silent fail - wird bei Interaktion erneut versucht
          });
      }
    }, { timeout: 5000 });
  }
}

/**
 * Lädt Plugin basierend auf Media Query
 * @param {string} selector - CSS Selector
 * @param {string} mediaQuery - CSS Media Query
 * @param {Function} importFn - Dynamic import function
 */
export function asyncLoadOnMedia(selector, mediaQuery, importFn) {
  const mql = window.matchMedia(mediaQuery);

  const handleChange = (e) => {
    if (e.matches) {
      const elements = document.querySelectorAll(selector);

      if (elements.length > 0) {
        asyncLoad(importFn)
          .then((Plugin) => {
            elements.forEach((el) => {
              if (typeof Plugin === 'function') {
                new Plugin(el);
              }
            });
          })
          .catch((err) => {
            console.error('[AsyncPluginLoader] Media query load failed:', err);
          });

        // Listener entfernen nach erfolgreichem Load
        mql.removeEventListener('change', handleChange);
      }
    }
  };

  // Sofort prüfen
  handleChange(mql);

  // Auf Änderungen reagieren
  mql.addEventListener('change', handleChange);
}

/**
 * Preload-Hint für Plugins setzen (für späteres schnelleres Laden)
 * @param {string} moduleUrl - URL des Moduls
 */
export function preloadModule(moduleUrl) {
  if (document.querySelector(`link[href="${moduleUrl}"]`)) {
    return; // Bereits vorhanden
  }

  const link = document.createElement('link');
  link.rel = 'modulepreload';
  link.href = moduleUrl;
  document.head.appendChild(link);
}

/**
 * Shopware PluginManager Integration
 * Registriert async-geladene Plugins beim PluginManager
 */
export class AsyncPluginManager {
  constructor() {
    this.loadedPlugins = new Map();
  }

  /**
   * Async Plugin registrieren
   * @param {string} name - Plugin name
   * @param {Function} importFn - Dynamic import
   * @param {string} selector - CSS selector
   * @param {Object} options - Plugin options
   */
  registerAsync(name, importFn, selector, options = {}) {
    const config = {
      loadOn: 'visible', // visible, interaction, media, immediate
      event: 'click',
      mediaQuery: null,
      ...options
    };

    switch (config.loadOn) {
      case 'visible':
        asyncLoadOnVisible(selector, importFn);
        break;

      case 'interaction':
        asyncLoadOnInteraction(selector, config.event, importFn);
        break;

      case 'media':
        if (config.mediaQuery) {
          asyncLoadOnMedia(selector, config.mediaQuery, importFn);
        }
        break;

      case 'immediate':
        asyncLoad(importFn).then((Plugin) => {
          document.querySelectorAll(selector).forEach((el) => {
            if (typeof Plugin === 'function') {
              new Plugin(el);
            }
          });
        });
        break;
    }

    this.loadedPlugins.set(name, { importFn, selector, config });
  }

  /**
   * Alle registrierten async Plugins auflisten
   */
  list() {
    return Array.from(this.loadedPlugins.keys());
  }
}

// Singleton-Instanz
export const asyncPluginManager = new AsyncPluginManager();

// Default Export
export default {
  asyncLoad,
  asyncLoadOnVisible,
  asyncLoadOnInteraction,
  asyncLoadOnMedia,
  preloadModule,
  asyncPluginManager
};
