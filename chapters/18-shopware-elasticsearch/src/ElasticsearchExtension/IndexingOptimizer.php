<?php

declare(strict_types=1);

/**
 * Index-Einstellungen fuer den eigenen Bulk-Import umschalten
 * Kapitel 18: Shopware 6 mit Elasticsearch
 *
 * WOFUER DAS HIER NICHT TAUGT: `bin/console es:index` damit einzurahmen.
 * Shopware legt bei jedem Reindex einen NEUEN Index <alias>_<timestamp> an.
 * Ein vorher gesetztes refresh_interval trifft den alten Index, nicht den
 * neu entstehenden. Und nach dem Schwenk setzt CreateAliasTaskHandler.php:109
 * refresh_interval fest auf null (= ES-Default 1s) — nicht auf den Wert, den
 * dieser Code vorher gesetzt hat. Wer Shopwares Reindex beeinflussen will,
 * setzt elasticsearch.index_settings in config/packages/elasticsearch.yaml;
 * das landet im CREATE des neuen Index.
 *
 * WOFUER ES TAUGT: eigene Massenschreibvorgaenge auf einem Index, den man
 * selbst anlegt und selbst fuellt (Import-Index, additiver Vektor-Index aus
 * 18.12, Migrations-Index). Dort gilt die Reihenfolge
 * prepareForBulkIndex() -> schreiben -> finalizeBulkIndex().
 *
 * Der Client kommt aus dem Bundle (Service-ID OpenSearch\Client). Der traegt
 * Hosts, TLS und Zugangsdaten aus der Shopware-Konfiguration. Eine eigene
 * URL-Konstante wie 'http://localhost:9200' faellt spaetestens auf einem
 * ES 8.x um, das ab Werk TLS und Authentifizierung verlangt.
 *
 * Getestet mit Shopware 6.6.10.6 und Elasticsearch 8.15.3.
 *
 * @see https://www.elastic.co/guide/en/elasticsearch/reference/8.15/tune-for-indexing-speed.html
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\ElasticsearchExtension;

use OpenSearch\Client;
use Psr\Log\LoggerInterface;

class IndexingOptimizer
{
    /**
     * Nach dem Bulk zurueck auf einen expliziten Wert. ES-Default waere 1s;
     * '5s' nimmt Schreiblast raus und ist fuer einen Katalog vertretbar.
     */
    private const DEFAULT_REFRESH_INTERVAL = '5s';

    /** Waehrend des Bulk: gar kein automatischer Refresh. */
    private const BULK_REFRESH_INTERVAL = '-1';

    public function __construct(
        private readonly Client $client,
        private readonly LoggerInterface $logger
    ) {
    }

    /**
     * Vor dem Massenschreiben aufrufen — und finalizeBulkIndex() danach
     * wirklich aufrufen, auch im Fehlerfall (try/finally). Ein Index, der mit
     * refresh_interval -1 stehen bleibt, zeigt neue Dokumente nie an.
     */
    public function prepareForBulkIndex(string $indexName): void
    {
        $this->logger->info('Index fuer Bulk-Schreiben vorbereiten', ['index' => $indexName]);

        $this->updateSettings($indexName, [
            'index' => [
                'refresh_interval' => self::BULK_REFRESH_INTERVAL,
                // 'async' handelt Haltbarkeit gegen Durchsatz: bei einem
                // Absturz fehlen die letzten Sekunden. Fuer einen Suchindex
                // vertretbar, weil er sich neu aufbauen laesst.
                'translog' => ['durability' => 'async'],
            ],
        ]);
    }

    /**
     * Nach dem Massenschreiben aufrufen.
     *
     * Ohne $forceMerge, und das ist Absicht: Elastic empfiehlt Force-Merge
     * ausdruecklich nur fuer Indizes, in die nicht mehr geschrieben wird
     * («We recommend only force merging a read-only index»). Ein Shopware-
     * Katalogindex wird im Livebetrieb laufend beschrieben — dort erzeugt
     * max_num_segments=1 grosse Segmente, die danach nie wieder aufgeraeumt
     * werden.
     */
    public function finalizeBulkIndex(string $indexName, bool $forceMerge = false): void
    {
        $this->logger->info('Bulk-Schreiben abschliessen', ['index' => $indexName]);

        $this->updateSettings($indexName, [
            'index' => [
                'refresh_interval' => self::DEFAULT_REFRESH_INTERVAL,
                'translog' => ['durability' => 'request'],
            ],
        ]);

        if ($forceMerge) {
            $this->forceMerge($indexName);
        }

        $this->refreshIndex($indexName);
    }

    /**
     * Segmente zusammenfuehren. Nur fuer Indizes, die ab jetzt nur noch
     * gelesen werden (abgeschlossener Import, Snapshot, Archiv).
     *
     * Laeuft lange und belastet CPU und I/O; der Aufruf kehrt erst zurueck,
     * wenn der Merge durch ist.
     */
    public function forceMerge(string $indexName, int $maxSegments = 1): void
    {
        $result = $this->client->indices()->forcemerge([
            'index' => $indexName,
            'max_num_segments' => $maxSegments,
        ]);

        $this->logger->info('Force-Merge fertig', [
            'index' => $indexName,
            'shards' => $result['_shards'] ?? [],
        ]);
    }

    /**
     * Macht geschriebene Dokumente sofort sichtbar, statt auf den naechsten
     * automatischen Refresh zu warten.
     */
    public function refreshIndex(string $indexName): void
    {
        $this->client->indices()->refresh(['index' => $indexName]);
    }

    /**
     * Leert Query- und Request-Cache des Index. Nach grossen Aenderungen
     * sinnvoll, um Speicher freizugeben — kostet danach kalte Abfragen.
     */
    public function clearCache(string $indexName): void
    {
        $this->client->indices()->clearCache(['index' => $indexName]);

        $this->logger->info('Index-Cache geleert', ['index' => $indexName]);
    }

    /**
     * @return array{documents: int, lucene_docs: int, size_bytes: int, segments: int}
     */
    public function getIndexStats(string $indexName): array
    {
        $data = $this->client->indices()->stats(['index' => $indexName]);

        // _stats liefert die Zahlen je PHYSISCHEM Index. Steht in
        // $indexName ein Alias (sw_product), ist der Schluessel trotzdem
        // sw_product_<timestamp> — deshalb wird hier summiert und nicht
        // nach $indexName gesucht.
        $docs = 0;
        $luceneDocs = 0;
        $size = 0;
        $segments = 0;

        foreach ($data['indices'] ?? [] as $index) {
            $primaries = $index['primaries'] ?? [];
            $luceneDocs += (int) ($primaries['docs']['count'] ?? 0);
            $size += (int) ($primaries['store']['size_in_bytes'] ?? 0);
            $segments += (int) ($primaries['segments']['count'] ?? 0);
        }

        // docs.count aus _stats und _cat/indices ist die Zahl der
        // LUCENE-Dokumente: Nested-Felder (categories, properties,
        // visibilities ...) zaehlen einzeln mit. Gemessen am Demo-Katalog:
        // 234 Lucene-Dokumente fuer 14 Produkte. Die Produktzahl liefert
        // nur _count.
        $docs = (int) ($this->client->count(['index' => $indexName])['count'] ?? 0);

        return [
            'documents' => $docs,
            'lucene_docs' => $luceneDocs,
            'size_bytes' => $size,
            'segments' => $segments,
        ];
    }

    public function indexExists(string $indexName): bool
    {
        return $this->client->indices()->exists(['index' => $indexName]);
    }

    /**
     * @param array<string, mixed> $settings
     */
    private function updateSettings(string $indexName, array $settings): void
    {
        // Bewusst ohne try/catch: Ein stiller Fehlschlag hier bedeutet, dass
        // der Bulk mit den falschen Einstellungen laeuft — das soll der
        // Aufrufer merken. Analyse-Einstellungen liessen sich hier ohnehin
        // nicht setzen, die sind statisch und brauchen einen geschlossenen
        // Index.
        $this->client->indices()->putSettings([
            'index' => $indexName,
            'body' => $settings,
        ]);
    }
}
