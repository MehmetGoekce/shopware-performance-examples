# Kapitel 2: Performance-Audit

Werkzeuge für die Bestandsaufnahme. Beide Skripte lesen nur und ändern nichts.
Getestet mit Shopware 6.6.10.6 (Dockware, Demo-Daten).

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/audit.sh` | Bestandsaufnahme auf dem Server: Versionen, Plugins, HTTP-Cache, OPcache (FPM), Message Queue, Redis/Suche, grosse Bilder |
| `scripts/analyze-images.sh` | Originalbilder nach Format zählen, grösste über einer Schwelle auflisten |
| `templates/AUDIT-TEMPLATE.md` | Vorlage für das Audit-Protokoll |

Konfigurationen stehen dort, wo das Buch sie begründet und testet — dieses
Kapitel findet Probleme, die Lösung steht im jeweiligen Kapitel:

| Thema | Datei |
|-------|-------|
| HTTP-Cache | Kapitel 6, `chapters/06-http-cache/` |
| Slow Query Log | Kapitel 8, `chapters/08-database/config/shopware.cnf` |
| OPcache, PHP-FPM | Kapitel 9, `chapters/09-php-performance/` |
| CLI-Worker (Supervisor) | Anhang C, `chapters/anhang-c-konfigurationen/config/supervisor-shopware.conf` |

## Verwendung

### Bestandsaufnahme

Als der Benutzer aufrufen, unter dem der Shop läuft:

```bash
sudo -u www-data ./chapters/02-performance-audit/scripts/audit.sh /var/www/shopware

# Mit Abruf-Test gegen die laufende Seite (zwei Abrufe als Gast, Age > 0 = Treffer)
SHOP_URL=https://ihr-shop.ch sudo -E -u www-data \
  ./chapters/02-performance-audit/scripts/audit.sh /var/www/shopware
```

Was das Skript anders macht als die naheliegenden Einzeiler:

- `plugin:list --active` gibt es nicht (Exit 1); `plugin:list | wc -l` zählt die
  Tabellenrahmen mit. Das Skript liest `plugin:list --json`.
- `debug:config shopware http_cache` bricht in `APP_ENV=prod` mit «frozen
  ParameterBag» ab, und `shopware.http_cache` hat keinen Schlüssel `enabled`.
  Das Skript liest `debug:dotenv` und prüft optional die Antwort-Header.
- `php -i` zeigt die CLI-Konfiguration. Das Skript fragt jede gefundene
  `php-fpmX.Y -i`.
- `ps aux | grep messenger:consume` findet sich selbst. Das Skript zählt mit
  `pgrep -fc` auf die PHP-Kommandozeile.
- `messenger:stats` schreibt seine Tabelle auf stderr.

### Bilder

```bash
./chapters/02-performance-audit/scripts/analyze-images.sh /var/www/shopware/public/media 500
```

`public/media` enthält die Originale; ausgeliefert werden meist die Thumbnails
aus `public/thumbnail`. Bildoptimierung: Kapitel 4.

## Tests

```bash
docker run --rm -v "$PWD:/code" -w /code bats/bats:latest tests/Shell/audit-scripts.bats
```

## Quellen

- [TTFB (web.dev)](https://web.dev/articles/ttfb)
- [Core Web Vitals (web.dev)](https://web.dev/articles/vitals)
- [Lighthouse Scoring](https://developer.chrome.com/docs/lighthouse/performance/performance-scoring)
- [Frosh Tools (GitHub)](https://github.com/FriendsOfShopware/FroshTools)
