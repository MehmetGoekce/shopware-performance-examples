# Anhang C: Konfigurationen

Die Vorlagen, die Anhang C des Buchs zeigt — jede hier im Container eingespielt
und laufen gelassen, nicht nur gelesen.

Was hier **nicht** liegt, liegt bei dem Kapitel, das es erklaert. Zweimal
dieselbe Konfiguration an zwei Stellen laeuft auseinander, und Anhaenge sind
die Stelle, an der das zuerst auffaellt:

| Thema | Datei |
|---|---|
| OPcache | `../09-php-performance/config/99-shopware-opcache.ini` |
| PHP-FPM-Pool | `../09-php-performance/config/shopware-fpm.conf` |
| Gzip | `../22-haeufigste-probleme/config/nginx-gzip.conf` |
| Logrotate | `../22-haeufigste-probleme/config/logrotate.conf` |
| Brotli | `../11-cdn-integration/config/nginx-brotli.conf` |
| Cache-Header vor einem CDN | `../11-cdn-integration/config/nginx-cdn-headers.conf` |
| Redis-Instanzen, Sentinel | `../10-redis-sentinel/config/` |
| `cache.yaml` (Redis als Application Cache) | `../07-shopware-cache/config/framework.yaml` |
| `http_cache.yaml` und `varnish.yaml` | `../06-http-cache/config/shopware.yaml` und `varnish.yaml` |

**Welches Kapitel gewinnt, wenn zwei es erklaeren.** Kanonisch ist die Vorlage
des Kapitels, das die Einstellung *erklaert* — nicht die des Kapitels, das sie
nur anwendet. Ein Kapitel, das dieselbe Zieldatei braucht, verweist auf die
kanonische Vorlage und liefert keine zweite. Grund: Zwei Vorlagen auf einer
Zieldatei ueberschreiben sich, und zwar lautlos — `php-fpm8.3 -t` und
`nginx -t` melden dabei weiter Erfolg. OPcache lag deshalb bis September 2026
doppelt vor (Kapitel 9 und Kapitel 22, beide nach
`conf.d/99-shopware-opcache.ini`); kanonisch ist jetzt Kapitel 9. Ebenso
doppelt lagen der PHP-FPM-Pool (Kapitel 9 und Anhang C, beide nach
`pool.d/shopware.conf`, MEM-288) und der nginx-vHost (Kapitel 9 und Anhang C,
beide `server_name shop.example.com` auf 443 - nginx ignoriert den zweiten mit
einer Warnung, MEM-290). Kanonisch ist beim Pool Kapitel 9, das ihn erklaert;
beim vHost dieser Anhang, denn Kapitel 9 erklaert nur dessen PHP-FPM-Teil.
Das Gate dafuer ist `tests/Shell/pool-template-drift.bats`.

## Dateien

| Datei | Ziel auf dem Server | Geprueft mit |
|---|---|---|
| `config/nginx-shopware.conf` | `/etc/nginx/sites-available/shopware.conf` | `nginx -t` (nginx 1.27.5) + Header- und ACME-Abfrage am laufenden nginx; von Hand auf `ubuntu:24.04` (nginx 1.24, `listen 443 ssl http2`) mit dem Kapitel-9-Pool: Routing, Upload bis 128M (darueber 413), Status-Listener `127.0.0.1:8081`; dasselbe in CI mit `tests/Integration/pool-vhost-boot.sh` |
| `config/mysql-shopware.cnf` | `/etc/mysql/mysql.conf.d/shopware.cnf` | `mysqld --validate-config` + Start von `mysql:8.0` auf frischem Datadir, `SHOW VARIABLES` und Groesse von `#innodb_redo` |
| `config/supervisor-shopware.conf` | `/etc/supervisor/conf.d/shopware-worker.conf` | `supervisord -n`, alle drei Prozesse erreichen RUNNING |
| `config/env.local.example` | `<shop>/.env.local` | im Testshop (Shopware 6.6.10.6) eingespielt, Shop antwortet mit 200, Keys in beiden Redis-Instanzen |

## Was die CI prueft — und was nicht

Der Job `appendix-configs` ist ein **Syntax- und Start-Gate**, kein
Verhaltens-Gate. Er faengt, was einen Dienst nicht starten laesst:

| Schritt | Faengt | Faengt nicht |
|---|---|---|
| `nginx -t` + Laufzeitabfrage | Syntaxfehler, fehlende Direktiven, dazu die drei Fallen unten als echte HTTP-Antworten | semantische Fehler ausserhalb dieser drei Pruefungen, z. B. einen Socket-Pfad, der nicht zum FPM-Pool passt |
| `mysqld --validate-config` | unbekannte Variablen und Tippfehler | Werte ausserhalb des gueltigen Bereichs (`instances = 999` geht durch) und **abgekuendigte** Direktiven — die Warnung MY-013907 erscheint erst beim echten Start |
| `supervisord -n` | Parsefehler, `numprocs` ohne `process_name`, falscher PHP-Pfad, Programme, die nicht RUNNING erreichen | Tippfehler im Shopware-Befehl selbst: der Schritt stubt `php` und `bin/console` weg, ein `messenger:consume asyncc` besteht ihn |

Fuer `config/env.local.example` gibt es kein Gate — die Datei wird von Hand im
Testshop geprueft.

## Drei Fallen, die diese Vorlagen vermeiden

**1. `expires` und `add_header Cache-Control` zusammen.** Beide Direktiven
erzeugen je einen eigenen `Cache-Control`-Header. Die Antwort traegt ihn dann
doppelt — nachgestellt an nginx 1.27.5:

```
cache-control: max-age=31536000
cache-control: public, immutable
```

**2. `add_header` in einer inneren `location`.** nginx vererbt `add_header`
nur, solange der innere Block keinen einzigen eigenen setzt. Mit einem
eigenen `add_header` faellt die komplette geerbte Liste weg — die
Security-Header des `server`-Blocks fehlen dann auf jeder CSS-, JS-, Font-
und Bildantwort. `nginx-shopware.conf` wiederholt deshalb **alle drei** in
jedem Asset-Block, auch `Referrer-Policy`.

**3. `location ~ /\. { deny all; }` trifft auch `/.well-known/`.** Gemessen:
403 statt 200 — certbot kann das Zertifikat nicht mehr erneuern, das im
selben `server`-Block eingebunden ist. Was den ACME-Block rettet, ist der
Modifier `^~`, **nicht** seine Position im File: `^~` beendet die
Location-Suche, bevor Regex-Locations geprueft werden. Mit `^~` antwortet die
Challenge auch dann mit 200, wenn der Block hinter der Punkt-Regel steht —
ohne `^~` bekommt sie 403, auch wenn er davor steht. Beides nachgestellt.

## Zwei Variablen, nicht eine

`config/packages/cache.yaml` aus Kapitel 7 referenziert `REDIS_URL` **und**
`REDIS_SESSION_URL`. Fehlt die zweite, meldet `bin/console cache:clear`
trotzdem `[OK]` — und der Shop antwortet danach auf jeden Request mit
HTTP 500. Der Fehler steht nur im `var/log/prod-*.log`:

```
Environment variable not found: "REDIS_SESSION_URL".
```

## Das RAM-Budget geht auf

Alle Zahlen gehoeren zu **einem** 16-GB-Server, auf dem alles zusammen laeuft:

| Dienst | RAM |
|---|---|
| MySQL Buffer Pool | 4 GB |
| PHP-FPM, 50 Worker à ~80 MB | 4 GB |
| Redis Cache | 4 GB |
| Redis Sessions | 1 GB |
| **Summe** | **13 GB** |

Der Rest bleibt fuer OS und Dateisystem-Cache. Die verbreiteten «70–80 % des
RAM fuer den Buffer Pool» gelten fuer einen Server, auf dem MySQL allein
laeuft — auf dieser Maschine waeren das 11 GB und der Server wuerde swappen.

## Versionen

Geprueft am 2026-09-19 gegen Shopware 6.6.10.6 (`dockware/dev:6.6.10.6`),
PHP 8.3.23, MySQL 8.0.46, Redis 7.4, nginx 1.27.5 und supervisor 4.3.0.
Gegen nginx 1.24.0 (ubuntu:24.04) lief die Vorlage am 2026-09-22 nach der
im Kopf beschriebenen http2-Anpassung zusammen mit dem Kapitel-9-Pool
(MEM-290): Routing, Upload-Grenze, Status-Listener, Header, ACME. Vollstaendige Matrix: `../../COMPATIBILITY.md`.
