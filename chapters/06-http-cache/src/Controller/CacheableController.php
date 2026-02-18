<?php
/**
 * Cacheable Controller Example
 * Kapitel 6: HTTP-Caching
 *
 * Demonstriert wie man Cache-Header in Shopware 6 Controllern setzt.
 *
 * Installation:
 *   1. Kopieren nach src/Controller/CacheableController.php
 *   2. Service registrieren in services.yaml
 *   3. Cache leeren: bin/console cache:clear
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

declare(strict_types=1);

namespace App\Controller;

use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Shopware\Storefront\Controller\StorefrontController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route(defaults: ['_routeScope' => ['storefront']])]
class CacheableController extends StorefrontController
{
    /**
     * Standard cacheable Seite
     *
     * Cache-Strategie: 2 Stunden fresh, 4 Stunden stale-while-revalidate
     */
    #[Route(
        path: '/custom-page',
        name: 'frontend.custom.page',
        methods: ['GET']
    )]
    public function customPage(Request $request, SalesChannelContext $context): Response
    {
        $response = $this->renderStorefront('@YourPlugin/storefront/page/custom.html.twig', [
            'title' => 'Custom Page',
            'data' => $this->getPageData(),
        ]);

        // ============================================================
        // Cache-Header setzen
        // ============================================================

        // Public = darf von CDN/Proxy gecacht werden
        // max-age = 2 Stunden (7200 Sekunden)
        $response->setSharedMaxAge(7200);

        // Stale-While-Revalidate: 4 Stunden
        // Erlaubt Auslieferung von "veraltetem" Content während Refresh
        $response->headers->addCacheControlDirective('stale-while-revalidate', '14400');

        // Stale-If-Error: 24 Stunden
        // Liefert veralteten Cache bei Backend-Fehlern
        $response->headers->addCacheControlDirective('stale-if-error', '86400');

        return $response;
    }

    /**
     * Seite mit kurzer TTL (für häufig aktualisierte Inhalte)
     *
     * Beispiel: Startseite mit Aktionen, Slider, etc.
     */
    #[Route(
        path: '/promotions',
        name: 'frontend.promotions.page',
        methods: ['GET']
    )]
    public function promotionsPage(Request $request, SalesChannelContext $context): Response
    {
        $response = $this->renderStorefront('@YourPlugin/storefront/page/promotions.html.twig', [
            'promotions' => $this->getPromotions(),
        ]);

        // Kurze TTL für häufig aktualisierte Inhalte
        $response->setSharedMaxAge(300); // 5 Minuten

        // Aber längere SWR für Performance
        $response->headers->addCacheControlDirective('stale-while-revalidate', '3600'); // 1 Stunde
        $response->headers->addCacheControlDirective('stale-if-error', '86400');

        return $response;
    }

    /**
     * Statische Seite mit langer TTL
     *
     * Beispiel: Impressum, AGB, Datenschutz
     */
    #[Route(
        path: '/legal/{page}',
        name: 'frontend.legal.page',
        methods: ['GET']
    )]
    public function legalPage(string $page, SalesChannelContext $context): Response
    {
        $response = $this->renderStorefront('@YourPlugin/storefront/page/legal.html.twig', [
            'page' => $page,
            'content' => $this->getLegalContent($page),
        ]);

        // Lange TTL für statischen Content
        $response->setSharedMaxAge(86400); // 24 Stunden

        $response->headers->addCacheControlDirective('stale-while-revalidate', '604800'); // 7 Tage
        $response->headers->addCacheControlDirective('stale-if-error', '604800');

        return $response;
    }

    /**
     * Private (nicht cacheable) Seite
     *
     * Beispiel: Benutzer-spezifische Inhalte
     */
    #[Route(
        path: '/my-wishlist',
        name: 'frontend.wishlist.page',
        methods: ['GET']
    )]
    public function wishlistPage(Request $request, SalesChannelContext $context): Response
    {
        $response = $this->renderStorefront('@YourPlugin/storefront/page/wishlist.html.twig', [
            'items' => $this->getWishlistItems($context),
        ]);

        // Private = nur Browser-Cache, kein CDN/Proxy
        // no-store = wirklich nicht cachen (auch nicht im Browser)
        $response->setPrivate();
        $response->headers->addCacheControlDirective('no-store');

        return $response;
    }

    /**
     * API-Endpunkt mit kurzer TTL
     *
     * Beispiel: Bestandsabfrage
     */
    #[Route(
        path: '/api/stock/{productId}',
        name: 'frontend.api.stock',
        methods: ['GET']
    )]
    public function stockApi(string $productId, SalesChannelContext $context): Response
    {
        $stock = $this->getProductStock($productId);

        $response = $this->json([
            'productId' => $productId,
            'stock' => $stock,
            'available' => $stock > 0,
        ]);

        // Kurze TTL für Bestandsdaten
        $response->setSharedMaxAge(60); // 1 Minute
        $response->headers->addCacheControlDirective('stale-while-revalidate', '300');

        return $response;
    }

    // ============================================================
    // Private Hilfsmethoden (Dummy-Implementierungen)
    // ============================================================

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    private function getPageData(): array
    {
        return ['example' => 'data'];
    }

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    private function getPromotions(): array
    {
        return [];
    }

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    private function getLegalContent(string $page): string
    {
        return '';
    }

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    private function getWishlistItems(SalesChannelContext $context): array
    {
        return [];
    }

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    private function getProductStock(string $productId): int
    {
        return 10;
    }
}
