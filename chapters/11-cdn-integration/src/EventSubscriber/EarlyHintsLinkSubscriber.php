<?php

declare(strict_types=1);

/**
 * Setzt einen Link-Header mit rel=preload fuer Theme-CSS und Theme-JS
 * Kapitel 11: CDN-Integration (Early Hints)
 *
 * Cloudflare sendet ein 103 Early Hints nur, wenn es vorher an einer Antwort
 * mit Status 200, 301 oder 302 einen Link-Header mit preload oder preconnect
 * gesehen hat, und nur fuer URIs ohne Dateiendung oder mit .html/.htm/.php.
 * Shopware setzt einen solchen Header nie, und
 * symfony/web-link (GenericLinkProvider, AddLinkHeaderListener) gehoert nicht
 * zu Shopware: in 6.6.10.6 nicht installiert, in 6.5 bis 6.7 keine
 * Abhaengigkeit von shopware/core. Dieser Subscriber liefert den Header
 * selbst - aus den Tags, die Shopware in den <head> gerendert hat, siehe
 * PreloadLinkBuilder.
 *
 * kernel.response laeuft im inneren Kernel, also bevor Shopwares HTTP-Cache
 * oder ein Reverse Proxy die Antwort speichert: Der Header wird mitgespeichert
 * und kommt auch bei einem Cache-Treffer mit. Gemessen an Shopware 6.6.10.6
 * (Dockware, prod, eingebauter HTTP-Cache).
 *
 * Kein Header bei: Status != 200, anderem Content-Type als text/html,
 * gestreamten Antworten, Sub-Requests aus PHP (forward/render). ESI-Fragmente
 * kommen als Main Request an, haben aber kein </head> und bleiben so ohne
 * Header. Den Content-Type setzt Shopwares Storefront-Controller selbst; eine
 * Antwort, die ihn erst durch Symfonys ResponseListener bekommt (eigener
 * Controller mit new Response($html)), bleibt ebenfalls ohne Header.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\EventSubscriber;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;
use YourPlugin\Service\PreloadLinkBuilder;

class EarlyHintsLinkSubscriber implements EventSubscriberInterface
{
    public function __construct(private readonly PreloadLinkBuilder $builder)
    {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::RESPONSE => 'onResponse',
        ];
    }

    public function onResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $response = $event->getResponse();

        if ($response->getStatusCode() !== 200
            || $response instanceof StreamedResponse
            || $response instanceof BinaryFileResponse
            || !str_starts_with((string) $response->headers->get('Content-Type', ''), 'text/html')
        ) {
            return;
        }

        $content = $response->getContent();

        if ($content === false || $content === '') {
            return;
        }

        $link = $this->builder->build($content);

        if ($link === null) {
            return;
        }

        // false = anhaengen: einen vorhandenen Link-Header nicht ueberschreiben.
        $response->headers->set('Link', $link, false);
    }
}
