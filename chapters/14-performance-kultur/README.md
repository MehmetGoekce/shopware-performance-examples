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
cd chapters/14-performance-kultur                           # Companion auf dem Shop-Server
php scripts/error-budget.php /var/www/shop                  # letzte 28 Tage
php scripts/error-budget.php /var/www/shop --days=7 --min-samples=200
```

Nur PHP noetig, kein Shopware-Kernel. Der aufrufende Benutzer braucht
Leserecht auf `var/log/rum-*.log` (im Testshop legt Monolog sie mit 0644 an,
dort genuegt auch ein anderer Benutzer als www-data).

Exit-Codes:

- `0` keine bewertete Metrik rot
- `1` mindestens eine Metrik rot (p75 nicht mehr gut)
- `2` Aufruf-, Pfad- oder Rechtefehler (auch: eine `rum-*.log` ist nicht lesbar)
- `3` keine Metrik bewertbar

Eine Metrik unter `--min-samples` (Vorgabe 100 wie bei `rum:check-alerts`)
bleibt ohne Bewertung und steht in der Zeile "Ohne Bewertung", damit
"Gesamt: green" nicht wie "alles gut" aussieht. INP meldet web-vitals nur nach
einer Interaktion, CLS nur aus Chromium-Browsern, deshalb liegen dort oft
weniger Seitenaufrufe vor.

Grenzen: Mehr als 29 Tage deckt das Plugin nicht ab (Monolog behaelt 30
Tagesdateien). Speicher: rund 130 MB je Million Seitenaufrufe und Metrik
(gemessen mit PHP 8.4); die CLI-`php.ini` von Debian/Ubuntu setzt
`memory_limit = -1`, bei einem eigenen Limit `php -d memory_limit=1G`.

Ausgabe im Testshop (Dockware 6.6.10.6, 390 kuenstliche Beacons, davon
10 INP-Doppelmeldungen, die einmal zaehlen):

```text
Error Budget seit 2026-08-25 16:54 UTC (28 Tage, SLO p75 <= Schwelle, Budget 25 % der Seitenaufrufe)

Metrik   Seitenaufrufe ueber Schwelle  verbraucht   uebrig  Stufe
LCP                200             30      60.0 %   40.0 %  yellow
INP                130             40     123.1 %  -23.1 %  red
CLS                 50             34           -        -  zu wenig Daten (< 100)

Gesamt: red
Ohne Bewertung (unter 100 Seitenaufrufen): CLS
```

INP liegt bei 31 % der Seitenaufrufe ueber 200 ms, `rum:report --hours=672`
meldet fuer dieselben 28 Tage ein p75 von 415 ms ("needs-improvement"). Stufe
rot heisst dasselbe: Das p75 ist nicht mehr gut.

### Report fuer Stakeholder

`scripts/generate-report.sh weekly|monthly` baut einen Markdown-Report aus
`rum:report` (gesamt und je Route) und dem Error Budget und laesst Top-Issues
und Erfolge als Platzhalter stehen. `monthly` heisst 28 Tage. Als Benutzer des
Webservers ausfuehren (`bin/console` schreibt in `var/cache`), den Companion
also an einem Ort ablegen, den www-data lesen darf (etwa unter `/opt`):

```bash
cd chapters/14-performance-kultur
sudo -u www-data SHOPWARE_DIR=/var/www/shop ./scripts/generate-report.sh weekly
```

Der Report landet in `$SHOPWARE_DIR/var/performance-reports/` (`OUTPUT_DIR`
aendert das), `SLACK_WEBHOOK` schickt zusaetzlich die Gesamtstufe an Slack.
Exit-Codes: `0` Report geschrieben, `1` Aufruffehler, `2` ein Werkzeug oder der
Slack-Versand ist gescheitert.

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
