<?php

declare(strict_types=1);

namespace App\Service;

use Doctrine\DBAL\ArrayParameterType;
use Doctrine\DBAL\Connection;
use Doctrine\DBAL\ParameterType;
use Shopware\Core\Defaults;

/**
 * DBAL statt DAL für interne Prozesse.
 *
 * Hier nur lesend. Wer per DBAL schreibt, umgeht Events, Indexer
 * und Cache-Invalidierung - den getesteten Schreibweg samt
 * Invalidierung zeigt Kapitel 7 (ProductUpdateService).
 *
 * Getestet mit Shopware 6.6.10.6 (Dockware, Demo-Daten).
 * ArrayParameterType gibt es ab doctrine/dbal 3.6 (= Shopware 6.5),
 * Connection::PARAM_STR_ARRAY entfällt mit DBAL 4 (Shopware 6.7).
 *
 * @see Kapitel 17, "DBAL für interne Prozesse"
 * @see Kapitel 7, "Programmatische Invalidierung"
 * @see https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html
 */
class FastIdLookupService
{
    public function __construct(
        private readonly Connection $connection
    ) {}

    /**
     * DBAL statt DAL für einfache ID-Lookups
     *
     * @return list<string>
     */
    public function getActiveProductIds(int $limit = 1000): array
    {
        $sql = <<<SQL
            SELECT LOWER(HEX(id)) as id
            FROM product
            WHERE active = 1
              AND parent_id IS NULL
              AND version_id = :liveVersion
            LIMIT :limit
        SQL;

        // Ohne Typangabe bindet DBAL :limit als String,
        // MySQL sieht LIMIT '1000' und bricht mit 1064 ab.
        return $this->connection->fetchFirstColumn($sql, [
            'liveVersion' => hex2bin(Defaults::LIVE_VERSION),
            'limit' => $limit,
        ], [
            'limit' => ParameterType::INTEGER,
        ]);
    }

    /**
     * Varianten je Hauptprodukt in einer Abfrage
     *
     * @param list<string> $productIds
     *
     * @return array<string, int>
     */
    public function getVariantCounts(array $productIds): array
    {
        if ($productIds === []) {
            return [];
        }

        $rows = $this->connection->fetchAllKeyValue(
            'SELECT LOWER(HEX(parent_id)), COUNT(*)
             FROM product
             WHERE parent_id IN (:ids) AND version_id = :liveVersion
             GROUP BY parent_id',
            [
                'ids' => array_map('hex2bin', $productIds),
                'liveVersion' => hex2bin(Defaults::LIVE_VERSION),
            ],
            ['ids' => ArrayParameterType::STRING]
        );

        return array_map('intval', $rows);
    }
}
