<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Service;

use Shopware\Core\Framework\Context;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Symfony\Component\Cache\Adapter\AdapterInterface;
use Symfony\Contracts\Cache\ItemInterface;

/**
 * FeatureFlagService - Lightweight Feature Flag Management
 *
 * @description
 * Verwaltet Feature Flags mit Performance-Budgets und Rollout-Kontrolle.
 * Optimiert für minimalen Runtime-Overhead (<1ms).
 *
 * @example
 * if ($featureFlags->isEnabled('new_checkout', $context)) {
 *     return $this->renderOptimizedCheckout();
 * }
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 * @package ShopwarePerformance\ABTesting
 */
class FeatureFlagService
{
    /**
     * Cache-TTL für Feature Flags (5 Minuten)
     */
    private const CACHE_TTL = 300;

    /**
     * @param AdapterInterface $cache Cache-Adapter
     * @param array<string, array<string, mixed>> $flagConfig Feature Flag Config
     */
    public function __construct(
        private readonly AdapterInterface $cache,
        private readonly array $flagConfig = []
    ) {
    }

    /**
     * Prüft ob Feature Flag aktiv ist
     *
     * @param string $flagKey Feature-Schlüssel
     * @param SalesChannelContext|null $context Optional: Sales Channel Context
     * @return bool True wenn aktiv
     */
    public function isEnabled(string $flagKey, ?SalesChannelContext $context = null): bool
    {
        $config = $this->getConfig($flagKey);

        if (!$config) {
            return false;
        }

        // Global deaktiviert
        if (!($config['enabled'] ?? false)) {
            return false;
        }

        // Rollout-Prozent prüfen
        if (isset($config['rollout_percent']) && $context) {
            $userId = $this->getUserId($context);
            $hash = $this->hashUserId($userId, $flagKey);

            if ($hash > $config['rollout_percent']) {
                return false;
            }
        }

        // Targeting Rules prüfen
        if (isset($config['rules']) && $context) {
            return $this->evaluateRules($config['rules'], $context);
        }

        return true;
    }

    /**
     * Aktiviert Feature Flag
     *
     * @param string $flagKey Feature-Schlüssel
     * @param int $rolloutPercent Rollout-Prozent (0-100)
     * @return void
     */
    public function enable(string $flagKey, int $rolloutPercent = 100): void
    {
        $this->updateConfig($flagKey, [
            'enabled' => true,
            'rollout_percent' => $rolloutPercent,
        ]);
    }

    /**
     * Deaktiviert Feature Flag
     *
     * @param string $flagKey Feature-Schlüssel
     * @return void
     */
    public function disable(string $flagKey): void
    {
        $this->updateConfig($flagKey, [
            'enabled' => false,
        ]);
    }

    /**
     * Erhöht Rollout-Prozent schrittweise
     *
     * @param string $flagKey Feature-Schlüssel
     * @param int $step Schrittgröße (z.B. 10 für +10%)
     * @return int Neuer Rollout-Prozent
     */
    public function increaseRollout(string $flagKey, int $step = 10): int
    {
        $config = $this->getConfig($flagKey);
        $currentPercent = $config['rollout_percent'] ?? 0;
        $newPercent = min(100, $currentPercent + $step);

        $this->updateConfig($flagKey, [
            'rollout_percent' => $newPercent,
        ]);

        return $newPercent;
    }

    /**
     * Gibt alle aktiven Feature Flags zurück
     *
     * @param SalesChannelContext|null $context Optional: Context für Targeting
     * @return array<string> Aktive Flag-Schlüssel
     */
    public function getActiveFlags(?SalesChannelContext $context = null): array
    {
        $activeFlags = [];

        foreach ($this->flagConfig as $flagKey => $config) {
            if ($this->isEnabled($flagKey, $context)) {
                $activeFlags[] = $flagKey;
            }
        }

        return $activeFlags;
    }

    /**
     * Gibt Feature Flag Konfiguration zurück
     *
     * @param string $flagKey Feature-Schlüssel
     * @return array<string, mixed>|null Konfiguration
     */
    public function getConfig(string $flagKey): ?array
    {
        return $this->cache->get(
            "feature_flag_{$flagKey}",
            function (ItemInterface $item) use ($flagKey): ?array {
                $item->expiresAfter(self::CACHE_TTL);

                return $this->flagConfig[$flagKey] ?? null;
            }
        );
    }

    /**
     * Setzt Feature Flag mit Performance-Budget
     *
     * @param string $flagKey Feature-Schlüssel
     * @param array<string, mixed> $config Konfiguration
     * @return void
     *
     * @example
     * $featureFlags->setFlag('optimized_search', [
     *     'enabled' => true,
     *     'rollout_percent' => 25,
     *     'performance_budget' => [
     *         'response_time' => 200,  // ms
     *         'memory_limit' => 50     // MB
     *     ],
     *     'rules' => [
     *         ['customer_group' => 'premium'],
     *         ['device_type' => 'desktop']
     *     ]
     * ]);
     */
    public function setFlag(string $flagKey, array $config): void
    {
        $this->flagConfig[$flagKey] = array_merge(
            $this->flagConfig[$flagKey] ?? [],
            $config
        );

        // Cache invalidieren
        $this->cache->delete("feature_flag_{$flagKey}");
    }

    /**
     * Gibt Performance-Budget für Feature Flag zurück
     *
     * @param string $flagKey Feature-Schlüssel
     * @return array<string, int>|null Performance-Budget
     */
    public function getPerformanceBudget(string $flagKey): ?array
    {
        $config = $this->getConfig($flagKey);

        return $config['performance_budget'] ?? null;
    }

    /**
     * Prüft ob Performance-Budget überschritten wurde
     *
     * @param string $flagKey Feature-Schlüssel
     * @param array<string, float> $metrics Gemessene Metriken
     * @return bool True wenn überschritten
     */
    public function exceedsBudget(string $flagKey, array $metrics): bool
    {
        $budget = $this->getPerformanceBudget($flagKey);

        if (!$budget) {
            return false;
        }

        foreach ($metrics as $metric => $value) {
            if (isset($budget[$metric]) && $value > $budget[$metric]) {
                return true;
            }
        }

        return false;
    }

    /**
     * Deaktiviert Feature Flag automatisch bei Budget-Überschreitung
     *
     * @param string $flagKey Feature-Schlüssel
     * @param array<string, float> $metrics Gemessene Metriken
     * @param string $reason Grund
     * @return bool True wenn deaktiviert
     */
    public function autoDisableOnBudgetExceeded(
        string $flagKey,
        array $metrics,
        string $reason = ''
    ): bool {
        if (!$this->exceedsBudget($flagKey, $metrics)) {
            return false;
        }

        $this->updateConfig($flagKey, [
            'enabled' => false,
            'disabled_reason' => $reason ?: 'Performance budget exceeded',
            'disabled_at' => (new \DateTime())->format('Y-m-d H:i:s'),
            'metrics_at_disable' => $metrics,
        ]);

        return true;
    }

    /**
     * Evaluiert Targeting-Rules
     *
     * @param array<array<string, mixed>> $rules Regel-Array
     * @param SalesChannelContext $context Sales Channel Context
     * @return bool True wenn alle Regeln erfüllt
     */
    private function evaluateRules(array $rules, SalesChannelContext $context): bool
    {
        foreach ($rules as $rule) {
            // Customer Group
            if (isset($rule['customer_group'])) {
                $customer = $context->getCustomer();
                if (!$customer || $customer->getGroupId() !== $rule['customer_group']) {
                    return false;
                }
            }

            // Device Type
            if (isset($rule['device_type'])) {
                $deviceType = $this->detectDeviceType();
                if ($deviceType !== $rule['device_type']) {
                    return false;
                }
            }

            // Sales Channel
            if (isset($rule['sales_channel'])) {
                if ($context->getSalesChannelId() !== $rule['sales_channel']) {
                    return false;
                }
            }

            // Custom Field
            if (isset($rule['custom_field'])) {
                $customer = $context->getCustomer();
                if (!$customer) {
                    return false;
                }

                $customFields = $customer->getCustomFields() ?? [];
                foreach ($rule['custom_field'] as $field => $value) {
                    if (($customFields[$field] ?? null) !== $value) {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    /**
     * Gibt Benutzer-ID zurück
     *
     * @param SalesChannelContext $context Sales Channel Context
     * @return string Benutzer-ID
     */
    private function getUserId(SalesChannelContext $context): string
    {
        if ($customer = $context->getCustomer()) {
            return $customer->getId();
        }

        // Fallback: Context-Token (Session)
        return $context->getToken();
    }

    /**
     * Hasht Benutzer-ID zu Prozent-Wert (0-100)
     *
     * @param string $userId Benutzer-ID
     * @param string $flagKey Feature-Schlüssel
     * @return int Hash-Wert (0-100)
     */
    private function hashUserId(string $userId, string $flagKey): int
    {
        $hash = md5($userId . ':' . $flagKey);
        $hashInt = hexdec(substr($hash, 0, 8));

        return $hashInt % 100;
    }

    /**
     * Aktualisiert Feature Flag Konfiguration
     *
     * @param string $flagKey Feature-Schlüssel
     * @param array<string, mixed> $updates Konfiguration-Updates
     * @return void
     */
    private function updateConfig(string $flagKey, array $updates): void
    {
        $config = $this->getConfig($flagKey) ?? [];
        $this->setFlag($flagKey, array_merge($config, $updates));
    }

    /**
     * Erkennt Device-Type
     *
     * @return string 'mobile', 'tablet' oder 'desktop'
     */
    private function detectDeviceType(): string
    {
        if (!isset($_SERVER['HTTP_USER_AGENT'])) {
            return 'unknown';
        }

        $userAgent = $_SERVER['HTTP_USER_AGENT'];

        if (preg_match('/Mobile|Android|iPhone|iPod/i', $userAgent)) {
            return 'mobile';
        }

        if (preg_match('/iPad|Tablet/i', $userAgent)) {
            return 'tablet';
        }

        return 'desktop';
    }
}
