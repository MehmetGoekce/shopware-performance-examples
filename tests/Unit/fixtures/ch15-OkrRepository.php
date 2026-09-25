<?php

declare(strict_types=1);

namespace App\Service;

/*
 * Schnittstelle fuer tests/Unit/OkrProgressServiceTest.php und PHPStan.
 * Der Service ist eine Skizze: Diese Ablage bindet jedes Team selbst
 * an, der Companion liefert sie nicht. Die Signaturen folgen den Aufrufen im
 * Service, sonst nichts.
 */
interface OkrRepository
{
    public function findById(string $id): array;

    public function findByQuarter(string $quarter): ?array;

    public function save(array $okrSet): void;
}
