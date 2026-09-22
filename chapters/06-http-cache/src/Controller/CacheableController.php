<?php
/**
 * Cacheable Controller Example
 * Kapitel 6: HTTP-Caching
 *
 * Zeigt, wie eine Storefront-Route in Shopware 6.6/6.7 in den HTTP-Cache kommt:
 * über den Routen-Default "_httpCache". Shopware setzt daraufhin selbst
 * "Cache-Control: public, s-maxage=<maxAge>", die Cache-Tags und den Header
 * "sw-invalidation-states".
 *
 * Wichtig: $response->setSharedMaxAge() allein reicht NICHT. Ohne "_httpCache"
 * kommt die Antwort als "private" beim Reverse Proxy an und wird weder vom
 * eingebauten Cache noch von Varnish gespeichert.
 *
 * Eingeloggte Kunden und Besucher mit Warenkorb gehen automatisch am Cache
 * vorbei (shopware.cache.invalidation.http_cache, Cookie "sw-states").
 * Ein eigenes "states" in _httpCache ergänzt diese Liste nur; ausnehmen lässt
 * sich eine Route davon nicht.
 *
 * Installation (in einem eigenen Plugin, Namespace "YourPlugin" anpassen):
 *   1. Kopieren nach src/Controller/CacheableController.php
 *   2. Service und Routen: src/Resources/config/services.xml und routes.xml
 *      aus diesem Ordner (setContainer/setTwig, sonst funktioniert
 *      renderStorefront() nicht)
 *   3. Templates unter src/Resources/views/storefront/page/ anlegen
 *   4. Cache leeren: bin/console cache:clear
 *
 * Prüfen (im Ordner chapters/06-http-cache):
 *   ./scripts/cache-debug.sh https://ihr-shop.ch /custom-page
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

declare(strict_types=1);

namespace YourPlugin\Controller;

use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Shopware\Storefront\Controller\StorefrontController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route(defaults: ['_routeScope' => ['storefront']])]
class CacheableController extends StorefrontController
{
    /**
     * Standard: cachebar mit der globalen TTL
     *
     * "_httpCache" => true nutzt SHOPWARE_HTTP_DEFAULT_TTL (Default 7200 s).
     * stale-while-revalidate / stale-if-error kommen aus config/shopware.yaml.
     */
    #[Route(
        path: '/custom-page',
        name: 'frontend.custom.page',
        defaults: ['_httpCache' => true],
        methods: ['GET']
    )]
    public function customPage(Request $request, SalesChannelContext $context): Response
    {
        return $this->renderStorefront('@YourPlugin/storefront/page/custom.html.twig', [
            'title' => 'Custom Page',
            'data' => $this->getPageData(),
        ]);
    }

    /**
     * Kurze TTL für häufig geänderte Inhalte
     *
     * Beispiel: Aktionsseite. Änderungen an Produkten, Kategorien oder
     * Erlebniswelten invalidiert Shopware ohnehin über Cache-Tags; die TTL ist
     * die Obergrenze für alles, was nicht getaggt ist.
     */
    #[Route(
        path: '/promotions',
        name: 'frontend.promotions.page',
        defaults: ['_httpCache' => ['maxAge' => 300]],
        methods: ['GET']
    )]
    public function promotionsPage(Request $request, SalesChannelContext $context): Response
    {
        return $this->renderStorefront('@YourPlugin/storefront/page/promotions.html.twig', [
            'promotions' => $this->getPromotions(),
        ]);
    }

    /**
     * Lange TTL für statische Inhalte
     *
     * Beispiel: Impressum, AGB, Datenschutz.
     */
    #[Route(
        path: '/legal/{page}',
        name: 'frontend.legal.page',
        defaults: ['_httpCache' => ['maxAge' => 86400]],
        methods: ['GET']
    )]
    public function legalPage(string $page, SalesChannelContext $context): Response
    {
        return $this->renderStorefront('@YourPlugin/storefront/page/legal.html.twig', [
            'page' => $page,
            'content' => $this->getLegalContent($page),
        ]);
    }

    /**
     * Nicht cachebar: benutzerspezifische Seite
     *
     * Ohne "_httpCache" schickt Shopware "Cache-Control" mit "private"
     * (ohne Reverse Proxy "no-cache, private"). Es ist nichts weiter zu tun.
     */
    #[Route(
        path: '/my-wishlist',
        name: 'frontend.custom-wishlist.page',
        methods: ['GET']
    )]
    public function wishlistPage(Request $request, SalesChannelContext $context): Response
    {
        return $this->renderStorefront('@YourPlugin/storefront/page/wishlist.html.twig', [
            'items' => $this->getWishlistItems($context),
        ]);
    }

    // ============================================================
    // Private Hilfsmethoden (Dummy-Implementierungen)
    // ============================================================

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    /**
     * @return array<string, string>
     */
    private function getPageData(): array
    {
        return ['example' => 'data'];
    }

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier die Shopware DAL nutzen.
    /**
     * @return list<array<string, mixed>>
     */
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
    /**
     * @return list<array<string, mixed>>
     */
    private function getWishlistItems(SalesChannelContext $context): array
    {
        return [];
    }
}
