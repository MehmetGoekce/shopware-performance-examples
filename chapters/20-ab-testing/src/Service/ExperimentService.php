<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Service;

use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Symfony\Component\HttpFoundation\Cookie;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * ExperimentService - Zentrale Verwaltung für A/B Tests
 *
 * @description
 * Verwaltet Experimente, Varianten-Zuweisungen und Performance-Tracking.
 * Implementiert deterministisches Hashing für konsistente Varianten-Zuordnung.
 *
 * @example
 * $variant = $experimentService->assignVariant(
 *     experimentId: 'checkout_optimization',
 *     context: $salesChannelContext
 * );
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ABTesting
 */
class ExperimentService
{
    private const COOKIE_PREFIX = 'exp_';
    private const COOKIE_LIFETIME = 30 * 24 * 60 * 60; // 30 Tage

    /**
     * @param EntityRepository $experimentRepository Repository für Experimente
     * @param RequestStack $requestStack HTTP Request Stack
     * @param PerformanceVariantCollector $performanceCollector Performance-Metriken Collector
     */
    public function __construct(
        private readonly EntityRepository $experimentRepository,
        private readonly RequestStack $requestStack,
        private readonly PerformanceVariantCollector $performanceCollector
    ) {
    }

    /**
     * Erstellt ein neues Experiment
     *
     * @param array<string, mixed> $data Experiment-Konfiguration
     * @param Context $context Shopware Context
     * @return string Experiment-ID
     *
     * @throws \InvalidArgumentException Wenn Konfiguration ungültig
     */
    public function create(array $data, Context $context): string
    {
        $this->validateExperimentData($data);

        $experimentId = $this->experimentRepository->create([
            [
                'name' => $data['name'],
                'key' => $this->generateKey($data['name']),
                'variants' => $this->prepareVariants($data['variants'], $data['traffic_split']),
                'performanceBudget' => $data['performance_budget'] ?? [],
                'status' => 'draft',
                'startDate' => null,
                'endDate' => null,
                'targetSampleSize' => $this->calculateSampleSize($data),
            ]
        ], $context)->getPrimaryKeys('id')[0];

        return $experimentId;
    }

    /**
     * Startet ein Experiment
     *
     * @param string $experimentId Experiment-ID
     * @param Context $context Shopware Context
     * @return void
     */
    public function start(string $experimentId, Context $context): void
    {
        $this->experimentRepository->update([
            [
                'id' => $experimentId,
                'status' => 'running',
                'startDate' => new \DateTime(),
            ]
        ], $context);
    }

    /**
     * Pausiert ein Experiment (z.B. bei Performance-Budget Überschreitung)
     *
     * @param string $experimentId Experiment-ID
     * @param string $reason Grund für Pause
     * @param Context $context Shopware Context
     * @return void
     */
    public function pause(string $experimentId, string $reason, Context $context): void
    {
        $this->experimentRepository->update([
            [
                'id' => $experimentId,
                'status' => 'paused',
                'pauseReason' => $reason,
                'pausedAt' => new \DateTime(),
            ]
        ], $context);
    }

    /**
     * Weist einem Benutzer eine Variante zu (deterministisch)
     *
     * @param string $experimentKey Experiment-Schlüssel (z.B. 'checkout_optimization')
     * @param SalesChannelContext $context Sales Channel Context
     * @return string Varianten-Name (z.B. 'control', 'variant_a')
     */
    public function assignVariant(string $experimentKey, SalesChannelContext $context): string
    {
        // 1. Prüfen ob bereits zugewiesen (Cookie)
        $request = $this->requestStack->getCurrentRequest();
        $cookieName = self::COOKIE_PREFIX . $experimentKey;

        if ($request && $request->cookies->has($cookieName)) {
            return $request->cookies->get($cookieName);
        }

        // 2. Experiment laden
        $experiment = $this->getExperiment($experimentKey, $context->getContext());

        if (!$experiment || $experiment['status'] !== 'running') {
            return 'control'; // Fallback
        }

        // 3. Deterministisches Hashing für Varianten-Zuordnung
        $userId = $this->getUserIdentifier($context);
        $variant = $this->hashToVariant($userId, $experimentKey, $experiment['variants']);

        // 4. Cookie setzen für Konsistenz
        $this->setVariantCookie($cookieName, $variant);

        // 5. Tracking-Event auslösen
        $this->performanceCollector->trackAssignment($experimentKey, $variant, $context);

        return $variant;
    }

    /**
     * Prüft ob ein Experiment aktiv ist
     *
     * @param string $experimentKey Experiment-Schlüssel
     * @param Context $context Shopware Context
     * @return bool True wenn aktiv
     */
    public function isActive(string $experimentKey, Context $context): bool
    {
        $experiment = $this->getExperiment($experimentKey, $context);

        return $experiment && $experiment['status'] === 'running';
    }

    /**
     * Gibt aktuelle Variante für Benutzer zurück (ohne neue Zuweisung)
     *
     * @param string $experimentKey Experiment-Schlüssel
     * @return string|null Varianten-Name oder null
     */
    public function getCurrentVariant(string $experimentKey): ?string
    {
        $request = $this->requestStack->getCurrentRequest();
        $cookieName = self::COOKIE_PREFIX . $experimentKey;

        if (!$request || !$request->cookies->has($cookieName)) {
            return null;
        }

        return $request->cookies->get($cookieName);
    }

    /**
     * Trackt eine Performance-Metrik für eine Variante
     *
     * @param string $experimentKey Experiment-Schlüssel
     * @param string $variant Varianten-Name
     * @param string $metric Metrik-Name (z.B. 'lcp', 'fid', 'cls')
     * @param float $value Metrik-Wert
     * @param SalesChannelContext $context Sales Channel Context
     * @return void
     */
    public function trackMetric(
        string $experimentKey,
        string $variant,
        string $metric,
        float $value,
        SalesChannelContext $context
    ): void {
        $experiment = $this->getExperiment($experimentKey, $context->getContext());

        if (!$experiment) {
            return;
        }

        // Performance-Budget prüfen
        if ($this->exceedsBudget($experiment, $metric, $value)) {
            $this->pause(
                $experiment['id'],
                "Performance budget exceeded: {$metric} = {$value}",
                $context->getContext()
            );
        }

        // Metrik speichern
        $this->performanceCollector->collect(
            experimentId: $experiment['id'],
            variant: $variant,
            metric: $metric,
            value: $value,
            context: $context
        );
    }

    /**
     * Gibt Experiment zurück
     *
     * @param string $experimentKey Experiment-Schlüssel
     * @param Context $context Shopware Context
     * @return array<string, mixed>|null Experiment-Daten
     */
    private function getExperiment(string $experimentKey, Context $context): ?array
    {
        $criteria = new Criteria();
        $criteria->addFilter(new EqualsFilter('key', $experimentKey));

        $result = $this->experimentRepository->search($criteria, $context);

        if ($result->count() === 0) {
            return null;
        }

        return $result->first()->jsonSerialize();
    }

    /**
     * Erzeugt eindeutigen Benutzer-Identifier
     *
     * @param SalesChannelContext $context Sales Channel Context
     * @return string Benutzer-ID oder Session-ID
     */
    private function getUserIdentifier(SalesChannelContext $context): string
    {
        // 1. Customer ID (wenn eingeloggt)
        if ($customer = $context->getCustomer()) {
            return 'customer_' . $customer->getId();
        }

        // 2. Session ID (Gäste)
        $request = $this->requestStack->getCurrentRequest();
        if ($request && $request->hasSession()) {
            return 'session_' . $request->getSession()->getId();
        }

        // 3. Fallback: IP + User Agent Hash
        $fallback = ($request?->getClientIp() ?? 'unknown') .
                    ($request?->headers->get('User-Agent') ?? 'unknown');

        return 'anonymous_' . md5($fallback);
    }

    /**
     * Hasht Benutzer-ID zu Variante (deterministisch)
     *
     * @param string $userId Benutzer-Identifier
     * @param string $experimentKey Experiment-Schlüssel
     * @param array<array<string, mixed>> $variants Verfügbare Varianten
     * @return string Varianten-Name
     */
    private function hashToVariant(string $userId, string $experimentKey, array $variants): string
    {
        // Hash erstellen (deterministisch pro User + Experiment)
        $hash = md5($userId . ':' . $experimentKey);
        $hashInt = hexdec(substr($hash, 0, 8)); // Erste 8 Zeichen als Int

        // Traffic-Split berechnen
        $totalWeight = array_sum(array_column($variants, 'traffic_percentage'));
        $position = $hashInt % $totalWeight;

        // Variante finden
        $cumulative = 0;
        foreach ($variants as $variant) {
            $cumulative += $variant['traffic_percentage'];
            if ($position < $cumulative) {
                return $variant['name'];
            }
        }

        // Fallback (sollte nicht passieren)
        return $variants[0]['name'] ?? 'control';
    }

    /**
     * Setzt Cookie für Varianten-Persistenz
     *
     * @param string $name Cookie-Name
     * @param string $value Varianten-Name
     * @return void
     */
    private function setVariantCookie(string $name, string $value): void
    {
        $request = $this->requestStack->getCurrentRequest();

        if (!$request) {
            return;
        }

        // Cookie wird in Response-Header gesetzt via Subscriber
        $request->attributes->set('_experiment_cookie', [
            'name' => $name,
            'value' => $value,
        ]);
    }

    /**
     * Bereitet Varianten-Array für Speicherung vor
     *
     * @param array<string> $variantNames Varianten-Namen
     * @param array<int> $trafficSplit Traffic-Verteilung (z.B. [50, 50])
     * @return array<array<string, mixed>> Varianten-Konfiguration
     */
    private function prepareVariants(array $variantNames, array $trafficSplit): array
    {
        $variants = [];

        foreach ($variantNames as $index => $name) {
            $variants[] = [
                'name' => $name,
                'traffic_percentage' => $trafficSplit[$index] ?? 0,
                'description' => '',
            ];
        }

        return $variants;
    }

    /**
     * Berechnet benötigte Sample Size für statistisches Vertrauen
     *
     * @param array<string, mixed> $data Experiment-Konfiguration
     * @return int Benötigte Sample Size
     */
    private function calculateSampleSize(array $data): int
    {
        // Vereinfachte Formel: (z^2 * p * (1-p)) / e^2
        // z = 1.96 (95% Confidence)
        // p = 0.5 (worst case)
        // e = 0.05 (5% Margin of Error)

        $z = 1.96;
        $p = 0.5;
        $e = $data['margin_of_error'] ?? 0.05;

        $sampleSize = (($z * $z) * $p * (1 - $p)) / ($e * $e);

        // Pro Variante
        $variantCount = count($data['variants']);

        return (int) ceil($sampleSize * $variantCount);
    }

    /**
     * Validiert Experiment-Konfiguration
     *
     * @param array<string, mixed> $data Experiment-Daten
     * @return void
     * @throws \InvalidArgumentException Bei ungültiger Konfiguration
     */
    private function validateExperimentData(array $data): void
    {
        if (empty($data['name'])) {
            throw new \InvalidArgumentException('Experiment name is required');
        }

        if (empty($data['variants']) || count($data['variants']) < 2) {
            throw new \InvalidArgumentException('At least 2 variants required');
        }

        if (!isset($data['traffic_split']) || count($data['traffic_split']) !== count($data['variants'])) {
            throw new \InvalidArgumentException('Traffic split must match variant count');
        }

        $totalSplit = array_sum($data['traffic_split']);
        if ($totalSplit !== 100) {
            throw new \InvalidArgumentException('Traffic split must sum to 100');
        }
    }

    /**
     * Prüft ob Metrik das Performance-Budget überschreitet
     *
     * @param array<string, mixed> $experiment Experiment-Daten
     * @param string $metric Metrik-Name
     * @param float $value Gemessener Wert
     * @return bool True wenn Budget überschritten
     */
    private function exceedsBudget(array $experiment, string $metric, float $value): bool
    {
        $budget = $experiment['performanceBudget'] ?? [];

        if (!isset($budget[$metric])) {
            return false;
        }

        return $value > $budget[$metric];
    }

    /**
     * Generiert URL-freundlichen Key aus Name
     *
     * @param string $name Experiment-Name
     * @return string URL-Slug
     */
    private function generateKey(string $name): string
    {
        $key = strtolower($name);
        $key = preg_replace('/[^a-z0-9]+/', '_', $key);
        $key = trim($key, '_');

        return $key;
    }
}
