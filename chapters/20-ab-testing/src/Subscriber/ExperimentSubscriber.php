<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Subscriber;

use ShopwarePerformance\ABTesting\Service\ExperimentService;
use ShopwarePerformance\ABTesting\Service\FeatureFlagService;
use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\Cookie;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * ExperimentSubscriber - Integriert A/B Tests in Shopware Events
 *
 * @description
 * Weist Varianten zu, setzt Cookies und stellt Template-Variablen bereit.
 * Performance-optimiert: Lazy Loading, minimale DB-Queries.
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ABTesting
 */
class ExperimentSubscriber implements EventSubscriberInterface
{
    /**
     * Aktive Experimente (gecacht zur Performance-Optimierung)
     */
    private array $activeExperiments = [];

    /**
     * @param ExperimentService $experimentService Experiment-Service
     * @param FeatureFlagService $featureFlagService Feature Flag Service
     */
    public function __construct(
        private readonly ExperimentService $experimentService,
        private readonly FeatureFlagService $featureFlagService
    ) {
    }

    /**
     * Registriert Event-Listener
     *
     * @return array<string, string|array<int, string|int>> Event-Mappings
     */
    public static function getSubscribedEvents(): array
    {
        return [
            StorefrontRenderEvent::class => 'onStorefrontRender',
            KernelEvents::RESPONSE => 'onKernelResponse',
        ];
    }

    /**
     * Fügt Experiment-Varianten zu Template-Variablen hinzu
     *
     * @param StorefrontRenderEvent $event Storefront Render Event
     * @return void
     */
    public function onStorefrontRender(StorefrontRenderEvent $event): void
    {
        $context = $event->getSalesChannelContext();

        // Aktive Experimente laden (nur einmal pro Request)
        if (empty($this->activeExperiments)) {
            $this->activeExperiments = $this->loadActiveExperiments();
        }

        // Varianten zuweisen und zu Template-Variablen hinzufügen
        $experimentVariants = [];

        foreach ($this->activeExperiments as $experimentKey) {
            $variant = $this->experimentService->assignVariant($experimentKey, $context);
            $experimentVariants[$experimentKey] = $variant;
        }

        // Template-Variablen setzen
        $event->setParameter('experimentVariants', $experimentVariants);

        // Feature Flags hinzufügen
        $activeFlags = $this->featureFlagService->getActiveFlags($context);
        $event->setParameter('featureFlags', $activeFlags);

        // Für JavaScript-Zugriff: Data Attributes
        $event->setParameter('experimentDataAttributes', $this->buildDataAttributes($experimentVariants));
    }

    /**
     * Setzt Experiment-Cookies in Response
     *
     * @param ResponseEvent $event Kernel Response Event
     * @return void
     */
    public function onKernelResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        $response = $event->getResponse();

        // Cookie aus Request-Attribut holen (gesetzt in ExperimentService)
        $cookieData = $request->attributes->get('_experiment_cookie');

        if (!$cookieData) {
            return;
        }

        // Cookie setzen
        $cookie = Cookie::create($cookieData['name'])
            ->withValue($cookieData['value'])
            ->withExpires(time() + (30 * 24 * 60 * 60)) // 30 Tage
            ->withPath('/')
            ->withSecure($request->isSecure())
            ->withHttpOnly(false) // JavaScript braucht Zugriff für Tracking
            ->withSameSite(Cookie::SAMESITE_STRICT);

        $response->headers->setCookie($cookie);
    }

    /**
     * Lädt aktive Experimente (gecacht)
     *
     * @return array<string> Experiment-Schlüssel
     */
    private function loadActiveExperiments(): array
    {
        // Hier könnten wir die Experimente aus DB laden
        // Für Performance: Nur aktive Experimente cachen

        // Beispiel: Hardcoded (in Production aus DB + Cache)
        return [
            'checkout_optimization',
            'product_listing_lazy_loading',
            'image_optimization',
        ];
    }

    /**
     * Baut HTML Data Attributes für JavaScript
     *
     * @param array<string, string> $experimentVariants Experiment-Varianten
     * @return string HTML Data Attributes
     *
     * @example
     * data-experiment-checkout="variant_a" data-experiment-listing="control"
     */
    private function buildDataAttributes(array $experimentVariants): string
    {
        $attributes = [];

        foreach ($experimentVariants as $experiment => $variant) {
            $key = 'data-experiment-' . str_replace('_', '-', $experiment);
            $attributes[] = sprintf('%s="%s"', $key, htmlspecialchars($variant, ENT_QUOTES));
        }

        return implode(' ', $attributes);
    }
}
