<?php
/**
 * ESI Widget Controller
 * Kapitel 6: HTTP-Caching
 *
 * Demonstriert Edge Side Includes (ESI) für dynamische Teile in gecachten Seiten.
 *
 * Problem: Wie cache ich eine Seite, wenn ein Teil dynamisch ist?
 * Lösung: ESI - Die Hauptseite wird gecacht, dynamische Teile werden separat geladen.
 *
 * Installation:
 *   1. Kopieren nach src/Controller/EsiWidgetController.php
 *   2. Service registrieren in services.yaml
 *   3. In Twig: {{ render_esi(controller('App\\Controller\\EsiWidgetController::stockWidget', {...})) }}
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

declare(strict_types=1);

namespace App\Controller;

use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Shopware\Storefront\Controller\StorefrontController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route(defaults: ['_routeScope' => ['storefront']])]
class EsiWidgetController extends StorefrontController
{
    public function __construct(
        private readonly EntityRepository $productRepository
    ) {
    }

    /**
     * Bestandsanzeige Widget (ESI)
     *
     * Dieses Widget zeigt den aktuellen Bestand eines Produkts.
     * Es wird via ESI in die gecachte Produktseite eingebunden.
     *
     * Twig-Einbindung:
     * {{ render_esi(controller('App\\Controller\\EsiWidgetController::stockWidget', { productId: page.product.id })) }}
     */
    #[Route(
        path: '/widgets/stock/{productId}',
        name: 'frontend.widget.stock',
        methods: ['GET'],
        defaults: ['XmlHttpRequest' => true]
    )]
    public function stockWidget(string $productId, SalesChannelContext $context): Response
    {
        $stock = $this->getProductStock($productId, $context);

        $response = $this->renderStorefront('@YourPlugin/storefront/widget/stock.html.twig', [
            'productId' => $productId,
            'stock' => $stock,
            'available' => $stock > 0,
            'lowStock' => $stock > 0 && $stock <= 5,
        ]);

        // Kurze TTL für Bestandsdaten (5 Minuten)
        // Wichtig: Kürzer als die Hauptseite!
        $response->setSharedMaxAge(300);

        // SWR für Performance bei hohem Traffic
        $response->headers->addCacheControlDirective('stale-while-revalidate', '600');

        return $response;
    }

    /**
     * Preis-Widget (ESI)
     *
     * Zeigt den aktuellen Preis inkl. Kundengruppen-spezifischer Preise.
     *
     * Twig-Einbindung:
     * {{ render_esi(controller('App\\Controller\\EsiWidgetController::priceWidget', { productId: page.product.id })) }}
     */
    #[Route(
        path: '/widgets/price/{productId}',
        name: 'frontend.widget.price',
        methods: ['GET'],
        defaults: ['XmlHttpRequest' => true]
    )]
    public function priceWidget(string $productId, SalesChannelContext $context): Response
    {
        $price = $this->getProductPrice($productId, $context);

        $response = $this->renderStorefront('@YourPlugin/storefront/widget/price.html.twig', [
            'productId' => $productId,
            'price' => $price,
            'currency' => $context->getCurrency()->getSymbol(),
        ]);

        // Preise können sich durch Kundengruppen unterscheiden
        // -> Vary-Header für Cache-Differenzierung
        $response->setVary(['Cookie']);

        // Mittlere TTL für Preise (15 Minuten)
        $response->setSharedMaxAge(900);
        $response->headers->addCacheControlDirective('stale-while-revalidate', '1800');

        return $response;
    }

    /**
     * Header mit Warenkorb-Count (ESI)
     *
     * Zeigt die Anzahl der Artikel im Warenkorb.
     * Benutzer-spezifisch, daher sehr kurze TTL.
     *
     * Twig-Einbindung:
     * {{ render_esi(controller('App\\Controller\\EsiWidgetController::cartCountWidget')) }}
     */
    #[Route(
        path: '/widgets/cart-count',
        name: 'frontend.widget.cart-count',
        methods: ['GET'],
        defaults: ['XmlHttpRequest' => true]
    )]
    public function cartCountWidget(SalesChannelContext $context): Response
    {
        $cart = $this->container->get('Shopware\Core\Checkout\Cart\SalesChannel\CartService')
            ->getCart($context->getToken(), $context);

        $count = $cart->getLineItems()->count();

        $response = $this->renderStorefront('@YourPlugin/storefront/widget/cart-count.html.twig', [
            'count' => $count,
        ]);

        // Private Cache (nur Browser)
        // Sehr kurze TTL da benutzer-spezifisch
        $response->setPrivate();
        $response->setMaxAge(30);

        return $response;
    }

    /**
     * "Zuletzt angesehen" Widget (ESI)
     *
     * Zeigt kürzlich angesehene Produkte (Session-basiert).
     */
    #[Route(
        path: '/widgets/recently-viewed',
        name: 'frontend.widget.recently-viewed',
        methods: ['GET'],
        defaults: ['XmlHttpRequest' => true]
    )]
    public function recentlyViewedWidget(SalesChannelContext $context): Response
    {
        $products = $this->getRecentlyViewedProducts($context);

        $response = $this->renderStorefront('@YourPlugin/storefront/widget/recently-viewed.html.twig', [
            'products' => $products,
        ]);

        // Private da benutzer-spezifisch
        $response->setPrivate();
        $response->setMaxAge(300); // 5 Minuten Browser-Cache

        return $response;
    }

    /**
     * Countdown Widget (ESI)
     *
     * Zeigt einen Countdown für zeitlich begrenzte Aktionen.
     * Kann gecacht werden da die Zeit clientseitig berechnet wird.
     */
    #[Route(
        path: '/widgets/countdown/{promotionId}',
        name: 'frontend.widget.countdown',
        methods: ['GET'],
        defaults: ['XmlHttpRequest' => true]
    )]
    public function countdownWidget(string $promotionId, SalesChannelContext $context): Response
    {
        $promotion = $this->getPromotion($promotionId);

        $response = $this->renderStorefront('@YourPlugin/storefront/widget/countdown.html.twig', [
            'promotionId' => $promotionId,
            'endDate' => $promotion['endDate'] ?? null,
            'title' => $promotion['title'] ?? '',
        ]);

        // Kann gecacht werden - JavaScript berechnet den Countdown
        $response->setSharedMaxAge(3600); // 1 Stunde
        $response->headers->addCacheControlDirective('stale-while-revalidate', '7200');

        return $response;
    }

    // ============================================================
    // Private Hilfsmethoden
    // ============================================================

    private function getProductStock(string $productId, SalesChannelContext $context): int
    {
        $criteria = new Criteria([$productId]);
        $product = $this->productRepository->search($criteria, $context->getContext())->first();

        return $product?->getStock() ?? 0;
    }

    private function getProductPrice(string $productId, SalesChannelContext $context): float
    {
        $criteria = new Criteria([$productId]);
        $criteria->addAssociation('prices');
        $product = $this->productRepository->search($criteria, $context->getContext())->first();

        // Vereinfachte Preislogik - in Produktion Shopware PriceCalculator nutzen
        return $product?->getCurrencyPrice($context->getCurrency()->getId())?->getGross() ?? 0.0;
    }

    private function getRecentlyViewedProducts(SalesChannelContext $context): array
    {
        // Implementierung: Aus Session oder Cookie laden
        return [];
    }

    private function getPromotion(string $promotionId): array
    {
        // Implementierung: Promotion aus Datenbank laden
        return [
            'endDate' => (new \DateTime('+7 days'))->format('c'),
            'title' => 'Summer Sale',
        ];
    }
}
