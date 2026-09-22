# Kapitel 6: HTTP-Caching

Code-Beispiele und Konfigurationen aus Kapitel 6 des Buches "Shop-Performance in 30 Tagen".

Gilt für **Shopware 6.6** (getestet mit 6.6.10.6) und im Wesentlichen für 6.7. Mit 6.8 kommt
eine neue Cache-Architektur (in 6.7.6 bereits experimentell hinter `CACHE_REWORK`).

## Inhalt

```
06-http-cache/
├── README.md                           # Diese Datei
├── config/
│   ├── shopware.yaml                   # Globale HTTP-Cache-Optionen (stale-*, Tracking-Parameter, Invalidierung)
│   ├── varnish.yaml                    # Shopware hinter Varnish mit xkey (6.6 und 6.7)
│   └── varnish.vcl                     # Kommentierte Lern-VCL mit xkey, Währungs-Cookie, ESI
├── scripts/
│   ├── cache-debug.sh                  # Prüft, ob eine URL aus dem Cache kommt
│   ├── cache-warmup.sh                 # Wärmt den Cache aus der Sitemap auf
│   └── cache-hit-rate.sh               # Hit-Rate aus varnishstat oder Access-Log
└── src/
    ├── Controller/
    │   ├── CacheableController.php     # Routen mit _httpCache und eigener TTL
    │   └── EsiWidgetController.php     # ESI-Fragment mit eigener TTL und Cache-Tag
    └── Resources/config/
        ├── services.xml                # Controller-Services inkl. setContainer/setTwig
        └── routes.xml                  # Lädt die Routen-Attribute
```

Die Controller nutzen den Platzhalter-Namespace `YourPlugin` und Templates unter `@YourPlugin/storefront/...`.
Beides beim Übernehmen in ein eigenes Plugin anpassen; die Twig-Templates selbst sind nicht enthalten.

## Wie der HTTP-Cache in Shopware 6.6 funktioniert

- **Ab Werk aktiv** (`SHOPWARE_HTTP_CACHE_ENABLED=1`, `SHOPWARE_HTTP_DEFAULT_TTL=7200`).
- **Nur in `APP_ENV=prod`.** In `dev` liegt der Cache nur im Arbeitsspeicher des Requests, es gibt nie einen Treffer.
- **Die Route entscheidet.** Gecacht wird nur, was den Routen-Default `_httpCache` hat
  (`true` oder `['maxAge' => 300]`). `$response->setSharedMaxAge()` allein reicht nicht.
- **Eingeloggte Kunden und Besucher mit Warenkorb** gehen am Cache vorbei (Cookie `sw-states`).
- **Cache-Key:** URL plus Cookie `sw-cache-hash` (nur für eingeloggte Kunden und Besucher mit Warenkorb;
  enthält Regeln, Währung, Steuerstatus ...) bzw. `sw-currency` (Gast hat die Währung gewechselt).
- **ESI** funktioniert auch ohne Varnish: Der eingebaute Cache löst `<esi:include>` selbst auf und
  speichert Fragmente als eigene Einträge mit eigener TTL.
- **`stale_while_revalidate`/`stale_if_error`** sind ab Werk nicht gesetzt. Sie wirken im eingebauten Cache;
  Varnish kennt `stale-if-error` nicht, und `config/varnish.vcl` setzt Grace selbst.
- **Ohne Reverse Proxy** sieht der Browser immer `Cache-Control: no-cache, private`. Der eingebaute
  Cache arbeitet trotzdem, erkennbar nur an `Age` und an der Antwortzeit.

## Schnellstart: eingebauter Cache

```bash
# .env bzw. Umgebung des Webservers (nicht nur der CLI!)
APP_ENV=prod

bin/console cache:clear

# Prüfen: zweiter Aufruf deutlich schneller?
./scripts/cache-debug.sh https://ihr-shop.ch / /kategorie/
```

## Varnish

1. `config/varnish.vcl` anpassen (Backend, ACL `purgers`) und laden,
   oder das offizielle Image [ghcr.io/shopware/varnish](https://github.com/shopware/varnish-shopware) nutzen
2. `config/varnish.yaml` nach `config/packages/varnish.yaml` kopieren, `hosts` eintragen
3. `bin/console cache:clear`

```bash
./scripts/cache-debug.sh https://ihr-shop.ch /
# X-Cache: HIT, Cache-Control für HTML: no-store (gewollt: der Browser soll HTML nicht selbst cachen)
```

Invalidierung: Speichert jemand ein Produkt, schickt Shopware einen `PURGE` mit Header
`xkey: product-<id> ...` an Varnish. `bin/console cache:clear:http` (ab 6.6.10.0) schickt einen
`BAN` für den ganzen Cache. In 6.6 macht `cache:clear` das ebenfalls; ab 6.7 leert `cache:clear`
den HTTP-Cache nicht mehr, im Deploy dann `cache:clear:http` explizit aufrufen.

### VCL-Syntax prüfen

```bash
docker run --rm --entrypoint varnishd \
  -v "$PWD/config/varnish.vcl:/etc/varnish/default.vcl:ro" \
  ghcr.io/shopware/varnish:6.7 -C -f /etc/varnish/default.vcl > /dev/null
```

Das Image ersetzt beim normalen Start Platzhalter per `sed -i` in `/etc/varnish/default.vcl`.
Eigene VCL deshalb per eigenem Image oder `docker cp` einbringen, nicht als einzelne Datei mounten.

## Hit-Rate messen

```bash
# Varnish-Zähler (im Container: VARNISHSTAT_CMD="docker exec varnish varnishstat")
./scripts/cache-hit-rate.sh --varnishstat

# Genauer: Log mit Handling (hit/miss/pass) als letztem Feld
varnishncsa -F '%h %t "%r" %s %b %{Varnish:handling}x' -w /var/log/varnish/cache.log
./scripts/cache-hit-rate.sh /var/log/varnish/cache.log
```

`varnishstat` zählt Besucher mit Login oder Warenkorb, die die VCL in `vcl_hit` auf Pass schickt,
als `cache_hit` mit. Die Quote aus den Zählern ist dann zu hoch.

## Getestet

Alle Dateien wurden gegen `dockware/dev:6.6.10.6` mit `ghcr.io/shopware/varnish:6.7` (Varnish 8.0.2) geprüft:
HIT/MISS, xkey-PURGE nach Preis- und Bestandsänderung, BAN bei `cache:clear:http`,
Währungs-Cookie, Pass bei Login und Warenkorb, ESI-Fragment mit eigener TTL (mit Varnish und im
eingebauten Cache), Tracking-Parameter (auch Werte mit `+` und mehrere hintereinander),
Sitemap-Warmup, `cache-debug.sh` gegen beide Betriebsarten. Mit dem Filesystem-Cache liessen parallele
Warmup-Aufrufe direkt nach `cache:clear` 3-9 von 21 Seiten kalt, mit dem zweiten Durchgang des Skripts
(ab `--parallel 2`) keine; mit Varnish, Redis und in 6.7.2.2 trat es nicht auf. Die CI kompiliert die VCL und führt
die BATS-Tests (`tests/Shell/http-cache-scripts.bats`) bei jedem Push aus.

## Weiterführende Links

- [Shopware Docs: HTTP Cache](https://developer.shopware.com/docs/concepts/framework/http_cache.html)
- [Shopware Varnish Docker Image](https://github.com/shopware/varnish-shopware)
- [Varnish xkey vmod](https://github.com/varnish/varnish-modules/blob/master/src/vmod_xkey.vcc)
- [web.dev - stale-while-revalidate](https://web.dev/articles/stale-while-revalidate)

## Lizenz

MIT - Siehe [LICENSE](../../LICENSE)
