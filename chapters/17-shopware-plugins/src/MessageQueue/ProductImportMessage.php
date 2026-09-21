<?php

declare(strict_types=1);

namespace App\MessageQueue;

use Shopware\Core\Framework\MessageQueue\LowPriorityMessageInterface;

/**
 * Message-Klasse für async Verarbeitung
 *
 * LowPriorityMessageInterface (ab Shopware 6.5.7.0) routet die
 * Nachricht ab Werk in den Transport low_priority - ohne Zeile in
 * framework.messenger.routing. Eine Klasse, die AsyncMessageInterface
 * implementiert UND dort nach low_priority geroutet wird, landet ab
 * Shopware 6.6.10.0 in beiden Transporten und wird zweimal verarbeitet
 * (gemessen in 6.6.10.6; bis 6.6.9 fing Shopware exakte Klassen-
 * einträge dort noch selbst ab).
 *
 * @see Kapitel 17, "Message Queue für asynchrone Verarbeitung"
 */
class ProductImportMessage implements LowPriorityMessageInterface
{
    /**
     * @param list<string> $productIds
     */
    public function __construct(
        private readonly array $productIds,
        private readonly string $importSource
    ) {}

    /**
     * @return list<string>
     */
    public function getProductIds(): array
    {
        return $this->productIds;
    }

    public function getImportSource(): string
    {
        return $this->importSource;
    }
}
