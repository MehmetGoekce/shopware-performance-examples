<?php

declare(strict_types=1);

namespace App\EventSubscriber;

use App\Service\CloudflarePurgeService;
use Shopware\Core\Content\Media\Event\MediaUploadedEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Loescht Cloudflare-Cache-Eintraege automatisch, wenn Media/Category/Product
 * geaendert oder neu hochgeladen werden.
 *
 * Begleitcode zu Kap 11, Subsection "Cache-Invalidierung".
 *
 * Skeleton — Production-Hardening offen:
 *  - @TODO Async-Dispatch via Symfony Messenger (Purge nicht im Request-Pfad)
 *  - @TODO Tags pro Entity-Pfad differenzieren (z.B. category-{path} statt id)
 *  - @TODO Debouncing: viele writes in kurzer Zeit zu einem Purge bundeln
 *
 * Quelle: https://developer.shopware.com/docs/guides/hosting/infrastructure/reverse-http-cache.html
 */
final class MediaPurgeSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly CloudflarePurgeService $purgeService,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            MediaUploadedEvent::class           => 'onMediaUploaded',
            'media.written'                     => 'onMediaWritten',
            'product.written'                   => 'onProductWritten',
            'category.written'                  => 'onCategoryWritten',
        ];
    }

    public function onMediaUploaded(MediaUploadedEvent $event): void
    {
        $this->purgeService->purgeByTags(['media-' . $event->getMediaId()]);
    }

    public function onMediaWritten(EntityWrittenEvent $event): void
    {
        $tags = array_map(static fn (string $id): string => 'media-' . $id, $event->getIds());
        $this->purgeService->purgeByTags($tags);
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        $tags = array_map(static fn (string $id): string => 'product-' . $id, $event->getIds());
        $this->purgeService->purgeByTags($tags);
    }

    public function onCategoryWritten(EntityWrittenEvent $event): void
    {
        $tags = array_map(static fn (string $id): string => 'category-' . $id, $event->getIds());
        $this->purgeService->purgeByTags($tags);
    }
}
