<?php

declare(strict_types=1);

namespace App\MessageQueue;

use Doctrine\DBAL\ArrayParameterType;
use Doctrine\DBAL\Connection;
use Psr\Log\LoggerInterface;
use Shopware\Core\Defaults;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

/**
 * Verarbeitet ProductImportMessage im Worker, nicht im Request.
 *
 * processBatch() ist der Platz für die eigentliche Import-Logik;
 * das Beispiel setzt nur updated_at. DBAL-Writes lösen weder Indexer
 * noch Cache-Invalidierung aus - den Weg dafür zeigt Kapitel 7
 * (ProductUpdateService). Den Speicher begrenzt der Worker selbst
 * (messenger:consume --memory-limit, Anhang C).
 *
 * @see Kapitel 17, "Async Message Handler"
 */
#[AsMessageHandler]
class AsyncProductHandler
{
    private const BATCH_SIZE = 100;

    public function __construct(
        private readonly Connection $connection,
        private readonly LoggerInterface $logger
    ) {}

    public function __invoke(ProductImportMessage $message): void
    {
        $productIds = $message->getProductIds();
        $this->logger->info('Processing {count} products', [
            'count' => \count($productIds),
            'source' => $message->getImportSource(),
        ]);

        // Batch-Verarbeitung: ein Statement je 100 Produkte
        foreach (array_chunk($productIds, self::BATCH_SIZE) as $batch) {
            $this->processBatch($batch);
        }
    }

    /**
     * @param list<string> $productIds
     */
    private function processBatch(array $productIds): void
    {
        // Direkte DBAL-Verarbeitung für Performance.
        // UTC_TIMESTAMP statt NOW(): Shopware speichert UTC, NOW()
        // liefert in 6.6 die Zeitzone der DB-Session (6.7: UTC).
        $this->connection->executeStatement(
            'UPDATE product SET updated_at = UTC_TIMESTAMP(3)
             WHERE id IN (:ids) AND version_id = :liveVersion',
            [
                'ids' => array_map('hex2bin', $productIds),
                'liveVersion' => hex2bin(Defaults::LIVE_VERSION),
            ],
            ['ids' => ArrayParameterType::STRING]
        );
    }
}
