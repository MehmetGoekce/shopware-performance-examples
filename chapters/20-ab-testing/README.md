# Kapitel 20: A/B Testing & Performance-Experimente

Code-Beispiele für Woche 5 der 30-Tage-Roadmap. Getestet gegen Shopware 6.6.10.6 und 6.7.2.2 (Dockware, prod, eingebauter HTTP-Cache) mit curl, die RUM-Anbindung mit Chromium, Firefox und WebKit.

## Dateien

Ein Plugin, `AbTesting/`. Es setzt das RUM-Plugin aus Kapitel 12 (`RumMonitoring`) voraus: Die Messwerte kommen aus dessen Logs, ein eigener Tracker oder eine Metrik-Datenbank gehört nicht dazu.

| Datei | Beschreibung |
|-------|--------------|
| `src/Resources/config/services.xml` | Experimente (Parameter `ab_testing.experiments`): Routen und Varianten mit Gewicht, die erste Variante ist die Kontrollgruppe |
| `src/Subscriber/ExperimentSubscriber.php` | Zuweisung per Cookie `exp_<experiment>` auf den Routen des Experiments, Variable `experimentVariants` für die Templates; eine neue Zuweisung wird nicht gecacht |
| `src/Subscriber/CacheKeySubscriber.php` | Ein Eintrag im HTTP-Cache je Variante (`HttpCacheKeyEvent`, ab Shopware 6.5.8.0) |
| `src/Log/ExperimentLogProcessor.php` | Schreibt die Variante in jede Zeile des RUM-Logs (`exp_listing_images: eager`) |
| `src/Resources/config/packages/monolog.yaml` | Log-Kanal `ab_testing`, eine Zeile je Zuweisung (für den SRM-Test) |
| `src/Stats/StatisticalAnalyzer.php` | Welch-t-Test mit Konfidenzintervall der Differenz, Stichprobengrösse, Sample-Ratio-Mismatch-Test |
| `src/Stats/Distributions.php` | t-, Normal- und Chi-Quadrat-Verteilung (exakt, keine Tabelle) |
| `src/Command/AbSampleSizeCommand.php` | `ab:sample-size`: Seitenaufrufe je Variante, Standardabweichung auf Wunsch aus den RUM-Logs |
| `src/Command/AbAnalyzeCommand.php` | `ab:analyze`: Varianten gegen die Kontrolle, mit SRM-Prüfung |
| `src/Resources/views/storefront/component/product/card/box-standard.html.twig` | Beispiel-Experiment `listing_images`: in der Variante `eager` laden die ersten vier Listing-Bilder sofort, das erste mit `fetchpriority="high"` |

## Installation

```bash
cp -r ../12-real-user-monitoring/RumMonitoring AbTesting <shopware>/custom/plugins/
cd <shopware>
bin/console plugin:refresh
bin/console plugin:install --activate RumMonitoring
bin/console plugin:install --activate AbTesting
bin/console assets:install
bin/console cache:clear
```

Ohne aktives `RumMonitoring` bricht `plugin:install` für `AbTesting` mit «Required plugin/package "memotech/rum-monitoring *" is missing» ab.

## Experiment konfigurieren

Im Parameter `ab_testing.experiments` in `services.xml`. Key und Variantennamen: `a-z`, `0-9`, `_`. Für Performance-Metriken gleiche Gewichte: Bei ungleichem Split hat die kleine Gruppe mehr Cache-Misses und damit eine höhere TTFB. Nach jeder Änderung `cache:clear` und den HTTP-Cache leeren. Ein Cookie-Wert, der keine konfigurierte Variante ist, wird ignoriert und neu zugewiesen, sonst könnte jeder Besucher mit erfundenen Werten beliebig viele Cache-Einträge anlegen.

## Wie Zuweisung und HTTP-Cache zusammenspielen

Gemessen auf `/Clothing/` (Demo-Daten), HTTP-Cache geleert:

| Fall | Ergebnis |
|------|----------|
| 20 neue Besucher ohne Cookie | 9 × `control`, 11 × `eager`, jeder mit eigenem `Set-Cookie`, keiner aus dem Cache |
| Cookie `eager`, drei Aufrufe mit 2 s Pause | 1. gerendert, 2. und 3. aus dem Cache (`Age` 2/4, TTFB 84 → 10 ms), alle mit `loading="eager"` |
| Cookie `control` | eigener Cache-Eintrag, alle Bilder `loading="lazy"` |
| Cookie mit unbekanntem Wert | wie ein neuer Besucher |
| Seite ohne Experiment (`/`) | gecacht wie ohne Plugin, kein `Set-Cookie` |

Gegenproben mit abgeändertem Plugin:

- Ohne `setPrivate()` für die neue Zuweisung: Der Cache speichert die erste Antwort samt `Set-Cookie`, und die 7 weiteren neuen Besucher bekamen dieselbe Variante aus dem Cache.
- Ohne `CacheKeySubscriber`: Ein Besucher mit Cookie `control` bekam die gecachte Seite der Variante `eager`.
- `$event->getRequest()` statt `$event->request`: Die Methode gibt es nicht, **jede** Seite antwortet mit HTTP 500, auch ohne Cookie, weil das Event bei jedem Cache-Lookup läuft.

Der Preis: Der erste Aufruf eines neuen Besuchers auf einer Experiment-Route kommt nie aus dem Cache. Clients ohne Cookie-Speicher (Crawler, Monitoring, Lighthouse CI) sind bei jedem Aufruf neu: gerendert, `private`, eine Zeile im Zuweisungs-Log. Seiten ausserhalb des Experiments haben für Besucher mit Cookie einen Cache-Eintrag je Variante, weil der Cache-Key vor dem Routing entsteht.

Auf 6.7 tragen auch nicht gecachte Seiten ein `Age`: Symfony übernimmt das Alter gecachter ESI-Fragmente (Header, Footer) in die Seite. Ob eine Seite aus dem Cache kommt, sehen Sie dort nicht am `Age` allein, sondern am `Date`, das nur eine gespeicherte Kopie beim zweiten Abruf wiederholt, oder eindeutig an `X-Symfony-Cache` (Kapitel 6.8); die TTFB taugt nicht dafür.

Hinter Varnish wirkt `HttpCacheKeyEvent` nicht; das Plugin ist dafür nicht getestet.

## Auswertung

```bash
bin/console ab:sample-size --effect=120 --metric=LCP --days=7 --route=frontend.navigation.page
bin/console ab:analyze listing_images --metric=LCP --days=14
```

`ab:analyze` wertet nur Seitenaufrufe auf den Routen des Experiments aus (anders mit `--route`): Der Log-Processor schreibt die Variante in jede Zeile eines Besuchers mit Cookie, auch auf Seiten ausserhalb des Experiments. Exit-Code 0 (ausgewertet), 1 (zu wenig Daten oder nicht auswertbar, etwa keine Streuung), 2 (falscher Aufruf) oder 3 (Sample Ratio Mismatch: Zuweisungen passen nicht zum Split, Ergebnis nicht verwenden). Zuweisungen an nicht mehr konfigurierte Varianten stehen in der Ausgabe, zählen aber nicht im Test. Mit mehr als einer Variante gilt je Vergleich das Signifikanzniveau geteilt durch die Zahl der Vergleiche (Bonferroni).

Grenzen:

- Randomisiert wird je Besucher, gemessen je Seitenaufruf. Wer mehrere Seiten der Route aufruft, zählt mehrfach, und seine Aufrufe hängen zusammen; das Konfidenzintervall ist dann zu schmal. Das Log enthält keine Besucher-ID, das Plugin kann es nicht korrigieren.
- Nur Besucher, deren Browser die RUM-Beacons schickt und die die Stichprobe von `RumMonitoring` trifft, landen in der Auswertung.
- Das Cookie `exp_<experiment>` enthält nur den Variantennamen, keine ID. Ob Sie dafür eine Einwilligung brauchen, klären Sie mit Ihrer Datenschutzberatung.

## Tests

- `tests/Unit/AbTestingTest.php` – Welch-t, Freiheitsgrade, p-Wert und Konfidenzintervall gegen SciPy 1.8 (`ttest_ind(equal_var=False)`), t-Verteilung bei kleinen Freiheitsgraden, Quantile, Stichprobengrösse (37 für 210 ms bei 320 ms Standardabweichung), SRM-Test gegen `stats.chisquare`, Konfiguration, Zuweisung nach Gewicht, Auswertung der RUM-Zeilen (eine Meldung je Seitenaufruf, Routenfilter), Zufallsauswahl erreicht jede Variante, Kontroll-Mittel 0 (CLS), Zuweisungs-Log samt Datei des Vortags, nicht lesbare Logs. 24 von 24 Mutanten getötet.
- Im Dockware-Shop 6.6.10.6: alle Fälle der Tabelle oben und die drei Gegenproben, Beacons aus Chromium, Firefox und WebKit mit Variante im RUM-Log, `ab:sample-size` und `ab:analyze` auf erzeugten Testdaten (Ausgabe gegen SciPy geprüft), SRM-Fall mit Exit-Code 3.
- Im Dockware-Shop 6.7.2.2: Installation, die Fälle der Tabelle oben, Variante im RUM-Log (Beacon per curl, gültiges und erfundenes Cookie), Routenfilter (400 Zeilen der Produktseite bleiben in der Vorgabe draussen), Exit 1 mit Meldung, wenn keine Gruppe streut.

## Quellen

- Kohavi, R., Tang, D., Xu, Y.: *Trustworthy Online Controlled Experiments*. Cambridge University Press, 2020 (Kapitel 21, Sample Ratio Mismatch)
- [Evan Miller: How Not To Run an A/B Test](https://www.evanmiller.org/how-not-to-run-an-ab-test.html)
- [SciPy: scipy.stats.ttest_ind](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.ttest_ind.html)
