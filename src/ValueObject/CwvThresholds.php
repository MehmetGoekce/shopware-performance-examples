<?php

declare(strict_types=1);

namespace PerformanceExamples\ValueObject;

/**
 * Google Core Web Vitals Schwellenwerte (Stand: 2024)
 *
 * Zentrale Definition der CWV-Schwellenwerte, die in mehreren
 * Kapiteln verwendet werden (RUM, Alerting, Tests).
 *
 * @see https://web.dev/articles/vitals
 */
final class CwvThresholds
{
    // LCP (Largest Contentful Paint) in ms
    public const LCP_GOOD = 2500;
    public const LCP_POOR = 4000;

    // INP (Interaction to Next Paint) in ms
    public const INP_GOOD = 200;
    public const INP_POOR = 500;

    // CLS (Cumulative Layout Shift) - Score
    public const CLS_GOOD = 0.1;
    public const CLS_POOR = 0.25;

    // FCP (First Contentful Paint) in ms
    public const FCP_GOOD = 1800;
    public const FCP_POOR = 3000;

    // TTFB (Time to First Byte) in ms
    public const TTFB_GOOD = 800;
    public const TTFB_POOR = 1800;

    /**
     * Gibt alle Schwellenwerte als Array zurück.
     *
     * @return array<string, array{good: int|float, poor: int|float}>
     */
    public static function all(): array
    {
        return [
            'LCP' => ['good' => self::LCP_GOOD, 'poor' => self::LCP_POOR],
            'INP' => ['good' => self::INP_GOOD, 'poor' => self::INP_POOR],
            'CLS' => ['good' => self::CLS_GOOD, 'poor' => self::CLS_POOR],
            'FCP' => ['good' => self::FCP_GOOD, 'poor' => self::FCP_POOR],
            'TTFB' => ['good' => self::TTFB_GOOD, 'poor' => self::TTFB_POOR],
        ];
    }
}
