# Kapitel 18: Shopware 6 mit Elasticsearch — Companion Code

Companion-Code zum Buch **«Shop-Performance in 30 Tagen»**.

Getestet gegen **Shopware 6.6.10.6** (Dockware, PHP 8.3, MySQL 8.0) und
**Elasticsearch 8.15.3**.

Was das genau heisst, weil eine Pauschalaussage hier in die Irre führt:

- **Gefahren und gemessen:** die sechs PHP-Klassen (byte-gleich als Plugin im
  Testshop installiert), `config/elasticsearch.yaml`,
  `config/dictionary-decompounder-analyzer.yaml`,
  `config/dense-vector-mapping.json`, `config/hybrid-rrf-query.json` und alle
  Skripte ausser dem OpenSearch-Gegenstück.
- **Gestartet, aber nicht im Testaufbau in Gebrauch:**
  `config/elasticsearch.yml` und `config/jvm.options`. Der Testknoten läuft
  ohne Bind-Mount, mit `xpack.security.enabled=false` und einem Heap aus
  `ES_JAVA_OPTS`. Beide Dateien sind gegen einen eigenen Node gestartet
  worden, nicht gegen den, an dem die übrigen Messungen entstanden sind.
- **Nicht gefahren:** `scripts/opensearch-hybrid-pipeline.sh` — am Quelltext
  und an der OpenSearch-Dokumentation belegt, aber nie gegen OpenSearch
  ausgeführt. Die Datei sagt das in ihrem Kopfkommentar noch einmal.

Elasticsearch 7.x und OpenSearch 2.x sind ebenfalls **ungetestet**. Wo etwas
versionsabhängig ist, steht es an der Datei.

## Das Wichtigste zuerst

**Shopware konfiguriert Elasticsearch über Umgebungsvariablen, nicht über eine
eigene YAML.** Eine Standardinstallation hat keine
`config/packages/elasticsearch.yaml`. In die `.env.local` gehören:

```bash
OPENSEARCH_URL=http://localhost:9200   # ELASTICSEARCH_URL gibt es nicht
SHOPWARE_ES_ENABLED=1
SHOPWARE_ES_INDEXING_ENABLED=1
SHOPWARE_ES_INDEX_PREFIX=sw            # ohne Unterstrich!
SHOPWARE_ES_THROW_EXCEPTION=1
```

Drei Fallen, alle gemessen:

- `ELASTICSEARCH_URL` liest Shopware an keiner Stelle. Bis 6.4 hiess die
  Variable `SHOPWARE_ES_HOSTS`, seit 6.5.0.0 `OPENSEARCH_URL`.
- `SHOPWARE_ES_INDEX_PREFIX=sw_` erzeugt den Alias `sw__product` — den
  Unterstrich hängt Shopware selbst an (`ElasticsearchHelper::getIndexName`).
- `SHOPWARE_ES_THROW_EXCEPTION=1` ist der Bundle-Default, und er bedeutet:
  Fällt der Cluster aus, antwortet die Suchseite mit **HTTP 500**. Erst `=0`
  fällt auf die Datenbanksuche zurück. Beides gemessen.

`config/elasticsearch.yaml` in diesem Ordner ist deshalb kein Ersatz für die
`.env.local`, sondern die Ergänzung für das, was die Variablen **nicht**
abdecken: `search.timeout`, `index_settings`, `analysis` und
`language_analyzer_mapping`.

## Verzeichnis

```
chapters/18-shopware-elasticsearch/
├── config/
│   ├── elasticsearch.yaml                     # Shopware-Seite (optional, s. o.)
│   ├── elasticsearch.yml                      # Node-Konfiguration
│   ├── jvm.options                            # Heap und JVM
│   ├── dictionary-decompounder-analyzer.yaml  # 18.5 Kompositazerlegung
│   ├── de_dictionary.sample.txt               # 18.5 Beispiel-Wortliste
│   ├── dense-vector-mapping.json              # 18.12 additives Vektorfeld
│   └── hybrid-rrf-query.json                  # 18.12 ES-8.x-Hybridabfrage
├── scripts/
│   ├── es-health-check.sh                     # Cluster-Zustand
│   ├── es-reindex.sh                          # Reindex mit Warteschlange
│   ├── es-index-stats.sh                      # Index-Kennzahlen
│   ├── es-benchmark.sh                        # Abfragen messen
│   ├── slowlog-settings.sh                    # Slow-Log setzen und zurücknehmen
│   ├── extract-dictionary.sh                  # 18.5 de_dictionary.txt bauen
│   └── opensearch-hybrid-pipeline.sh          # 18.12 OpenSearch (ungetestet)
├── src/
│   ├── ElasticsearchExtension/
│   │   ├── CustomAnalyzerDefinition.php       # eigene Analyzer im Index
│   │   ├── ProductMappingExtension.php        # Custom-Fields typisieren
│   │   ├── SearchBoostSubscriber.php          # Relevanz-Zuschläge
│   │   ├── IndexingOptimizer.php              # eigene Massenimporte
│   │   ├── ProductEmbeddingSubscriber.php     # 18.12 Vektorpfad (Gerüst)
│   │   └── EmbeddingClient.php                # 18.12 Naht zum Modell
│   └── Resources/config/services.xml          # Verdrahtung der Klassen
└── README.md
```

## Schnellstart

### 1. Elasticsearch installieren

Shopware 6.6 und 6.7 laufen weiterhin mit Elasticsearch; OpenSearch ist keine
Pflicht, sondern der Weg, den Shopware selbst empfiehlt. Der Unterschied wird
erst bei den Erweiterungen relevant (Advanced Search, Vektorsuche).

**Elasticsearch 8.x hat Security ab Werk an** und schreibt TLS und ein
generiertes `elastic`-Passwort beim ersten Start selbst in die
`elasticsearch.yml`. Jeder `curl http://localhost:9200` ohne Zugangsdaten
läuft dort ins Leere. Für den ersten Aufbau entweder die Zugangsdaten nutzen
oder `xpack.security.enabled: false` bewusst setzen.

### 2. Heap setzen

```bash
# /etc/elasticsearch/jvm.options.d/custom.options
-Xms4g
-Xmx4g
```

Die Hälfte des RAM, und **höchstens 26 GB**: Elastic dokumentiert «26GB is
safe on most systems and can be as large as 30GB on some systems». Die oft
zitierten 31-32 GB liegen ausserhalb dieser Empfehlung. `Xms` und `Xmx` immer
gleich.

### 3. Shopware konfigurieren

Siehe oben — `.env.local`. `config/elasticsearch.yaml` nur, wenn `timeout`,
Shard-Zahl oder eigene Analyzer gebraucht werden.

### 4. Ersten Index bauen

```bash
bin/console es:index --no-queue
```

`--no-queue` ist nicht optional, wenn kein Worker läuft: `es:index` stellt
sonst nur eine Nachricht in die Warteschlange, der Index bleibt leer — und
`es:status` meldet trotzdem `completed`. `es:create:alias` wird hier nicht
gebraucht und gehört, wenn überhaupt, **nach** den Reindex.

## Skripte

| Skript | Was es tut |
|---|---|
| `es-health-check.sh` | Cluster-Zustand, Heap, Disk, ausstehende Aufgaben. Exit 1 bei Warnungen. |
| `es-reindex.sh` | Reindex inkl. Warteschlange, Alias-Schwenk und Aufräumen. |
| `es-index-stats.sh` | Kennzahlen je Index, Entitätszahl über `_count`. |
| `es-benchmark.sh` | Acht Abfragetypen gegen den Produktindex, Wanduhr- und Serverzeit getrennt. |
| `slowlog-settings.sh` | Slow-Log-Schwellen setzen (ohne Argument) und zurücknehmen (`--reset`). |
| `extract-dictionary.sh` | Baut `de_dictionary.txt` aus `de_DE_frami.dic` (LibreOffice), nach UTF-8 umkodiert und klein geschrieben. |
| `opensearch-hybrid-pipeline.sh` | OpenSearch-Gegenstück zur Hybridabfrage. **Ungetestet.** |

```bash
ES_URL=http://localhost:9200 ./scripts/es-health-check.sh
ES_URL=http://localhost:9200 ./scripts/es-benchmark.sh --iterations=20
```

`es-benchmark.sh` nimmt bei Bedarf Zugangsdaten über `ES_USER`/`ES_PASSWORD`
entgegen — die übrigen Skripte sprechen einen offenen Endpunkt an.

Zwei Dinge, die der Benchmark bewusst anders macht als die erste Fassung:
Eine Abfrage, die Elasticsearch mit HTTP 400 ablehnt, ist **kein** Messwert
und wird als `[FAILED]` gemeldet (Exit 1). Und die Dokumentzahl kommt aus
`_count`, nicht aus `docs.count`: Letzteres zählt Lucene-Dokumente, also
verschachtelte Felder mit — gemessen 234 bei 14 Produkten.

## Konfigurationsdateien

### `config/elasticsearch.yaml` (Shopware-Seite)

- `hosts` ist ein **Skalar**. Mehrere Knoten als ein String mit Komma.
  Eine YAML-Liste bricht den Container-Build («Expected "scalar", but got
  "array"»).
- `timeout` gibt es auf oberster Ebene nicht — nur `search.timeout`, und der
  braucht eine Zeiteinheit (`'30s'`).
- Der `analysis`-Block steht unter `index_settings`, nicht unter
  `elasticsearch.analysis`. Der dokumentierte Knoten ist
  `performNoDeepMerging()`: Er **ersetzt** Shopwares eigenen Block, und jede
  Index-Erstellung scheitert danach an
  `normalizer [sw_lowercase_normalizer] not found`.
- `language_analyzer_mapping` ist die Zeile, ohne die ein eigener Analyzer
  definiert, aber von nichts benutzt wird.

### `config/elasticsearch.yml` (Node)

**Index-Level-Settings gehören nicht in die Node-Konfiguration.** Seit ES 5.x
verweigert der Node den Start: `node settings must not contain any index level
settings`, Exit 1. Das betrifft `index.search.slowlog.*`,
`index.indexing.slowlog.*` und `index.merge.*`. Der Slow-Log wird deshalb zur
Laufzeit gesetzt — dafür gibt es `scripts/slowlog-settings.sh`.

Zwei weitere Punkte aus dem Test:

- `vm.max_map_count` (mindestens 262144) ist ein harter Bootstrap-Check.
- ES 8.x **schreibt selbst** in diese Datei. Read-only eingehängt startet der
  Node nicht.

### `config/jvm.options`

Siehe Heap oben. `bootstrap.memory_lock: true` wirkt nur, wenn der Prozess
die Sperre auch setzen darf (`ulimit -l unlimited`, im Container
`--ulimit memlock=-1:-1`). Im Einzelknoten-Betrieb sind die Bootstrap-Checks
aus: Der Node startet dann trotzdem und **meldet es** — `WARN Unable to lock
JVM Memory: error=12, reason=Cannot allocate memory`, allerdings nur als
Warnung. Der Schutz vor Swapping fehlt dabei, obwohl die Zeile gesetzt ist;
nachprüfen mit `GET /_nodes?filter_path=**.mlockall`. Im Mehrknoten-Betrieb
greifen die Checks, und derselbe Aufbau startet gar nicht mehr (Exit 78).

## PHP-Klassen

Ohne `src/Resources/config/services.xml` passiert nichts: Ein Subscriber wird
nur aufgerufen, wenn sein Service den Tag `kernel.event_subscriber` trägt.
Der Namespace `YourPlugin` ist ein Platzhalter.

### `CustomAnalyzerDefinition`

Eigene Analyzer (deutscher Volltext mit Stemming, Autocomplete mit
Edge-N-Grammen, `keyword_lowercase`) über `ElasticsearchIndexConfigEvent`.

Zwei Dinge, die in der ersten Fassung fehlten: Das Event heisst so — ein
String `'elasticsearch.index.settings'` existiert in Shopware nicht, und ein
Subscriber darauf wird nie aufgerufen. Und ein Analyzer wirkt erst, wenn ihn
etwas benutzt: dafür `language_analyzer_mapping: { de: german_analyzer }`.

Ein phonetischer Filter ist **nicht** enthalten: `"type": "phonetic"` braucht
das Plugin `analysis-phonetic`; ohne es antwortet ES mit
`Unknown filter type [phonetic]` — und weil der Subscriber bei jeder
Index-Erstellung läuft, scheitert dann jedes `es:index`.

### `ProductMappingExtension`

Typisiert Custom Fields im Produkt-Mapping. `$type` ist eine
`CustomFieldTypes::*`-Konstante, kein Elasticsearch-Typ; `'integer'` fällt
still in den default-Zweig und bricht Range und Sortierung.

### `SearchBoostSubscriber`

**Feld-Gewichte gehören nicht in Code.** Sie stehen in
`product_search_config_field.ranking` und werden im Admin gepflegt
(Einstellungen > Shop > Suche). Die Vorgabe einer frischen 6.6-Installation:
productNumber 1000, customSearchKeywords 800, name 700, manufacturerNumber /
ean / manufacturer.name je 500. Shopware macht daraus den ES-`boost` je Feld.

Was sich so nicht ausdrücken lässt — «der exakt eingegebene Artikel ganz nach
oben» — kommt über `ElasticsearchEntitySearcherSearchEvent` an die fertige
Abfrage. Gemessen: Score des exakten Treffers 2302 → 13815, Reihenfolge
anschliessend wie erwartet, Trefferzahl unverändert.

Die frühere Fassung hängte eine Criteria-Extension an. Die liest kein
Shopware-Code; die erzeugte Abfrage war Byte für Byte dieselbe wie ohne
Subscriber. Der Claim «Exact match boost (100x)» in diesem README war damit
unbelegt und ist ersatzlos gestrichen.

### `IndexingOptimizer`

Für **eigene** Massenimporte, nicht für `es:index`. Shopware legt bei jedem
Reindex einen neuen Index an; ein vorher gesetztes `refresh_interval` trifft
den alten, und nach dem Alias-Schwenk setzt Shopware den Wert selbst auf
`null`. Force-Merge ist deshalb `false` per Vorgabe: Elastic empfiehlt ihn
ausdrücklich nur für Indizes, in die nicht mehr geschrieben wird.

### `ProductEmbeddingSubscriber` (18.12)

Braucht `SHOPWARE_ES_EXCLUDE_SOURCE=1`. Shopware beschneidet das `_source` des
Produktindex ab Werk auf `id` und `autoIncrement`; ein Teil-Update baut das
Dokument aus dem gespeicherten `_source` neu auf und **verwirft alles andere**.
Gemessen: Vor dem Teil-Update findet die Suche das Dokument über seinen Namen,
danach nicht mehr. Die Klasse prüft das und bricht ab, statt den Katalog still
auszuhöhlen. Der Variablenname liest sich rückwärts — `1` schaltet die
Beschneidung ab.

## Fortgeschritten (18.5 / 18.12)

### Kompositazerlegung (18.5)

```bash
./scripts/extract-dictionary.sh        # baut de_dictionary.txt
# config/dictionary-decompounder-analyzer.yaml in die eigene YAML übernehmen
# danach voller Reindex (18.11), sonst greift der Analyzer nicht
```

Die Wortliste **muss klein geschrieben und UTF-8 sein**. Beides erzwingt das
Skript und prüft es danach gegen:

- Der `dictionary_decompounder` vergleicht ohne Rücksicht auf Gross- und
  Kleinschreibung nicht — mit den rohen Hunspell-Stämmen («Schuh») feuert er
  nie ein einziges Teilwort (gemessen: «Kinderschuhe» → `[kinderschuh]`).
  `tr` taugt dafür nicht, es lässt Umlaute byteweise stehen.
- Die Quelldatei ist **ISO-8859-1**, nicht UTF-8. Ohne `iconv` ist das
  Ergebnis kein gültiges UTF-8 — und genau das verlangt Elasticsearch.

Zweite Falle: die Reihenfolge der Filter. Erst zerlegen, dann stemmen — die
Empfehlung stimmt, die frühere Begründung nicht. «Jacke» geht in der
umgekehrten Reihenfolge **nicht** verloren; die Anfrage wird ja ebenfalls
gestemmt. Was bricht, ist die Gegenrichtung: Mit Stemmer zuerst steht
`winter` im Index, die Anfrage «Winter» kommt aber als `wint` an, weil der
Stemmer dort vor dem Decompounder läuft und ein Wort mit vier Zeichen nicht
mehr zerlegt wird. Beides gemessen, mit der Wortliste, die
`extract-dictionary.sh` wirklich erzeugt.

Dritte Falle, die nur die echte Liste zeigt: Bei rund 163 000 Stämmen und
`min_subword_size: 3` fällt Unsinn an — «Kinderschuhe» ergibt
`[kinderschuh, kind, kind, ind, ind, der, schuh]`, weil «ind» und «der» eigene
Stämme sind. Wer das nicht will, hebt `min_subword_size` auf 4 und misst nach.

### Vektor- und Hybridsuche (18.12, Ausblick)

Shopware-Core hat auch in 6.7 keine Vektorsuche. Die Artefakte hier bauen den
Weg **additiv**, ohne den lexikalischen Index zu ersetzen:

- `config/dense-vector-mapping.json` — additives `dense_vector`-Feld.
  Der Default für `index_options` ist seit 8.11 `int8_hnsw`, also quantisiert;
  das gehört in jede Heap-Rechnung.
- `src/ElasticsearchExtension/ProductEmbeddingSubscriber.php` — hält das Feld
  aktuell (Gerüst, Modell als Naht). Voraussetzungen siehe oben.
- `config/hybrid-rrf-query.json` — ES-8.x-Hybridabfrage über `retriever.rrf`.
  **Lizenzpflichtig:** Auf einem `basic`-Cluster antwortet sie mit HTTP 403,
  `current license is non-compliant for [Reciprocal Rank Fusion (RRF)]`
  (gemessen). `RRFRankPlugin` fordert PLATINUM.
- `scripts/opensearch-hybrid-pipeline.sh` — OpenSearch-Gegenstück über den
  `normalization-processor`. OpenSearch hat seit **2.19** ausserdem RRF nativ
  (`score-ranker-processor`, Apache-2.0) — der Satz «OpenSearch hat kein
  RRF-Pendant» stimmte bis 2.18. Nicht gefahren.

Kein Weg überlebt einen Reindex: Jeder `es:index`-Lauf baut den Index neu aus
Shopwares Mapping. Mapping und Vektoren müssen danach neu eingespielt werden.

## Quellen

- [Shopware ES Docs](https://developer.shopware.com/docs/guides/plugins/plugins/elasticsearch/)
- [Elastic Heap Sizing](https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html)
- [Elastic dense_vector](https://www.elastic.co/guide/en/elasticsearch/reference/current/dense-vector.html)
- [Elastic RRF](https://www.elastic.co/guide/en/elasticsearch/reference/current/rrf.html)
- [OpenSearch RRF (2.19)](https://opensearch.org/blog/introducing-reciprocal-rank-fusion-hybrid-search/)
- [OpenSearch Score Ranker Processor](https://docs.opensearch.org/latest/search-plugins/search-pipelines/score-ranker-processor/)
