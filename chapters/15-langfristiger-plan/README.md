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
- **OkrProgressService.php** - OKR-Fortschritts-Tracking, **Skizze** (ohne eigene
  `OkrRepository`-/`RumDataRepository`-Anbindung nicht lauffähig); Scores und Stufen
  prüft `tests/Unit/OkrProgressServiceTest.php`

### Scripts (`scripts/`)

Alle drei Skripte lesen **eine Eingabedatei (JSON)** und brauchen `jq` ab
Version 1.6 (`apt install jq`; jq 1.5 aus Ubuntu 18.04 kennt `IN` nicht). Ohne
Eingabe geben sie `Usage` aus und enden mit Exit 1, es gibt keinen stillen
Rückfall auf Beispieldaten. Eine kaputte Eingabe (ungültiges JSON, fehlendes
Pflichtfeld, falscher Typ) endet mit einer Meldung je fehlerhaftem Eintrag und
Exit 65, eine fehlende oder nicht lesbare Datei mit Exit 66, ein fehlendes `jq`
mit Exit 2.

- **quarterly-review.sh** - Quarterly-Review-Report (Markdown)
- **tech-debt-report.sh** - Tech-Debt-Bericht, Skala wie im Buch
- **roadmap-status.sh** - Roadmap-Status mit Milestones und Risiken

### Beispieldaten (`examples/`)

- **tech-debt.demo.json**, **tech-debt-history.demo.json**
- **quarterly-review.demo.json**
- **roadmap-status.demo.json** (Zieldaten passend zum Stichtag 2026-09-15)

Die Zahlen sind erfunden und zeigen nur den Aufbau der Berichte; die
Quartals-Demo ist unabhängig von der Tech-Debt-Demo. Nur eine Datei,
deren Name auf `.demo.json` endet, kennzeichnen die Skripte als
«BEISPIELDATEN … keine Messung». Kopieren Sie eine Demo-Datei als Vorlage, dann
unter einem anderen Namen.

### Config (`config/`)

- **kpi-targets.yaml** - KPI-Zielwerte für 3 Jahre; `current_baseline` ist
  leer und wartet auf Ihre eigene Messung
- **maintenance-workflow.yml** - GitHub-Actions-Workflow für die wöchentliche
  Wartung (composer audit, Lighthouse-Baseline, Issue bei Fehlern)

## Verwendung

### Roadmap planen

```bash
# Plan aus der Vorlage (Themen, Milestones, OKRs, Risiken je Quartal)
cp templates/roadmap.yaml config/roadmap-2026.yaml
vi config/roadmap-2026.yaml
```

Die Vorlage ist der Plan und hat keinen Status. Den Stand je Milestone liest
`roadmap-status.sh` aus einer eigenen Statusdatei (unten).

### Tech Debt bewerten

Score = Summe der Severity-Punkte aller offenen Items (critical 100, high 40,
medium 10, low 2), ohne Obergrenze: unter 200 gesund, 200-499 Aufmerksamkeit,
ab 500 kritisch. Priorität = Severity-Punkte / Aufwandspunkte (trivial 1,
small 2, medium 5, large 13, xlarge 21). Unbekannte Werte zählen wie medium
(10 Punkte, Aufwand 5). Die Items liefert eine eigene Klasse, die
`TechDebtRepository` implementiert (Jira, GitHub Issues, Tabelle).

```php
use App\Service\TechDebtTrackerService;

$score = (new TechDebtTrackerService(new MyJiraTechDebtRepository()))->getTechDebtScore();

echo $score['total_score'], ' ', $score['status'];   // z. B. "230 attention"
```

### Tech-Debt-Report

Eingabe ist dieselbe Liste, die `TechDebtRepository::findAllPerformanceDebt()`
liefert, als JSON: nur offene Items, Pflichtfelder `title`, `severity`,
`effort`, optional `category` (fehlt oder `null` = `other`). Skript und Service rechnen
gleich, das prüfen BATS und PHPUnit mit derselben Fixture
(`tests/Unit/fixtures/ch15-tech-debt-equivalence.json`).

```json
[
    {"title": "N+1 Queries in Produktliste", "severity": "critical", "effort": "medium", "category": "database"},
    {"title": "Synchrone Third-Party Scripts", "severity": "high", "effort": "small", "estimated_hours": 8}
]
```

Zusätzlich liest das Skript, falls vorhanden (`null` gilt wie fehlend):
`estimated_hours` (Stundensumme und Sprint-Empfehlung), `id` und `status`
(`backlog`, `in_progress` = in Arbeit, `resolved` fällt überall heraus; andere
Werte zählen als offen). Unbekannte `severity`, `effort` und `status` meldet es
auf stderr.

Sprint-Empfehlung: Offene critical-Items stehen zuerst und ausserhalb des
Budgets, wie Kapitel 15 es verlangt («Sofort beheben», SLA < 1 Sprint). Die
übrigen folgen nach Priorität, soweit sie ins 25-%-Budget (20 h von 80 h)
passen. Items ohne Stundenschätzung plant das Skript nicht ein, es nennt sie.

```bash
./scripts/tech-debt-report.sh tech-debt.json                          # Text
./scripts/tech-debt-report.sh --json tech-debt.json                   # z. B. für quarterly-review
./scripts/tech-debt-report.sh --trend tech-debt-verlauf.json tech-debt.json

# Demo
./scripts/tech-debt-report.sh --trend examples/tech-debt-history.demo.json examples/tech-debt.demo.json
```

Den Verlauf für `--trend` legen Sie selbst an: jeden Monat einen Eintrag aus
der `--json`-Ausgabe anhängen, `score` ← `.summary.tech_debt_score`, `items` ←
`.summary.total_items` (offene Items), `hours` ← `.summary.total_hours`
(geschätzte Stunden im Backlog, ohne Items in Arbeit):

```bash
./scripts/tech-debt-report.sh --json tech-debt.json 2>/dev/null \
  | jq -c --arg m "$(date +%Y-%m)" '{month: $m, score: .summary.tech_debt_score,
        items: .summary.total_items, hours: .summary.total_hours}'
```

`items` und `hours` sind optional.

### Quarterly Review

```bash
./scripts/quarterly-review.sh q3-2026.json
./scripts/quarterly-review.sh q3-2026.json --output /pfad/report.md
# ohne --output: reports/quarterly-review-Q3-2026.md (OUTPUT_DIR ändert das Verzeichnis)

# Demo
./scripts/quarterly-review.sh examples/quarterly-review.demo.json
```

Pflicht sind `quarter` (`Q1`-`Q4`) und `year`. Jeder Datenblock ist optional:
Fehlt er, steht im Report «Keine Daten» statt einer Zahl. Ist er da, müssen
seine Felder vollständig sein. Summen, Mittelwerte, Veränderungen, Budget-Varianz
und die Stufen rechnet das Skript: Tech Debt wie oben, OKR mit den Grenzen von
`OkrProgressService` (ab 0.9 Exceptional, ab 0.7 Strong, ab 0.5 On Track, ab 0.3
At Risk). Wie der Service mittelt es je Objective gewichtet (`weight`, Vorgabe 1),
rundet auf zwei Stellen, bildet den Gesamtwert aus den gerundeten
Objective-Scores und stuft den **angezeigten** Wert ein: Ein Gesamtwert, der als
0.70 erscheint, heisst «Strong», auch wenn das ungerundete Mittel 0.6967 wäre.
Beide runden wie `round()` ab PHP 8.4, der Service auch unter PHP 8.2 und 8.3:
(0.96 + 0.85 + 0.95 + 0.82) / 4 = 0.89499999999999991 ergibt 0.89 «Strong»;
`round()` von PHP 8.2/8.3 machte daraus 0.90 «Exceptional». Die gemeinsamen
Fälle stehen in `tests/Unit/fixtures/ch15-okr-equivalence.json`.

| Block | Felder | Quelle für echte Werte |
|---|---|---|
| `cwv` | `lcp_ms`, `inp_ms`, `cls` je `{start, end}` (p75) | `bin/console rum:report` (Kapitel 12). Die RUM-Logs reichen 30 Tage zurück: den Startwert zu Quartalsbeginn ablegen (siehe «Mit Kapitel 12») |
| `okrs` | `[{objective, key_results: [{title, score (0-1, 0.7 = 70 %), weight?, baseline?, target?, achieved?}]}]`; weglassen statt leerer Liste | Ihr OKR-Tracker; ein Error-Budget-Key-Result aus `chapters/14-performance-kultur/scripts/error-budget.php` |
| `incidents` | `p0`, `p1`, `p2` (ganze Zahlen), optional `postmortems_done` (höchstens p0 + p1 + p2), `mttr_hours`, `root_causes: [{cause, count}]` | Ihr Incident-Tracker |
| `tech_debt` | `start` und `end` je `{items, hours, score}`, optional `resolved: [{title, hours}]` | `tech-debt-report.sh --json` zu Quartalsbeginn und -ende: `items` ← `.summary.total_items`, `hours` ← `.summary.total_hours`, `score` ← `.summary.tech_debt_score` |
| `budget` | `categories: [{category, planned, spent}]`, optional `currency` (Vorgabe CHF), `annual_total` + `spent_year_to_date` | Ihre Buchhaltung |
| `sections` | `[{title, markdown}]` | freie Abschnitte (Highlights, Learnings, Planung), unverändert übernommen |

### Roadmap-Status

```bash
ROADMAP_FILE=roadmap-status.json ./scripts/roadmap-status.sh
./scripts/roadmap-status.sh --file roadmap-status.json --alerts-only
./scripts/roadmap-status.sh --file roadmap-status.json --stichtag 2026-09-30

# Demo (die Zieldaten passen zum Stichtag, ohne ihn ist in einem Jahr alles überfällig)
./scripts/roadmap-status.sh --file examples/roadmap-status.demo.json --stichtag 2026-09-15
```

Die Statusdatei übernimmt die Feldnamen der Vorlage (`quarters.Qn.milestones[]`
und `quarters.Qn.risks[]`, flach in je eine Liste) und ergänzt den Status aus
Ihrem Tracker. Die Milestones übertragen Sie einmal aus Ihrem Plan, danach
pflegen Sie nur noch `status`. Kapitel 15 druckt Kopf, Ziele und Q1 der
Vorlage als Auszug; die Milestones der übrigen Quartale stehen nur hier.

```json
{
    "milestones": [
        {"id": "M-Q1-1", "title": "RUM-Auswertung eingerichtet", "target_date": "2026-01-31",
         "status": "completed", "owner": "DevOps Team"}
    ],
    "risks": [
        {"id": "R-1", "risk": "Team-Kapazität durch andere Projekte",
         "probability": "medium", "impact": "high", "mitigation": "20% Performance-Zeit festlegen"}
    ]
}
```

`status` ist `completed`, `in_progress`, `at_risk` oder `pending`. Überfällig
ist ein offener Milestone, dessen Zieldatum vor dem Stichtag liegt (Vorgabe:
heute); am Zieltag selbst noch nicht. `risks` ist optional, eine fehlende
`id` wird zu `R-1`, `R-2` … Die YAML-Vorlage
weist das Skript mit Exit 65 ab, weil sie keinen Status hat.

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
