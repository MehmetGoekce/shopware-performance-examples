<?php

declare(strict_types=1);

namespace ShopwarePerformance\ThirdPartyScripts\Service;

use Psr\Log\LoggerInterface;
use Symfony\Component\HttpFoundation\Cookie;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * ConsentPerformanceService - Performance-optimiertes Consent Management
 *
 * @description
 * Verwaltet Cookie-Consent und Third-Party Scripts ohne Performance-Einbußen.
 * Implementiert lazy loading, conditional loading und consent-aware script injection.
 *
 * @example
 * // Consent prüfen und Script laden
 * if ($consentService->hasConsent('analytics')) {
 *     $consentService->loadConsentedScript('google-analytics', [
 *         'measurement_id' => 'G-XXXXXXXXXX',
 *     ]);
 * }
 *
 * // Consent-Status tracken ohne Performance-Impact
 * $consentService->trackConsentChange('analytics', true);
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ThirdPartyScripts
 */
class ConsentPerformanceService
{
    private const COOKIE_NAME = 'sw_consent_preferences';
    private const COOKIE_LIFETIME = 365 * 24 * 60 * 60; // 1 Jahr

    /**
     * @var array<string, array<string, mixed>> Script-Definitionen nach Kategorie
     */
    private array $scriptDefinitions = [];

    /**
     * @var array<string, bool> Aktuelle Consent-Status (Cache)
     */
    private ?array $consentCache = null;

    /**
     * @param RequestStack $requestStack HTTP Request Stack
     * @param LoggerInterface $logger Logger
     * @param array<string, array<string, mixed>> $consentConfig Consent-Konfiguration
     */
    public function __construct(
        private readonly RequestStack $requestStack,
        private readonly LoggerInterface $logger,
        array $consentConfig = []
    ) {
        $this->loadScriptDefinitions($consentConfig);
    }

    /**
     * Prüft ob Consent für Kategorie vorhanden
     *
     * @param string $category Consent-Kategorie (z.B. 'analytics', 'marketing')
     * @return bool True wenn Consent erteilt
     */
    public function hasConsent(string $category): bool
    {
        $consents = $this->getConsentStatus();

        return $consents[$category] ?? false;
    }

    /**
     * Gibt alle Consent-Status zurück
     *
     * @return array<string, bool> Kategorie => Status
     */
    public function getConsentStatus(): array
    {
        if ($this->consentCache !== null) {
            return $this->consentCache;
        }

        $request = $this->requestStack->getCurrentRequest();

        if (!$request || !$request->cookies->has(self::COOKIE_NAME)) {
            // Kein Consent gesetzt - nur essentials erlaubt
            $this->consentCache = [
                'essential' => true,
                'functional' => false,
                'analytics' => false,
                'marketing' => false,
                'advertising' => false,
            ];

            return $this->consentCache;
        }

        try {
            $cookieValue = $request->cookies->get(self::COOKIE_NAME);
            $consents = json_decode($cookieValue, true, 512, JSON_THROW_ON_ERROR);

            $this->consentCache = array_merge([
                'essential' => true,
                'functional' => false,
                'analytics' => false,
                'marketing' => false,
                'advertising' => false,
            ], $consents);

            return $this->consentCache;

        } catch (\JsonException $e) {
            $this->logger->error('Failed to parse consent cookie', [
                'error' => $e->getMessage(),
            ]);

            return $this->consentCache = ['essential' => true];
        }
    }

    /**
     * Speichert Consent-Präferenzen
     *
     * @param array<string, bool> $consents Consent-Status
     * @return Cookie Cookie-Objekt zum Setzen in Response
     */
    public function saveConsent(array $consents): Cookie
    {
        // Validate
        $validCategories = ['essential', 'functional', 'analytics', 'marketing', 'advertising'];
        foreach ($consents as $category => $status) {
            if (!in_array($category, $validCategories, true)) {
                throw new \InvalidArgumentException("Invalid consent category: {$category}");
            }
        }

        // Essential immer true
        $consents['essential'] = true;

        // Cache invalidieren
        $this->consentCache = null;

        $cookieValue = json_encode($consents, JSON_THROW_ON_ERROR);

        $this->logger->info('Consent preferences saved', [
            'consents' => $consents,
        ]);

        return Cookie::create(self::COOKIE_NAME)
            ->withValue($cookieValue)
            ->withExpires(time() + self::COOKIE_LIFETIME)
            ->withPath('/')
            ->withSecure(true)
            ->withHttpOnly(false) // JavaScript muss lesen können
            ->withSameSite(Cookie::SAMESITE_LAX);
    }

    /**
     * Lädt Script nur wenn Consent vorhanden
     *
     * @param string $scriptName Script-Name (z.B. 'google-analytics')
     * @param array<string, mixed> $config Script-Konfiguration
     * @return string|null HTML/JS Code oder null wenn kein Consent
     */
    public function loadConsentedScript(string $scriptName, array $config = []): ?string
    {
        if (!isset($this->scriptDefinitions[$scriptName])) {
            $this->logger->warning('Unknown script requested', [
                'script' => $scriptName,
            ]);

            return null;
        }

        $definition = $this->scriptDefinitions[$scriptName];
        $category = $definition['category'];

        // Consent prüfen
        if (!$this->hasConsent($category)) {
            $this->logger->debug('Script blocked due to missing consent', [
                'script' => $scriptName,
                'category' => $category,
            ]);

            return null;
        }

        // Script generieren
        return $this->generateScriptCode($definition, $config);
    }

    /**
     * Generiert Consent-aware Script-Loader (lädt Scripts dynamisch nach Consent)
     *
     * @return string JavaScript Code
     */
    public function generateConsentLoader(): string
    {
        $scriptDefinitionsJson = json_encode($this->scriptDefinitions, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);

        return <<<JS
        <script>
        (function() {
            'use strict';

            const scriptDefinitions = {$scriptDefinitionsJson};
            const loadedScripts = new Set();

            // Liest Consent-Cookie
            function getConsent() {
                const cookies = document.cookie.split(';');
                for (let cookie of cookies) {
                    const [name, value] = cookie.trim().split('=');
                    if (name === 'sw_consent_preferences') {
                        try {
                            return JSON.parse(decodeURIComponent(value));
                        } catch (e) {
                            console.error('Failed to parse consent cookie', e);
                            return { essential: true };
                        }
                    }
                }
                return { essential: true };
            }

            // Lädt Script wenn Consent vorhanden
            function loadScript(scriptName, config = {}) {
                if (loadedScripts.has(scriptName)) {
                    return; // Bereits geladen
                }

                const definition = scriptDefinitions[scriptName];
                if (!definition) {
                    console.warn('Unknown script:', scriptName);
                    return;
                }

                const consent = getConsent();
                if (!consent[definition.category]) {
                    console.debug('Script blocked by consent:', scriptName, definition.category);
                    return;
                }

                // Script laden
                const script = document.createElement('script');
                script.type = definition.type || 'text/javascript';
                script.async = definition.async !== false;
                script.defer = definition.defer === true;

                // URL mit Config-Parametern
                let url = definition.url;
                if (definition.params && Object.keys(config).length > 0) {
                    const params = new URLSearchParams();
                    Object.entries(config).forEach(([key, value]) => {
                        params.set(key, value);
                    });
                    url += (url.includes('?') ? '&' : '?') + params.toString();
                }

                script.src = url;
                script.onload = function() {
                    loadedScripts.add(scriptName);
                    console.log('Consent script loaded:', scriptName);

                    // Callback ausführen
                    if (definition.onload) {
                        try {
                            eval('(' + definition.onload + ')()');
                        } catch (e) {
                            console.error('Script onload failed:', scriptName, e);
                        }
                    }
                };

                script.onerror = function() {
                    console.error('Failed to load script:', scriptName);
                };

                document.head.appendChild(script);
            }

            // Globale Funktion für externe Nutzung
            window.loadConsentedScript = loadScript;

            // Event-Listener für Consent-Änderungen
            window.addEventListener('consentUpdated', function(e) {
                const consents = e.detail;
                console.log('Consent updated, reloading scripts', consents);

                // Alle Scripts neu evaluieren
                Object.keys(scriptDefinitions).forEach(function(scriptName) {
                    loadScript(scriptName);
                });
            });

            // Initial load für bereits erteilte Consents
            const initialConsent = getConsent();
            Object.entries(scriptDefinitions).forEach(function([scriptName, definition]) {
                if (definition.autoload && initialConsent[definition.category]) {
                    loadScript(scriptName, definition.config || {});
                }
            });
        })();
        </script>
        JS;
    }

    /**
     * Trackt Consent-Änderung (Performance-aware)
     *
     * @param string $category Kategorie
     * @param bool $granted Consent erteilt/widerrufen
     * @return void
     */
    public function trackConsentChange(string $category, bool $granted): void
    {
        // Lightweight tracking ohne Third-Party Scripts
        $this->logger->info('Consent changed', [
            'category' => $category,
            'granted' => $granted,
            'timestamp' => time(),
            'user_agent' => $this->requestStack->getCurrentRequest()?->headers->get('User-Agent'),
        ]);

        // Event für Frontend auslösen (via Cookie oder ähnliches)
        // In Realität würde dies über JavaScript Event kommuniziert
    }

    /**
     * Generiert Consent-Banner HTML (Performance-optimiert)
     *
     * @param array<string, mixed> $options Banner-Optionen
     * @return string HTML Code
     */
    public function generateConsentBanner(array $options = []): string
    {
        $position = $options['position'] ?? 'bottom';
        $style = $options['style'] ?? 'minimal';
        $categories = $options['categories'] ?? ['functional', 'analytics', 'marketing'];

        $categoriesJson = json_encode($categories, JSON_THROW_ON_ERROR);

        return <<<HTML
        <div id="consent-banner" class="consent-banner consent-{$position} consent-{$style}" style="display:none;">
            <div class="consent-banner-content">
                <h3>Cookie-Einstellungen</h3>
                <p>Wir nutzen Cookies für Funktionalität, Analyse und Marketing. Sie können Ihre Präferenzen jederzeit anpassen.</p>

                <div class="consent-categories">
                    <label>
                        <input type="checkbox" value="essential" checked disabled>
                        Essenziell (erforderlich)
                    </label>
                    {$this->generateCategoryCheckboxes($categories)}
                </div>

                <div class="consent-actions">
                    <button onclick="acceptAllConsents()">Alle akzeptieren</button>
                    <button onclick="acceptSelectedConsents()">Auswahl speichern</button>
                    <button onclick="rejectAllConsents()">Nur essenzielle</button>
                </div>
            </div>
        </div>

        <script>
        (function() {
            'use strict';

            const categories = {$categoriesJson};

            // Banner anzeigen wenn kein Consent gesetzt
            if (!document.cookie.includes('sw_consent_preferences')) {
                document.getElementById('consent-banner').style.display = 'block';
            }

            window.acceptAllConsents = function() {
                const consents = { essential: true };
                categories.forEach(cat => consents[cat] = true);
                saveConsent(consents);
            };

            window.acceptSelectedConsents = function() {
                const consents = { essential: true };
                categories.forEach(cat => {
                    const checkbox = document.querySelector('input[value="' + cat + '"]');
                    consents[cat] = checkbox ? checkbox.checked : false;
                });
                saveConsent(consents);
            };

            window.rejectAllConsents = function() {
                saveConsent({ essential: true });
            };

            function saveConsent(consents) {
                // Cookie setzen
                const value = JSON.stringify(consents);
                const expires = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toUTCString();
                document.cookie = 'sw_consent_preferences=' + encodeURIComponent(value) +
                                 '; expires=' + expires + '; path=/; secure; samesite=lax';

                // Banner ausblenden
                document.getElementById('consent-banner').style.display = 'none';

                // Event für Script-Loader
                window.dispatchEvent(new CustomEvent('consentUpdated', { detail: consents }));

                // Optional: Seite neu laden um Scripts zu laden
                // window.location.reload();
            }
        })();
        </script>

        <style>
        .consent-banner {
            position: fixed;
            left: 0;
            right: 0;
            background: #fff;
            box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
            padding: 20px;
            z-index: 99999;
        }
        .consent-bottom { bottom: 0; }
        .consent-top { top: 0; }
        .consent-banner-content { max-width: 1200px; margin: 0 auto; }
        .consent-categories { margin: 15px 0; }
        .consent-categories label { display: block; margin: 8px 0; }
        .consent-actions { margin-top: 15px; }
        .consent-actions button {
            padding: 10px 20px;
            margin-right: 10px;
            cursor: pointer;
            border: 1px solid #ccc;
            background: #f5f5f5;
            border-radius: 4px;
        }
        .consent-actions button:first-child {
            background: #007bff;
            color: #fff;
            border-color: #007bff;
        }
        </style>
        HTML;
    }

    /**
     * Registriert Script-Definition
     *
     * @param string $name Script-Name
     * @param array<string, mixed> $definition Script-Definition
     * @return void
     */
    public function registerScript(string $name, array $definition): void
    {
        $this->scriptDefinitions[$name] = array_merge([
            'category' => 'marketing',
            'url' => '',
            'type' => 'text/javascript',
            'async' => true,
            'defer' => false,
            'autoload' => false,
            'params' => false,
            'onload' => null,
            'config' => [],
        ], $definition);
    }

    /**
     * Lädt Script-Definitionen aus Config
     *
     * @param array<string, array<string, mixed>> $config Konfiguration
     * @return void
     */
    private function loadScriptDefinitions(array $config): void
    {
        // Standard-Scripts
        $this->scriptDefinitions = [
            'google-analytics' => [
                'category' => 'analytics',
                'url' => 'https://www.googletagmanager.com/gtag/js',
                'params' => true,
                'async' => true,
                'autoload' => true,
                'onload' => "function() {
                    window.dataLayer = window.dataLayer || [];
                    function gtag(){dataLayer.push(arguments);}
                    gtag('js', new Date());
                    gtag('config', 'G-XXXXXXXXXX');
                }",
            ],
            'facebook-pixel' => [
                'category' => 'marketing',
                'url' => 'https://connect.facebook.net/en_US/fbevents.js',
                'async' => true,
                'autoload' => true,
                'onload' => "function() {
                    fbq('init', 'PIXEL_ID');
                    fbq('track', 'PageView');
                }",
            ],
            'hotjar' => [
                'category' => 'analytics',
                'url' => 'https://static.hotjar.com/c/hotjar-{hjid}.js',
                'async' => true,
                'autoload' => true,
            ],
        ];

        // Custom Scripts aus Config
        foreach ($config as $name => $definition) {
            $this->registerScript($name, $definition);
        }
    }

    /**
     * Generiert Script-Code aus Definition
     *
     * @param array<string, mixed> $definition Script-Definition
     * @param array<string, mixed> $config Runtime-Config
     * @return string HTML/JS Code
     */
    private function generateScriptCode(array $definition, array $config): string
    {
        $url = $definition['url'];

        // Parameter anhängen
        if ($definition['params'] && !empty($config)) {
            $params = http_build_query($config);
            $url .= (str_contains($url, '?') ? '&' : '?') . $params;
        }

        $async = $definition['async'] ? 'async' : '';
        $defer = $definition['defer'] ? 'defer' : '';

        return sprintf(
            '<script src="%s" type="%s" %s %s></script>',
            htmlspecialchars($url, ENT_QUOTES, 'UTF-8'),
            $definition['type'],
            $async,
            $defer
        );
    }

    /**
     * Generiert Checkboxen für Kategorien
     *
     * @param array<string> $categories Kategorien
     * @return string HTML
     */
    private function generateCategoryCheckboxes(array $categories): string
    {
        $labels = [
            'functional' => 'Funktional (verbessert Benutzererfahrung)',
            'analytics' => 'Analyse (hilft uns die Website zu verbessern)',
            'marketing' => 'Marketing (personalisierte Inhalte)',
            'advertising' => 'Werbung (relevante Anzeigen)',
        ];

        $html = '';
        foreach ($categories as $category) {
            $label = $labels[$category] ?? ucfirst($category);
            $html .= sprintf(
                '<label><input type="checkbox" value="%s"> %s</label>',
                htmlspecialchars($category, ENT_QUOTES, 'UTF-8'),
                htmlspecialchars($label, ENT_QUOTES, 'UTF-8')
            );
        }

        return $html;
    }
}
