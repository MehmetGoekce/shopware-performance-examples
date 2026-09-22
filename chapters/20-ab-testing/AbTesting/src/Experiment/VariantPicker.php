<?php

declare(strict_types=1);

namespace AbTesting\Experiment;

/**
 * Waehlt eine Variante nach Gewicht. $roll ist eine Zufallszahl aus
 * [0, Summe der Gewichte) - im Plugin random_int(), im Test fest.
 */
final class VariantPicker
{
    /**
     * @param array<string, int> $weights Variante => Gewicht, z. B. ['control' => 50, 'eager' => 50]
     */
    public static function pick(array $weights, int $roll): string
    {
        $total = array_sum($weights);
        if ($roll < 0 || $roll >= $total) {
            throw new \InvalidArgumentException(sprintf('roll muss in [0, %d) liegen', $total));
        }

        $cumulative = 0;
        foreach ($weights as $name => $weight) {
            $cumulative += $weight;
            if ($roll < $cumulative) {
                return $name;
            }
        }

        throw new \LogicException('unerreichbar');
    }

    /**
     * @param array<string, int> $weights
     */
    public static function random(array $weights): string
    {
        return self::pick($weights, random_int(0, array_sum($weights) - 1));
    }
}
