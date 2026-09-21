<?php

declare(strict_types=1);

namespace App\Subscriber;

use Psr\Log\LoggerInterface;
use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Write\Command\ChangeSet;
use Shopware\Core\Framework\DataAbstractionLayer\Write\Command\ChangeSetAware;
use Shopware\Core\Framework\DataAbstractionLayer\Write\Validation\PreWriteValidationEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Changesets nur anfordern, wo sie gebraucht werden.
 *
 * Shopware erzeugt Changesets aus Performance-Gründen nicht von
 * selbst: Sobald einer angefordert ist, liest der Write-Gateway den
 * alten Zustand per zusätzlichem SELECT * je Entity-Typ und
 * Schreibaufruf, alle Datensätze in einer Abfrage
 * (EntityWriteGateway::generateChangeSets()). Deshalb nur anfordern,
 * wenn das Feld im Schreibauftrag steht.
 *
 * Falle (gemessen in Shopware 6.6.10.6): ChangeSet vergleicht die
 * String-Darstellung von altem und neuem Wert. Bei JSON-Spalten wie
 * "price" meldet hasChanged() deshalb auch dann true, wenn derselbe
 * Preis erneut gespeichert wird - MySQL gibt das JSON anders
 * formatiert zurück. priceChanged() vergleicht darum die Inhalte.
 *
 * @see Kapitel 17, "Changesets nur bei Bedarf"
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/checkout/order/listen-to-order-changes.html
 */
class ChangesetAwareSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly LoggerInterface $logger
    ) {}

    public static function getSubscribedEvents(): array
    {
        return [
            // Changeset VORHER anfordern
            PreWriteValidationEvent::class => 'requestChangeset',
            ProductEvents::PRODUCT_WRITTEN_EVENT => 'onProductWritten',
        ];
    }

    public function requestChangeset(PreWriteValidationEvent $event): void
    {
        foreach ($event->getCommands() as $command) {
            if (!$command instanceof ChangeSetAware) {
                continue;
            }

            // Nur für Produktänderungen, die den Preis schreiben
            // (der Payload trägt Spaltennamen)
            if ($command->getDefinition()->getEntityName() === 'product'
                && \array_key_exists('price', $command->getPayload())) {
                $command->requestChangeSet();
            }
        }
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        foreach ($event->getWriteResults() as $result) {
            $changeSet = $result->getChangeSet();

            if ($changeSet === null) {
                continue;
            }

            // Nur wenn sich der Preis geändert hat. info() puffert in
            // prod (fingers_crossed) und landet nur im Log, wenn derselbe
            // Request einen Fehler loggt; auf der Konsole mit -vv.
            if ($this->priceChanged($changeSet)) {
                $this->logger->info('Preis geändert: {id}', [
                    'id' => $result->getPrimaryKey(),
                    'before' => $changeSet->getBefore('price'),
                    'after' => $changeSet->getAfter('price'),
                ]);
            }
        }
    }

    private function priceChanged(ChangeSet $changeSet): bool
    {
        if (!$changeSet->hasChanged('price')) {
            return false;
        }

        $before = $changeSet->getBefore('price');
        $after = $changeSet->getAfter('price');

        // JSON-Spalte: Inhalte vergleichen, nicht Strings
        return json_decode((string) $before, true) != json_decode((string) $after, true);
    }
}
