# Kapitel 1: Der Performance-Imperativ

Code-Beispiele für das Einführungskapitel.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `../../src/Subscriber/HttpCacheSubscriber.php` | HTTP-Cache-Header Subscriber |
| `../../src/Service/PerformanceRoiCalculator.php` | ROI-Berechnung für Performance |

## HTTP-Cache-Header (Case Study)

Aus der Case Study im Buch: Aggressive Cache-Header reduzierten die Backend-Last um 70%.

```php
// Kurzform aus dem Buch:
$response->headers->set(
    'Cache-Control',
    'public, max-age=300, stale-while-revalidate=86400'
);
$response->headers->set('Surrogate-Control', 'max-age=3600');
```

Der vollständige `HttpCacheSubscriber` im Repository:
- Unterscheidet nach Seitentyp (Produkt, Kategorie, Home, CMS)
- Exkludiert Checkout und Account-Seiten
- Setzt `Vary`-Header für korrektes Caching
- Unterstützt CDN/Varnish via `Surrogate-Control`

## ROI-Berechnung (Modellrechnung)

Die Modellrechnung aus dem Buch als ausführbarer Code:

```php
use PerformanceExamples\Service\PerformanceRoiCalculator;

$calculator = new PerformanceRoiCalculator();
$report = $calculator->generateSampleReport();

// Ergebnis:
// Bei einer Investition von CHF 12.600 ergibt sich ein zusätzlicher
// Jahresumsatz von CHF 1.200.000 (ROI: 9.423%).
```

### Formel

Basierend auf der Deloitte/Google Studie "Milliseconds Make Millions" (2020):

```
Conversion-Steigerung = (Verbesserung in 100ms) × 8.4%

Beispiel:
- Aktuelle Ladezeit: 4.8s
- Ziel-Ladezeit: 2.0s
- Verbesserung: 2.8s = 28 × 100ms
- Conversion-Lift: 28 × 8.4% = ~235% (theoretisch)
- Konservativ geschätzt: +15% (realistisch)
```

## Verwendung

```bash
# ROI-Berechnung ausführen
php -r "
require 'vendor/autoload.php';
use PerformanceExamples\Service\PerformanceRoiCalculator;

\$calc = new PerformanceRoiCalculator();
print_r(\$calc->generateSampleReport());
"
```

## Key Takeaways

1. **stale-while-revalidate** ermöglicht schnelle Antworten während der Cache im Hintergrund aktualisiert wird
2. **Surrogate-Control** gibt CDNs/Reverse-Proxies separate Cache-Zeiten
3. **Vary-Header** stellt sicher, dass verschiedene Varianten korrekt gecacht werden
4. **8.4% Conversion-Lift pro 100ms** ist eine verifizierte Zahl aus einer Studie mit 37 E-Commerce-Sites

## Quellen

- [Milliseconds Make Millions (Deloitte/Google, 2020)](https://web.dev/case-studies/milliseconds-make-millions)
- [Vodafone Case Study (web.dev, 2021)](https://web.dev/case-studies/vodafone)
- [Cache-Control Header (MDN)](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)
