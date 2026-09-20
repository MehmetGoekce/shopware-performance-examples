<?php

declare(strict_types=1);

/**
 * Abschnitt 18.12 — additiver Vektorpfad, Schritt 3 (Geruest)
 * Kapitel 18: Shopware 6 mit Elasticsearch
 *
 * Haelt das dense_vector-Feld NEBEN Shopwares eigenem Indexer aktuell. Der
 * lexikalische Index wird nicht angefasst; geschrieben wird nur das additive
 * Feld description_embedding (siehe config/dense-vector-mapping.json).
 *
 * DIE VORAUSSETZUNG, ohne die dieser Weg den Index zerstoert:
 * Shopware beschneidet das _source des Produktindex ab Werk auf id und
 * autoIncrement (ElasticsearchProductDefinition.php:143-145). Ein
 * Teil-Update (_update oder _bulk mit "update") baut das Dokument aus dem
 * gespeicherten _source neu auf — und was nicht im _source steht, ist danach
 * weg. Gemessen an einem Index mit derselben _source-Beschneidung: vor dem
 * Teil-Update findet die Suche das Dokument ueber seinen Namen, danach nicht
 * mehr; im Dokument stehen nur noch id, autoIncrement und das neu gesetzte
 * Feld.
 *
 * Deshalb braucht dieser Pfad ein vollstaendiges _source:
 *
 *   SHOPWARE_ES_EXCLUDE_SOURCE=1
 *
 * Der Name liest sich rueckwaerts: der Wert 1 schaltet die Beschneidung AB,
 * der Index traegt danach alle Felder im _source (gemessen: 47 statt 2), und
 * das Teil-Update erhaelt sie. Ohne diese Variable bricht dieser Subscriber
 * beim ersten Schreibvorgang mit einer Ausnahme ab, statt den Katalog still
 * auszuhoehlen.
 *
 * Zweite Einschraenkung: Jeder `bin/console es:index`-Lauf baut einen frischen
 * Index aus Shopwares Mapping und schwenkt den Alias. Das additive Feld
 * ueberlebt das nicht — weder Mapping noch Werte. Wer den Weg produktiv
 * faehrt, haengt sich an ElasticsearchIndexCreatedEvent und spielt Mapping
 * und Vektoren danach neu ein.
 *
 * Grenze: Die Einbettung selbst entsteht AUSSERHALB von Shopware (lokaler
 * Sentence-Transformers-Dienst oder eine Anbieter-API). EmbeddingClient ist
 * die Naht — absichtlich ein Interface ohne Implementierung, weil die Wahl
 * (selbst gehostet vs. API, DSGVO/AVV) vom Shop abhaengt (18.12 «Caveats
 * fuer Produktion»).
 *
 * Fuer das Indexieren und fuer die Anfrage MUSS dasselbe Modell laufen,
 * sonst liegen beide Seiten in verschiedenen Vektorraeumen.
 *
 * Getestet mit Shopware 6.6.10.6 und Elasticsearch 8.15.3.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\ElasticsearchExtension;

use OpenSearch\Client;
use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class ProductEmbeddingSubscriber implements EventSubscriberInterface
{
    private const INDEX_ALIAS = 'sw_product';
    private const BATCH_SIZE = 500;

    private ?bool $sourceComplete = null;

    public function __construct(
        private readonly Client $client,
        private readonly EmbeddingClient $embeddings,
        private readonly string $indexAlias = self::INDEX_ALIAS,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        // PRODUCT_WRITTEN_EVENT === 'product.written'
        return [
            ProductEvents::PRODUCT_WRITTEN_EVENT => 'onProductWritten',
        ];
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        $ids = array_values(array_unique($event->getIds()));
        if ($ids === []) {
            return;
        }

        $this->assertSourceComplete();

        // Nur die beruehrten Produkte neu einbetten, in Haeppchen. Produktiv
        // gehoert das in die Message-Queue statt in den schreibenden Request —
        // die Latenz des Einbettungsmodells darf den DAL-Schreibvorgang nicht
        // aufhalten.
        foreach (array_chunk($ids, self::BATCH_SIZE) as $chunk) {
            $this->reembed($chunk);
        }
    }

    /**
     * @param list<string> $ids
     */
    private function reembed(array $ids): void
    {
        // 1. Die einzubettenden Texte (Name + Beschreibung) laden.
        $texts = $this->embeddings->loadProductTexts($ids);
        if ($texts === []) {
            return;
        }

        // 2. Ein Modellaufruf fuer das ganze Haeppchen.
        $vectors = $this->embeddings->embed(array_values($texts));

        if (\count($vectors) !== \count($texts)) {
            throw new \RuntimeException(sprintf(
                'EmbeddingClient::embed() lieferte %d Vektoren fuer %d Texte — die Zuordnung ueber die Reihenfolge waere falsch.',
                \count($vectors),
                \count($texts)
            ));
        }

        // 3. Nur das additive Vektorfeld per _bulk nachtragen. Shopwares
        //    Indexer ueberschreibt es nicht, weil es nicht in seinem Mapping
        //    steht — siehe aber die Einschraenkung zum Reindex im Kopf.
        $body = [];
        foreach (array_keys($texts) as $i => $productId) {
            $body[] = ['update' => [
                '_index' => $this->indexAlias,
                '_id' => $productId,
            ]];
            $body[] = ['doc' => [
                'description_embedding' => $vectors[$i],
            ]];
        }

        $response = $this->client->bulk(['body' => $body]);

        // _bulk antwortet mit HTTP 200, auch wenn jedes einzelne Dokument
        // gescheitert ist. Ohne diese Pruefung bleibt der Vektorpfad still
        // stehen.
        if ($response['errors'] ?? false) {
            throw new \RuntimeException('Bulk-Update der Einbettungen fehlgeschlagen: ' . json_encode($response['items'] ?? []));
        }
    }

    /**
     * Prueft einmal je Prozess, ob der Index ein vollstaendiges _source
     * fuehrt. Ohne das macht jedes Teil-Update den Treffer unauffindbar.
     */
    private function assertSourceComplete(): void
    {
        if ($this->sourceComplete === true) {
            return;
        }

        $mappings = $this->client->indices()->getMapping(['index' => $this->indexAlias]);

        foreach ($mappings as $index => $data) {
            if (isset($data['mappings']['_source']['includes'])) {
                throw new \RuntimeException(sprintf(
                    'Index %s fuehrt ein beschnittenes _source (%s). Ein Teil-Update wuerde alle uebrigen Felder verwerfen. '
                    . 'SHOPWARE_ES_EXCLUDE_SOURCE=1 setzen und neu indexieren.',
                    $index,
                    implode(', ', $data['mappings']['_source']['includes'])
                ));
            }
        }

        $this->sourceComplete = true;
    }
}
