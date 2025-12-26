# Kapitel 15: Langfristiger Plan - Companion Code

Praktische Implementierungen für nachhaltiges Performance-Management:
12-Monats-Roadmaps, OKR-Tracking und Tech-Debt-Management.

## Inhalt

### Templates (`templates/`)

- **roadmap.yaml** - 12-Monats-Performance-Roadmap mit Quartals-Themen
- **okr-examples.yaml** - OKR-Beispiele für verschiedene Reifestufen
- **budget-review.yaml** - Jahres-Budget-Review Template
- **maintenance-calendar.yaml** - Wartungskalender (täglich bis jährlich)

### Services (`src/`)

- **TechDebtTrackerService.php** - Technical Debt Tracking und Priorisierung
- **AnnualReportService.php** - Jahresberichte und KPI-Aggregation
- **OkrProgressService.php** - OKR-Fortschritts-Tracking

### Scripts (`scripts/`)

- **quarterly-review.sh** - Automatisiertes Quarterly Review
- **tech-debt-report.sh** - Tech-Debt-Bericht generieren
- **roadmap-status.sh** - Roadmap-Status prüfen

### Config (`config/`)

- **kpi-targets.yaml** - KPI-Zielwerte für 3 Jahre

## Verwendung

### Roadmap erstellen

```bash
# Roadmap aus Template generieren
cp templates/roadmap.yaml config/roadmap-2025.yaml

# Mit eigenen Werten anpassen
vi config/roadmap-2025.yaml
```

### OKRs tracken

```php
use App\Service\OkrProgressService;

$okrService = new OkrProgressService($repository);

// Aktuellen Fortschritt berechnen
$progress = $okrService->calculateQuarterProgress('Q1-2025');

// Status: on_track, at_risk, off_track
echo $progress['status'];
```

### Tech-Debt-Report

```bash
# Tech-Debt-Bericht erstellen
./scripts/tech-debt-report.sh

# Mit Trend-Analyse
./scripts/tech-debt-report.sh --trend
```

### Quarterly Review

```bash
# Quarterly Review vorbereiten
./scripts/quarterly-review.sh Q1

# Output: Markdown-Report mit allen KPIs
```

## Wartungskalender

Das Template `maintenance-calendar.yaml` definiert:

| Frequenz | Aufgaben |
|----------|----------|
| Täglich | Dashboard-Check, Alert-Review |
| Wöchentlich | Budget-Review, Team-Update |
| Monatlich | Deep-Dive-Analyse, Stakeholder-Report |
| Quartalsweise | OKR-Review, Roadmap-Adjustment |
| Jährlich | Strategie-Planung, Budget-Planung |

## Integration

### Mit Kapitel 12 (RUM)

```php
// RUM-Daten für Jahresbericht
$rumService = new RumDashboardService(...);
$yearData = $rumService->getYearlyTrends();
```

### Mit Kapitel 14 (Kultur)

```php
// Culture Score in Jahresbericht
$cultureService = new CultureMetricsService(...);
$cultureScore = $cultureService->calculateCultureScore();
```

## Referenzen

- Kapitel 15 im Buch: "Langfristiger Plan"
- [Atlassian: State of Teams 2024](https://www.atlassian.com/state-of-teams-2024)
- [McKinsey: Technical Debt Research](https://www.mckinsey.com/capabilities/mckinsey-digital/our-insights/tech-debt-reclaiming-tech-equity)
- [Shopify Engineering Blog](https://shopify.engineering/)
