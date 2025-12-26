# Kapitel 13: Continuous Performance Testing

Companion-Code zum Buch "Shop-Performance in 30 Tagen".

## Inhalt

Dieses Kapitel zeigt, wie Sie Performance-Tests in Ihre CI/CD-Pipeline integrieren:

- **Lighthouse CI** - Automatisierte Performance-Audits
- **Performance Budgets** - Grenzwerte definieren und durchsetzen
- **GitHub Actions / GitLab CI** - Pipeline-Integration
- **LHCI Server** - Trend-Analyse und Dashboards

## Dateien

```
13-continuous-testing/
├── config/
│   ├── lighthouserc.js          # Lighthouse CI Konfiguration
│   └── budget.json              # Performance-Budget (standalone)
├── .github/
│   └── workflows/
│       └── lighthouse-ci.yml    # GitHub Actions Workflow
├── docker/
│   ├── docker-compose.yml       # LHCI Server Setup
│   └── .env.example             # Umgebungsvariablen
└── scripts/
    ├── lhci-shopware-auth.js    # Shopware Login-Handler
    ├── run-lighthouse.sh        # Lokaler Test-Runner
    └── budget-check.sh          # Budget-Validierung
```

## Quick Start

### 1. Lighthouse CI installieren

```bash
npm install -g @lhci/cli
```

### 2. Konfiguration kopieren

```bash
cp config/lighthouserc.js /pfad/zum/shopware-projekt/
```

### 3. Ersten Test ausführen

```bash
cd /pfad/zum/shopware-projekt
lhci autorun
```

## Performance-Budget (Empfohlen)

| Metrik | Budget | Begründung |
|--------|--------|------------|
| LCP | ≤ 2.500ms | Google Core Web Vitals |
| CLS | ≤ 0.1 | Google Core Web Vitals |
| INP | ≤ 200ms | Google Core Web Vitals |
| JavaScript | ≤ 300KB | Mobile Performance |
| CSS | ≤ 100KB | Render-Blocking |
| Performance Score | ≥ 75 | Lighthouse Mindeststandard |

## CI/CD-Integration

### GitHub Actions

1. Kopiere `.github/workflows/lighthouse-ci.yml` in dein Repository
2. Füge `LHCI_GITHUB_APP_TOKEN` als Repository Secret hinzu
3. Push auslösen

### GitLab CI

Füge den Inhalt aus dem Buch in deine `.gitlab-ci.yml` ein.

## LHCI Server (Optional)

Für Trend-Analyse und Team-Dashboards:

```bash
cd docker
cp .env.example .env
# .env anpassen (LHCI_TOKEN generieren)
docker-compose up -d
```

Dashboard: http://localhost:9001

## Shopware-spezifische Tests

Der `lhci-shopware-auth.js` ermöglicht authentifizierte Tests:

- Checkout-Prozess
- Mein Konto-Bereich
- Wunschliste

## Schwellenwerte anpassen

Die Budgets in `lighthouserc.js` und `budget.json` sind für einen typischen Shopware-Shop optimiert. Für Ihren spezifischen Shop:

1. Baseline messen: `lhci autorun` ohne Budgets
2. Realistische Ziele setzen (10-20% besser als aktuell)
3. Budgets schrittweise verschärfen

## Weiterführende Links

- [Lighthouse CI Dokumentation](https://github.com/GoogleChrome/lighthouse-ci)
- [Performance Budgets](https://web.dev/performance-budgets-101/)
- [Core Web Vitals](https://web.dev/vitals/)

## Lizenz

MIT - Frei verwendbar für kommerzielle Projekte.
