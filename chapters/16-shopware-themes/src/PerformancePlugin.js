/**
 * Performance-optimiertes Shopware Plugin Beispiel
 *
 * Demonstriert Best Practices für performante Plugins:
 * - Lazy Initialization
 * - Event Delegation
 * - RequestAnimationFrame für DOM Updates
 * - Debouncing/Throttling
 * - Memory-effiziente Event Listener
 */

import Plugin from 'src/plugin-system/plugin.class';
import DomAccess from 'src/helper/dom-access.helper';

export default class PerformancePlugin extends Plugin {
  /**
   * Default Options
   * Alle konfigurierbaren Optionen mit Defaults
   */
  static options = {
    // Selektoren
    itemSelector: '.performance-item',
    triggerSelector: '.performance-trigger',

    // Timing
    debounceDelay: 150,
    throttleDelay: 100,

    // Features
    enableLazyImages: true,
    enableIntersectionObserver: true,
    enableVirtualization: false,

    // Thresholds
    intersectionRootMargin: '100px',
    intersectionThreshold: 0.1
  };

  /**
   * Lifecycle: Plugin initialisieren
   */
  init() {
    // DOM-Elemente cachen (einmalig)
    this.cacheElements();

    // Event Listener registrieren
    this.registerEvents();

    // Lazy Loading initialisieren
    if (this.options.enableIntersectionObserver) {
      this.initIntersectionObserver();
    }

    // Plugin als initialisiert markieren
    this.el.classList.add('performance-plugin-initialized');
  }

  /**
   * DOM-Elemente einmalig cachen
   * Vermeidet wiederholte DOM-Abfragen
   */
  cacheElements() {
    this._items = DomAccess.querySelectorAll(
      this.el,
      this.options.itemSelector,
      false // Kein Fehler wenn nicht gefunden
    );

    this._triggers = DomAccess.querySelectorAll(
      this.el,
      this.options.triggerSelector,
      false
    );
  }

  /**
   * Events mit Delegation registrieren
   * Effizienter als einzelne Listener pro Element
   */
  registerEvents() {
    // Event Delegation: Ein Listener für alle Trigger
    this.el.addEventListener('click', this._onDelegatedClick.bind(this));

    // Resize mit Debounce
    this._debouncedResize = this.debounce(
      this._onResize.bind(this),
      this.options.debounceDelay
    );
    window.addEventListener('resize', this._debouncedResize);

    // Scroll mit Throttle
    this._throttledScroll = this.throttle(
      this._onScroll.bind(this),
      this.options.throttleDelay
    );
    window.addEventListener('scroll', this._throttledScroll, { passive: true });
  }

  /**
   * Delegated Click Handler
   * @param {Event} event
   */
  _onDelegatedClick(event) {
    const trigger = event.target.closest(this.options.triggerSelector);

    if (!trigger) {
      return;
    }

    event.preventDefault();

    // RAF für DOM-Änderungen
    requestAnimationFrame(() => {
      this.handleTriggerClick(trigger);
    });
  }

  /**
   * Trigger-Klick verarbeiten
   * @param {HTMLElement} trigger
   */
  handleTriggerClick(trigger) {
    const itemId = trigger.dataset.itemId;

    if (!itemId) {
      return;
    }

    // Item finden und togglen
    const item = this.el.querySelector(`[data-id="${itemId}"]`);

    if (item) {
      item.classList.toggle('active');

      // Custom Event für externe Listener
      this.el.dispatchEvent(new CustomEvent('performance-plugin:toggle', {
        detail: { item, trigger, active: item.classList.contains('active') },
        bubbles: true
      }));
    }
  }

  /**
   * Resize Handler (debounced)
   */
  _onResize() {
    // Layout-Berechnungen nur wenn nötig
    if (this._items.length === 0) {
      return;
    }

    // Batch DOM-Reads
    const containerWidth = this.el.offsetWidth;
    const itemWidths = Array.from(this._items).map(item => item.offsetWidth);

    // RAF für DOM-Writes
    requestAnimationFrame(() => {
      this.updateLayout(containerWidth, itemWidths);
    });
  }

  /**
   * Scroll Handler (throttled)
   */
  _onScroll() {
    // Nur wenn Plugin sichtbar
    const rect = this.el.getBoundingClientRect();
    const isVisible = rect.top < window.innerHeight && rect.bottom > 0;

    if (!isVisible) {
      return;
    }

    // Scroll-Position-basierte Logik
    this.handleScroll(window.scrollY);
  }

  /**
   * IntersectionObserver für Lazy Loading
   */
  initIntersectionObserver() {
    if (!('IntersectionObserver' in window)) {
      // Fallback: Alles sofort laden
      this.loadAllItems();
      return;
    }

    this._observer = new IntersectionObserver(
      this._onIntersection.bind(this),
      {
        root: null,
        rootMargin: this.options.intersectionRootMargin,
        threshold: this.options.intersectionThreshold
      }
    );

    // Lazy Items beobachten
    this._items.forEach(item => {
      if (item.dataset.lazy === 'true') {
        this._observer.observe(item);
      }
    });
  }

  /**
   * IntersectionObserver Callback
   * @param {IntersectionObserverEntry[]} entries
   */
  _onIntersection(entries) {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        this.loadItem(entry.target);
        this._observer.unobserve(entry.target);
      }
    });
  }

  /**
   * Einzelnes Item laden
   * @param {HTMLElement} item
   */
  loadItem(item) {
    // Lazy Image laden
    const img = item.querySelector('img[data-src]');

    if (img) {
      img.src = img.dataset.src;
      img.removeAttribute('data-src');

      img.onload = () => {
        img.classList.add('loaded');
      };
    }

    item.dataset.lazy = 'false';
    item.classList.add('loaded');
  }

  /**
   * Alle Items laden (Fallback)
   */
  loadAllItems() {
    this._items.forEach(item => this.loadItem(item));
  }

  /**
   * Layout aktualisieren
   * @param {number} containerWidth
   * @param {number[]} itemWidths
   */
  updateLayout(containerWidth, itemWidths) {
    // Implementierung je nach Bedarf
    const columns = Math.floor(containerWidth / 300);

    this.el.style.setProperty('--columns', columns);
  }

  /**
   * Scroll-Position verarbeiten
   * @param {number} scrollY
   */
  handleScroll(scrollY) {
    // Implementierung je nach Bedarf (Parallax, Sticky, etc.)
  }

  // ============================================================
  // Utility Funktionen
  // ============================================================

  /**
   * Debounce: Funktion erst nach Pause ausführen
   * @param {Function} fn
   * @param {number} delay
   */
  debounce(fn, delay) {
    let timeoutId;

    return (...args) => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => fn.apply(this, args), delay);
    };
  }

  /**
   * Throttle: Funktion maximal alle X ms ausführen
   * @param {Function} fn
   * @param {number} limit
   */
  throttle(fn, limit) {
    let inThrottle;

    return (...args) => {
      if (!inThrottle) {
        fn.apply(this, args);
        inThrottle = true;
        setTimeout(() => inThrottle = false, limit);
      }
    };
  }

  // ============================================================
  // Cleanup
  // ============================================================

  /**
   * Plugin zerstören und aufräumen
   */
  destroy() {
    // Event Listener entfernen
    window.removeEventListener('resize', this._debouncedResize);
    window.removeEventListener('scroll', this._throttledScroll);

    // Observer stoppen
    if (this._observer) {
      this._observer.disconnect();
    }

    // Referenzen aufräumen
    this._items = null;
    this._triggers = null;

    // CSS-Klasse entfernen
    this.el.classList.remove('performance-plugin-initialized');
  }
}
