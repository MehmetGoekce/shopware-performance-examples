<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use Shopware\Core\Content\Product\Events\ProductSearchCriteriaEvent;
use Shopware\Core\Content\Product\Events\ProductSuggestCriteriaEvent;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Customizes search relevance and boosting for Elasticsearch queries.
 *
 * This subscriber modifies search queries to:
 * - Boost exact matches higher than partial matches
 * - Prioritize in-stock products
 * - Apply custom scoring functions
 *
 * Usage:
 *   Register as service with kernel.event_subscriber tag
 *
 * Performance Tips:
 * - Use function_score sparingly (adds query overhead)
 * - Prefer filter context over query context for non-scoring conditions
 * - Test boost values with real user behavior data
 */
class SearchBoostSubscriber implements EventSubscriberInterface
{
    /**
     * Boost values for different match types.
     * Higher = more important for ranking.
     */
    private const BOOST_EXACT_MATCH = 100.0;
    private const BOOST_PRODUCT_NUMBER = 80.0;
    private const BOOST_NAME = 50.0;
    private const BOOST_DESCRIPTION = 10.0;
    private const BOOST_IN_STOCK = 1.2; // 20% boost for in-stock items

    public static function getSubscribedEvents(): array
    {
        return [
            ProductSearchCriteriaEvent::class => 'onProductSearch',
            ProductSuggestCriteriaEvent::class => 'onProductSuggest',
        ];
    }

    /**
     * Modify search criteria for product listings.
     */
    public function onProductSearch(ProductSearchCriteriaEvent $event): void
    {
        $criteria = $event->getCriteria();
        $term = $criteria->getTerm();

        if (empty($term)) {
            return;
        }

        // Add custom extensions for ES query modification
        $criteria->addExtension('customSearchBoost', new SearchBoostExtension([
            'exactMatchBoost' => self::BOOST_EXACT_MATCH,
            'productNumberBoost' => self::BOOST_PRODUCT_NUMBER,
            'nameBoost' => self::BOOST_NAME,
            'descriptionBoost' => self::BOOST_DESCRIPTION,
            'inStockBoost' => self::BOOST_IN_STOCK,
        ]));
    }

    /**
     * Modify criteria for autocomplete/suggest.
     * Prioritize fast response over complex scoring.
     */
    public function onProductSuggest(ProductSuggestCriteriaEvent $event): void
    {
        $criteria = $event->getCriteria();

        // Limit suggest results for speed
        $criteria->setLimit(10);

        // Only return essential fields for autocomplete
        $criteria->setIncludes([
            'product' => [
                'id',
                'name',
                'productNumber',
                'cover',
            ],
        ]);
    }
}

/**
 * Extension to carry boost configuration to ES query builder.
 */
class SearchBoostExtension extends \Shopware\Core\Framework\Struct\Struct
{
    protected float $exactMatchBoost;
    protected float $productNumberBoost;
    protected float $nameBoost;
    protected float $descriptionBoost;
    protected float $inStockBoost;

    public function __construct(array $data)
    {
        $this->exactMatchBoost = $data['exactMatchBoost'] ?? 100.0;
        $this->productNumberBoost = $data['productNumberBoost'] ?? 80.0;
        $this->nameBoost = $data['nameBoost'] ?? 50.0;
        $this->descriptionBoost = $data['descriptionBoost'] ?? 10.0;
        $this->inStockBoost = $data['inStockBoost'] ?? 1.2;
    }

    public function getExactMatchBoost(): float
    {
        return $this->exactMatchBoost;
    }

    public function getProductNumberBoost(): float
    {
        return $this->productNumberBoost;
    }

    public function getNameBoost(): float
    {
        return $this->nameBoost;
    }

    public function getDescriptionBoost(): float
    {
        return $this->descriptionBoost;
    }

    public function getInStockBoost(): float
    {
        return $this->inStockBoost;
    }
}
