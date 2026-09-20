# Kapitel 22: Quickstart

Schnellstart für die Diagnose-Skripte zu den 20 häufigsten
Performance-Problemen.

Alle Skripte lesen nur. Sie ändern nichts am Shop und können auf einem
Produktivsystem laufen.

## Alles auf einmal

```bash
cd chapters/22-haeufigste-probleme
chmod +x scripts/*.sh

./scripts/run-all-diagnostics.sh https://ihr-shop.example /var/www/shopware
```

Die Reihenfolge der Argumente ist bei jedem Skript gleich: erst die URL,
dann der Pfad zur Installation.

## Die fünf Prüfungen, die am häufigsten etwas finden

### 1. Debug-Modus

```bash
./scripts/check-debug-mode.sh https://ihr-shop.example /var/www/shopware
```

Ein Shop, der versehentlich in `APP_ENV=dev` läuft, ist der mit Abstand
grösste Einzelfund. Sofort-Fix:

```bash
cd /var/www/shopware
printf 'APP_ENV=prod\nAPP_DEBUG=0\n' >> .env.local
bin/console cache:clear:all
bin/console assets:install
bin/console theme:compile --keep-assets --sync
bin/console cache:warmup
```

Existiert eine `.env.local.php` (aus `composer dump-env prod`), hat sie
**Vorrang** vor `.env.local`. Dann dort ändern oder die Datei neu erzeugen.

### 2. HTTP-Cache

```bash
./scripts/check-http-cache.sh https://ihr-shop.example /var/www/shopware
```

**Erwartet:** ein `Age`-Header, der über zwei Requests hinweg wächst.

**Nicht erwartet:** `Cache-Control: public, max-age=…`. Eine
Shopware-6.6-Storefront antwortet dem Browser immer mit
`Cache-Control: no-cache, private` — auch bei einem Cache-Treffer. Wer auf
diesen Header prüft, hält jeden korrekt konfigurierten Shop für defekt.

### 3. OPcache

```bash
./scripts/check-opcache.sh
```

Das Skript misst die **FPM**-SAPI, nicht die CLI. `php -i | grep opcache`
zeigt unter Debian/Ubuntu die falsche `php.ini`, und in der CLI ist OPcache
wegen `opcache.enable_cli=0` ohnehin meist gar nicht aktiv.

### 4. Kompression

```bash
./scripts/check-compression.sh https://ihr-shop.example
```

Das Skript holt die echten CSS- und JS-URLs aus dem HTML. Geratene Pfade wie
`/bundles/storefront/assets/js/storefront.js` gibt es in 6.6 nicht; sie
liefern eine 404-Seite, und die ist klein und unkomprimiert — also ein
falsches „keine Kompression".

Häufigster echter Fund: Shopware liefert sein JS als `text/javascript` aus.
Eine `gzip_types`- oder `mod_deflate`-Liste, die nur `application/javascript`
nennt, lässt ausgerechnet die grösste Datei unkomprimiert.

### 5. Sessions

```bash
./scripts/test-session-lock.sh https://ihr-shop.example /var/www/shopware
```

Misst zwei gleichzeitige Requests **derselben** Session gegen dieselben zwei
nacheinander. Dauert parallel fast so lange wie sequenziell, werden die
Requests serialisiert — der `files`-Save-Handler sperrt die Session.

## Konfigurationsvorlagen einspielen

```bash
SHOP=/var/www/shopware
PHPV=8.3   # "php -v" zeigt die installierte Version

# OPcache — NICHT nach 10-opcache.ini kopieren, das ist der Symlink der
# Distribution und traegt als einziger zend_extension=opcache.so.
sudo cp config/php-opcache.ini /etc/php/${PHPV}/fpm/conf.d/99-shopware-opcache.ini
sudo chmod 644 /etc/php/${PHPV}/fpm/conf.d/99-shopware-opcache.ini
sudo systemctl reload php${PHPV}-fpm

# Kompression, Nginx
sudo cp config/nginx-gzip.conf /etc/nginx/conf.d/
sudo nginx -t && sudo systemctl reload nginx

# Kompression und Ablaufzeiten, Apache
# NICHT zwischen "# BEGIN Shopware" und "# END Shopware" einfügen —
# alles dazwischen erzeugt Shopware neu und überschreibt es dabei.
sudo cp config/apache-compression.conf /etc/apache2/conf-available/
sudo a2enconf apache-compression && sudo systemctl reload apache2

# WebP-Auslieferung, Apache: Inhalt VOR "# BEGIN Shopware" in die
# public/.htaccess einfügen. Dahinter wirkt die Regel nicht — Shopwares
# Block liefert existierende Dateien mit [L] aus.
# Unter Nginx entsprechend config/nginx-webp.conf.
cat config/apache-webp.conf   # von Hand einsetzen, kein cp

# Shopware HTTP-Cache
sudo cp config/shopware-cache.yaml ${SHOP}/config/packages/
sudo chmod 644 ${SHOP}/config/packages/shopware-cache.yaml
sudo -u www-data bin/console cache:clear
```

**Das `chmod 644` nicht überspringen.** Eine Datei in `config/packages/`, die
der PHP-Benutzer nicht lesen darf, lässt den Container-Build mit
`does not contain valid YAML: … cannot be read` abbrechen — der Shop
antwortet dann mit HTTP 500. Eine Datei in `conf.d/` mit denselben Rechten
wird dagegen **stillschweigend** ignoriert: kein Fehler, die Werte gelten
einfach nicht.

## Ergebnis lesen

`run-all-diagnostics.sh` gibt keine Punktzahl aus, sondern drei Listen:

* **unauffällig** — hier ist nichts zu tun.
* **etwas gefunden** — das Einzelskript aufrufen, es erklärt den Fund.
* **nicht ausführbar** — meist eine fehlende Voraussetzung (`jq`, `mysql`).

Eine Prozentzahl gäbe es nur um den Preis, einen abgeschalteten HTTP-Cache
und einen fehlenden Preconnect gleich schwer zu wiegen. Deshalb steht dort
keine.

## Nächste Schritte

1. Die Funde durchgehen und nach erwartetem Aufwand-Nutzen-Verhältnis
   sortieren — nicht nach Reihenfolge der Ausgabe.
2. Den zugehörigen Abschnitt in Kapitel 22 lesen. Dort steht, warum ein Fund
   ein Problem ist und was er nicht ist.
3. Eine Änderung nach der anderen umsetzen und jeweils messen. Wer drei
   Dinge gleichzeitig ändert, weiss hinterher nicht, welches gewirkt hat.
4. Diagnose wiederholen.

---

**Professionelles Audit:** [memotech.ch/performance-check](https://memotech.ch/performance-check)
