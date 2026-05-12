# Kapitel 9: PHP-Performance optimieren

Companion-Code zum Buch **"Shop-Performance in 30 Tagen"**

## Inhalt

Dieses Verzeichnis enthält alle PHP-Konfigurationen und Scripts aus Kapitel 9:

### config/
- `99-shopware-opcache.ini` - OPcache-Konfiguration fuer Shopware 6
- `99-shopware.ini` - php.ini Einstellungen fuer FPM
- `99-shopware-cli.ini` - php.ini Einstellungen fuer CLI
- `shopware-fpm.conf` - PHP-FPM Pool-Konfiguration
- `nginx-php-fpm.conf` - Nginx FastCGI-Konfiguration

### scripts/
- `opcache-status.php` - OPcache-Monitoring Script
- `php-fpm-memory.sh` - Worker-Speicherverbrauch messen
- `calculate-max-children.sh` - pm.max_children berechnen
- `jit-benchmark.sh` - JIT A/B-Test durchfuehren

## Schnellstart

### 1. OPcache konfigurieren

```bash
# Konfiguration kopieren
sudo cp config/99-shopware-opcache.ini /etc/php/8.3/fpm/conf.d/

# PHP-FPM neustarten
sudo systemctl reload php8.3-fpm

# Status pruefen
php -r "print_r(opcache_get_status(false));"
```

### 2. PHP-FPM dimensionieren

```bash
# Worker-Speicher messen
./scripts/php-fpm-memory.sh

# Optimale Worker-Anzahl berechnen
# VORHER: Werte in calculate-max-children.sh anpassen!
./scripts/calculate-max-children.sh

# Pool-Konfiguration anpassen und aktivieren
sudo cp config/shopware-fpm.conf /etc/php/8.3/fpm/pool.d/
sudo systemctl reload php8.3-fpm
```

### 3. Monitoring einrichten

```bash
# OPcache-Status Script installieren
cp scripts/opcache-status.php /var/www/shopware/public/

# WICHTIG: Zugriff einschraenken! (nur localhost)
# Nginx-Konfiguration pruefen
```

## Typische Ergebnisse

| Metrik | Standard-PHP | Optimiert |
|--------|--------------|-----------|
| OPcache Hit Rate | 80-90% | 99%+ |
| Requests/Sekunde | 100 | 120-145 |
| Memory pro Worker | 150MB+ | 80-120MB |

## Voraussetzungen

- Ubuntu 22.04/24.04 oder Debian 12
- PHP 8.3 (empfohlen, LTS-Stable) - PHP 8.2 lauffaehig, PHP 8.4 ab Jan 2026 GA und in Verbindung mit aktuellen Plugins einsetzbar
- Root-Zugriff (fuer Konfigurationsaenderungen)
- Apache Benchmark (`ab`) fuer JIT-Tests

> Hinweis: Alle Pfade in diesem Verzeichnis verwenden `/etc/php/8.3/...`. Fuer PHP 8.4 sind die Pfade analog (`/etc/php/8.4/...`); die Konfigurations-Direktiven sind identisch.

## Referenzen

- [Tideways: OPcache Configuration](https://tideways.com/profiler/blog/fine-tune-your-opcache-configuration-to-avoid-caching-suprises)
- [Tideways: PHP-FPM Tuning](https://tideways.com/profiler/blog/an-introduction-to-php-fpm-tuning)
- [Kinsta: PHP Benchmarks](https://kinsta.com/blog/php-benchmarks/)
- [Shopware Requirements](https://developer.shopware.com/docs/guides/installation/requirements.html)
