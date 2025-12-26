<?php

declare(strict_types=1);

/**
 * RUM Controller
 *
 * Empfängt Web Vitals Metriken vom Browser und speichert sie.
 *
 * Installation:
 *   1. Datei nach src/Controller/ kopieren
 *   2. bin/console cache:clear
 *
 * Endpoint: POST /api/rum
 */

namespace App\Controller;

use Psr\Log\LoggerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Annotation\Route;

#[Route('/api/rum', name: 'api_rum', methods: ['POST'])]
class RumController extends AbstractController
{
    private const ALLOWED_METRICS = ['CLS', 'INP', 'LCP', 'FCP', 'TTFB'];

    private const THRESHOLDS = [
        'LCP' => ['good' => 2500, 'poor' => 4000],
        'INP' => ['good' => 200, 'poor' => 500],
        'CLS' => ['good' => 0.1, 'poor' => 0.25],
        'FCP' => ['good' => 1800, 'poor' => 3000],
        'TTFB' => ['good' => 800, 'poor' => 1800],
    ];

    public function __construct(
        private readonly LoggerInterface $rumLogger
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        // Rate Limiting (einfache Variante)
        $clientIp = $request->getClientIp();
        $cacheKey = 'rum_rate_' . md5($clientIp);

        // CORS für Cross-Origin Requests (falls CDN)
        $response = new JsonResponse();
        $response->headers->set('Access-Control-Allow-Origin', '*');
        $response->headers->set('Access-Control-Allow-Methods', 'POST');

        // Daten parsen
        $content = $request->getContent();
        if (empty($content)) {
            return $this->errorResponse('Empty body', Response::HTTP_BAD_REQUEST);
        }

        try {
            $data = json_decode($content, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            return $this->errorResponse('Invalid JSON', Response::HTTP_BAD_REQUEST);
        }

        // Validierung
        if (!$this->validateData($data)) {
            return $this->errorResponse('Invalid data', Response::HTTP_BAD_REQUEST);
        }

        // Metrik-Name validieren
        $metricName = strtoupper($data['name']);
        if (!in_array($metricName, self::ALLOWED_METRICS, true)) {
            return $this->errorResponse('Unknown metric', Response::HTTP_BAD_REQUEST);
        }

        // Rating berechnen (falls nicht vom Client gesendet)
        $rating = $data['rating'] ?? $this->calculateRating($metricName, $data['value']);

        // Strukturierte Log-Daten
        $logData = [
            'metric' => $metricName,
            'value' => round((float) $data['value'], 2),
            'rating' => $rating,
            'delta' => isset($data['delta']) ? round((float) $data['delta'], 2) : null,
            'page' => $this->sanitizePath($data['page'] ?? '/'),
            'page_type' => $data['page_type'] ?? 'unknown',
            'device_type' => $data['device_type'] ?? 'unknown',
            'connection' => $data['connection'] ?? 'unknown',
            'returning_user' => $data['returning_user'] ?? false,
            'user_agent' => $this->truncate($request->headers->get('User-Agent', ''), 200),
            'ip_country' => $request->headers->get('CF-IPCountry',
                           $request->headers->get('X-Country-Code', 'unknown')),
            'timestamp' => $data['timestamp'] ?? time() * 1000,
        ];

        // Attribution-Daten (für Debugging)
        if (isset($data['attribution'])) {
            $logData['attribution'] = $this->sanitizeAttribution($data['attribution']);
        }

        // Loggen
        $this->rumLogger->info('RUM', $logData);

        return new JsonResponse(['status' => 'ok']);
    }

    /**
     * Validiert die empfangenen Daten
     */
    private function validateData(array $data): bool
    {
        // Pflichtfelder
        if (!isset($data['name'], $data['value'])) {
            return false;
        }

        // Wert muss numerisch sein
        if (!is_numeric($data['value'])) {
            return false;
        }

        // Wert muss positiv oder 0 sein
        if ($data['value'] < 0) {
            return false;
        }

        // Maximale Werte (Spam-Schutz)
        if ($data['value'] > 60000) { // Max 60 Sekunden
            return false;
        }

        return true;
    }

    /**
     * Berechnet das Rating basierend auf Schwellenwerten
     */
    private function calculateRating(string $metric, float $value): string
    {
        $thresholds = self::THRESHOLDS[$metric] ?? null;

        if (!$thresholds) {
            return 'unknown';
        }

        if ($value <= $thresholds['good']) {
            return 'good';
        }

        if ($value <= $thresholds['poor']) {
            return 'needs-improvement';
        }

        return 'poor';
    }

    /**
     * Bereinigt den Pfad
     */
    private function sanitizePath(string $path): string
    {
        // Query-String entfernen
        $path = strtok($path, '?');

        // Nur erlaubte Zeichen
        $path = preg_replace('/[^a-zA-Z0-9\-_\/\.]/', '', $path);

        // Maximale Länge
        return $this->truncate($path, 200);
    }

    /**
     * Bereinigt Attribution-Daten
     */
    private function sanitizeAttribution(array $attribution): array
    {
        $sanitized = [];

        $allowedKeys = [
            'element', 'url', 'eventTarget', 'eventType',
            'timeToFirstByte', 'resourceLoadDelay', 'resourceLoadTime',
            'elementRenderDelay', 'inputDelay', 'processingDuration',
            'presentationDelay', 'largestShiftTarget', 'largestShiftValue'
        ];

        foreach ($allowedKeys as $key) {
            if (isset($attribution[$key])) {
                $value = $attribution[$key];

                // Strings kürzen
                if (is_string($value)) {
                    $value = $this->truncate($value, 100);
                }

                $sanitized[$key] = $value;
            }
        }

        return $sanitized;
    }

    /**
     * Kürzt einen String
     */
    private function truncate(string $value, int $maxLength): string
    {
        if (strlen($value) > $maxLength) {
            return substr($value, 0, $maxLength) . '...';
        }

        return $value;
    }

    /**
     * Gibt eine Fehler-Response zurück
     */
    private function errorResponse(string $message, int $status): JsonResponse
    {
        return new JsonResponse(['error' => $message], $status);
    }
}
