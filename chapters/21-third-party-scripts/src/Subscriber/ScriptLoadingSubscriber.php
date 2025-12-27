<?php

declare(strict_types=1);

namespace ShopwarePerformance\ThirdPartyScripts\Subscriber;

use ShopwarePerformance\ThirdPartyScripts\Service\ConsentPerformanceService;
use ShopwarePerformance\ThirdPartyScripts\Service\TagManagerService;
use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Psr\Log\LoggerInterface;

/**
 * ScriptLoadingSubscriber - Optimiertes Script-Loading im Storefront
 *
 * @description
 * Injiziert Third-Party Scripts performance-optimiert in Storefront-Templates.
 * Implementiert async/defer, consent-aware loading und lazy loading.
 *
 * @example
 * // Dieser Subscriber wird automatisch registriert
 * // Scripts werden basierend auf Context und Consent geladen
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ThirdPartyScripts
 */
class ScriptLoadingSubscriber implements EventSubscriberInterface
{
    /**
     * @var array<string, array<string, mixed>> Script-Konfiguration pro Route
     */
    private array $routeScripts = [
        'frontend.home.page' => [
            'gtm' => ['strategy' => 'lazy', 'delay' => 2000],
            'consent_banner' => true,
        ],
        'frontend.detail.page' => [
            'gtm' => ['strategy' => 'interaction'],
            'product_analytics' => true,
        ],
        'frontend.checkout.cart.page' => [
            'gtm' => ['strategy' => 'lazy', 'delay' => 1000],
            'checkout_analytics' => true,
        ],
        'frontend.checkout.confirm.page' => [
            'gtm' => ['strategy' => 'immediate'], // Conversion-Tracking kritisch
            'conversion_pixels' => true,
        ],
    ];

    /**
     * @param TagManagerService $tagManagerService GTM Service
     * @param ConsentPerformanceService $consentService Consent Service
     * @param LoggerInterface $logger Logger
     * @param string $gtmContainerId GTM Container-ID
     * @param bool $enableGtm GTM aktivieren
     * @param bool $enableConsent Consent-Banner aktivieren
     */
    public function __construct(
        private readonly TagManagerService $tagManagerService,
        private readonly ConsentPerformanceService $consentService,
        private readonly LoggerInterface $logger,
        private readonly string $gtmContainerId = '',
        private readonly bool $enableGtm = true,
        private readonly bool $enableConsent = true
    ) {
    }

    /**
     * {@inheritdoc}
     */
    public static function getSubscribedEvents(): array
    {
        return [
            StorefrontRenderEvent::class => [
                ['injectScripts', 100], // Früh, vor Template-Rendering
                ['injectDataLayer', 90],
            ],
        ];
    }

    /**
     * Injiziert Scripts basierend auf Route und Consent
     *
     * @param StorefrontRenderEvent $event Storefront Render Event
     * @return void
     */
    public function injectScripts(StorefrontRenderEvent $event): void
    {
        $request = $event->getRequest();
        $routeName = $request->attributes->get('_route');

        if (!$routeName) {
            return;
        }

        $parameters = $event->getParameters();

        // 1. Consent-Banner injizieren (nur wenn aktiviert)
        if ($this->enableConsent && $this->shouldShowConsentBanner($routeName)) {
            $consentBanner = $this->consentService->generateConsentBanner([
                'position' => 'bottom',
                'style' => 'minimal',
                'categories' => ['functional', 'analytics', 'marketing'],
            ]);

            $parameters['consentBanner'] = $consentBanner;
        }

        // 2. Consent-Loader injizieren
        if ($this->enableConsent) {
            $parameters['consentLoader'] = $this->consentService->generateConsentLoader();
        }

        // 3. Google Tag Manager injizieren (wenn aktiviert)
        if ($this->enableGtm && !empty($this->gtmContainerId)) {
            $gtmConfig = $this->getGtmConfigForRoute($routeName);

            $gtmSnippet = $this->tagManagerService->generateOptimizedSnippet(
                containerId: $this->gtmContainerId,
                strategy: $gtmConfig['strategy'] ?? 'lazy',
                delay: $gtmConfig['delay'] ?? null,
                triggers: $gtmConfig['triggers'] ?? ['scroll', 'mousemove', 'touchstart']
            );

            $parameters['gtmSnippet'] = $gtmSnippet;
        }

        // 4. Route-spezifische Scripts
        if (isset($this->routeScripts[$routeName])) {
            $routeConfig = $this->routeScripts[$routeName];

            foreach ($routeConfig as $scriptKey => $scriptConfig) {
                if ($scriptKey === 'gtm') {
                    continue; // Bereits behandelt
                }

                $this->injectRouteScript($scriptKey, $scriptConfig, $parameters);
            }
        }

        // 5. Performance Hints als HTML Comments
        if ($request->query->getBoolean('debug_scripts')) {
            $parameters['scriptDebugInfo'] = $this->generateDebugInfo($routeName);
        }

        $event->setParameters($parameters);

        $this->logger->debug('Scripts injected', [
            'route' => $routeName,
            'gtm_enabled' => $this->enableGtm,
            'consent_enabled' => $this->enableConsent,
        ]);
    }

    /**
     * Injiziert Data Layer Initialization
     *
     * @param StorefrontRenderEvent $event Storefront Render Event
     * @return void
     */
    public function injectDataLayer(StorefrontRenderEvent $event): void
    {
        if (!$this->enableGtm) {
            return;
        }

        $request = $event->getRequest();
        $salesChannelContext = $event->getSalesChannelContext();
        $parameters = $event->getParameters();

        // Data Layer Daten sammeln
        $dataLayerData = $this->collectDataLayerData($request, $salesChannelContext, $parameters);

        // Data Layer Init Code generieren
        $dataLayerInit = $this->tagManagerService->generateDataLayerInit($dataLayerData);

        $parameters['dataLayerInit'] = $dataLayerInit;

        $event->setParameters($parameters);
    }

    /**
     * Sammelt Data Layer Daten basierend auf Context
     *
     * @param \Symfony\Component\HttpFoundation\Request $request Request
     * @param \Shopware\Core\System\SalesChannel\SalesChannelContext $context Sales Channel Context
     * @param array<string, mixed> $parameters Template-Parameter
     * @return array<array<string, mixed>> Data Layer Events
     */
    private function collectDataLayerData($request, $context, array $parameters): array
    {
        $dataLayer = [];

        // 1. Page Info
        $routeName = $request->attributes->get('_route');
        $dataLayer[] = [
            'event' => 'page_view',
            'page_type' => $this->getPageType($routeName),
            'page_path' => $request->getPathInfo(),
        ];

        // 2. User Info (wenn eingeloggt)
        if ($customer = $context->getCustomer()) {
            $dataLayer[] = [
                'user_id' => $customer->getId(),
                'customer_group' => $customer->getGroupId(),
                'is_logged_in' => true,
            ];
        } else {
            $dataLayer[] = [
                'is_logged_in' => false,
            ];
        }

        // 3. Product View (Detailseite)
        if ($routeName === 'frontend.detail.page' && isset($parameters['product'])) {
            $product = $parameters['product'];

            $dataLayer[] = [
                'event' => 'view_item',
                'ecommerce' => [
                    'items' => [[
                        'item_id' => $product->getId(),
                        'item_name' => $product->getName(),
                        'price' => $product->getCalculatedPrice()->getUnitPrice(),
                        'currency' => $context->getCurrency()->getIsoCode(),
                    ]],
                ],
            ];
        }

        // 4. Cart Info (Checkout-Seiten)
        if (str_starts_with($routeName, 'frontend.checkout.')) {
            $cart = $context->getCart();

            if ($cart->getLineItems()->count() > 0) {
                $dataLayer[] = [
                    'event' => 'view_cart',
                    'ecommerce' => [
                        'value' => $cart->getPrice()->getTotalPrice(),
                        'currency' => $context->getCurrency()->getIsoCode(),
                        'items' => $cart->getLineItems()->count(),
                    ],
                ];
            }
        }

        return $dataLayer;
    }

    /**
     * Bestimmt Page Type aus Route-Name
     *
     * @param string|null $routeName Route-Name
     * @return string Page Type (z.B. 'home', 'product', 'cart')
     */
    private function getPageType(?string $routeName): string
    {
        if (!$routeName) {
            return 'unknown';
        }

        return match (true) {
            $routeName === 'frontend.home.page' => 'home',
            $routeName === 'frontend.detail.page' => 'product',
            $routeName === 'frontend.navigation.page' => 'category',
            $routeName === 'frontend.search.page' => 'search',
            str_starts_with($routeName, 'frontend.checkout.cart') => 'cart',
            str_starts_with($routeName, 'frontend.checkout.confirm') => 'checkout',
            str_starts_with($routeName, 'frontend.checkout.finish') => 'confirmation',
            default => 'other',
        };
    }

    /**
     * Gibt GTM-Config für Route zurück
     *
     * @param string $routeName Route-Name
     * @return array<string, mixed> GTM Config
     */
    private function getGtmConfigForRoute(string $routeName): array
    {
        if (!isset($this->routeScripts[$routeName]['gtm'])) {
            // Default: Lazy loading mit 3s delay
            return [
                'strategy' => 'lazy',
                'delay' => 3000,
            ];
        }

        return $this->routeScripts[$routeName]['gtm'];
    }

    /**
     * Prüft ob Consent-Banner angezeigt werden soll
     *
     * @param string $routeName Route-Name
     * @return bool True wenn Banner anzeigen
     */
    private function shouldShowConsentBanner(string $routeName): bool
    {
        // Banner nur auf wichtigen Seiten anzeigen
        $showOnRoutes = [
            'frontend.home.page',
            'frontend.detail.page',
            'frontend.navigation.page',
        ];

        return in_array($routeName, $showOnRoutes, true);
    }

    /**
     * Injiziert route-spezifisches Script
     *
     * @param string $scriptKey Script-Key
     * @param mixed $scriptConfig Script-Config
     * @param array<string, mixed> $parameters Template-Parameter (by reference)
     * @return void
     */
    private function injectRouteScript(string $scriptKey, $scriptConfig, array &$parameters): void
    {
        if (!$scriptConfig) {
            return;
        }

        // Beispiel: Product Analytics Script
        if ($scriptKey === 'product_analytics' && isset($parameters['product'])) {
            $product = $parameters['product'];

            $analyticsScript = <<<JS
            <script>
            // Product Analytics (Consent-aware)
            if (window.loadConsentedScript) {
                window.loadConsentedScript('product-analytics', {
                    product_id: '{$product->getId()}',
                    product_name: '{$product->getName()}',
                });
            }
            </script>
            JS;

            $parameters['productAnalytics'] = $analyticsScript;
        }

        // Beispiel: Conversion Pixels
        if ($scriptKey === 'conversion_pixels' && isset($parameters['order'])) {
            $order = $parameters['order'];

            // Nur laden wenn Consent für Marketing vorhanden
            $conversionPixels = $this->consentService->loadConsentedScript('facebook-pixel', [
                'value' => $order->getAmountTotal(),
                'currency' => $order->getCurrency()->getIsoCode(),
            ]);

            if ($conversionPixels) {
                $parameters['conversionPixels'] = $conversionPixels;
            }
        }
    }

    /**
     * Generiert Debug-Informationen
     *
     * @param string $routeName Route-Name
     * @return string HTML Comment mit Debug-Info
     */
    private function generateDebugInfo(string $routeName): string
    {
        $config = $this->routeScripts[$routeName] ?? [];

        $info = [
            'route' => $routeName,
            'gtm_enabled' => $this->enableGtm,
            'gtm_container' => $this->gtmContainerId,
            'consent_enabled' => $this->enableConsent,
            'route_scripts' => array_keys($config),
        ];

        $json = json_encode($info, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

        return <<<HTML
        <!--
        Third-Party Scripts Debug Info:
        {$json}
        -->
        HTML;
    }

    /**
     * Konfiguriert Route-spezifische Scripts
     *
     * @param string $route Route-Name
     * @param array<string, mixed> $scripts Script-Konfiguration
     * @return void
     */
    public function configureRouteScripts(string $route, array $scripts): void
    {
        $this->routeScripts[$route] = array_merge(
            $this->routeScripts[$route] ?? [],
            $scripts
        );
    }

    /**
     * Deaktiviert Script für Route
     *
     * @param string $route Route-Name
     * @param string $scriptKey Script-Key
     * @return void
     */
    public function disableScriptForRoute(string $route, string $scriptKey): void
    {
        if (isset($this->routeScripts[$route][$scriptKey])) {
            unset($this->routeScripts[$route][$scriptKey]);
        }
    }
}
