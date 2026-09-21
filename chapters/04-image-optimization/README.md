# Kapitel 4: Bildoptimierung

Code-Beispiele für Tag 3-4 der 30-Tage-Roadmap. Getestet gegen Shopware 6.6.10.6 (Dockware, prod) mit Chromium; `optimize-images.sh` zusätzlich unter Ubuntu 24.04 (ImageMagick 6, pngquant, cwebp aus `apt`).

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/image-analysis.js` | DevTools-Snippet: gewählte srcset-Datei, benötigte gegen echte Pixelbreite, KB, `loading` |
| `scripts/optimize-images.sh` | Bilder vor dem Upload verkleinern und komprimieren – Originale bleiben unangetastet |
| `src/Resources/views/storefront/component/product/card/box-standard.html.twig` | `sizes` der Produktbox an die echte Bildbreite anpassen |

Das Twig-Override gehört in Ihr Theme oder Plugin unter denselben Pfad, danach `bin/console cache:clear`. Das LCP-Bild (Hero) behandelt Kapitel 3 (`chapters/03-core-web-vitals/`).

## Verwendung

### Bild-Analyse

Seite im Browser laden, bis zum Ende scrollen (lazy Bilder laden erst dann), Inhalt von `scripts/image-analysis.js` in die DevTools-Console einfügen. Spalte `Faktor`: Dateibreite geteilt durch benötigte Breite (CSS-Breite × Pixeldichte). Werte über 1,5 bedeuten eine zu grosse Datei.

### Bilder vor dem Upload optimieren

```bash
sudo apt install imagemagick pngquant webp
./scripts/optimize-images.sh --dry-run ./fotos ./fotos-optimiert
./scripts/optimize-images.sh --webp ./fotos ./fotos-optimiert
```

Verkleinert auf höchstens 2000 × 2000 px, wendet die EXIF-Drehung an und entfernt EXIF/IPTC/XMP, behält das ICC-Farbprofil, JPEG mit Qualität 80 (progressiv), PNG über pngquant. Mit `--webp` entsteht je Bild zusätzlich eine WebP-Datei. Shopware erzeugt Thumbnails im Format des hochgeladenen Originals: ein WebP-Original ergibt WebP-Thumbnails, ohne Plugin.

## Was dieses Kapitel bewusst nicht mitliefert

- **Keine YAML-Konfiguration für `FroshPlatformThumbnailProcessor`.** Das Plugin hat keinen Symfony-Konfigurationszweig; eine Datei `config/packages/frosh_thumbnail.yaml` lässt `cache:clear` scheitern und die Storefront mit HTTP 500 antworten (getestet). Konfiguriert wird es in der Administration – und es braucht einen Bilddienst dahinter, sonst liefert jede srcset-Stufe das Original.

## Quellen

- [Shopware: Media](https://developer.shopware.com/docs/guides/plugins/plugins/content/media/)
- [Shopware: Remote Thumbnail Generation](https://developer.shopware.com/docs/guides/plugins/plugins/content/media/remote-thumbnail-generation.html)
- [FroshPlatformThumbnailProcessor](https://github.com/FriendsOfShopware/FroshPlatformThumbnailProcessor)
- [Web Almanac 2024 - Page Weight](https://almanac.httparchive.org/en/2024/page-weight)
