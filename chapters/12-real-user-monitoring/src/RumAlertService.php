<?php

declare(strict_types=1);

/**
 * RUM Alert Service
 *
 * Prüft RUM-Metriken und sendet Alerts bei Überschreitung der Schwellenwerte.
 *
 * Installation:
 *   1. Datei nach src/Service/ kopieren
 *   2. In services.yaml registrieren
 *   3. Cron-Job einrichten (siehe Command)
 */

namespace App\Service;

use PerformanceExamples\ValueObject\CwvThresholds;
use Psr\Log\LoggerInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class RumAlertService
{
    /**
     * Core Web Vitals Schwellenwerte (p75)
     * Mapping: good → warning, poor → critical
     *
     * @see CwvThresholds
     */
    private const THRESHOLDS = [
        'LCP' => ['warning' => CwvThresholds::LCP_GOOD, 'critical' => CwvThresholds::LCP_POOR],
        'INP' => ['warning' => CwvThresholds::INP_GOOD, 'critical' => CwvThresholds::INP_POOR],
        'CLS' => ['warning' => CwvThresholds::CLS_GOOD, 'critical' => CwvThresholds::CLS_POOR],
        'FCP' => ['warning' => CwvThresholds::FCP_GOOD, 'critical' => CwvThresholds::FCP_POOR],
        'TTFB' => ['warning' => CwvThresholds::TTFB_GOOD, 'critical' => CwvThresholds::TTFB_POOR],
    ];

    /**
     * Mindestanzahl Samples für statistisch signifikante Aussage
     */
    private const MIN_SAMPLES = 100;

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly LoggerInterface $logger,
        private readonly ?string $slackWebhook = null,
        private readonly ?string $alertEmail = null
    ) {}

    /**
     * Prüft eine Metrik und sendet ggf. einen Alert
     */
    public function checkAndAlert(
        string $metric,
        float $p75Value,
        int $sampleCount,
        array $context = []
    ): ?string {
        // Nicht genug Daten
        if ($sampleCount < self::MIN_SAMPLES) {
            $this->logger->debug('RUM Alert: Nicht genug Samples', [
                'metric' => $metric,
                'samples' => $sampleCount,
                'min_required' => self::MIN_SAMPLES
            ]);
            return null;
        }

        // Unbekannte Metrik
        $thresholds = self::THRESHOLDS[$metric] ?? null;
        if (!$thresholds) {
            $this->logger->warning('RUM Alert: Unbekannte Metrik', ['metric' => $metric]);
            return null;
        }

        // Level bestimmen
        $level = $this->determineLevel($p75Value, $thresholds);

        if ($level === 'ok') {
            return null;
        }

        // Alert senden
        $this->sendAlert($metric, $p75Value, $level, $sampleCount, $context);

        return $level;
    }

    /**
     * Prüft alle Metriken aus einem Statistik-Array
     */
    public function checkAllMetrics(array $stats): array
    {
        $alerts = [];

        foreach (['LCP', 'INP', 'CLS', 'FCP', 'TTFB'] as $metric) {
            if (!isset($stats[$metric])) {
                continue;
            }

            $metricStats = $stats[$metric];

            $level = $this->checkAndAlert(
                $metric,
                $metricStats['p75'] ?? 0,
                $metricStats['samples'] ?? 0,
                $metricStats
            );

            if ($level !== null) {
                $alerts[$metric] = $level;
            }
        }

        return $alerts;
    }

    /**
     * Bestimmt das Alert-Level
     */
    private function determineLevel(float $value, array $thresholds): string
    {
        if ($value >= $thresholds['critical']) {
            return 'critical';
        }

        if ($value >= $thresholds['warning']) {
            return 'warning';
        }

        return 'ok';
    }

    /**
     * Sendet einen Alert an alle konfigurierten Kanäle
     */
    private function sendAlert(
        string $metric,
        float $value,
        string $level,
        int $samples,
        array $context
    ): void {
        $emoji = $level === 'critical' ? ':rotating_light:' : ':warning:';
        $threshold = self::THRESHOLDS[$metric][$level] ?? 'unknown';

        $message = sprintf(
            '%s *%s* %s Alert\n' .
            '• Metrik: *%s*\n' .
            '• Wert (p75): *%.2f* (Schwelle: %s)\n' .
            '• Samples: %d\n' .
            '• Zeit: %s',
            $emoji,
            strtoupper($level),
            $metric,
            $metric,
            $value,
            $threshold,
            $samples,
            date('Y-m-d H:i:s')
        );

        // Kontext hinzufügen
        if (!empty($context['good_rate'])) {
            $message .= sprintf("\n• Good Rate: %.1f%%", $context['good_rate'] * 100);
        }

        // Slack senden
        if ($this->slackWebhook) {
            $this->sendSlackAlert($message, $level);
        }

        // Email senden
        if ($this->alertEmail) {
            $this->sendEmailAlert($metric, $value, $level, $samples);
        }

        // Immer loggen
        $this->logger->warning('RUM Alert', [
            'metric' => $metric,
            'value' => $value,
            'level' => $level,
            'samples' => $samples,
            'threshold' => $threshold
        ]);
    }

    /**
     * Sendet Alert an Slack
     */
    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier Retry-Logik und Rate-Limiting nutzen.
    private function sendSlackAlert(string $message, string $level): void
    {
        $color = $level === 'critical' ? 'danger' : 'warning';

        try {
            $this->httpClient->request('POST', $this->slackWebhook, [
                'json' => [
                    'attachments' => [
                        [
                            'color' => $color,
                            'text' => $message,
                            'mrkdwn_in' => ['text']
                        ]
                    ]
                ]
            ]);
        } catch (\Exception $e) {
            $this->logger->error('Slack Alert fehlgeschlagen', [
                'error' => $e->getMessage()
            ]);
        }
    }

    /**
     * Sendet Alert per Email
     */
    // EXAMPLE: Vereinfacht für Lernzwecke. Produktions-Code würde hier Symfony Mailer nutzen.
    private function sendEmailAlert(
        string $metric,
        float $value,
        string $level,
        int $samples
    ): void {
        // Email-Versand würde hier implementiert
        // (Symfony Mailer oder natives mail())
        $this->logger->info('Email Alert würde gesendet', [
            'to' => $this->alertEmail,
            'metric' => $metric
        ]);
    }

    /**
     * Gibt die konfigurierten Schwellenwerte zurück
     */
    public static function getThresholds(): array
    {
        return self::THRESHOLDS;
    }

    /**
     * Gibt die Mindestanzahl Samples zurück
     */
    public static function getMinSamples(): int
    {
        return self::MIN_SAMPLES;
    }
}
