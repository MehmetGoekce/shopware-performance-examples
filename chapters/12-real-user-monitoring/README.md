# Kapitel 12: Real User Monitoring (RUM)

Companion-Code zum Buchkapitel "Real User Monitoring (RUM)": ein kleines
Shopware-Plugin, das die Web Vitals echter Besucher misst, in eine Log-Datei
schreibt und auswertet.

Getestet mit Shopware 6.6.10.6 und 6.7.2.2 (Dockware, Demo-Daten), web-vitals
6.2.2, Chromium, Firefox und WebKit (Playwright).

## Ablauf

```
Browser                          Shop                              Betrieb
------------------------------   -------------------------------   ---------------------------
rum.js + web-vitals 6.2.2   -->  POST /api/rum (RumController) -->  bin/console rum:report
LCP, INP, CLS, FCP, TTFB         var/log/rum-YYYY-MM-DD.log         bin/console rum:check-alerts
je Metrik ein sendBeacon         eine JSON-Zeile pro Metrik         (cron, optional Webhook)
```

## Dateien

| Datei | Zweck |
|-------|-------|
| `RumMonitoring/src/Resources/views/storefront/layout/meta.html.twig` | bindet `rum.js` in `layout_head_javascript_tracking` ein, nur mit `APP_ENV=prod` und Stichprobe > 0 |
| `RumMonitoring/src/Resources/public/rum.js` | meldet jede Metrik per `navigator.sendBeacon` an `/api/rum` |
| `RumMonitoring/src/Resources/public/rum-payload.js` | baut den Beacon (Route, Pfad, Attributions-Ziel, Geraeteklasse) |
| `RumMonitoring/src/Resources/public/web-vitals.attribution.js` | web-vitals 6.2.2, byte-gleich mit `dist/` im npm-Paket (Apache-2.0, Lizenz in `web-vitals.LICENSE.txt`) |
| `RumMonitoring/src/Controller/RumController.php` | `POST /api/rum`, prueft den Beacon und schreibt eine Log-Zeile |
| `RumMonitoring/src/Rum/RumPayload.php` | Validierung: nur bekannte Metriken, kein Query-String, keine IP, kein User-Agent |
| `RumMonitoring/src/Rum/RumStatistics.php` | p50/p75/p90 (Nearest-Rank) und Bewertung nach Googles Schwellen |
| `RumMonitoring/src/Rum/RumLogReader.php` | liest `rum-*.log` im Zeitfenster zeilenweise |
| `RumMonitoring/src/Command/RumReportCommand.php` | `rum:report` |
| `RumMonitoring/src/Command/RumCheckAlertsCommand.php` | `rum:check-alerts` |
| `RumMonitoring/src/Resources/config/packages/monolog.yaml` | Log-Kanal `rum` (JSON, taeglich rotiert, 30 Dateien) |
| `RumMonitoring/src/Resources/config/config.xml` | Plugin-Einstellung "Stichprobe" |

## Installation

```bash
cp -r RumMonitoring /var/www/shop/custom/plugins/
cd /var/www/shop
bin/console plugin:refresh
bin/console plugin:install --activate RumMonitoring   # kopiert auch rum.js nach public/bundles/
bin/console cache:clear
```

Danach im Browser eine Seite oeffnen, klicken, den Tab wechseln. Im Netzwerk-Tab
stehen bis zu fuenf `POST /api/rum` mit Status 204, in `var/log/` liegt
`rum-<datum>.log`.

**Stichprobe:** Administration > Erweiterungen > Meine Erweiterungen > RUM Monitoring >
Konfigurieren, oder `bin/console system:config:set RumMonitoring.config.sampleRate 0.1 --json`
(ohne `--json` wird der Wert als Text gespeichert). `1` misst jeden
Seitenaufruf, `0.1` jeden zehnten, `0` schaltet das Skript ab. Gewuerfelt wird
einmal je Seitenaufruf, damit die Metriken eines Aufrufs zusammenbleiben.

## Auswertung

```bash
bin/console rum:report                    # letzte 24 Stunden
bin/console rum:report --hours=168 --by=route
bin/console rum:report --by=device        # mobile / desktop (Viewport < 768 px)
bin/console rum:report --by=country       # nur hinter Cloudflare (Header CF-IPCountry)
```

Beispiel mit vier LCP- und vier INP-Werten aus dem Test:

```
+--------+------+---------+-------+-------+-------+-------------------+
| Metrik | alle | Samples | p50   | p75   | p90   | p75-Bewertung     |
+--------+------+---------+-------+-------+-------+-------------------+
| INP    | *    | 4       | 210   | 220   | 600   | needs-improvement |
| LCP    | *    | 4       | 2000  | 2500  | 3000  | good              |
+--------+------+---------+-------+-------+-------+-------------------+
```

p75 wie bei Google: der Wert, unter oder auf dem 75 % der Seitenaufrufe liegen.
Genau auf der Schwelle gilt als "good" (LCP 2500 ms, INP 200 ms, CLS 0.1).

## Alerts

```bash
# /etc/cron.d/rum-alerts
*/15 * * * * www-data cd /var/www/shop && bin/console rum:check-alerts
```

`rum:check-alerts` prueft LCP, INP und CLS der letzten Stunde, sobald mindestens
100 Samples vorliegen (`--hours`, `--min-samples`). Jede Metrik, deren p75 nicht
"good" ist, wird gemeldet:

- ohne `RUM_ALERT_WEBHOOK`: als Ausgabe - cron verschickt sie per Mail
- mit `RUM_ALERT_WEBHOOK=https://hooks.slack.com/services/...` in der `.env`:
  als `{"text": "..."}` per POST (Format der Slack Incoming Webhooks). Antwortet
  der Webhook nicht mit 2xx, gibt der Befehl Meldung und Fehler aus und endet mit
  Exit 1.

Solange alles gut ist, bleibt der Befehl still - sonst kaeme alle 15 Minuten eine
Mail. `-v` zeigt die Messwerte.

## Was man wissen muss

- **Warum `/api/rum`:** Shopware lehnt jede Route ohne `_routeScope` mit 412
  "Invalid route scope" ab. Der Controller nutzt den API-Scope mit
  `auth_required: false` wie `/api/_info/health-check`: keine Anmeldung, keine
  Session. Eine Storefront-Route (`/rum`) ginge auch, startet aber fuer jeden
  Beacon ohne Cookie eine neue Session. Wer `/api` am Proxy auf Admin-IPs
  beschraenkt, muss `POST /api/rum` freigeben.
- **CLS nur in Chromium.** Firefox und WebKit melden FCP, TTFB, LCP und INP,
  aber kein CLS (web-vitals-README "Browser Support", im Test bestaetigt).
- **Assets von einem CDN-Host:** `rum.js` ist ein Modul-Skript, und Modul-Skripte
  laedt der Browser fremder Herkunft nur mit CORS. Liefert das CDN keinen
  `Access-Control-Allow-Origin`-Header, laeuft das Skript nicht.
- **Datenschutz:** Geloggt werden Metrik, Wert, Route, Pfad ohne Query-String,
  CSS-Selektor des verursachenden Elements, Geraeteklasse und - nur hinter
  Cloudflare - das Land. Keine IP, kein User-Agent; rum.js setzt keine Cookies.
  Ob Sie dafuer eine Einwilligung brauchen, klaeren Sie mit Ihrer
  Datenschutzberatung.
- **Log-Dateien:** `rotating_file` schreibt `rum-YYYY-MM-DD.log`, nie `rum.log`.
  Nach 30 Tagen loescht Monolog die aelteste Datei.

## web-vitals aktualisieren

```bash
npm pack web-vitals@<version>
tar xzf web-vitals-<version>.tgz
cp package/dist/web-vitals.attribution.js RumMonitoring/src/Resources/public/
```

Vorher `docs/upgrading-to-v<major>.md` im web-vitals-Repo lesen: v4 hat
`resourceLoadTime` in `resourceLoadDuration` umbenannt, v5 `LCPAttribution.element`
in `target` und `onFID()` entfernt. `rum-payload.js` liest die Felder von v5/v6.

## Tests

```bash
vendor/bin/phpunit --filter RumMonitoringTest          # Validierung, Perzentile, Log-Leser
npx vitest run tests/JavaScript/rum-payload.test.js    # Beacon-Aufbau, Attribution, Stichprobe
```

## Weiterfuehrende Ressourcen

- [web-vitals Library](https://github.com/GoogleChrome/web-vitals)
- [Defining the Core Web Vitals metrics thresholds](https://web.dev/articles/defining-core-web-vitals-thresholds)
- [Chrome UX Report](https://developer.chrome.com/docs/crux/)
