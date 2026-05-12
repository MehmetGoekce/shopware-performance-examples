# Kapitel 11: CDN-Integration

Companion-Code zum Buchkapitel "CDN-Integration für globale Performance".

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

## Dateien

### config/

| Datei | Beschreibung |
|-------|--------------|
| `cloudflare-page-rules.json` | Beispiel Page Rules für Shopware |
| `nginx-cdn-headers.conf` | Nginx Cache-Header Konfiguration (inkl. HTTP/3 + Brotli-Levels) |
| `shopware-cdn.yaml` | Shopware CDN-Konfiguration (inkl. Vary-Header + Cache-Tag-Pattern) |
| `bunny-pull-zone.json` | Bunny CDN Pull Zone Einstellungen |

### src/ (PHP-Klassen — Skeleton, Production-Hardening offen)

| Klasse | Beschreibung |
|--------|--------------|
| `Service/CloudflarePurgeService.php` | Cache-Purge via API v4 (purgeByUrls / purgeByTags / purgeByHostnames / purgeEverything) |
| `EventSubscriber/MediaPurgeSubscriber.php` | Auto-Purge bei Media/Product/Category-Writes |
| `Middleware/CacheHeaderMiddleware.php` | Cache-Control + Surrogate-Control + Cache-Tag + Surrogate-Key pro Route |

### scripts/

| Script | Beschreibung |
|--------|--------------|
| `cdn-warmup.sh` | Cache Warming nach Deployment |
| `cloudflare-purge.sh` | Cloudflare Cache-Invalidierung |
| `bunny-purge.sh` | Bunny CDN Cache-Invalidierung |
| `cdn-test.sh` | CDN-Konfiguration testen |

### Root

| Datei | Beschreibung |
|-------|--------------|
| `.env.example` | Shopware/Symfony Env-Vars (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, ASSET_URL, CDN_URL) |

## Quick Start

### 1. Cloudflare einrichten

```bash
# API Token erstellen: cloudflare.com/profile/api-tokens
# Berechtigung: Zone:Cache Purge

export CLOUDFLARE_API_TOKEN="your-token"
export CLOUDFLARE_ZONE_ID="your-zone-id"

# Test
./scripts/cloudflare-purge.sh --test
```

### 2. Cache-Header prüfen

```bash
# Header einer URL prüfen
curl -I https://ihr-shop.de/media/image.jpg

# Erwartete Header:
# Cache-Control: public, max-age=31536000
# CF-Cache-Status: HIT
```

### 3. Cache Warming

```bash
# Nach Deployment Cache vorwärmen
./scripts/cdn-warmup.sh https://ihr-shop.de

# Nur kritische URLs
./scripts/cdn-warmup.sh https://ihr-shop.de --critical-only
```

## Cache-Strategie

### Empfohlene TTLs

| Content-Typ | TTL | Cache-Control |
|-------------|-----|---------------|
| Bilder (mit Hash) | 1 Jahr | `public, max-age=31536000, immutable` |
| CSS/JS (mit Hash) | 1 Jahr | `public, max-age=31536000, immutable` |
| Fonts | 1 Jahr | `public, max-age=31536000` |
| HTML (Produktseiten) | 5-60 Min | `public, max-age=300, stale-while-revalidate=60` |
| API-Responses | 0 | `private, no-store` |

### Bypass-Regeln

```
# Diese URLs NICHT cachen:
/checkout/*
/account/*
/api/*
/admin/*
/store-api/*
```

## Metriken

### Erfolgs-Indikatoren

| Metrik | Ziel | Messen mit |
|--------|------|------------|
| Cache Hit Ratio | >90% | CDN Dashboard |
| TTFB | <200ms | WebPageTest |
| Origin-Requests | <10% | Server Logs |
| Global Latenz | <100ms | Catchpoint/Pingdom |

### Cloudflare Analytics

```bash
# Cache-Statistiken via API abrufen
curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/analytics/dashboard" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json"
```

## Troubleshooting

### Cache-Miss trotz korrekter Header

```bash
# 1. Vary-Header prüfen
curl -I https://shop.de/page | grep -i vary

# Problem: Vary: Cookie verhindert Caching
# Lösung: Vary nur für nötige Header setzen
```

### Stale Content nach Deployment

```bash
# Kompletten Cache purgen
./scripts/cloudflare-purge.sh --all

# Nur bestimmte URLs
./scripts/cloudflare-purge.sh --urls "/media/*,/theme/*"
```

### CORS-Fehler mit CDN

```bash
# Origin prüfen
curl -I -H "Origin: https://shop.de" https://cdn.shop.de/font.woff2

# Access-Control-Allow-Origin muss gesetzt sein
```

## Cache-Tag-Pattern (Cloudflare auf allen Plans seit 2026)

Tag-basierter Purge ist seit 2026 auf ALLEN Cloudflare-Plans (Free, Pro,
Business, Enterprise) verfügbar — Rate-Limits skalieren aber pro Tier:

| Plan | Rate-Limit | Use-Case |
|------|------------|----------|
| Free | 5/min | Hobby-Shops, niedriges Purge-Volumen |
| Pro | 5/s | KMU mit moderatem Edit-Volumen |
| Business | 10/s | Hochfrequente Updates (Preis-Sync) |
| Enterprise | 50/s | Mass-Updates, Multi-Sales-Channel |

Quelle: [Cloudflare Cache-Purge-Doku](https://developers.cloudflare.com/cache/how-to/purge-cache/).

`CloudflarePurgeService::purgeByTags(['product-123'])` invalidiert alle
Responses mit `Cache-Tag: product-123` in einem Call — egal ob die als
Produktdetailseite, Kategorie-Listing oder Suchresultat ausgespielt
werden. Voraussetzung: `CacheHeaderMiddleware` (oder eigener Subscriber)
emittiert die `Cache-Tag`-Header am Origin.

## Shopware 6.7.6 Caching-Rework (Q1 2026)

Wer von Shopware 6.6 auf 6.7.6+ upgradet, sollte CDN-Page-Rules
auditieren: alte "No-Cache wenn `sw-states`-Cookie gesetzt"-Regeln
werden obsolet (cookie wird deprecated). Mit aktivem `CACHE_REWORK`-
Feature-Flag werden eingeloggte User und gefüllte Carts standardmäßig
cachebar. Siehe Buch Kap 11.4 "Forward-Hinweis Shopware 6.7.6".

## Weiterführende Ressourcen

- [Cloudflare Documentation](https://developers.cloudflare.com/cache/)
- [Cloudflare Cache-Purge](https://developers.cloudflare.com/cache/how-to/purge-cache/)
- [Bunny CDN Docs](https://docs.bunny.net/)
- [Shopware CDN Guide](https://developer.shopware.com/docs/guides/hosting/infrastructure/cdn.html)
- [Shopware Caching Concepts](https://developer.shopware.com/docs/concepts/framework/http_cache.html)
- [Shopware New Caching System (6.7.6)](https://www.shopware.com/en/news/new-caching-system/)
- [Cloudflare Workers Module Format](https://developers.cloudflare.com/workers/reference/migrate-to-module-workers/)
- [Web.dev: CDNs](https://web.dev/articles/content-delivery-networks)
