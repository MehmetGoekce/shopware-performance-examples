<?php

declare(strict_types=1);

namespace App\Service;

/*
 * Schnittstelle fuer tests/Unit/OkrProgressServiceTest.php und PHPStan.
 * Der Service ist eine Skizze: Diese Ablage bindet jedes Team selbst
 * an, der Companion liefert sie nicht. Die Signaturen folgen den Aufrufen im
 * Service, sonst nichts.
 */
interface RumDataRepository
{
    public function getCurrentMetric(string $metric): ?float;

    public function getPageGoodRate(string $page): ?float;

    public function getConversionRate(): ?float;
}
