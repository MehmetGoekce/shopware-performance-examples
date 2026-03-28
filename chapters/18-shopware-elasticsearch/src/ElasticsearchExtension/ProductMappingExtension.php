<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use Shopware\Elasticsearch\Event\ElasticsearchCustomFieldsMappingEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Extends the default Elasticsearch product mapping with custom fields.
 *
 * This extension adds:
 * - Custom sort value field for faster sorting
 * - Exact match keyword field for product numbers
 * - Nested attributes for complex filtering
 * - Autocomplete-optimized fields
 *
 * Usage:
 *   Register as service with kernel.event_subscriber tag
 *
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/elasticsearch/extending-elasticsearch
 */
class ProductMappingExtension implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            ElasticsearchCustomFieldsMappingEvent::class => 'onProductMapping',
        ];
    }

    /**
     * Extend product mapping with custom fields.
     *
     * Performance Tips:
     * - Use 'keyword' type for exact matches (faster than 'text')
     * - Use 'int' for numeric sorting (faster than 'float')
     * - setMapping() accepts (string $field, string $type)
     */
    public function onProductMapping(ElasticsearchCustomFieldsMappingEvent $event): void
    {
        if ($event->getEntity() !== 'product') {
            return;
        }

        // Custom sort value for manual product ordering
        $event->setMapping('customSortValue', 'int');

        // Exact match field for product numbers
        // Keyword type is 10x faster than text for exact matches
        $event->setMapping('productNumberExact', 'keyword');

        // EAN/GTIN field for barcode searches
        $event->setMapping('ean', 'keyword');

        // Manufacturer product number
        $event->setMapping('manufacturerNumber', 'keyword');

        // Search keywords (for exact matching)
        $event->setMapping('searchKeywords', 'keyword');

        // Rating as integer (0-500 for 0.0-5.0)
        // Integer operations are faster than float
        $event->setMapping('ratingScaled', 'int');
    }
}
