<?php

declare(strict_types=1);

namespace App\Service;

/**
 * Quelle der offenen Performance-Schulden fuer TechDebtTrackerService.
 *
 * Binden Sie hier Ihren Tracker an (Jira-JQL, GitHub-Label, Tabelle).
 */
interface TechDebtRepository
{
    /**
     * Nur offene Items. severity: critical|high|medium|low,
     * effort: trivial|small|medium|large|xlarge. Unbekannte Werte zaehlen
     * wie medium (10 Punkte, Aufwand 5).
     *
     * @return list<array{title: string, severity: string, effort: string, category?: string}>
     */
    public function findAllPerformanceDebt(): array;
}
