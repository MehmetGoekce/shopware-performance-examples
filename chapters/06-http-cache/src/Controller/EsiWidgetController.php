<?php
/**
 * ESI Widget Controller
 * Kapitel 6: HTTP-Caching
 *
 * Edge Side Includes (ESI): Die Seite wird gecacht, ein Fragment darin hat
 * eine eigene, kürzere TTL. Shopware 6.6 bindet Header und Footer nur mit dem
 * Feature-Flag CACHE_REWORK per render_esi ein, ab Werk rendert es sie direkt.
 *
 * Ablauf:
 *   1. Varnish schickt "Surrogate-Capability: shopware=ESI/1.0" (config/varnish.vcl)
 *   2. Shopware rendert render_esi() als <esi:include src="..."> und setzt
 *      "Surrogate-Control: content=\"ESI/1.0\""
 *   3. Varnish holt das Fragment separat (eigener Cache-Eintrag) und setzt die Seite zusammen
 *   Ohne ESI-fähigen Proxy rendert Shopware das Fragment direkt in die Seite.
 *
 * Twig-Einbindung (z. B. in der Produktseite):
 *   {{ render_esi(url('frontend.widget.stock', { productId: page.product.id })) }}
 *
 * Nicht für ESI geeignet: benutzerspezifische Teile wie Warenkorb-Zähler oder
 * "Zuletzt angesehen". Die lädt man per JavaScript nach (so macht es auch die
 * Shopware-Storefront mit dem Offcanvas-Warenkorb). Preise brauchen kein eigenes
 * Fragment: Kundengruppe und Währung stecken im Cache-Key (Cookies sw-cache-hash
 * bzw. sw-currency), Preisänderungen invalidiert Shopware über die Cache-Tags.
 *
 * Cache-Tags: Eigene DAL-Abfragen im Controller taggen die Antwort in 6.6 NICHT
 * automatisch mit "product-<id>". Ohne eigenes Tag würde eine Bestandsänderung
 * das Fragment erst nach Ablauf der TTL erneuern. Deshalb hängt stockWidget()
 * das Tag per AddCacheTagEvent an (verfügbar ab Shopware 6.6.6.0).
 *
 * Installation (in einem eigenen Plugin):
 *   1. Kopieren nach src/Controller/EsiWidgetController.php
 *   2. Als Service registrieren, Argumente: sales_channel.product.repository, event_dispatcher
 *   3. Cache leeren: bin/console cache:clear
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

declare(strict_types=1);

namespace App\Controller;

use Shopware\Core\Framework\Adapter\Cache\Event\AddCacheTagEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\System\SalesChannel\Entity\SalesChannelRepository;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Shopware\Storefront\Controller\StorefrontController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Contracts\EventDispatcher\EventDispatcherInterface;

#[Route(defaults: ['_routeScope' => ['storefront']])]
class EsiWidgetController extends StorefrontController
{
    public function __construct(
        private readonly SalesChannelRepository $productRepository,
        private readonly EventDispatcherInterface $eventDispatcher
    ) {
    }

    /**
     * Bestandsanzeige (ESI-Fragment)
     *
     * TTL 5 Minuten, kürzer als die Produktseite. Varnish liefert das Fragment
     * nach Ablauf noch bis zur Grace-Zeit aus und lädt es im Hintergrund neu.
     * Ändert sich das Produkt (z. B. der Bestand), invalidiert Shopware das
     * Fragment sofort über das Tag "product-<id>".
     */
    #[Route(
        path: '/widgets/stock/{productId}',
        name: 'frontend.widget.stock',
        defaults: ['_httpCache' => ['maxAge' => 300]],
        methods: ['GET']
    )]
    public function stockWidget(string $productId, SalesChannelContext $context): Response
    {
        $stock = $this->getProductStock($productId, $context);

        // Tag für die Invalidierung: Shopware purged "product-<id>", sobald das Produkt geschrieben wird
        $this->eventDispatcher->dispatch(new AddCacheTagEvent('product-' . $productId));

        return $this->renderStorefront('@YourPlugin/storefront/widget/stock.html.twig', [
            'productId' => $productId,
            'stock' => $stock,
            'available' => $stock > 0,
            'lowStock' => $stock > 0 && $stock <= 5,
        ]);
    }

    /**
     * Countdown für eine Aktion (ESI-Fragment)
     *
     * Kann lange gecacht werden: Das Enddatum ändert sich selten, die
     * verbleibende Zeit rechnet JavaScript im Browser aus.
     */
    #[Route(
        path: '/widgets/countdown/{promotionId}',
        name: 'frontend.widget.countdown',
        defaults: ['_httpCache' => ['maxAge' => 3600]],
        methods: ['GET']
    )]
    public function countdownWidget(string $promotionId, SalesChannelContext $context): Response
    {
        $promotion = $this->getPromotion($promotionId);

        return $this->renderStorefront('@YourPlugin/storefront/widget/countdown.html.twig', [
            'promotionId' => $promotionId,
            'endDate' => $promotion['endDate'],
            'title' => $promotion['title'],
        ]);
    }

    // ============================================================
    // Private Hilfsmethoden
    // ============================================================

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde fehlende Produkte behandeln.
    private function getProductStock(string $productId, SalesChannelContext $context): int
    {
        $criteria = new Criteria([$productId]);
        $product = $this->productRepository->search($criteria, $context)->first();

        return $product?->getStock() ?? 0;
    }

    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde die Promotion aus der Datenbank laden.
    /**
     * @return array{endDate: string, title: string}
     */
    private function getPromotion(string $promotionId): array
    {
        return [
            'endDate' => (new \DateTime('+7 days'))->format('c'),
            'title' => 'Summer Sale',
        ];
    }
}
