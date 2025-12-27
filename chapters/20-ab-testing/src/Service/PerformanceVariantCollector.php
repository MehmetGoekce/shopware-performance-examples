<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Service;

use Doctrine\DBAL\Connection;
use Shopware\Core\System\SalesChannel\SalesChannelContext;

/**
 * PerformanceVariantCollector - Sammelt Performance-Metriken pro Experiment-Variante
 *
 * @description
 * Speichert Core Web Vitals und Custom Metrics für jede Variante.
 * Optimiert für hohe Schreiblast mit Bulk-Inserts.
 *
 * @example
 * $collector->collect(
 *     experimentId: 'abc-123',
 *     variant: 'optimized',
 *     metric: 'lcp',
 *     value: 1850.5,
 *     context: $salesChannelContext
 * );
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ABTesting
 */
class PerformanceVariantCollector
{
    /**
     * Buffer für Batch-Inserts (Performance-Optimierung)
     */
    private array $buffer = [];

    /**
     * Maximale Buffer-Größe bevor Flush
     */
    private const BUFFER_SIZE = 100;

    /**
     * Erlaubte Performance-Metriken
     */
    private const ALLOWED_METRICS = [
        // Core Web Vitals
        'lcp',  // Largest Contentful Paint
        'fid',  // First Input Delay
        'cls',  // Cumulative Layout Shift
        'ttfb', // Time to First Byte
        'fcp',  // First Contentful Paint
        'inp',  // Interaction to Next Paint

        // Custom Metrics
        'dom_interactive',
        'dom_complete',
        'load_event_end',
        'resource_count',
        'js_heap_size',

        // Business Metrics
        'time_to_interactive',
        'time_to_conversion',
    ];

    /**
     * @param Connection $connection Doctrine DBAL Connection
     */
    public function __construct(
        private readonly Connection $connection
    ) {
    }

    /**
     * Sammelt eine Performance-Metrik
     *
     * @param string $experimentId Experiment-ID
     * @param string $variant Varianten-Name
     * @param string $metric Metrik-Name
     * @param float $value Gemessener Wert
     * @param SalesChannelContext $context Sales Channel Context
     * @return void
     */
    public function collect(
        string $experimentId,
        string $variant,
        string $metric,
        float $value,
        SalesChannelContext $context
    ): void {
        if (!$this->isValidMetric($metric)) {
            throw new \InvalidArgumentException("Invalid metric: {$metric}");
        }

        $this->buffer[] = [
            'id' => bin2hex(random_bytes(16)),
            'experiment_id' => $experimentId,
            'variant' => $variant,
            'metric' => $metric,
            'value' => $value,
            'customer_id' => $context->getCustomer()?->getId(),
            'device_type' => $this->detectDeviceType(),
            'sales_channel_id' => $context->getSalesChannelId(),
            'created_at' => (new \DateTime())->format('Y-m-d H:i:s'),
        ];

        // Auto-Flush bei Buffer-Limit
        if (count($this->buffer) >= self::BUFFER_SIZE) {
            $this->flush();
        }
    }

    /**
     * Trackt Varianten-Zuweisung (für Conversion-Tracking)
     *
     * @param string $experimentKey Experiment-Schlüssel
     * @param string $variant Zugewiesene Variante
     * @param SalesChannelContext $context Sales Channel Context
     * @return void
     */
    public function trackAssignment(
        string $experimentKey,
        string $variant,
        SalesChannelContext $context
    ): void {
        $this->connection->insert('experiment_assignments', [
            'id' => bin2hex(random_bytes(16)),
            'experiment_key' => $experimentKey,
            'variant' => $variant,
            'customer_id' => $context->getCustomer()?->getId(),
            'session_id' => $this->getSessionId(),
            'device_type' => $this->detectDeviceType(),
            'sales_channel_id' => $context->getSalesChannelId(),
            'created_at' => (new \DateTime())->format('Y-m-d H:i:s'),
        ]);
    }

    /**
     * Schreibt Buffer in Datenbank (Bulk-Insert)
     *
     * @return int Anzahl geschriebener Einträge
     */
    public function flush(): int
    {
        if (empty($this->buffer)) {
            return 0;
        }

        $count = count($this->buffer);

        // Bulk-Insert für Performance
        foreach ($this->buffer as $metric) {
            $this->connection->insert('experiment_metrics', $metric);
        }

        $this->buffer = [];

        return $count;
    }

    /**
     * Gibt aggregierte Metriken für ein Experiment zurück
     *
     * @param string $experimentId Experiment-ID
     * @param string|null $variant Optionaler Filter auf Variante
     * @return array<string, array<string, float>> Aggregierte Daten
     */
    public function getAggregatedMetrics(string $experimentId, ?string $variant = null): array
    {
        $sql = "
            SELECT
                variant,
                metric,
                COUNT(*) as sample_count,
                AVG(value) as mean,
                STDDEV(value) as stddev,
                MIN(value) as min,
                MAX(value) as max,
                PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY value) as p50,
                PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY value) as p75,
                PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value) as p95,
                PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY value) as p99
            FROM experiment_metrics
            WHERE experiment_id = :experiment_id
        ";

        $params = ['experiment_id' => $experimentId];

        if ($variant !== null) {
            $sql .= " AND variant = :variant";
            $params['variant'] = $variant;
        }

        $sql .= " GROUP BY variant, metric";

        $results = $this->connection->fetchAllAssociative($sql, $params);

        // Gruppieren nach Variante
        $aggregated = [];
        foreach ($results as $row) {
            $variantName = $row['variant'];
            $metricName = $row['metric'];

            if (!isset($aggregated[$variantName])) {
                $aggregated[$variantName] = [];
            }

            $aggregated[$variantName][$metricName] = [
                'sample_count' => (int) $row['sample_count'],
                'mean' => (float) $row['mean'],
                'stddev' => (float) $row['stddev'],
                'min' => (float) $row['min'],
                'max' => (float) $row['max'],
                'p50' => (float) $row['p50'],
                'p75' => (float) $row['p75'],
                'p95' => (float) $row['p95'],
                'p99' => (float) $row['p99'],
            ];
        }

        return $aggregated;
    }

    /**
     * Gibt Rohdaten für ein Experiment zurück (für externe Analyse)
     *
     * @param string $experimentId Experiment-ID
     * @param int $limit Maximale Anzahl Einträge
     * @return array<array<string, mixed>> Rohdaten
     */
    public function getRawMetrics(string $experimentId, int $limit = 10000): array
    {
        $sql = "
            SELECT
                variant,
                metric,
                value,
                device_type,
                created_at
            FROM experiment_metrics
            WHERE experiment_id = :experiment_id
            ORDER BY created_at DESC
            LIMIT :limit
        ";

        return $this->connection->fetchAllAssociative($sql, [
            'experiment_id' => $experimentId,
            'limit' => $limit,
        ]);
    }

    /**
     * Exportiert Metriken als CSV
     *
     * @param string $experimentId Experiment-ID
     * @param string $outputPath Datei-Pfad
     * @return int Anzahl exportierter Zeilen
     */
    public function exportToCSV(string $experimentId, string $outputPath): int
    {
        $metrics = $this->getRawMetrics($experimentId, 100000);

        $fp = fopen($outputPath, 'w');

        if (!$fp) {
            throw new \RuntimeException("Could not open file: {$outputPath}");
        }

        // Header
        fputcsv($fp, ['variant', 'metric', 'value', 'device_type', 'created_at']);

        // Daten
        foreach ($metrics as $metric) {
            fputcsv($fp, [
                $metric['variant'],
                $metric['metric'],
                $metric['value'],
                $metric['device_type'],
                $metric['created_at'],
            ]);
        }

        fclose($fp);

        return count($metrics);
    }

    /**
     * Gibt Conversion-Rate pro Variante zurück
     *
     * @param string $experimentKey Experiment-Schlüssel
     * @param \DateTime $since Startdatum
     * @return array<string, array<string, mixed>> Conversion-Daten
     */
    public function getConversionRates(string $experimentKey, \DateTime $since): array
    {
        $sql = "
            SELECT
                a.variant,
                COUNT(DISTINCT a.customer_id) as users,
                COUNT(DISTINCT o.customer_id) as conversions,
                (COUNT(DISTINCT o.customer_id)::float / COUNT(DISTINCT a.customer_id)) * 100 as conversion_rate,
                AVG(o.amount_total) as avg_order_value
            FROM experiment_assignments a
            LEFT JOIN `order` o ON o.customer_id = a.customer_id
                AND o.created_at >= a.created_at
                AND o.created_at <= a.created_at + INTERVAL '1 hour'
            WHERE a.experiment_key = :experiment_key
                AND a.created_at >= :since
            GROUP BY a.variant
        ";

        $results = $this->connection->fetchAllAssociative($sql, [
            'experiment_key' => $experimentKey,
            'since' => $since->format('Y-m-d H:i:s'),
        ]);

        $conversions = [];
        foreach ($results as $row) {
            $conversions[$row['variant']] = [
                'users' => (int) $row['users'],
                'conversions' => (int) $row['conversions'],
                'conversion_rate' => round((float) $row['conversion_rate'], 2),
                'avg_order_value' => round((float) $row['avg_order_value'], 2),
            ];
        }

        return $conversions;
    }

    /**
     * Löscht alte Metriken (Daten-Retention)
     *
     * @param int $daysToKeep Tage, die behalten werden
     * @return int Anzahl gelöschter Einträge
     */
    public function cleanup(int $daysToKeep = 90): int
    {
        $cutoffDate = (new \DateTime())
            ->modify("-{$daysToKeep} days")
            ->format('Y-m-d H:i:s');

        return $this->connection->executeStatement(
            "DELETE FROM experiment_metrics WHERE created_at < :cutoff",
            ['cutoff' => $cutoffDate]
        );
    }

    /**
     * Prüft ob Metrik erlaubt ist
     *
     * @param string $metric Metrik-Name
     * @return bool True wenn erlaubt
     */
    private function isValidMetric(string $metric): bool
    {
        return in_array($metric, self::ALLOWED_METRICS, true);
    }

    /**
     * Erkennt Device-Type aus User-Agent
     *
     * @return string 'mobile', 'tablet' oder 'desktop'
     */
    private function detectDeviceType(): string
    {
        if (!isset($_SERVER['HTTP_USER_AGENT'])) {
            return 'unknown';
        }

        $userAgent = $_SERVER['HTTP_USER_AGENT'];

        if (preg_match('/Mobile|Android|iPhone|iPad|iPod/i', $userAgent)) {
            if (preg_match('/iPad|Tablet/i', $userAgent)) {
                return 'tablet';
            }
            return 'mobile';
        }

        return 'desktop';
    }

    /**
     * Gibt aktuelle Session-ID zurück
     *
     * @return string|null Session-ID
     */
    private function getSessionId(): ?string
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return session_id();
        }

        return null;
    }

    /**
     * Destructor - Flusht Buffer bei Skript-Ende
     */
    public function __destruct()
    {
        $this->flush();
    }
}
