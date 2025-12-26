<?php

declare(strict_types=1);

namespace App\Subscriber;

use Psr\Log\LoggerInterface;
use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Defaults;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Write\Command\ChangeSetAware;
use Shopware\Core\Framework\DataAbstractionLayer\Write\Validation\PreWriteValidationEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Changeset-Aware Subscriber
 *
 * Demonstrates how to use changesets to detect WHAT changed,
 * not just THAT something changed.
 *
 * IMPORTANT: Changesets are NOT added automatically for performance reasons.
 * You must explicitly request them in PreWriteValidationEvent.
 *
 * Use cases:
 * - Track price changes for analytics
 * - Audit log of specific field changes
 * - Conditional logic based on old vs new values
 */
class ChangesetAwareSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly LoggerInterface $logger
    ) {}

    public static function getSubscribedEvents(): array
    {
        return [
            // MUST be registered to request changesets
            PreWriteValidationEvent::class => 'requestChangeset',

            // Then we can use the changeset in the written event
            ProductEvents::PRODUCT_WRITTEN_EVENT => 'onProductWritten',
        ];
    }

    /**
     * Request changeset BEFORE the write happens
     *
     * This is required because changesets are not generated
     * by default (for performance reasons).
     */
    public function requestChangeset(PreWriteValidationEvent $event): void
    {
        foreach ($event->getCommands() as $command) {
            // Only for changeset-aware commands
            if (!$command instanceof ChangeSetAware) {
                continue;
            }

            // Only for products (narrow the scope!)
            if ($command->getEntityName() !== 'product') {
                continue;
            }

            // Request the changeset
            $command->requestChangeSet();
        }
    }

    /**
     * React to product changes with changeset data
     */
    public function onProductWritten(EntityWrittenEvent $event): void
    {
        // Only live version
        if ($event->getContext()->getVersionId() !== Defaults::LIVE_VERSION) {
            return;
        }

        foreach ($event->getWriteResults() as $result) {
            $changeSet = $result->getChangeSet();

            // No changeset = nothing changed or not requested
            if ($changeSet === null) {
                continue;
            }

            $productId = $result->getPrimaryKey();

            // ============================================
            // Example: Track price changes
            // ============================================
            if ($changeSet->hasChanged('price')) {
                $this->handlePriceChange(
                    $productId,
                    $changeSet->getBefore('price'),
                    $changeSet->getAfter('price')
                );
            }

            // ============================================
            // Example: Track stock changes
            // ============================================
            if ($changeSet->hasChanged('stock')) {
                $this->handleStockChange(
                    $productId,
                    (int) $changeSet->getBefore('stock'),
                    (int) $changeSet->getAfter('stock')
                );
            }

            // ============================================
            // Example: Track active status changes
            // ============================================
            if ($changeSet->hasChanged('active')) {
                $this->handleActiveChange(
                    $productId,
                    (bool) $changeSet->getBefore('active'),
                    (bool) $changeSet->getAfter('active')
                );
            }
        }
    }

    private function handlePriceChange(string $productId, mixed $before, mixed $after): void
    {
        $this->logger->info('Product price changed', [
            'productId' => $productId,
            'before' => $before,
            'after' => $after,
        ]);

        // Here you could:
        // - Send notification to price monitoring
        // - Update price history table
        // - Trigger competitor price comparison
    }

    private function handleStockChange(string $productId, int $before, int $after): void
    {
        $this->logger->info('Product stock changed', [
            'productId' => $productId,
            'before' => $before,
            'after' => $after,
            'delta' => $after - $before,
        ]);

        // Alert on low stock
        if ($after <= 10 && $before > 10) {
            $this->logger->warning('Low stock alert for product {productId}', [
                'productId' => $productId,
                'stock' => $after,
            ]);
        }

        // Alert on out of stock
        if ($after === 0 && $before > 0) {
            $this->logger->warning('Product {productId} is now out of stock', [
                'productId' => $productId,
            ]);
        }
    }

    private function handleActiveChange(string $productId, bool $before, bool $after): void
    {
        if ($after && !$before) {
            $this->logger->info('Product {productId} activated', [
                'productId' => $productId,
            ]);
        } elseif (!$after && $before) {
            $this->logger->info('Product {productId} deactivated', [
                'productId' => $productId,
            ]);
        }
    }
}
