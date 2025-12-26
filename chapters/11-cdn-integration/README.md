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
| `nginx-cdn-headers.conf` | Nginx Cache-Header Konfiguration |
| `shopware-cdn.yaml` | Shopware CDN-Konfiguration |
| `bunny-pull-zone.json` | Bunny CDN Pull Zone Einstellungen |

### scripts/

| Script | Beschreibung |
|--------|--------------|
| `cdn-warmup.sh` | Cache Warming nach Deployment |
| `cloudflare-purge.sh` | Cloudflare Cache-Invalidierung |
| `bunny-purge.sh` | Bunny CDN Cache-Invalidierung |
| `cdn-test.sh` | CDN-Konfiguration testen |

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

## Weiterführende Ressourcen

- [Cloudflare Documentation](https://developers.cloudflare.com/cache/)
- [Bunny CDN Docs](https://docs.bunny.net/)
- [Shopware CDN Guide](https://developer.shopware.com/docs/guides/hosting/infrastructure/cdn.html)
- [Web.dev: CDNs](https://web.dev/articles/content-delivery-networks)
