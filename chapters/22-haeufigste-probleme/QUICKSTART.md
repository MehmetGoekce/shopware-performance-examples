# Kapitel 22: Quickstart Guide

Schnellstart für die Diagnose-Scripts zu den 20 häufigsten Performance-Problemen.

## 5-Minuten-Diagnose

```bash
cd chapters/22-haeufigste-probleme

# Scripts ausführbar machen
chmod +x scripts/*.sh

# Alle Diagnosen ausführen
./scripts/run-all-diagnostics.sh https://ihr-shop.de /pfad/zu/shopware
```

## Die Top 5 Quick-Checks

### 1. Debug-Modus prüfen (Kritisch!)

```bash
./scripts/check-debug-mode.sh . /pfad/zu/shopware
```

**Sofort-Fix:**
```bash
echo "APP_ENV=prod" >> .env.local
echo "APP_DEBUG=0" >> .env.local
bin/console cache:clear
```

### 2. HTTP-Cache prüfen

```bash
./scripts/check-http-cache.sh https://ihr-shop.de
```

**Erwartet:** `Cache-Control: public, max-age=...`

### 3. OPcache prüfen

```bash
./scripts/check-opcache.sh
```

**Erwartet:** `opcache.enable=1`, `validate_timestamps=0`

### 4. Gzip-Kompression prüfen

```bash
./scripts/check-compression.sh https://ihr-shop.de
```

**Erwartet:** `Content-Encoding: gzip`

### 5. Plugin-Anzahl prüfen

```bash
./scripts/audit-plugins.sh . /pfad/zu/shopware
```

**Grenze:** Max. 30 aktive Plugins

## Config-Vorlagen kopieren

```bash
# OPcache optimal konfigurieren
sudo cp config/php-opcache.ini /etc/php/8.2/fpm/conf.d/10-opcache.ini
sudo systemctl reload php8.2-fpm

# Nginx Gzip aktivieren
sudo cp config/nginx-gzip.conf /etc/nginx/conf.d/
sudo nginx -t && sudo systemctl reload nginx

# Apache Gzip aktivieren
cat config/apache-compression.conf >> /var/www/shopware/.htaccess

# Shopware HTTP-Cache
cp config/shopware-cache.yaml /var/www/shopware/config/packages/
bin/console cache:clear
```

## Ergebnis interpretieren

| Score | Bewertung | Aktion |
|-------|-----------|--------|
| 80-100% | Excellent | Nur Fine-Tuning nötig |
| 60-79% | Gut | 3-5 Probleme beheben |
| 40-59% | Mittel | Systematisch optimieren |
| 0-39% | Kritisch | Sofort handeln! |

## Nächste Schritte

1. Probleme nach Impact priorisieren
2. Kapitel 22 im Buch lesen
3. Lösungen implementieren
4. Diagnose wiederholen

---

**Professionelles Audit:** [memotech.ch/performance-audit](https://memotech.ch/performance-audit)
