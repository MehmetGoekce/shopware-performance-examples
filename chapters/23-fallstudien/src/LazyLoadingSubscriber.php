<?php

declare(strict_types=1);

namespace App\Subscriber;

use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Fallstudie 2: Schweizer Fashion-Shop - Lazy Loading
 * Kapitel 23: Reale Fallstudien aus 26 Jahren
 *
 * Fügt native Lazy-Loading-Attribute zu Bildern hinzu.
 * Reduziert initiale Ladezeit durch verzögertes Laden
 * von Bildern außerhalb des Viewports.
 *
 * Ergebnis: LCP von 8.2s auf 1.8s reduziert
 */
class LazyLoadingSubscriber implements EventSubscriberInterface
{
    private const EAGER_LOAD_COUNT = 3;

    public static function getSubscribedEvents(): array
    {
        return [
            StorefrontRenderEvent::class => 'onStorefrontRender',
        ];
    }

    public function onStorefrontRender(StorefrontRenderEvent $event): void
    {
        $parameters = $event->getParameters();

        // Product-Listing optimieren
        if (isset($parameters['listing'])) {
            $this->optimizeProductListing($parameters['listing']);
        }

        // Einzelne Produktseite optimieren
        if (isset($parameters['product'])) {
            $this->optimizeProductPage($parameters['product']);
        }
    }

    /**
     * Erste N Produkte eager laden, Rest lazy
     */
    private function optimizeProductListing($listing): void
    {
        $products = $listing->getEntities();
        $index = 0;

        foreach ($products as $product) {
            $cover = $product->getCover();
            if ($cover === null) {
                continue;
            }

            $media = $cover->getMedia();
            if ($media === null) {
                continue;
            }

            // Erste Bilder im Viewport eager laden
            if ($index < self::EAGER_LOAD_COUNT) {
                $media->addExtension('lazyLoading', new LazyLoadingExtension(
                    loading: 'eager',
                    fetchpriority: $index === 0 ? 'high' : 'auto',
                    decoding: 'sync'
                ));
            } else {
                // Rest lazy laden
                $media->addExtension('lazyLoading', new LazyLoadingExtension(
                    loading: 'lazy',
                    fetchpriority: 'low',
                    decoding: 'async'
                ));
            }

            $index++;
        }
    }

    /**
     * Hauptbild eager, Galerie lazy
     */
    private function optimizeProductPage($product): void
    {
        $media = $product->getMedia();
        if ($media === null) {
            return;
        }

        $isFirst = true;
        foreach ($media as $mediaEntity) {
            if ($isFirst) {
                // Hauptbild mit höchster Priorität
                $mediaEntity->addExtension('lazyLoading', new LazyLoadingExtension(
                    loading: 'eager',
                    fetchpriority: 'high',
                    decoding: 'sync'
                ));
                $isFirst = false;
            } else {
                // Galerie-Bilder lazy
                $mediaEntity->addExtension('lazyLoading', new LazyLoadingExtension(
                    loading: 'lazy',
                    fetchpriority: 'low',
                    decoding: 'async'
                ));
            }
        }
    }
}

/**
 * Extension für Lazy-Loading-Attribute
 */
class LazyLoadingExtension extends \Shopware\Core\Framework\Struct\Struct
{
    public function __construct(
        public readonly string $loading = 'lazy',
        public readonly string $fetchpriority = 'auto',
        public readonly string $decoding = 'async'
    ) {
    }

    /**
     * Generiert HTML-Attribute für <img> Tag
     */
    public function getAttributes(): string
    {
        return sprintf(
            'loading="%s" fetchpriority="%s" decoding="%s"',
            $this->loading,
            $this->fetchpriority,
            $this->decoding
        );
    }
}
