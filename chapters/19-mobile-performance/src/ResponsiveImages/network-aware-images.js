/**
 * Network-Aware Image Loading
 *
 * Adapts image quality based on:
 * - Network connection type (4G, 3G, 2G)
 * - Data saver mode
 * - Device memory
 *
 * Usage:
 *   import { NetworkAwareImages } from './network-aware-images.js';
 *   NetworkAwareImages.init();
 */

export class NetworkAwareImages {
    static quality = 'high';
    static initialized = false;

    /**
     * Initialize network-aware image loading
     */
    static init() {
        if (this.initialized) return;
        this.initialized = true;

        // Determine initial quality
        this.quality = this.determineQuality();

        // Listen for connection changes
        if ('connection' in navigator) {
            navigator.connection.addEventListener('change', () => {
                this.quality = this.determineQuality();
                this.updateImages();
            });
        }

        // Apply to existing images
        this.updateImages();

        // Observe new images
        this.observeNewImages();

        console.log(`[NetworkAwareImages] Quality set to: ${this.quality}`);
    }

    /**
     * Determine image quality based on network conditions
     */
    static determineQuality() {
        const connection = navigator.connection ||
                          navigator.mozConnection ||
                          navigator.webkitConnection;

        // Data saver mode
        if (connection?.saveData) {
            return 'low';
        }

        // Effective connection type
        const effectiveType = connection?.effectiveType;
        switch (effectiveType) {
            case 'slow-2g':
            case '2g':
                return 'low';
            case '3g':
                return 'medium';
            case '4g':
            default:
                return 'high';
        }
    }

    /**
     * Get quality suffix for image URLs
     */
    static getQualitySuffix() {
        switch (this.quality) {
            case 'low':
                return '_q40'; // 40% quality
            case 'medium':
                return '_q70'; // 70% quality
            case 'high':
            default:
                return ''; // Original quality
        }
    }

    /**
     * Get maximum image width based on quality
     */
    static getMaxWidth() {
        switch (this.quality) {
            case 'low':
                return 480;
            case 'medium':
                return 768;
            case 'high':
            default:
                return 1920;
        }
    }

    /**
     * Update all images on page
     */
    static updateImages() {
        document.querySelectorAll('[data-network-aware]').forEach((img) => {
            this.updateImage(img);
        });
    }

    /**
     * Update single image based on quality
     */
    static updateImage(img) {
        const originalSrc = img.dataset.src || img.src;
        const baseSrc = this.getBaseSrc(originalSrc);

        if (!baseSrc) return;

        // Get appropriate quality version
        const newSrc = this.getQualitySrc(baseSrc);
        img.src = newSrc;

        // Update srcset if present
        if (img.srcset) {
            const newSrcset = this.updateSrcset(img.dataset.srcset || img.srcset);
            img.srcset = newSrcset;
        }

        img.dataset.quality = this.quality;
    }

    /**
     * Get base source URL without quality suffix
     */
    static getBaseSrc(src) {
        // Remove existing quality suffixes
        return src.replace(/_q\d+/, '');
    }

    /**
     * Get quality-adjusted source URL
     */
    static getQualitySrc(baseSrc) {
        if (this.quality === 'high') return baseSrc;

        // Insert quality suffix before extension
        const extMatch = baseSrc.match(/(\.[^.]+)$/);
        if (!extMatch) return baseSrc;

        const ext = extMatch[1];
        const base = baseSrc.slice(0, -ext.length);
        return `${base}${this.getQualitySuffix()}${ext}`;
    }

    /**
     * Update srcset with quality adjustments
     */
    static updateSrcset(srcset) {
        const maxWidth = this.getMaxWidth();

        return srcset
            .split(',')
            .map((entry) => {
                const [url, descriptor] = entry.trim().split(/\s+/);
                const width = parseInt(descriptor, 10);

                // Skip sources larger than max width
                if (width > maxWidth) {
                    return null;
                }

                const newUrl = this.getQualitySrc(this.getBaseSrc(url));
                return `${newUrl} ${descriptor}`;
            })
            .filter(Boolean)
            .join(', ');
    }

    /**
     * Observe new images added to DOM
     */
    static observeNewImages() {
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType !== Node.ELEMENT_NODE) return;

                    // Check if it's an image
                    if (node.matches?.('[data-network-aware]')) {
                        this.updateImage(node);
                    }

                    // Check children
                    node.querySelectorAll?.('[data-network-aware]').forEach((img) => {
                        this.updateImage(img);
                    });
                });
            });
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true,
        });
    }

    /**
     * Check if data saver is enabled
     */
    static isDataSaverEnabled() {
        return navigator.connection?.saveData === true;
    }

    /**
     * Get connection info for debugging
     */
    static getConnectionInfo() {
        const connection = navigator.connection ||
                          navigator.mozConnection ||
                          navigator.webkitConnection;

        if (!connection) {
            return { supported: false };
        }

        return {
            supported: true,
            effectiveType: connection.effectiveType,
            downlink: connection.downlink,
            rtt: connection.rtt,
            saveData: connection.saveData,
            type: connection.type,
        };
    }
}

/**
 * Lazy Loading with Intersection Observer
 *
 * Modern lazy loading with network awareness.
 */
export class SmartLazyLoad {
    constructor(options = {}) {
        this.options = {
            rootMargin: options.rootMargin || '50px 0px',
            threshold: options.threshold || 0.01,
            loadingClass: options.loadingClass || 'loading',
            loadedClass: options.loadedClass || 'loaded',
        };

        this.observer = null;
        this.init();
    }

    init() {
        if (!('IntersectionObserver' in window)) {
            // Fallback: load all images immediately
            this.loadAllImages();
            return;
        }

        this.observer = new IntersectionObserver(
            this.handleIntersection.bind(this),
            {
                rootMargin: this.options.rootMargin,
                threshold: this.options.threshold,
            }
        );

        this.observe();
    }

    observe() {
        document.querySelectorAll('[data-lazy-src]').forEach((img) => {
            img.classList.add(this.options.loadingClass);
            this.observer.observe(img);
        });
    }

    handleIntersection(entries) {
        entries.forEach((entry) => {
            if (!entry.isIntersecting) return;

            const img = entry.target;
            this.loadImage(img);
            this.observer.unobserve(img);
        });
    }

    loadImage(img) {
        const src = img.dataset.lazySrc;
        const srcset = img.dataset.lazySrcset;

        if (srcset) {
            img.srcset = NetworkAwareImages.updateSrcset(srcset);
        }

        if (src) {
            img.src = NetworkAwareImages.getQualitySrc(
                NetworkAwareImages.getBaseSrc(src)
            );
        }

        img.classList.remove(this.options.loadingClass);
        img.classList.add(this.options.loadedClass);

        // Remove data attributes
        delete img.dataset.lazySrc;
        delete img.dataset.lazySrcset;
    }

    loadAllImages() {
        document.querySelectorAll('[data-lazy-src]').forEach((img) => {
            this.loadImage(img);
        });
    }

    destroy() {
        if (this.observer) {
            this.observer.disconnect();
        }
    }
}

// Auto-initialize
if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', () => {
        NetworkAwareImages.init();
        new SmartLazyLoad();
    });
}
