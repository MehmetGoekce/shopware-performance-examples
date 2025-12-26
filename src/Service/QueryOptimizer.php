<?php

declare(strict_types=1);

namespace PerformanceExamples\Service;

use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\MultiFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric\CountAggregation;

/**
 * Optimierte Datenbankabfragen für Shopware 6
 *
 * Kapitel 8: Datenbank-Optimierung
 *
 * Demonstriert Best Practices:
 * - Minimale Feldauswahl
 * - Effiziente Filter
 * - Aggregationen statt Schleifen
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
class QueryOptimizer
{
    public function __construct(
        private readonly EntityRepository $productRepository,
        private readonly EntityRepository $orderRepository
    ) {}

    /**
     * SCHLECHT: Lädt alle Felder und Relationen
     *
     * Problem: Diese Abfrage lädt ALLES, auch wenn nur IDs benötigt werden.
     * Bei 10.000 Produkten = mehrere MB Daten + dutzende JOINs.
     */
    public function getProductsBad(Context $context): array
    {
        $criteria = new Criteria();
        // FEHLER: Keine Limits
        // FEHLER: Lädt alle Assoziationen
        $criteria->addAssociation('categories');
        $criteria->addAssociation('manufacturer');
        $criteria->addAssociation('media');
        $criteria->addAssociation('prices');
        $criteria->addAssociation('properties');

        return $this->productRepository
            ->search($criteria, $context)
            ->getElements();
    }

    /**
     * GUT: Lädt nur benötigte Felder
     *
     * Performance-Verbesserung: ~90% weniger Daten, ~80% schneller
     */
    public function getProductsGood(Context $context, int $limit = 100): array
    {
        $criteria = new Criteria();
        $criteria->setLimit($limit);

        // Nur benötigte Felder laden
        $criteria->addFields(['id', 'productNumber', 'name', 'stock']);

        // Nur aktive Produkte
        $criteria->addFilter(new EqualsFilter('active', true));

        return $this->productRepository
            ->search($criteria, $context)
            ->getElements();
    }

    /**
     * SCHLECHT: Zählt in PHP-Schleife
     *
     * Problem: Lädt ALLE Bestellungen in den Speicher nur um zu zählen.
     */
    public function countOrdersBad(Context $context, string $customerId): int
    {
        $criteria = new Criteria();
        $criteria->addFilter(new EqualsFilter('orderCustomer.customerId', $customerId));

        $orders = $this->orderRepository->search($criteria, $context);

        // FEHLER: Zählen in PHP statt SQL
        return count($orders->getElements());
    }

    /**
     * GUT: Verwendet COUNT-Aggregation
     *
     * Performance-Verbesserung: Nur 1 Zahl statt alle Datensätze
     */
    public function countOrdersGood(Context $context, string $customerId): int
    {
        $criteria = new Criteria();
        $criteria->addFilter(new EqualsFilter('orderCustomer.customerId', $customerId));

        // Aggregation statt Datensätze laden
        $criteria->addAggregation(new CountAggregation('order_count', 'id'));

        // Keine Daten laden, nur Aggregation
        $criteria->setLimit(0);

        $result = $this->orderRepository->search($criteria, $context);

        /** @var \Shopware\Core\Framework\DataAbstractionLayer\Search\AggregationResult\Metric\CountResult $count */
        $count = $result->getAggregations()->get('order_count');

        return $count?->getCount() ?? 0;
    }

    /**
     * Optimierte Produktsuche mit mehreren Filtern
     *
     * Verwendet MultiFilter für effiziente WHERE-Klauseln
     */
    public function searchProducts(
        Context $context,
        ?string $categoryId = null,
        ?float $minPrice = null,
        ?float $maxPrice = null,
        int $limit = 50
    ): array {
        $criteria = new Criteria();
        $criteria->setLimit($limit);
        $criteria->addFields(['id', 'name', 'productNumber', 'price']);

        $filters = [
            new EqualsFilter('active', true),
        ];

        if ($categoryId !== null) {
            $filters[] = new EqualsFilter('categoryTree', $categoryId);
        }

        if ($minPrice !== null) {
            $filters[] = new \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter(
                'price.gross',
                [
                    \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter::GTE => $minPrice,
                ]
            );
        }

        if ($maxPrice !== null) {
            $filters[] = new \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter(
                'price.gross',
                [
                    \Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\RangeFilter::LTE => $maxPrice,
                ]
            );
        }

        // Alle Filter kombinieren
        $criteria->addFilter(new MultiFilter(MultiFilter::CONNECTION_AND, $filters));

        return $this->productRepository
            ->search($criteria, $context)
            ->getElements();
    }
}
