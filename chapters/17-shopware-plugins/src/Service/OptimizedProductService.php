<?php

declare(strict_types=1);

namespace App\Service;

use Shopware\Core\Content\Product\ProductCollection;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting\FieldSorting;

/**
 * DAL-Abfragen, die nur laden, was die Seite anzeigt.
 *
 * Getestet mit Shopware 6.6.10.6 (Dockware, Demo-Daten).
 *
 * @see Kapitel 17, "Die DAL performant nutzen"
 * @see https://developer.shopware.com/docs/resources/references/adr/2023-02-02-deprecate-autoload-true-in-dal-associations.html
 */
class OptimizedProductService
{
    public function __construct(
        private readonly EntityRepository $productRepository
    ) {}

    /**
     * Lädt nur die wirklich benötigten Felder und Assoziationen
     */
    public function getProductsForListing(
        string $categoryId,
        Context $context,
        int $limit = 24
    ): ProductCollection {
        $criteria = new Criteria();
        $criteria->setLimit($limit);

        // Filter so früh wie möglich
        $criteria->addFilter(
            new EqualsFilter('categories.id', $categoryId)
        );

        // NUR benötigte Assoziationen - keine Tiefe!
        $criteria->addAssociation('cover.media');

        // Staffelpreise: nur die erste Staffel. Ohne Sortierung
        // wäre "der erste" ein beliebiger Datensatz.
        $criteria->getAssociation('prices')
            ->addSorting(new FieldSorting('quantityStart'))
            ->setLimit(1);

        return $this->productRepository
            ->search($criteria, $context)
            ->getEntities();
    }

    /**
     * Nur IDs, keine Entities: searchIds() hydriert nichts.
     * Das ist der DAL-Weg, wenn Erweiterbarkeit (Events,
     * Extensions) wichtiger ist als der letzte Rest Tempo.
     *
     * @return list<string>
     */
    public function getActiveProductIds(Context $context, int $limit = 1000): array
    {
        $criteria = new Criteria();
        $criteria->setLimit($limit);
        $criteria->addFilter(new EqualsFilter('active', true));
        $criteria->addFilter(new EqualsFilter('parentId', null));

        /** @var list<string> $ids */
        $ids = $this->productRepository->searchIds($criteria, $context)->getIds();

        return $ids;
    }
}
