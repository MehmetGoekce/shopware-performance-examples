<?php

declare(strict_types=1);

namespace PerformanceKultur;

/**
 * Rohdaten fuer den Performance Culture Score.
 *
 * Woher die Zahlen kommen, ist in jedem Team anders (GitHub oder GitLab,
 * Incident-Tracker, Survey-Tool, Kalender, Wiki, Slack). Diese Schnittstelle
 * schreiben Sie fuer Ihre Werkzeuge; CultureMetricsService rechnet nur.
 *
 * null heisst immer "keine Daten". Die Komponente bleibt dann ohne Bewertung
 * und zaehlt nicht in den Score, statt mit einem erfundenen Wert hineinzugehen.
 */
interface CultureDataSource
{
    /**
     * PRs der letzten $days Tage und wie viele davon ein Performance-Review
     * hatten (Label "performance-reviewed" oder Review-Kommentar).
     *
     * @return array{total: int, performance_reviewed: int}|null
     */
    public function pullRequestCounts(int $days): ?array;

    /**
     * Performance-Incidents der letzten $days Tage. Eine leere Liste heisst
     * "keine Incidents", null heisst "kein Tracker angebunden".
     *
     * @return list<array{recovery_time_hours: float, postmortem_completed: bool}>|null
     */
    public function performanceIncidents(int $days): ?array;

    /**
     * Letzte Developer-Survey (templates/developer-survey.yaml), Durchschnitt
     * auf der Skala 1-5.
     *
     * @return array{date: string, average_score: float, response_rate: float}|null
     */
    public function latestSurvey(): ?array;

    /**
     * Knowledge-Sharing-Aktivitaet der letzten $days Tage.
     *
     * @return array{brown_bags: int, wiki_updates: int, slack_messages: int}|null
     */
    public function knowledgeSharingCounts(int $days): ?array;
}
