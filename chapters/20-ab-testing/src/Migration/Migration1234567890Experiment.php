<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Migration;

use Doctrine\DBAL\Connection;
use Shopware\Core\Framework\Migration\MigrationStep;

/**
 * Migration für A/B Testing Datenbank-Schema
 *
 * @description
 * Erstellt Tabellen für Experimente, Metriken und Zuweisungen.
 * Optimiert für hohe Schreiblast mit Indizes.
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */
class Migration1234567890Experiment extends MigrationStep
{
    /**
     * Gibt Zeitstempel der Migration zurück
     *
     * @return int Zeitstempel
     */
    public function getCreationTimestamp(): int
    {
        return 1234567890;
    }

    /**
     * Führt Migration aus (UP)
     *
     * @param Connection $connection Doctrine Connection
     * @return void
     */
    public function update(Connection $connection): void
    {
        // Tabelle: experiments
        $connection->executeStatement("
            CREATE TABLE IF NOT EXISTS `experiment` (
                `id` BINARY(16) NOT NULL,
                `key` VARCHAR(255) NOT NULL,
                `name` VARCHAR(255) NOT NULL,
                `description` TEXT NULL,
                `status` VARCHAR(50) NOT NULL DEFAULT 'draft',
                `variants` JSON NOT NULL,
                `performance_budget` JSON NULL,
                `target_sample_size` INT NOT NULL DEFAULT 1000,
                `start_date` DATETIME NULL,
                `end_date` DATETIME NULL,
                `paused_at` DATETIME NULL,
                `pause_reason` VARCHAR(255) NULL,
                `created_at` DATETIME(3) NOT NULL,
                `updated_at` DATETIME(3) NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq.experiment.key` (`key`),
                KEY `idx.experiment.status` (`status`),
                KEY `idx.experiment.start_date` (`start_date`),
                KEY `idx.experiment.end_date` (`end_date`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");

        // Tabelle: experiment_metrics
        $connection->executeStatement("
            CREATE TABLE IF NOT EXISTS `experiment_metrics` (
                `id` BINARY(16) NOT NULL,
                `experiment_id` VARCHAR(255) NOT NULL,
                `variant` VARCHAR(100) NOT NULL,
                `metric` VARCHAR(100) NOT NULL,
                `value` DECIMAL(10, 2) NOT NULL,
                `customer_id` BINARY(16) NULL,
                `device_type` VARCHAR(20) NULL,
                `sales_channel_id` BINARY(16) NULL,
                `created_at` DATETIME(3) NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx.experiment_metrics.experiment_variant` (`experiment_id`, `variant`),
                KEY `idx.experiment_metrics.metric` (`metric`),
                KEY `idx.experiment_metrics.created_at` (`created_at`),
                KEY `idx.experiment_metrics.customer` (`customer_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");

        // Tabelle: experiment_assignments
        $connection->executeStatement("
            CREATE TABLE IF NOT EXISTS `experiment_assignments` (
                `id` BINARY(16) NOT NULL,
                `experiment_key` VARCHAR(255) NOT NULL,
                `variant` VARCHAR(100) NOT NULL,
                `customer_id` BINARY(16) NULL,
                `session_id` VARCHAR(255) NULL,
                `device_type` VARCHAR(20) NULL,
                `sales_channel_id` BINARY(16) NULL,
                `created_at` DATETIME(3) NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx.experiment_assignments.key_customer` (`experiment_key`, `customer_id`),
                KEY `idx.experiment_assignments.session` (`session_id`),
                KEY `idx.experiment_assignments.created_at` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");

        // Tabelle: experiment_conversions (für Business-Metriken)
        $connection->executeStatement("
            CREATE TABLE IF NOT EXISTS `experiment_conversions` (
                `id` BINARY(16) NOT NULL,
                `experiment_key` VARCHAR(255) NOT NULL,
                `variant` VARCHAR(100) NOT NULL,
                `customer_id` BINARY(16) NULL,
                `conversion_type` VARCHAR(50) NOT NULL,
                `conversion_value` DECIMAL(10, 2) NULL,
                `time_to_conversion` INT NULL COMMENT 'Seconds from assignment to conversion',
                `created_at` DATETIME(3) NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx.experiment_conversions.key_variant` (`experiment_key`, `variant`),
                KEY `idx.experiment_conversions.customer` (`customer_id`),
                KEY `idx.experiment_conversions.type` (`conversion_type`),
                KEY `idx.experiment_conversions.created_at` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");
    }

    /**
     * Führt Migration rückgängig (DOWN)
     *
     * @param Connection $connection Doctrine Connection
     * @return void
     */
    public function updateDestructive(Connection $connection): void
    {
        $connection->executeStatement('DROP TABLE IF EXISTS `experiment_conversions`');
        $connection->executeStatement('DROP TABLE IF EXISTS `experiment_assignments`');
        $connection->executeStatement('DROP TABLE IF EXISTS `experiment_metrics`');
        $connection->executeStatement('DROP TABLE IF EXISTS `experiment`');
    }
}
