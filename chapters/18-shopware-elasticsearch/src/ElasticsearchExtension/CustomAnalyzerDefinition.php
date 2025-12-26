<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use Shopware\Elasticsearch\Framework\ElasticsearchHelper;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Defines custom Elasticsearch analyzers for German language optimization.
 *
 * Analyzers included:
 * - german_analyzer: Full German text analysis with stemming
 * - autocomplete_analyzer: Edge n-grams for search-as-you-type
 * - keyword_lowercase: Lowercase keyword for case-insensitive exact matches
 *
 * Usage:
 *   Register as service with kernel.event_subscriber tag
 *   These analyzers are applied during index creation
 *
 * @see https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-lang-analyzer.html
 */
class CustomAnalyzerDefinition implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            'elasticsearch.index.settings' => 'onIndexSettings',
        ];
    }

    /**
     * Add custom analyzers to index settings.
     *
     * Performance Notes:
     * - Analyzers are only applied during indexing
     * - More filters = slower indexing but potentially better search
     * - Keep search_analyzer simple for fast queries
     */
    public function onIndexSettings(array &$settings): void
    {
        $settings['analysis'] = array_merge_recursive(
            $settings['analysis'] ?? [],
            $this->getAnalysisSettings()
        );
    }

    private function getAnalysisSettings(): array
    {
        return [
            'analyzer' => [
                // Full German text analyzer
                'german_analyzer' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                        'german_stop',
                        'german_normalization',
                        'german_stemmer',
                    ],
                ],

                // Autocomplete analyzer with edge n-grams
                'autocomplete_analyzer' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                        'autocomplete_filter',
                    ],
                ],

                // Search-time analyzer for autocomplete (no n-grams)
                'autocomplete_search' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                    ],
                ],

                // Keyword analyzer with lowercase (for exact matches)
                'keyword_lowercase' => [
                    'type' => 'custom',
                    'tokenizer' => 'keyword',
                    'filter' => [
                        'lowercase',
                        'trim',
                    ],
                ],

                // Phonetic analyzer for fuzzy matching
                'phonetic_german' => [
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => [
                        'lowercase',
                        'cologne_phonetic',
                    ],
                ],
            ],

            'filter' => [
                // German stopwords
                'german_stop' => [
                    'type' => 'stop',
                    'stopwords' => '_german_',
                ],

                // German stemmer (light version for better precision)
                'german_stemmer' => [
                    'type' => 'stemmer',
                    'language' => 'light_german',
                ],

                // Edge n-gram for autocomplete (2-15 chars)
                'autocomplete_filter' => [
                    'type' => 'edge_ngram',
                    'min_gram' => 2,
                    'max_gram' => 15,
                    'preserve_original' => true,
                ],

                // Cologne phonetic for German fuzzy matching
                'cologne_phonetic' => [
                    'type' => 'phonetic',
                    'encoder' => 'cologne',
                    'replace' => false,
                ],

                // Synonym filter (customize for your domain)
                'german_synonyms' => [
                    'type' => 'synonym',
                    'synonyms' => [
                        'notebook, laptop, mobilrechner',
                        'handy, smartphone, mobiltelefon',
                        'fernseher, tv, television',
                        'kühlschrank, kühlgerät',
                        'drucker, printer',
                        'maus, mouse',
                        'tastatur, keyboard',
                    ],
                ],
            ],

            'normalizer' => [
                // Lowercase normalizer for keywords
                'lowercase' => [
                    'type' => 'custom',
                    'filter' => ['lowercase'],
                ],
            ],

            'char_filter' => [
                // HTML strip for descriptions
                'html_strip' => [
                    'type' => 'html_strip',
                ],

                // Replace umlauts (optional, usually not needed)
                'umlaut_mapping' => [
                    'type' => 'mapping',
                    'mappings' => [
                        'ä => ae',
                        'ö => oe',
                        'ü => ue',
                        'ß => ss',
                    ],
                ],
            ],
        ];
    }
}
