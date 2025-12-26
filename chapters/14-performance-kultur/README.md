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
│   ├── PerformanceBudgetService.php # Budget-Tracking
│   └── CultureMetricsService.php    # Kultur-Metriken
└── scripts/
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
# - RUM Dashboard Alerts
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
- Error Budget: `PerformanceBudgetService.php`
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
