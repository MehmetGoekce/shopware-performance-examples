/**
 * AsyncSlider — lädt die Slider-Bibliothek erst bei der ersten Interaktion
 *
 * Zwei Stufen: Der Chunk dieses Plugins lädt nur, wenn
 * [data-async-slider] auf der Seite steht (main.js). tiny-slider
 * selbst lädt erst, wenn der Besucher das Element berührt oder
 * mit der Maus darüberfährt.
 *
 * Achtung: Webpack baut jedes Theme und Plugin mit einem eigenen
 * Compiler. `import('tiny-slider')` bündelt die Bibliothek deshalb ein
 * zweites Mal (performance-theme.tiny-slider.<hash>.js), obwohl die
 * Storefront sie für ihre eigenen Slider schon mitbringt. Nutzt eine
 * Seite beide, lädt tiny-slider doppelt.
 */
import Plugin from 'src/plugin-system/plugin.class';

export default class AsyncSliderPlugin extends Plugin {
    static options = {
        sliderSelector: '.async-slider-container',
    };

    init() {
        const load = () => this.loadSlider();
        this.el.addEventListener('mouseenter', load, { once: true });
        this.el.addEventListener('touchstart', load, { once: true, passive: true });
    }

    async loadSlider() {
        if (this.slider) {
            return;
        }

        const { tns } = await import('tiny-slider');
        this.slider = tns({
            container: this.el.querySelector(this.options.sliderSelector),
            items: 1,
            slideBy: 'page',
        });
    }
}
