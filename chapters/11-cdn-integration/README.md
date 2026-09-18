# Kapitel 11: CDN-Integration

Companion-Code zum Buchkapitel «CDN-Integration für globale Performance».
Getestet gegen **Shopware 6.6.10.6** (Dockware, `APP_ENV=prod`, nginx 1.18).

## Architektur

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Besucher  │────▶│    CDN      │────▶│   Origin    │
│  (weltweit) │◀────│ Edge-Server │◀────│  (Frankfurt)│
└─────────────┘     └─────────────┘     └─────────────┘
                         │
                    ┌────┴────┐
                    │  Cache  │
                    │ (lokal) │
                    └─────────┘
```

## Was Shopware selbst macht — und was nicht

Drei Punkte, die den Rest dieses Verzeichnisses erklären (alle im Testshop gemessen):

1. **Ohne Reverse Proxy cached kein CDN HTML.** Shopware sendet an jede
   Storefront-Antwort `Cache-Control: no-cache, private` (`CacheControlListener`).
   Mit `reverse_proxy.enabled: true` wird daraus `public, s-maxage=7200`.
2. **Der Schutz personalisierter Antworten liegt beim Proxy.** Shopware sendet
   zusätzlich `sw-invalidation-states: logged-in,cart-filled` und setzt bei
   Login oder gefülltem Warenkorb die Cookies `sw-states` und `sw-cache-hash`.
   Wer diese Cookies am Edge nicht auswertet, cached Zustände mit, die nicht
   geteilt werden dürfen. Varnish erledigt das mit der offiziellen VCL, ein CDN
   braucht dafür eine eigene Bypass-Regel.
3. **Shopware sendet nie einen `Cache-Tag`-Header.** Die Tags kommen als `xkey`
   (Varnish) bzw. `surrogate-key` (Fastly). Gemessen: Produktseite 139 Tags /
   4963 Bytes. Für Cloudflare übersetzt `CdnCacheTagSubscriber` sie.

## Dateien

### config/

| Datei | Beschreibung |
|-------|--------------|
| `nginx-cdn-headers.conf` | Cache-Header **nur für statische Assets**; ergänzt die Shopware-nginx-Config, ersetzt sie nicht |
| `shopware-cdn.yaml` | Assets auf die CDN-Domain (`public`, `theme`, `asset`, `sitemap`) + kommentierte Reverse-Proxy-Sektion |
| `cloudflare-page-rules.json` | Drei Asset-Regeln (= Free-Limit) |
| `bunny-pull-zone.json` | Pull-Zone mit `IgnoreQueryStrings: false` |

### src/

| Klasse | Beschreibung |
|--------|--------------|
| `Service/CloudflarePurgeService.php` | Purge via API v4, zerlegt Listen in 100er-Blöcke |
| `EventSubscriber/CdnCacheTagSubscriber.php` | Übersetzt Shopwares `xkey` in einen `Cache-Tag`-Header |
| `EventSubscriber/CdnPurgeSubscriber.php` | Purge bei `product.written` / `category.written` |
| `Resources/config/services.xml` | Service-Definitionen (Namespace `YourPlugin` anpassen) |

### scripts/

| Script | Beschreibung |
|--------|--------------|
| `cdn-test.sh` | Prüft Status, Cache-Header, CORS, Bypass |
| `cdn-warmup.sh` | Warmup inkl. Auflösung von sitemapindex und `.xml.gz` |
| `cloudflare-purge.sh` | Purge nach URL, Tag, Prefix oder komplett |
| `bunny-purge.sh` | Bunny-Pull-Zone-Purge |

## Quick Start

```bash
export CLOUDFLARE_API_TOKEN="..."   # Zone > Cache Purge > Purge
export CLOUDFLARE_ZONE_ID="..."

./scripts/cloudflare-purge.sh --test
./scripts/cdn-test.sh https://ihr-shop.de
./scripts/cdn-warmup.sh https://ihr-shop.de --all
```

`cdn-warmup.sh` wärmt immer nur den PoP, der dem ausführenden Rechner am
nächsten liegt — ein Runner in Frankfurt wärmt nicht Singapur.

## Cache-Strategie

| Content-Typ | TTL | Cache-Control |
|-------------|-----|---------------|
| Theme-Assets (`/theme/`) | 1 Jahr | `public, max-age=31536000, immutable` |
| Bundle-Assets (`/bundles/`) | 1 Jahr | `public, max-age=31536000, immutable` |
| Medien, Thumbnails | 1 Jahr | `public, max-age=31536000, immutable` |
| HTML | Shopware entscheidet | `public, s-maxage=<SHOPWARE_HTTP_DEFAULT_TTL>` (nur mit Reverse Proxy) |
| Checkout, Konto, Store-API | nicht cachen | von Shopware gesetzt, keine nginx-Regel nötig |

**Versionierung:** Theme-Assets liegen unter einem Hash-Pfad, tragen aber
zusätzlich `?<lastModified>`; Bundle-Assets werden **ausschliesslich** über den
Query-String versioniert; Medien haben den Upload-Timestamp im Pfad **und**
`?ts=`. Der CDN-Cache-Key muss den Query-String deshalb enthalten.

## Invalidierung

Alle Purge-Arten (URL, Hostname, Tag, Prefix, Everything) sind auf **allen**
Cloudflare-Plans verfügbar; nur die Rate-Limits unterscheiden sich:

| Plan | Rate-Limit | Max. Operationen pro Request |
|------|-----------|------------------------------|
| Free | 5/min | 100 |
| Pro | 5/s | 100 |
| Business | 10/s | 100 |
| Enterprise | 50/s | 100 (Single-File-Purge 500) |

```bash
# Vollqualifizierte URLs, keine Wildcards
./scripts/cloudflare-purge.sh --urls 'https://shop.de/media/a.jpg'

# Statt Wildcards: Prefix
./scripts/cloudflare-purge.sh --prefixes 'shop.de/theme/,shop.de/bundles/'

# Per Tag (setzt CdnCacheTagSubscriber voraus)
./scripts/cloudflare-purge.sh --tags 'product-abc123'
```

`Cache-Tag`-Grenzen: Header max. 16 KB (~1.000 Tags), komma-separiert, keine
Leerzeichen im Tag, max. 100 Tags pro Purge-Request.

Listing-Seiten und Suchergebnisse taggt Shopware nicht («List-type routes are
not tagged with all entities returned in the response … These routes instead
rely on their TTL») — sie laufen über die TTL ab, nicht über den Purge.

## Messwerte und Ziele

Cache-Hit-Rate und Origin-Anteil hängen von Sortiment, Traffic-Mix und TTL ab.
Als Orientierung, nicht als Zielvorgabe: liegt die Hit-Rate für statische Assets
unter 80 %, stimmt meist etwas an den Cache-Headern oder am Cache-Key nicht.

## Troubleshooting

| Symptom | Ursache |
|---------|---------|
| Checkout/Konto/Store-API liefern 404 | nginx-Location ohne `try_files`/`fastcgi_pass` |
| nginx startet nicht: `duplicate location "/"` | Buch-Block zusätzlich zu Shopwares `location /` eingefügt |
| Zwei `Cache-Control`-Header | `expires` **und** `add_header Cache-Control` im selben Block |
| `HTTP 500` nach dem Einspielen der CDN-Config | `url` ohne `type` unter `shopware.filesystem.*` |
| Theme-Assets bleiben auf der Shop-Domain | nur `public` gesetzt, `theme`/`asset`/`sitemap` fehlen |
| `HTTP 500` nach Aktivieren des Reverse Proxy | Default `redis_url: redis://redis` — Gateway explizit wählen |
| `cache:clear` bricht ab | Reverse Proxy aktiv, `BAN /` an `reverse_proxy.hosts` bleibt unbeantwortet |
| Altes Plugin-JS trotz Update | CDN ignoriert Query-Strings (`IgnoreQueryStrings: true`) |

## Quellen

- https://developer.shopware.com/docs/concepts/framework/http_cache.html
- https://developer.shopware.com/docs/guides/hosting/infrastructure/filesystem.html
- https://developers.cloudflare.com/cache/how-to/purge-cache/
- https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-tags/
- https://nginx.org/en/docs/http/ngx_http_core_module.html#location
