<?php

declare(strict_types=1);

namespace RumMonitoring\Rum;

/**
 * Prueft einen Beacon aus rum.js und macht daraus eine Log-Zeile.
 *
 * Geloggt wird nur, was die Auswertung braucht: keine IP, kein User-Agent,
 * kein Query-String (dort stehen gern E-Mail-Adressen oder Gutscheincodes).
 */
final class RumPayload
{
    public const MAX_BODY_BYTES = 2048;

    public const METRICS = ['LCP', 'INP', 'CLS', 'FCP', 'TTFB'];

    private const RATINGS = ['good', 'needs-improvement', 'poor'];

    private const NAVIGATION_TYPES = [
        'navigate', 'reload', 'back-forward', 'back-forward-cache', 'prerender', 'restore', 'soft-navigation',
    ];

    /**
     * @return array<string, string|float|null>|null null = Beacon verwerfen
     */
    public static function fromJson(string $body, ?string $country = null): ?array
    {
        if ($body === '' || \strlen($body) > self::MAX_BODY_BYTES) {
            return null;
        }

        try {
            $data = json_decode($body, true, 4, \JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return null;
        }

        if (!\is_array($data)) {
            return null;
        }

        $name = $data['name'] ?? null;
        $value = $data['value'] ?? null;

        if (!\in_array($name, self::METRICS, true) || !\is_int($value) && !\is_float($value)) {
            return null;
        }

        // Ein LCP ueber 60 s oder ein negativer Wert ist kein Messwert, sondern Muell
        if ($value < 0 || $value > 60000) {
            return null;
        }

        return [
            'metric' => $name,
            'value' => round((float) $value, $name === 'CLS' ? 4 : 1),
            'rating' => self::oneOf($data['rating'] ?? null, self::RATINGS),
            'navigation_type' => self::oneOf($data['navigationType'] ?? null, self::NAVIGATION_TYPES),
            'route' => self::match($data['route'] ?? null, '/^[a-z0-9._-]{1,64}$/'),
            'path' => self::path($data['path'] ?? null),
            'target' => self::text($data['target'] ?? null, 200),
            'device' => self::oneOf($data['device'] ?? null, ['mobile', 'desktop']),
            // Nur hinter Cloudflare gesetzt (Header CF-IPCountry), sonst null
            'country' => self::match($country, '/^[A-Z]{2}$/'),
        ];
    }

    /**
     * @param list<string> $allowed
     */
    private static function oneOf(mixed $value, array $allowed): ?string
    {
        return \is_string($value) && \in_array($value, $allowed, true) ? $value : null;
    }

    private static function match(mixed $value, string $pattern): ?string
    {
        return \is_string($value) && preg_match($pattern, $value) === 1 ? $value : null;
    }

    private static function text(mixed $value, int $maxLength): ?string
    {
        if (!\is_string($value) || $value === '') {
            return null;
        }

        return mb_substr($value, 0, $maxLength);
    }

    private static function path(mixed $value): ?string
    {
        if (!\is_string($value) || !str_starts_with($value, '/')) {
            return null;
        }

        $path = (string) parse_url($value, \PHP_URL_PATH);

        return mb_substr($path, 0, 200);
    }
}
