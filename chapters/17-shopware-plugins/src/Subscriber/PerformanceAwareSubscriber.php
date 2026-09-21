<?php

declare(strict_types=1);

namespace App\Subscriber;

use Doctrine\DBAL\Connection;
use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Defaults;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Subscriber mit Guard-Clauses: bricht ab, bevor er Arbeit macht.
 *
 * Beispiel: Merkt sich den Zeitpunkt der letzten Namensänderung im
 * Zusatzfeld "name_changed_at" der Produktübersetzung.
 *
 * Zwei Fakten bestimmen die Form (gemessen in Shopware 6.6.10.6):
 * - "name" ist übersetzbar. Ein Update kommt als
 *   product_translation.written an, nicht als product.written -
 *   dessen Payload enthält kein "name".
 * - custom_fields liegt für Produkte in product_translation.
 *   Die Tabelle product hat keine solche Spalte.
 *
 * Der Schreibweg per DBAL löst kein Event aus. Darum braucht es
 * keinen Schleifenschutz - ein DAL-Update an dieser Stelle würde den
 * Subscriber rekursiv erneut aufrufen. Dafür invalidiert DBAL keinen
 * Cache: für ein Feld, das die Storefront nicht anzeigt, ist das hier
 * in Ordnung.
 *
 * @see Kapitel 17, "Event-Subscriber optimieren"
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/plugin-fundamentals/listening-to-events.html
 */
class PerformanceAwareSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly Connection $connection
    ) {}

    public static function getSubscribedEvents(): array
    {
        return [
            ProductEvents::PRODUCT_TRANSLATION_WRITTEN_EVENT => 'onTranslationWritten',
        ];
    }

    public function onTranslationWritten(EntityWrittenEvent $event): void
    {
        // 1. Nur Live-Version verarbeiten: Der Admin schreibt erst in
        //    eine Entwurfsversion und führt sie dann zusammen - dasselbe
        //    Produkt löst dabei mehrere Events aus.
        if ($event->getContext()->getVersionId() !== Defaults::LIVE_VERSION) {
            return;
        }

        // 2. Nur relevante Writes filtern
        $keys = [];
        foreach ($event->getWriteResults() as $result) {
            if (!\array_key_exists('name', $result->getPayload())) {
                continue;
            }

            /** @var array{productId: string, languageId: string} $pk */
            $pk = $result->getPrimaryKey();
            $keys[] = $pk;
        }

        if ($keys === []) {
            return;
        }

        // 3. Ein Statement für alle Treffer, DBAL statt DAL
        $this->markNameChanged($keys);
    }

    /**
     * @param list<array{productId: string, languageId: string}> $keys
     */
    private function markNameChanged(array $keys): void
    {
        $rows = implode(',', array_fill(0, \count($keys), '(?, ?)'));
        $params = [
            (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format(\DATE_ATOM),
            hex2bin(Defaults::LIVE_VERSION),
        ];
        foreach ($keys as $key) {
            $params[] = hex2bin($key['productId']);
            $params[] = hex2bin($key['languageId']);
        }

        $this->connection->executeStatement(
            "UPDATE product_translation
             SET custom_fields = JSON_SET(
                 COALESCE(custom_fields, '{}'),
                 '$.name_changed_at',
                 ?
             )
             WHERE product_version_id = ?
               AND (product_id, language_id) IN ($rows)",
            $params
        );
    }
}
