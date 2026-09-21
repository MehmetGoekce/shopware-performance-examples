# Kapitel 9: PHP-Performance optimieren

Companion-Code zum Buch **"Shop-Performance in 30 Tagen"**

## Inhalt

### config/
- `99-shopware-opcache.ini` - OPcache-Konfiguration fuer Shopware 6.
  **Die kanonische OPcache-Vorlage des Companions.** Kapitel 22 (Problem 12)
  und Anhang C verweisen hierher und liefern keine eigene Fassung.
- `99-shopware.ini` - php.ini-Einstellungen fuer FPM
- `99-shopware-cli.ini` - php.ini-Einstellungen fuer CLI
- `shopware-fpm.conf` - PHP-FPM Pool-Konfiguration
- `nginx-php-fpm.conf` - Nginx-Upstream plus Vorlage fuer die location-Bloecke
- `nginx-shopware-vhost.conf` - vollstaendiger vHost, der diesen Upstream nutzt
- `frankenphp-Caddyfile.example` - Evaluierungs-Skelett, kein Production-Setup

### scripts/
- `opcache-status.php` - OPcache-Monitoring (gehaertet)
- `php-fpm-memory.sh` - RSS je Worker messen
- `calculate-max-children.sh` - pm.max_children berechnen
- `jit-benchmark.sh` - JIT A/B-Test mit Laufzeit-Gegenprobe
- `preload.example.php` - OPcache-Preload-Vorlage

## Schnellstart

### 1. OPcache konfigurieren

```bash
# Konfiguration kopieren - beachten Sie den Dateinamen!
sudo cp config/99-shopware-opcache.ini /etc/php/8.3/fpm/conf.d/
sudo chmod 644 /etc/php/8.3/fpm/conf.d/99-shopware-opcache.ini

sudo systemctl reload php8.3-fpm

# Pruefen - in der FPM-SAPI, nicht in der CLI:
php-fpm8.3 -m | grep -i 'zend opcache'
php-fpm8.3 -i | grep -E '^opcache\.(enable|memory_consumption|max_accelerated_files) =>'
```

> **Nicht nach `10-opcache.ini` kopieren.** Dieser Name ist auf Debian und
> Ubuntu bereits vergeben: Die Datei ist ein Symlink der Distribution auf
> `/etc/php/8.3/mods-available/opcache.ini`, und **nur dort** steht
> `zend_extension=opcache.so`. Wer sie ueberschreibt, laedt die Erweiterung
> nicht mehr - OPcache ist dann komplett aus, obwohl in der Konfiguration
> `opcache.enable=1` steht. `cp` folgt dabei dem Symlink und ueberschreibt die
> gemeinsame Datei - auch der CLI fehlt die Erweiterung danach. `php-fpm8.3 -t` meldet trotzdem
> "test is successful", der Ausfall ist also lautlos.

> **`php -i | grep opcache` beantwortet die Frage nicht.** CLI und FPM lesen
> auf Debian und Ubuntu verschiedene `conf.d`-Verzeichnisse; `php --ini`
> durchsucht nur `/etc/php/8.3/cli/conf.d`. Eine Datei unter `fpm/conf.d/` -
> genau dort liegt die OPcache-Konfiguration - sieht `php -i` nie.

### 2. PHP-FPM dimensionieren

```bash
# RSS je Worker am LAUFENDEN, warmen Shop messen
./scripts/php-fpm-memory.sh

# Damit rechnen (Vorgabewerte = Beispielserver des Buchs, 16 GB)
./scripts/calculate-max-children.sh -w 82

# PHP-Einstellungen fuer die FPM-SAPI - NICHT auslassen: hier stehen u. a.
# upload_max_filesize und post_max_size auf 128M. Ohne diese Datei bleibt es
# bei PHPs Vorgabe 2M bzw. 8M, denn der Pool unten setzt beides nicht.
sudo cp config/99-shopware.ini /etc/php/8.3/fpm/conf.d/

# Pool einspielen
sudo cp config/shopware-fpm.conf /etc/php/8.3/fpm/pool.d/shopware.conf
sudo mkdir -p /var/log/php-fpm && sudo chown www-data:www-data /var/log/php-fpm
sudo php-fpm8.3 -t && sudo systemctl restart php8.3-fpm

# Webserver: Upstream global, vHost je Shop
sudo cp config/nginx-php-fpm.conf /etc/nginx/conf.d/php-fpm.conf
sudo cp config/nginx-shopware-vhost.conf /etc/nginx/sites-available/shopware
sudo ln -s /etc/nginx/sites-available/shopware /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Gegenprobe: die Statusseite muss von FPM kommen, nicht aus dem Shop
curl -s http://127.0.0.1:8080/fpm-status | head -3
```

Zwei Dinge, die sonst schiefgehen:

- **Das Logverzeichnis legt PHP-FPM nicht selbst an.** Fehlt `/var/log/php-fpm`,
  startet FPM gar nicht: `Unable to create or open slowlog(...)`.
- **Den mitgelieferten Pool `www.conf` abschalten.** Sonst laeuft ein zweiter
  Pool mit, den niemand anspricht: ab Werk zwei Worker im Leerlauf, hoechstens
  fuenf, ausserhalb jeder RAM-Rechnung - und was Sie in `www.conf` eintragen,
  wirkt nicht auf den Shopware-Pool.

### 3. Monitoring einrichten

```bash
# Ablage AUSSERHALB von public/
sudo mkdir -p /var/www/shopware/private
sudo cp scripts/opcache-status.php /var/www/shopware/private/

# Aufruf ueber die CLI zeigt den OPcache DER CLI - fuer die FPM-Zahlen
# entweder eine eigene nginx-Location (siehe Kopfkommentar der Datei) oder:
cachetool opcache:status --fcgi=/run/php/php8.3-fpm-shopware.sock
```

Das Skript gibt Cache-Internals preis (Speicherauslastung, Trefferquote,
Dateizahlen). Es gehoert **nicht** nach `public/`.

### 4. JIT messen, bevor Sie ihn einschalten

```bash
# Ungecachte Route nehmen - die Startseite misst den HTTP-Cache, nicht PHP
sudo ./scripts/jit-benchmark.sh -u https://ihr-shop.example/account/login \
     -d /var/www/shopware/public
```

Das Skript bricht ab, wenn Xdebug oder pcov geladen sind: Beide ueberschreiben
`zend_execute_ex()`, und PHP schaltet JIT dann still ab - die Messung waere ein
Vergleich von "aus" mit "aus".

## Gemessene Werte

Alle Zahlen aus **einem** Aufbau: Dockware 6.6.10.6 mit Demo-Daten, lokale
Datenbank, ein Container auf einem Notebook, Route `/account/login`
(`Cache-Control: no-store`), 250 Requests bei Nebenlaeufigkeit 4. Kein
Lasttest. Auf einem Shop mit echter Datenmenge faellt der CPU-Anteil kleiner
aus - messen Sie Ihre eigenen Werte.

| Messung | Ergebnis |
|---------|----------|
| OPcache eines warmen Storefronts | 2278 Skripte, 58,6 MB von 256 MB |
| RSS je Worker, warm | 79-86 MB (kalt: rund 16 MB) |
| JIT aus -> tracing, Median aus 14 Paaren | 56,5 -> 62,5 req/s (+10 %) |
| pcov geladen -> entladen, JIT in beiden Armen aus | 42,6 -> 57,3 req/s (+35 %) |
| Preload von `vendor/symfony` + `vendor/doctrine` | 4306 Dateien, 2985 Klassen, 31,2 MB, +2,4 s Startzeit |

Der groesste einzelne Gewinn in dieser Messreihe war nicht JIT, sondern das
Entfernen einer Coverage-Erweiterung aus der Produktionskonfiguration.

## Voraussetzungen

- Ubuntu 22.04/24.04 oder Debian 12
- PHP 8.3 (empfohlen). Shopware 6.6 ist mit 8.2, 8.3 und 8.4 kompatibel;
  PHP 8.4 ist seit November 2024 erschienen.
- Root-Zugriff fuer Konfigurationsaenderungen
- Apache Benchmark (`ab`) fuer den JIT-Test: `sudo apt install apache2-utils`

> Alle Pfade verwenden `/etc/php/8.3/...`. Fuer PHP 8.4 sind sie analog
> (`/etc/php/8.4/...`); die Direktiven sind identisch.

## Referenzen

- [Tideways: OPcache Configuration](https://tideways.com/profiler/blog/fine-tune-your-opcache-configuration-to-avoid-caching-suprises)
- [Tideways: PHP-FPM Tuning](https://tideways.com/profiler/blog/an-introduction-to-php-fpm-tuning)
- [PHP-Handbuch: OPcache-Konfiguration](https://www.php.net/manual/en/opcache.configuration.php)
- [Shopware Requirements (6.6)](https://developer.shopware.com/docs/v6.6/guides/installation/requirements.html)
