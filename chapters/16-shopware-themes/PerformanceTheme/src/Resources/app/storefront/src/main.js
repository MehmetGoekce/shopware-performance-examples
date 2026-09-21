/**
 * main.js — Einstieg des Theme-JavaScripts (Webpack, auch in 6.7)
 *
 * Plugins mit einer Funktion statt einer Klasse registrieren:
 * Webpack legt das Plugin in einen eigenen Chunk, und der
 * PluginManager lädt ihn nur auf Seiten, auf denen der Selektor
 * vorkommt. So registriert Shopware ab 6.6 auch seine eigenen
 * Plugins (Storefront main.js). In 6.5.8 kann der PluginManager das
 * nur mit aktivem Feature-Flag v6.6.0.0, davor gar nicht.
 */
const PluginManager = window.PluginManager;

PluginManager.register(
    'AsyncSlider',
    () => import('./plugin/async-slider/async-slider.plugin'),
    '[data-async-slider]'
);
