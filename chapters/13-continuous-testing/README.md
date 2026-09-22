# Kapitel 13: Continuous Performance Testing

Companion-Code zum Buch "Shop-Performance in 30 Tagen".

Lighthouse CI misst einen **laufenden Shop** (Staging oder Preview), nicht den
Code im CI-Runner. Ein `php -S` im Runner hat keine Datenbank und keine Domain
und liefert CSS/JS unkomprimiert aus. Die Grössen-Budgets würden dann den
Server messen: `storefront.js` kam mit 235 statt 76 KB an.

Getestet mit `@lhci/cli` 0.15.1 (Lighthouse 12.6.1), Shopware 6.6.10.6
(Dockware, Demo-Daten), `patrickhulce/lhci-server:0.15.1`, k6 v2.3.0,
Locust 2.46.6.

## Dateien

```
13-continuous-testing/
├── config/
│   ├── lighthouserc.cjs          # Basis: 3 Seiten, Budgets, Median-Lauf
│   ├── lighthouserc.matrix.cjs   # 5 Seiten, Grenzen je Seitentyp (assertMatrix)
│   ├── lighthouserc.auth.cjs     # Konto-Seiten hinter dem Login
│   └── budget.json               # Alternative zu den Assertions (alles "error")
├── scripts/
│   ├── lhci-shopware-auth.cjs    # Login vor jeder URL (puppeteerScript)
│   ├── loadtest-k6.js            # Lasttest k6
│   └── locustfile.py             # Lasttest Locust
├── .github/workflows/
│   ├── lighthouse-ci.yml         # Pull Request gegen LHCI_BASE_URL, PR-Kommentar
│   └── lighthouse-staging.yml    # nach jedem Deployment, Slack, LHCI-Server
├── gitlab/.gitlab-ci.yml         # GitLab-Job
└── docker/docker-compose.yml     # LHCI-Server mit Basic Auth
```

Die Konfigurationen sind `.cjs`: In einem Projekt mit `"type": "module"` in der
`package.json` lädt eine `lighthouserc.js` mit `module.exports` nicht.

## Schnellstart

```bash
npm install -g @lhci/cli@0.15.1
cp config/lighthouserc.cjs /pfad/zum/projekt/

cd /pfad/zum/projekt
LHCI_BASE_URL=https://staging.ihr-shop.ch lhci autorun
```

Nie `npx lhci …` ohne installiertes `@lhci/cli`: npx lädt dann das fremde
npm-Paket `lhci`, das nichts prüft und mit Exit 0 endet. Ein Gate damit ist
immer grün.

Die Pfade in `lighthouserc.cjs` an den eigenen Shop anpassen: Kategorie und
Produkt über die SEO-URL, `/navigation/<name>` und `/detail/<name>` antworten
mit 400.

## Was die Konfiguration entscheidet

- `aggregationMethod: 'median-run'`: Ohne diese Zeile wertet LHCI bei
  Obergrenzen den **besten** von drei Läufen.
- `resource-summary:script:count` steht auf 30: Shopware 6.6 lädt ab Werk 16
  (Startseite) bis 25 (Kategorie, Produkt) Skripte.
- `upload.target: 'filesystem'` schreibt `.lighthouseci/manifest.json`; daraus
  baut der Workflow den PR-Kommentar.
- `budget.json` geht nur **statt** der Assertions (`--budgetsFile`), nicht
  zusätzlich, und macht jede Grenze zu `error`.

## Seiten hinter dem Login

```bash
npm install --save-dev puppeteer
SHOPWARE_TEST_EMAIL=… SHOPWARE_TEST_PASSWORD=… \
LHCI_BASE_URL=https://staging.ihr-shop.ch lhci autorun --config=config/lighthouserc.auth.cjs
```

Ein eigenes Testkonto auf Staging verwenden. Das Skript läuft vor jeder URL; ab
der zweiten ist der Browser schon eingeloggt und es tippt nichts mehr.

## CI

**GitHub:** Workflow nach `.github/workflows/` kopieren, `lighthouserc.cjs` ins
Repository-Root, Variable `LHCI_BASE_URL` setzen und den Job `lighthouse` als
Required Check eintragen. Der Stand des Pull Requests muss unter der URL
deployt sein.

**GitLab:** `gitlab/.gitlab-ci.yml` übernehmen, CI/CD-Variable `LHCI_BASE_URL`.

## LHCI-Server

```bash
cd docker
LHCI_PASSWORD=… docker compose up -d
docker compose exec lhci-server npx lhci wizard   # Server-URL: http://localhost:9001
```

Der Wizard gibt den Build-Token aus; ihn als Secret `LHCI_TOKEN` hinterlegen.
Für den Zugriff aus der CI gehört ein Reverse-Proxy mit TLS vor den Port.

## Lasttests

```bash
k6 run -e BASE_URL=https://staging.ihr-shop.ch scripts/loadtest-k6.js
locust -f scripts/locustfile.py --host=https://staging.ihr-shop.ch
```

k6 endet mit Exit 99, wenn eine Schwelle reisst; Locust hat keine Schwellen.
Nie gegen Production.

## Lizenz

MIT
