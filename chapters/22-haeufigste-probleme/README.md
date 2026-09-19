# Kapitel 22: Die 20 häufigsten Performance-Probleme — Companion Code

Diagnose-Skripte und Konfigurationsvorlagen zu den 20 Problemen aus Kapitel 22.

Alle Skripte **messen und lesen nur**. Keines ändert etwas am Shop, keines
kompiliert ein Theme, keines schreibt in die Datenbank. Sie sind dafür
gedacht, auf einem Produktivsystem gefahrlos zu laufen.

Getestet gegen **Shopware 6.6.10.6** (Dockware, PHP 8.3, MySQL 8.0, Apache
2.4, Redis 7.4).

## Aufruf

Alle Skripte nehmen dieselben zwei Argumente, in dieser Reihenfolge:

```bash
./scripts/<skript>.sh [SHOP_URL] [SHOP_PATH]
```

* `SHOP_URL` — Basis-URL des Shops, Default `http://localhost`
* `SHOP_PATH` — Wurzel der Shopware-Installation, Default `.`

Skripte, die nur eines von beiden brauchen, nehmen das andere trotzdem
entgegen und werten es nicht aus. So kann `run-all-diagnostics.sh` alle
gleich aufrufen.

Jedes Skript kennt `--help`. Die Exit-Codes sind einheitlich:

| Code | Bedeutung |
|---|---|
| 0 | unauffällig |
| 1 | etwas gefunden, das man sich ansehen sollte |
| 64 | Aufruffehler (falsche Argumente) |
| 69 | Voraussetzung fehlt (z. B. `jq`, `mysql`, keine FPM-Binary) |

## Die 20 Probleme

| # | Problem | Skript |
|---|---------|--------|
| 1 | Langsame DB-Queries | `diagnose-slow-queries.sh` |
| 2 | HTTP-Cache nicht aktiv | `check-http-cache.sh` |
| 3 | Grosse JavaScript-Bundles | `analyze-bundles.sh` |
| 4 | Unoptimierte Bilder | `check-images.sh` |
| 5 | Fehlende Preconnects | `audit-preconnects.sh` |
| 6 | Render-Blocking CSS | `check-render-blocking.sh` |
| 7 | N+1-Queries | `detect-n1-queries.sh` |
| 8 | Session-Lock | `test-session-lock.sh` |
| 9 | Warenkorb-Berechnung | `profile-cart.sh` |
| 10 | Zu viele Plugins | `audit-plugins.sh` |
| 11 | Elasticsearch nicht konfiguriert | `check-elasticsearch.sh` |
| 12 | OPcache nicht aktiviert | `check-opcache.sh` |
| 13 | Debug-Modus in Produktion | `check-debug-mode.sh` |
| 14 | Fehlende Kompression | `check-compression.sh` |
| 15 | Cronjobs und Worker | `analyze-cronjobs.sh` |
| 16 | Theme-Probleme | `audit-themes.sh` |
| 17 | Grosse Log-Dateien | `check-logs.sh` |
| 18 | Kein CDN | `check-cdn.sh` |
| 19 | Synchrone API-Calls | `detect-sync-calls.sh` |
| 20 | Fehlende Browser-Cache-Header | `check-cache-headers.sh` |

Dazu zwei Skripte, die alle anderen aufrufen:

| Skript | Zweck |
|---|---|
| `run-all-diagnostics.sh` | Alle 20 Prüfungen nacheinander, mit Kurzfassung am Ende |
| `generate-report.sh` | Dasselbe als Markdown-Report nach stdout |

## Konfigurationsvorlagen

| Datei | Wofür |
|---|---|
| `config/shopware-cache.yaml` | HTTP-Cache und Cache-Backend (Problem 2) |
| `config/redis-session.yaml` | Sessions in eine eigene Redis-Instanz (Problem 8) |
| `config/php-opcache.ini` | OPcache für PHP-FPM (Problem 12) |
| `config/nginx-gzip.conf` | Kompression unter Nginx (Problem 14) |
| `config/apache-compression.conf` | Kompression und Ablaufzeiten unter Apache (Problem 14, 20) |
| `config/logrotate.conf` | Log-Aufbewahrung (Problem 17) — mit der Warnung, dass sie meist gar nicht nötig ist |

Die Vorlagen sind kommentiert und erklären jeweils, **warum** ein Wert so
gesetzt ist. Wer nur die Werte kopiert, verliert den wichtigeren Teil.

**Nach dem Kopieren die Dateirechte prüfen.** Eine Datei in
`config/packages/` oder in `conf.d/`, die der PHP-Benutzer nicht lesen darf,
führt je nach Ort zu einem HTTP 500 oder wird stillschweigend ignoriert:

```bash
sudo chmod 644 <zieldatei>
```

## Schnellstart

```bash
cd chapters/22-haeufigste-probleme
chmod +x scripts/*.sh

# Alles auf einmal
./scripts/run-all-diagnostics.sh https://ihr-shop.example /var/www/shopware

# Einzelnes Problem
./scripts/check-http-cache.sh https://ihr-shop.example /var/www/shopware

# Als Report
./scripts/generate-report.sh https://ihr-shop.example /var/www/shopware \
    > performance-report.md
```

Ausführlicher: `QUICKSTART.md`.

## Voraussetzungen

| Werkzeug | Wofür | Ohne es |
|---|---|---|
| `bash` 4.0+, `curl` | alle Skripte | nichts läuft |
| `php` | `audit-plugins.sh`, `check-elasticsearch.sh`, `analyze-cronjobs.sh` | Abschnitte entfallen |
| `mysql`-Client | `diagnose-slow-queries.sh`, `audit-themes.sh`, `profile-cart.sh` | Exit 69 bzw. Abschnitt entfällt |
| `jq` | `audit-plugins.sh` | Exit 69 |
| `php-fpm<version>` | `check-opcache.sh` | Exit 69 mit Hinweis auf den Web-Weg |

Nicht nötig: Node.js, npm, Composer. Der Ordner enthält kein JavaScript und
kein installierbares Plugin.

## Warum keine Punktzahl

`run-all-diagnostics.sh` gibt bewusst keinen „Performance Score" aus. Die
Prüfungen sind weder gleich gewichtet noch unabhängig voneinander: ein
abgeschalteter HTTP-Cache wiegt schwerer als ein fehlender Preconnect, und in
einer Prozentzahl zählten beide gleich viel. Eine solche Zahl sieht nach
Messung aus und ist doch nur eine Zählung.

Aus demselben Grund stehen in den Skripten keine Versprechen der Form
„HTTP-Cache aktivieren spart 50 % TTFB". Was eine Massnahme im konkreten Shop
bringt, zeigt nur eine Messung vorher und nachher an derselben URL.

## Lizenz

MIT. Frei verwendbar für kommerzielle und private Projekte.

## Weiterführend

* Kapitel 22 im Buch „Shop-Performance in 30 Tagen"
* [Shopware Performance Documentation](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html)
* [memotech.ch/performance-check](https://memotech.ch/performance-check)
