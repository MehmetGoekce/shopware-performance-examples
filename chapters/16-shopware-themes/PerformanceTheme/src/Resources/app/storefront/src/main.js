/**
 * main.js — Einstieg des Theme-JavaScripts (Webpack, auch in 6.7)
 *
 * Plugins mit einer Funktion statt einer Klasse registrieren:
 * Webpack legt das Plugin in einen eigenen Chunk, und der
 * PluginManager lädt ihn nur auf Seiten, auf denen der Selektor
 * vorkommt. So registriert Shopware seit 6.5 auch seine eigenen
 * Plugins (Storefront main.js).
 */
const PluginManager = window.PluginManager;

PluginManager.register(
    'AsyncSlider',
    () => import('./plugin/async-slider/async-slider.plugin'),
    '[data-async-slider]'
);
