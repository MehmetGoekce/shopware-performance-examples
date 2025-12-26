<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use Shopware\Elasticsearch\Framework\ElasticsearchHelper;
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
            'elasticsearch.product.mapping' => 'onProductMapping',
        ];
    }

    /**
     * Extend product mapping with custom fields.
     *
     * Performance Tips:
     * - Use 'keyword' type for exact matches (faster than 'text')
     * - Use 'integer' for numeric sorting (faster than 'float')
     * - Avoid 'nested' type if possible (expensive queries)
     * - Set 'doc_values: true' for aggregation fields
     */
    public function onProductMapping(array &$mapping): void
    {
        // Custom sort value for manual product ordering
        // Use integer for fastest comparison
        $mapping['properties']['customSortValue'] = [
            'type' => 'integer',
            'doc_values' => true,
        ];

        // Exact match field for product numbers
        // Keyword type is 10x faster than text for exact matches
        $mapping['properties']['productNumberExact'] = [
            'type' => 'keyword',
            'normalizer' => 'lowercase',
        ];

        // EAN/GTIN field for barcode searches
        $mapping['properties']['ean'] = [
            'type' => 'keyword',
        ];

        // Manufacturer product number
        $mapping['properties']['manufacturerNumber'] = [
            'type' => 'keyword',
        ];

        // Autocomplete field with edge n-grams
        // Enables search-as-you-type functionality
        $mapping['properties']['nameAutocomplete'] = [
            'type' => 'text',
            'analyzer' => 'autocomplete_analyzer',
            'search_analyzer' => 'standard',
        ];

        // Nested custom attributes for complex filtering
        // WARNING: Nested queries are expensive - use sparingly!
        $mapping['properties']['customAttributes'] = [
            'type' => 'nested',
            'properties' => [
                'key' => ['type' => 'keyword'],
                'value' => [
                    'type' => 'text',
                    'fields' => [
                        'keyword' => ['type' => 'keyword'],
                    ],
                ],
            ],
        ];

        // Price range field for fast faceting
        $mapping['properties']['priceRange'] = [
            'type' => 'keyword',
            'doc_values' => true,
        ];

        // Availability score for sorting
        // Combines stock and delivery time
        $mapping['properties']['availabilityScore'] = [
            'type' => 'integer',
            'doc_values' => true,
        ];

        // Search keywords as keyword array (for exact matching)
        $mapping['properties']['searchKeywords'] = [
            'type' => 'keyword',
        ];

        // Rating as scaled integer (0-500 for 0.0-5.0)
        // Integer operations are faster than float
        $mapping['properties']['ratingScaled'] = [
            'type' => 'integer',
            'doc_values' => true,
        ];
    }
}
