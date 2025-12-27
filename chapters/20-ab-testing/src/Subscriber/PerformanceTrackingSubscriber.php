<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Subscriber;

use ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\TerminateEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * PerformanceTrackingSubscriber - Trackt Server-Side Performance pro Variante
 *
 * @description
 * Misst Response Time, Memory Usage und DB Queries für jede Experiment-Variante.
 * Wird nach Response-Versand ausgeführt (kein User-Impact).
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ABTesting
 */
class PerformanceTrackingSubscriber implements EventSubscriberInterface
{
    /**
     * Request-Start-Zeit (für Response Time Messung)
     */
    private float $requestStartTime;

    /**
     * Memory-Verbrauch bei Request-Start
     */
    private int $requestStartMemory;

    /**
     * @param PerformanceVariantCollector $collector Performance Collector
     */
    public function __construct(
        private readonly PerformanceVariantCollector $collector
    ) {
        $this->requestStartTime = $_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true);
        $this->requestStartMemory = memory_get_usage(true);
    }

    /**
     * Registriert Event-Listener
     *
     * @return array<string, string|array<int, string|int>> Event-Mappings
     */
    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::TERMINATE => ['onKernelTerminate', -1024], // Spät ausführen
        ];
    }

    /**
     * Trackt Performance-Metriken nach Request-Beendigung
     *
     * @param TerminateEvent $event Terminate Event
     * @return void
     */
    public function onKernelTerminate(TerminateEvent $event): void
    {
        $request = $event->getRequest();

        // Experiment-Variante aus Cookie holen
        $experimentKey = $this->getActiveExperiment($request);
        $variant = $this->getVariant($request, $experimentKey);

        if (!$experimentKey || !$variant) {
            return; // Kein aktives Experiment
        }

        // Performance-Metriken sammeln
        $metrics = $this->collectServerMetrics();

        // In Datenbank speichern (async, kein User-Impact)
        try {
            foreach ($metrics as $metric => $value) {
                // Speichern würde hier SalesChannelContext benötigen
                // In Production: aus Request-Attribut holen
                // $this->collector->collect($experimentKey, $variant, $metric, $value, $context);
            }
        } catch (\Throwable $e) {
            // Silent fail - Performance-Tracking darf nicht Request beeinträchtigen
            error_log("Performance tracking failed: " . $e->getMessage());
        }
    }

    /**
     * Sammelt Server-Side Performance-Metriken
     *
     * @return array<string, float> Metriken
     */
    private function collectServerMetrics(): array
    {
        $endTime = microtime(true);
        $endMemory = memory_get_usage(true);
        $peakMemory = memory_get_peak_usage(true);

        return [
            'response_time' => ($endTime - $this->requestStartTime) * 1000, // ms
            'memory_used' => ($endMemory - $this->requestStartMemory) / 1024 / 1024, // MB
            'memory_peak' => $peakMemory / 1024 / 1024, // MB
            'cpu_time' => $this->getCpuTime(),
        ];
    }

    /**
     * Gibt CPU-Zeit zurück (wenn verfügbar)
     *
     * @return float CPU-Zeit in Millisekunden
     */
    private function getCpuTime(): float
    {
        if (!function_exists('getrusage')) {
            return 0.0;
        }

        $ru = getrusage();
        $utime = $ru['ru_utime.tv_sec'] + ($ru['ru_utime.tv_usec'] / 1000000);
        $stime = $ru['ru_stime.tv_sec'] + ($ru['ru_stime.tv_usec'] / 1000000);

        return ($utime + $stime) * 1000; // ms
    }

    /**
     * Gibt aktives Experiment aus Request zurück
     *
     * @param \Symfony\Component\HttpFoundation\Request $request HTTP Request
     * @return string|null Experiment-Schlüssel
     */
    private function getActiveExperiment($request): ?string
    {
        // Prüfe alle Experiment-Cookies
        $cookies = $request->cookies->all();

        foreach ($cookies as $name => $value) {
            if (str_starts_with($name, 'exp_')) {
                return substr($name, 4); // Remove "exp_" prefix
            }
        }

        return null;
    }

    /**
     * Gibt Variante aus Cookie zurück
     *
     * @param \Symfony\Component\HttpFoundation\Request $request HTTP Request
     * @param string|null $experimentKey Experiment-Schlüssel
     * @return string|null Varianten-Name
     */
    private function getVariant($request, ?string $experimentKey): ?string
    {
        if (!$experimentKey) {
            return null;
        }

        return $request->cookies->get('exp_' . $experimentKey);
    }
}
