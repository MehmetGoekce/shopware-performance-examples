# Anhang C: Konfigurationen

Die Vorlagen, die Anhang C des Buchs zeigt — jede hier im Container geprueft,
jede mit einem Gate in der CI.

Was hier **nicht** liegt, liegt bei dem Kapitel, das es erklaert. Zweimal
dieselbe Konfiguration an zwei Stellen laeuft auseinander, und Anhaenge sind
die Stelle, an der das zuerst auffaellt:

| Thema | Datei |
|---|---|
| OPcache | `../22-haeufigste-probleme/config/php-opcache.ini` |
| Gzip | `../22-haeufigste-probleme/config/nginx-gzip.conf` |
| Logrotate | `../22-haeufigste-probleme/config/logrotate.conf` |
| Brotli | `../11-cdn-integration/config/nginx-brotli.conf` |
| Cache-Header vor einem CDN | `../11-cdn-integration/config/nginx-cdn-headers.conf` |
| Redis-Instanzen, Sentinel | `../10-redis-sentinel/config/` |
| `cache.yaml` (Redis als Application Cache) | `../07-shopware-cache/config/framework.yaml` |
| `varnish.yaml`, `http_cache.yaml` | `../06-http-cache/config/` |

## Dateien

| Datei | Ziel auf dem Server | Geprueft mit |
|---|---|---|
| `config/nginx-shopware.conf` | `/etc/nginx/sites-available/shopware.conf` | `nginx -t` (nginx 1.27) + Header-Abfrage am laufenden nginx |
| `config/php-fpm-pool.conf` | `/etc/php/8.3/fpm/pool.d/shopware.conf` | `php-fpm -t` + FastCGI-Request (`cgi-fcgi`) gegen `php:8.3-fpm` |
| `config/mysql-shopware.cnf` | `/etc/mysql/mysql.conf.d/shopware.cnf` | `mysqld --validate-config` + Start von `mysql:8.0` mit `SHOW VARIABLES` |
| `config/supervisor-shopware.conf` | `/etc/supervisor/conf.d/shopware-worker.conf` | `supervisord -n` startet alle drei Prozesse |
| `config/env.local.example` | `<shop>/.env.local` | im Testshop (Shopware 6.6.10.6) eingespielt, Shop antwortet mit 200 |

## Drei Fallen, die diese Vorlagen vermeiden

**1. `expires` und `add_header Cache-Control` zusammen.** Beide Direktiven
erzeugen je einen eigenen `Cache-Control`-Header. Die Antwort traegt ihn dann
doppelt — nachgestellt an nginx 1.27:

```
cache-control: max-age=31536000
cache-control: public, immutable
```

**2. `add_header` in einer inneren `location`.** nginx vererbt `add_header`
nur, solange der innere Block keinen einzigen eigenen setzt. Mit einem
eigenen `add_header` faellt die komplette geerbte Liste weg — die
Security-Header des `server`-Blocks fehlen dann auf jeder CSS-, JS-, Font-
und Bildantwort. `nginx-shopware.conf` wiederholt sie deshalb in jedem
Asset-Block.

**3. `location ~ /\. { deny all; }` ohne Ausnahme.** Die Regel trifft auch
`/.well-known/acme-challenge/`. Gemessen: 403 statt 200 — certbot kann das
Zertifikat nicht mehr erneuern, das im selben `server`-Block eingebunden ist.

## Zwei Variablen, nicht eine

`config/packages/cache.yaml` aus Kapitel 7 referenziert `REDIS_URL` **und**
`REDIS_SESSION_URL`. Fehlt die zweite, meldet `bin/console cache:clear`
trotzdem `[OK]` — und der Shop antwortet danach auf jeden Request mit
HTTP 500. Der Fehler steht nur im `var/log/prod-*.log`:

```
Environment variable not found: "REDIS_SESSION_URL".
```

## Versionen

Geprueft am 2026-09-19 gegen Shopware 6.6.10.6 (`dockware/dev:6.6.10.6`),
PHP 8.3.23, MySQL 8.0.46, Redis 7.4, nginx 1.27.5 und 1.24.0, supervisor 4.2.
Vollstaendige Matrix: `../../COMPATIBILITY.md`.
