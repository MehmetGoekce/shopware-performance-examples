/**
 * AsyncSlider — lädt die Slider-Bibliothek erst bei der ersten Interaktion
 *
 * Zwei Stufen: Der Chunk dieses Plugins lädt nur, wenn
 * [data-async-slider] auf der Seite steht (main.js). tiny-slider
 * selbst lädt erst, wenn der Besucher das Element berührt, mit der
 * Maus darüberfährt oder per Tastatur hineinspringt.
 *
 * Die Basisklasse kommt aus window.PluginBaseClass (ab 6.5), nicht per
 * import aus 'src/plugin-system/plugin.class': Webpack baut jedes
 * Theme und Plugin mit einem eigenen Compiler, ein Import bündelt die
 * Klasse samt Abhängigkeiten ein zweites Mal.
 *
 * Achtung: Aus demselben Grund bündelt `import('tiny-slider')` die
 * Bibliothek erneut (performance-theme.tiny-slider.<hash>.js), obwohl
 * die Storefront sie für ihre eigenen Slider schon mitbringt. Nutzt
 * eine Seite beide, lädt tiny-slider doppelt.
 */
const { PluginBaseClass } = window;

export default class AsyncSliderPlugin extends PluginBaseClass {
    static options = {
        sliderSelector: '.async-slider-container',
    };

    init() {
        const load = () => this.loadSlider();
        this.el.addEventListener('mouseenter', load, { once: true });
        this.el.addEventListener('touchstart', load, { once: true, passive: true });
        this.el.addEventListener('focusin', load, { once: true });
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
