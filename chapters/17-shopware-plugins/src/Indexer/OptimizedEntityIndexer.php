<?php

declare(strict_types=1);

namespace App\Indexer;

use Doctrine\DBAL\ArrayParameterType;
use Doctrine\DBAL\Connection;
use Doctrine\DBAL\ParameterType;
use Shopware\Core\Defaults;
use Shopware\Core\Framework\DataAbstractionLayer\EntityWriteResult;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenContainerEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Indexing\EntityIndexer;
use Shopware\Core\Framework\DataAbstractionLayer\Indexing\EntityIndexingMessage;
use Shopware\Core\Framework\Plugin\Exception\DecorationPatternException;

/**
 * Eigener Indexer: rechnet beim Schreiben vor, was beim Lesen teuer wäre.
 *
 * Beispiel: Anzahl der Varianten je Hauptprodukt im Zusatzfeld
 * "variant_count" der Produktübersetzungen (Live-Version). Die Spalte
 * custom_fields liegt für Produkte in product_translation, nicht in
 * product.
 *
 * Getestet mit Shopware 6.6.10.6 (Dockware, Demo-Daten):
 * - dal:refresh:index --only=custom.optimized.indexer (iterate/handle)
 * - neue Variante -> Hauptprodukt wird neu berechnet (update);
 *   ein reines Bestands-Update löst nichts aus
 *
 * @see Kapitel 17, "Entity-Indexer optimieren"
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/framework/data-handling/add-data-indexer.html
 */
class OptimizedEntityIndexer extends EntityIndexer
{
    private const BATCH_SIZE = 50;

    public function __construct(
        private readonly Connection $connection
    ) {}

    public function getName(): string
    {
        return 'custom.optimized.indexer';
    }

    public function iterate(?array $offset): ?EntityIndexingMessage
    {
        // Batch-basiertes Iterieren, Keyset statt OFFSET
        $sql = <<<SQL
            SELECT LOWER(HEX(id)) as id
            FROM product
            WHERE parent_id IS NULL
              AND version_id = :liveVersion
              AND (:lastId IS NULL OR id > :lastId)
            ORDER BY id
            LIMIT :limit
        SQL;

        $ids = $this->connection->fetchFirstColumn($sql, [
            'liveVersion' => hex2bin(Defaults::LIVE_VERSION),
            'lastId' => isset($offset['lastId']) ? hex2bin($offset['lastId']) : null,
            'limit' => self::BATCH_SIZE,
        ], [
            // Ohne INTEGER: LIMIT '50' -> MySQL-Fehler 1064
            'limit' => ParameterType::INTEGER,
        ]);

        if ($ids === []) {
            return null;
        }

        return new EntityIndexingMessage(
            $ids,
            ['lastId' => end($ids)]
        );
    }

    public function update(EntityWrittenContainerEvent $event): ?EntityIndexingMessage
    {
        // Entwürfe des Admins zählen nicht; die Registry prüft die
        // Version selbst nicht.
        if ($event->getContext()->getVersionId() !== Defaults::LIVE_VERSION) {
            return null;
        }

        // Filtern, bevor gerechnet wird: variant_count ändert sich nur,
        // wenn ein Produkt angelegt wird oder sein parentId wechselt -
        // nicht bei Preis, Bestand oder Name.
        $productIds = [];
        foreach ($event->getEventByEntityName('product')?->getWriteResults() ?? [] as $result) {
            if ($result->getOperation() === EntityWriteResult::OPERATION_INSERT
                || \array_key_exists('parentId', $result->getPayload())) {
                $productIds[] = $result->getPrimaryKey();
            }
        }

        if ($productIds === []) {
            return null;
        }

        // Varianten auf ihr Hauptprodukt abbilden - die Datenbank
        // weiss es auch dann, wenn der Payload parentId nicht trägt.
        // Grenze: Eine gelöschte Variante steht nicht mehr in der
        // Tabelle; ihr Hauptprodukt holt erst der nächste Voll-Lauf nach.
        $ids = $this->connection->fetchFirstColumn(
            'SELECT DISTINCT LOWER(HEX(COALESCE(parent_id, id)))
             FROM product
             WHERE id IN (:ids) AND version_id = :liveVersion',
            [
                'ids' => array_map('hex2bin', $productIds),
                'liveVersion' => hex2bin(Defaults::LIVE_VERSION),
            ],
            ['ids' => ArrayParameterType::STRING]
        );

        if ($ids === []) {
            return null;
        }

        // Async verarbeiten: der Request wartet nicht auf den Indexer
        return new EntityIndexingMessage($ids, null, forceQueue: true);
    }

    public function handle(EntityIndexingMessage $message): void
    {
        /** @var list<string> $ids */
        $ids = $message->getData();

        if ($ids === []) {
            return;
        }

        // Connection statt DAL: Ein DAL-Write würde erneut
        // update() auslösen - eine Endlosschleife.
        $this->connection->executeStatement(
            "UPDATE product_translation pt
             SET pt.custom_fields = JSON_SET(
                 COALESCE(pt.custom_fields, '{}'),
                 '$.variant_count',
                 (SELECT COUNT(*) FROM product v
                  WHERE v.parent_id = pt.product_id
                    AND v.version_id = pt.product_version_id)
             )
             WHERE pt.product_id IN (:ids)
               AND pt.product_version_id = :liveVersion",
            [
                'ids' => array_map('hex2bin', $ids),
                'liveVersion' => hex2bin(Defaults::LIVE_VERSION),
            ],
            ['ids' => ArrayParameterType::STRING]
        );
    }

    public function getTotal(): int
    {
        return (int) $this->connection->fetchOne(
            'SELECT COUNT(*) FROM product WHERE parent_id IS NULL AND version_id = :liveVersion',
            ['liveVersion' => hex2bin(Defaults::LIVE_VERSION)]
        );
    }

    public function getDecorated(): EntityIndexer
    {
        throw new DecorationPatternException(self::class);
    }
}
