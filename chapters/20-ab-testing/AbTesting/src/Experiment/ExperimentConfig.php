<?php

declare(strict_types=1);

namespace AbTesting\Experiment;

/**
 * Die Experimente aus dem Parameter ab_testing.experiments (services.xml).
 *
 * Die erste Variante eines Experiments ist die Kontrollgruppe. Ein Cookie-Wert
 * zaehlt nur, wenn er eine der konfigurierten Varianten nennt - sonst koennte
 * jeder Besucher mit einem erfundenen Wert beliebig viele Cache-Eintraege anlegen.
 */
final class ExperimentConfig
{
    public const COOKIE_PREFIX = 'exp_';

    /** @var array<string, array{routes: list<string>, variants: array<string, int>}> */
    private array $experiments = [];

    /**
     * @param array<mixed> $experiments
     */
    public function __construct(array $experiments)
    {
        foreach ($experiments as $key => $experiment) {
            if (!\is_string($key) || preg_match('/^[a-z0-9_]{1,40}$/', $key) !== 1) {
                throw new \InvalidArgumentException(sprintf('Ungueltiger Experiment-Key "%s"', (string) $key));
            }

            $routes = $experiment['routes'] ?? null;
            $variants = $experiment['variants'] ?? null;

            if (!\is_array($routes) || $routes === [] || !\is_array($variants) || \count($variants) < 2) {
                throw new \InvalidArgumentException(sprintf('Experiment "%s" braucht Routen und mindestens zwei Varianten', $key));
            }

            $weights = [];
            foreach ($variants as $name => $weight) {
                if (!\is_string($name) || preg_match('/^[a-z0-9_]{1,40}$/', $name) !== 1 || !is_numeric($weight) || (int) $weight < 1) {
                    throw new \InvalidArgumentException(sprintf('Experiment "%s": Variante "%s" braucht einen Namen aus a-z0-9_ und ein Gewicht >= 1', $key, (string) $name));
                }
                $weights[$name] = (int) $weight;
            }

            $this->experiments[$key] = ['routes' => array_values(array_map('strval', $routes)), 'variants' => $weights];
        }
    }

    /**
     * @return array<string, array{routes: list<string>, variants: array<string, int>}>
     */
    public function all(): array
    {
        return $this->experiments;
    }

    /**
     * @return array<string, array{routes: list<string>, variants: array<string, int>}>
     */
    public function forRoute(string $route): array
    {
        return array_filter($this->experiments, static fn (array $e): bool => \in_array($route, $e['routes'], true));
    }

    public function isVariant(string $key, mixed $value): bool
    {
        return \is_string($value) && isset($this->experiments[$key]['variants'][$value]);
    }

    public function control(string $key): string
    {
        return (string) array_key_first($this->experiments[$key]['variants']);
    }

    public static function cookieName(string $key): string
    {
        return self::COOKIE_PREFIX . $key;
    }
}
