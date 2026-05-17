<?php

declare(strict_types=1);

namespace App\ElasticsearchExtension;

use Shopware\Core\System\CustomField\CustomFieldTypes;
use Shopware\Elasticsearch\Event\ElasticsearchCustomFieldsMappingEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Extends the Elasticsearch *custom-fields* mapping for the product entity.
 *
 * The event only touches custom fields (index path
 * customFields.<languageId>.<name>), not arbitrary top-level fields.
 *
 * setMapping(string $field, string $type): $type is a CustomFieldTypes::*
 * constant, NOT a raw Elasticsearch type. Shopware translates it in
 * Shopware\Elasticsearch\Product\CustomFieldUpdater::getTypeFromCustomFieldType():
 *
 *   INT -> long | FLOAT -> double | BOOL -> boolean | DATETIME -> date
 *   TEXT|HTML -> text | PRICE|JSON -> object | everything else -> keyword
 *
 * Trap: 'integer' is not a constant and silently degrades to keyword
 * (breaks range/sort). Use CustomFieldTypes::INT (value 'int'). There is
 * no keyword constant; the literal 'keyword' only works via the default
 * branch — the community's de-facto pattern, not a typed contract.
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
     * Extend the product custom-fields mapping.
     *
     * - Numeric fields: CustomFieldTypes::INT -> ES "long" (range/sort)
     * - Exact-match string fields: ES "keyword" via the default branch
     *   (no dedicated keyword constant exists)
     */
    public function onProductMapping(ElasticsearchCustomFieldsMappingEvent $event): void
    {
        if ($event->getEntity() !== 'product') {
            return;
        }

        // Custom sort value for manual product ordering -> ES "long"
        $event->setMapping('customSortValue', CustomFieldTypes::INT);

        // Exact-match string fields -> ES "keyword" (default branch).
        // The literal 'keyword' is not a CustomFieldTypes constant; it
        // resolves to the keyword ES type only because Shopware's match()
        // routes every unlisted value through the default arm.
        $event->setMapping('productNumberExact', 'keyword');
        $event->setMapping('ean', 'keyword');
        $event->setMapping('manufacturerNumber', 'keyword');
        $event->setMapping('searchKeywords', 'keyword');

        // Rating scaled to integer (0-500 for 0.0-5.0) -> ES "long"
        $event->setMapping('ratingScaled', CustomFieldTypes::INT);
    }
}
