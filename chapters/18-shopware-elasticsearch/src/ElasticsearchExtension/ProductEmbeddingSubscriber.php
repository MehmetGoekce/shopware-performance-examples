<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use OpenSearch\Client;
use Shopware\Core\Content\Product\ProductEvents;
use Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Section 18.12 — additive vector path, step 3 (skeleton).
 *
 * Keeps the dense_vector field in sync ALONGSIDE Shopware's standard
 * indexer. It does NOT touch the lexical product index: it only writes
 * the additive `description_embedding` field (see
 * config/dense-vector-mapping.json) on the existing sw_product index.
 *
 * Boundary: embedding generation lives OUTSIDE Shopware (local
 * Sentence-Transformers service or a vendor API). EmbeddingClient is the
 * seam — intentionally an interface, not implemented here, because the
 * choice (self-hosted vs. API, DSGVO/AVV path) is shop-specific (18.12
 * "Caveats für Produktion").
 *
 * The same embedding model MUST be used for indexing and for query-time
 * embedding, or both sides operate in different vector spaces.
 *
 * Register as service with the kernel.event_subscriber tag and inject
 * the OpenSearch\Client (Shopware-canonical, API-compatible with ES too)
 * plus your EmbeddingClient implementation.
 */
class ProductEmbeddingSubscriber implements EventSubscriberInterface
{
    private const INDEX_ALIAS = 'sw_product';
    private const BATCH_SIZE = 500;

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

        // Re-embed only the touched products, in batches. In production
        // hand this to the message queue instead of doing it inline —
        // embedding latency must not block the DAL write.
        foreach (array_chunk($ids, self::BATCH_SIZE) as $chunk) {
            $this->reembed($chunk);
        }
    }

    /**
     * @param list<string> $ids
     */
    private function reembed(array $ids): void
    {
        // 1. Load the text to embed (name + description) for these ids.
        //    Use a lightweight repository/Connection lookup here.
        $texts = $this->embeddings->loadProductTexts($ids);

        // 2. One embedding model call for the whole batch.
        $vectors = $this->embeddings->embed(array_values($texts));

        // 3. Partial-update only the additive vector field via _bulk.
        //    Shopware's indexer never overwrites it (the field is not in
        //    its mapping), so a doc update is safe.
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

        if ($body !== []) {
            $this->client->bulk(['body' => $body]);
        }
    }
}

/**
 * Seam for the embedding backend (self-hosted Sentence-Transformers or a
 * vendor API). Implement in your bundle; see 18.12 for the trade-offs
 * (latency budget, DSGVO/AVV, query-embedding cache).
 */
interface EmbeddingClient
{
    /**
     * @param list<string> $ids
     *
     * @return array<string, string> productId => text to embed
     */
    public function loadProductTexts(array $ids): array;

    /**
     * @param list<string> $texts
     *
     * @return list<list<float>> one vector per input text, same order
     */
    public function embed(array $texts): array;
}
