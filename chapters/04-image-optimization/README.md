# Kapitel 4: Bildoptimierung

Code-Beispiele und Tools für Tag 3-4 der 30-Tage-Roadmap.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/image-analysis.js` | DevTools-Snippet zur Bildgrößen-Analyse |
| `scripts/optimize-images.sh` | Bash-Skript für Bulk-Optimierung |
| `templates/cms-element-image.html.twig` | CMS-Bild mit Lazy Loading Steuerung |
| `templates/sw-thumbnails-examples.html.twig` | sw_thumbnails Best Practices |
| `config/frosh_thumbnail.yaml` | FroshPlatformThumbnailProcessor Config |

## Verwendung

### Bildgrößen im Frontend analysieren

Öffnen Sie Chrome DevTools (F12) → Console:

```javascript
// Kopieren Sie den Inhalt von scripts/image-analysis.js
```

### Bilder vor Upload optimieren

```bash
# Skript ausführbar machen
chmod +x scripts/optimize-images.sh

# Alle Bilder in einem Ordner optimieren
./scripts/optimize-images.sh /pfad/zu/bildern
```

### FroshThumbnailProcessor installieren

```bash
composer require frosh/platform-thumbnail-processor
bin/console plugin:refresh
bin/console plugin:install --activate FroshPlatformThumbnailProcessor

# Konfiguration kopieren
cp config/frosh_thumbnail.yaml /pfad/zu/shop/config/packages/
```

## Bildformat-Vergleich

| Format | Kompression vs. JPEG | Browser-Support |
|--------|---------------------|-----------------|
| **WebP** | 25-34% kleiner | ~96% |
| **AVIF** | 35-50% kleiner | ~94% |

## Shopware Thumbnail-Größen (Standard)

| Größe | Verwendung |
|-------|------------|
| 400×400 | Produktboxen, Warenkorb |
| 800×800 | Produktdetail (Mobile) |
| 1920×1920 | Hero-Bilder, Produktdetail (Desktop) |

## Quick Wins Checkliste

- [ ] Bildgrößen im Frontend analysiert
- [ ] Unnötige Thumbnail-Größen entfernt
- [ ] WebP aktiviert (FroshThumbnailProcessor)
- [ ] `sw_thumbnails` mit `sizes`-Attribut
- [ ] Hero-Bilder: `loading="eager"` + `fetchpriority="high"`
- [ ] Below-the-fold: `loading="lazy"`

## Quellen

- [Web Almanac 2024 - Page Weight](https://almanac.httparchive.org/en/2024/page-weight)
- [Google WebP Study](https://developers.google.com/speed/webp/docs/webp_study)
- [caniuse: WebP](https://caniuse.com/webp)
- [caniuse: AVIF](https://caniuse.com/avif)
- [Shopware Docs: Media](https://developer.shopware.com/docs/guides/plugins/plugins/content/media)
