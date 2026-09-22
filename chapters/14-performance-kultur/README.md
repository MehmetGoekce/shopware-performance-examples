# Kapitel 14: Performance-Kultur im Team

Companion-Code zum Buch "Shop-Performance in 30 Tagen".

## Inhalt

Dieses Kapitel behandelt die organisatorischen Aspekte von Performance:

- **Shared Ownership** - Performance als Team-Verantwortung
- **Performance-Champions** - Experten im Team etablieren
- **Code Reviews** - Performance-Fokus in Reviews
- **Blameless Postmortems** - Aus Incidents lernen
- **Feedback-Kultur** - Kontinuierliche Verbesserung

## Dateien

```
14-performance-kultur/
├── templates/
│   ├── postmortem-template.md       # Incident-Analyse Template
│   ├── champion-program.yaml        # Champion-Programm Definition
│   ├── error-budget-policy.yaml     # Error Budget Regeln
│   └── developer-survey.yaml        # DevEx Survey Fragen
├── checklists/
│   ├── code-review-performance.md   # PR-Review Checklist
│   ├── champion-onboarding.md       # Champion Einarbeitung
│   └── new-hire-performance.md      # Onboarding neue Mitarbeiter
├── src/
│   ├── PerformanceBudgetService.php # Error Budget aus den RUM-Logs (Kapitel 12)
│   └── CultureMetricsService.php    # Kultur-Metriken
└── scripts/
    ├── error-budget.php             # Error Budget je Core Web Vital
    ├── generate-report.sh           # Performance-Report Generator
    └── pr-stats.sh                  # PR-Statistiken
```

## Quick Start

### 1. PR-Template erweitern

Kopiere die Checklist in dein GitHub/GitLab PR-Template:

```markdown
## Performance Checklist
- [ ] Keine neuen großen Dependencies
- [ ] Bilder optimiert (WebP, lazy)
- [ ] Keine N+1 Queries
- [ ] Cache-Invalidierung korrekt
```

### 2. Slack-Channel einrichten

```bash
# Channel: #performance
# Integrations:
# - Lighthouse CI Alerts
# - RUM-Alerts (rum:check-alerts aus Kapitel 12, Webhook)
# - Weekly Digest Bot
```

### 3. Ersten Champion benennen

1. `champion-program.yaml` anpassen
2. Champion auswählen (Freiwillig!)
3. Onboarding mit `champion-onboarding.md`

## Templates

### Postmortem

Das `postmortem-template.md` ist für Performance-Incidents optimiert:

- Blameless Kultur betont
- Performance-spezifische Metriken
- 5 Whys Analyse
- Action Items mit Owner

### Error Budget

Das `error-budget-policy.yaml` definiert:

- SLO-Schwellenwerte
- Budget-Berechnung
- Eskalationsstufen
- Release-Policies

### Error Budget ausrechnen

Das SLO lautet wie bei Google "p75 <= Schwelle" (LCP 2500 ms, INP 200 ms,
CLS 0.1). Daraus folgt das Budget: Hoechstens 25 % der Seitenaufrufe duerfen
ueber der Schwelle liegen. `scripts/error-budget.php` rechnet das aus den
RUM-Logs von Kapitel 12 aus. Voraussetzung: Plugin `RumMonitoring` ist
installiert und hat Daten gesammelt.

```bash
cd chapters/14-performance-kultur
php scripts/error-budget.php /var/www/html                  # letzte 28 Tage
php scripts/error-budget.php /var/www/html --days=7 --min-samples=200
```

Als Benutzer des Webservers ausfuehren (liest `var/log/rum-*.log`). Nur PHP
noetig, kein Shopware-Kernel. Exit-Codes: `0` kein SLO verletzt, `1` mindestens
eine Metrik rot, `2` Aufruf- oder Pfadfehler, `3` zu wenig Daten (unter
`--min-samples`, Vorgabe 100 wie bei `rum:check-alerts`).

Ausgabe im Testshop (Dockware 6.6.10.6, 390 kuenstliche Beacons, davon
10 INP-Doppelmeldungen, die einmal zaehlen):

```text
Error Budget seit 2026-08-25 16:30 UTC (28 Tage, SLO p75 <= Schwelle, Budget 25 % der Seitenaufrufe)

Metrik   Seitenaufrufe ueber Schwelle  verbraucht   uebrig  Stufe
LCP                200             30      60.0 %   40.0 %  yellow
INP                130             40     123.1 %  -23.1 %  red
CLS                 50             34           -        -  zu wenig Daten (< 100)

Gesamt: red
```

INP liegt bei 31 % der Seitenaufrufe ueber 200 ms, `rum:report` meldet fuer
dieselben Daten ein p75 von 415 ms ("needs-improvement"). Stufe rot heisst
dasselbe: Das p75 ist nicht mehr gut.

`scripts/generate-report.sh weekly|monthly` baut daraus einen Markdown-Report
(`rum:report` gesamt und je Route, Error Budget) und laesst Top-Issues und
Erfolge als Platzhalter stehen. Umgebung: `SHOPWARE_DIR`, `OUTPUT_DIR`,
optional `SLACK_WEBHOOK`.

## Metriken

### Performance-Kultur Score

```
Score = (PRs mit Review × 0.3) +
        (Budget Compliance × 0.3) +
        (MTTR Score × 0.2) +
        (DevEx Survey × 0.2)
```

### Tracking

- PRs mit Performance-Review: `pr-stats.sh`
- Error Budget: `scripts/error-budget.php` (rechnet mit `src/PerformanceBudgetService.php`)
- Incident MTTR: Aus Incident-Tracker
- Developer Satisfaction: Quarterly Survey

## Best Practices

1. **Start Small**: Ein Champion, eine Checklist
2. **Make it Easy**: Tools und Templates bereitstellen
3. **Celebrate Wins**: Erfolge teilen
4. **Learn from Failures**: Blameless Postmortems
5. **Measure Progress**: Metriken tracken

## Weiterführende Links

- [DORA State of DevOps 2024](https://cloud.google.com/devops/state-of-devops)
- [Google SRE Book](https://sre.google/)
- [SPACE Framework](https://queue.acm.org/detail.cfm?id=3454124)

## Lizenz

MIT - Frei verwendbar für kommerzielle Projekte.
