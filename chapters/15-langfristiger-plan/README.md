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

- **TechDebtTrackerService.php** + **TechDebtRepository.php** - Tech-Debt-Score
  und Priorisierung wie im Buch, lauffähig und getestet
  (`tests/Unit/TechDebtTrackerServiceTest.php`)
- **AnnualPerformanceReportService.php** - Jahresbericht, **Skizze** (nicht lauffähig)
- **OkrProgressService.php** - OKR-Fortschritts-Tracking, **Skizze** (nicht lauffähig)

### Scripts (`scripts/`)

Alle drei Skripte laufen mit **Beispieldaten, die im Skript stehen**. Sie
zeigen den Aufbau eines Reports, keine Messung, und sagen das in ihrer
Ausgabe. Für eigene Daten ersetzen Sie die Datenblöcke am Skriptanfang.

- **quarterly-review.sh** - Quarterly-Review-Report (Markdown)
- **tech-debt-report.sh** - Tech-Debt-Bericht, Skala wie im Buch
- **roadmap-status.sh** - Roadmap-Status mit Milestones und Risiken

### Config (`config/`)

- **kpi-targets.yaml** - KPI-Zielwerte für 3 Jahre; `current_baseline` ist
  leer und wartet auf Ihre eigene Messung
- **maintenance-workflow.yml** - GitHub-Actions-Workflow für die wöchentliche
  Wartung (composer audit, Lighthouse-Baseline, Issue bei Fehlern)

## Verwendung

### Roadmap erstellen

```bash
# Roadmap aus Template generieren
cp templates/roadmap.yaml config/roadmap-2025.yaml

# Mit eigenen Werten anpassen
vi config/roadmap-2025.yaml
```

### Tech Debt bewerten

Score = Summe der Severity-Punkte aller offenen Items (critical 100, high 40,
medium 10, low 2), ohne Obergrenze: unter 200 gesund, 200-499 Aufmerksamkeit,
ab 500 kritisch. Priorität = Severity-Punkte / Aufwandspunkte (trivial 1,
small 2, medium 5, large 13, xlarge 21). Die Items liefert eine eigene Klasse,
die `TechDebtRepository` implementiert (Jira, GitHub Issues, Tabelle).

```php
use App\Service\TechDebtTrackerService;

$score = (new TechDebtTrackerService(new MyJiraTechDebtRepository()))->getTechDebtScore();

echo $score['total_score'], ' ', $score['status'];   // z. B. "230 attention"
```

### Tech-Debt-Report (Beispieldaten)

```bash
./scripts/tech-debt-report.sh            # Text
./scripts/tech-debt-report.sh --trend    # mit Beispielverlauf
./scripts/tech-debt-report.sh --json     # "data_source" nennt die Beispieldaten
```

### Quarterly Review (Beispieldaten)

```bash
./scripts/quarterly-review.sh Q1
# Output: Markdown-Report in reports/, mit Hinweis auf die Beispieldaten
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

Das Plugin `RumMonitoring` hat keine Lese-API und behält die Logs 30 Tage
(Monolog, eine Datei pro Tag). Für Jahresverläufe legen Sie jeden Monat die
Ausgabe ab und werten die zwölf Monatsdateien aus:

```bash
bin/console rum:report --hours=672 > reports/rum-$(date +%Y-%m).txt
```

Den Monatsbericht mit Error Budget baut
`chapters/14-performance-kultur/scripts/generate-report.sh monthly`
(Wartungskalender M-1).

### Mit Kapitel 14 (Kultur)

```php
use PerformanceKultur\CultureMetricsService;
use PerformanceKultur\PerformanceBudgetService;

$budget = PerformanceBudgetService::calculate($records);
$culture = (new CultureMetricsService(new MyTeamDataSource()))->calculateCultureScore($budget);
```

Details: `chapters/14-performance-kultur/README.md`.

## Referenzen

- Kapitel 15 im Buch: "Langfristiger Plan"
- [Atlassian: State of Teams 2024](https://www.atlassian.com/state-of-teams-2024)
- [McKinsey: Technical Debt Research](https://www.mckinsey.com/capabilities/mckinsey-digital/our-insights/tech-debt-reclaiming-tech-equity)
- [Shopify Engineering Blog](https://shopify.engineering/)
