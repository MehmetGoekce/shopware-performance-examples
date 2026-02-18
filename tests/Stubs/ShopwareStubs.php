<?php

declare(strict_types=1);

/**
 * Stub classes for Shopware dependencies in unit tests.
 *
 * These stubs allow testing Shopware-dependent code without
 * requiring the full Shopware installation.
 */

namespace Shopware\Core\System\SystemConfig;

class SystemConfigService
{
    public function get(string $key, ?string $salesChannelId = null): mixed
    {
        return null;
    }

    public function set(string $key, mixed $value, ?string $salesChannelId = null): void
    {
    }
}

namespace Shopware\Storefront\Theme;

class ThemeService
{
    public function compileTheme(
        string $salesChannelId,
        string $themeId,
        \Shopware\Core\Framework\Context $context,
        ?callable $configurationCollection = null
    ): void {
    }
}

namespace Shopware\Core\Framework;

class Context
{
    public static function createDefaultContext(): self
    {
        return new self();
    }
}

namespace Shopware\Core\Framework\DataAbstractionLayer;

class EntityRepository
{
    public function search(Search\Criteria $criteria, \Shopware\Core\Framework\Context $context): Search\EntitySearchResult
    {
        return new Search\EntitySearchResult('', 0, new EntityCollection(), null, $criteria, $context);
    }
}

class EntityCollection implements \Countable, \IteratorAggregate
{
    public function count(): int { return 0; }
    public function getIterator(): \ArrayIterator { return new \ArrayIterator([]); }
}

namespace Shopware\Core\Framework\DataAbstractionLayer\Search;

class Criteria
{
    private ?int $limit = null;

    public function __construct(private readonly array $ids = []) {}
    public function setLimit(?int $limit): self { $this->limit = $limit; return $this; }
    public function addFilter(mixed ...$filters): self { return $this; }
    public function addSorting(mixed ...$sortings): self { return $this; }
    public function addAssociation(string $association): self { return $this; }
    public function addFields(array $fields): self { return $this; }
    public function addAggregation(mixed $aggregation): self { return $this; }
    public function getLimit(): ?int { return $this->limit; }
}

class EntitySearchResult implements \Countable, \IteratorAggregate
{
    public function __construct(
        private readonly string $entity = '',
        private readonly int $total = 0,
        private readonly mixed $entities = null,
        private readonly mixed $aggregations = null,
        private readonly ?Criteria $criteria = null,
        private readonly mixed $context = null
    ) {}
    public function getIds(): array { return []; }
    public function getElements(): array { return []; }
    public function first(): mixed { return null; }
    public function count(): int { return $this->total; }
    public function getIterator(): \ArrayIterator { return new \ArrayIterator([]); }
    public function getAggregations(): AggregationResult\AggregationResultCollection { return new AggregationResult\AggregationResultCollection(); }
}

namespace Shopware\Core\Framework\DataAbstractionLayer\Search\Filter;

class EqualsFilter
{
    public function __construct(public readonly string $field, public readonly mixed $value) {}
}

class MultiFilter
{
    public const CONNECTION_AND = 'AND';
    public const CONNECTION_OR = 'OR';
    public function __construct(public readonly string $operator, public readonly array $queries) {}
}

class RangeFilter
{
    public const GTE = 'gte';
    public const LTE = 'lte';
    public function __construct(public readonly string $field, public readonly array $parameters) {}
}

namespace Shopware\Core\Framework\DataAbstractionLayer\Search\Sorting;

class FieldSorting
{
    public function __construct(public readonly string $field, public readonly string $direction = 'ASC') {}
}

namespace Shopware\Core\Framework\DataAbstractionLayer\Search\Aggregation\Metric;

class CountAggregation
{
    public function __construct(public readonly string $name, public readonly string $field) {}
}

namespace Shopware\Core\Framework\DataAbstractionLayer\Search\AggregationResult;

class AggregationResultCollection
{
    public function get(string $name): ?Metric\CountResult { return null; }
}

namespace Shopware\Core\Framework\DataAbstractionLayer\Search\AggregationResult\Metric;

class CountResult
{
    public function __construct(private readonly int $count = 0) {}
    public function getCount(): int { return $this->count; }
}

namespace Shopware\Core\Framework\Adapter\Cache;

class CacheInvalidator
{
    public function invalidate(array $tags): void {}
}

namespace Shopware\Core\Framework\Routing;

class KernelListenerPriorities
{
    public const KERNEL_CONTROLLER_EVENT_SCOPE_VALIDATE = 0;
}

namespace Symfony\Component\EventDispatcher;

if (!interface_exists(\Symfony\Component\EventDispatcher\EventSubscriberInterface::class, false)) {
    interface EventSubscriberInterface
    {
        public static function getSubscribedEvents(): array;
    }
}

namespace Symfony\Component\HttpKernel;

if (!class_exists(\Symfony\Component\HttpKernel\KernelEvents::class, false)) {
    class KernelEvents
    {
        public const RESPONSE = 'kernel.response';
    }
}

namespace Symfony\Component\HttpKernel\Event;

if (!class_exists(\Symfony\Component\HttpKernel\Event\ResponseEvent::class, false)) {
    class ResponseEvent
    {
        public function getRequest(): mixed { return null; }
        public function getResponse(): mixed { return null; }
    }
}

namespace Shopware\Core;

class PlatformRequest
{
    public const ATTRIBUTE_SALES_CHANNEL_ID = 'sw-sales-channel-id';
}

namespace Shopware\Storefront\Event;

class StorefrontRenderEvent {}

namespace Shopware\Storefront\Controller;

class StorefrontController
{
    protected function renderStorefront(string $view, array $parameters = []): mixed
    {
        return null;
    }
}

