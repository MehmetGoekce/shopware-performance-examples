<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Tests;

use PHPUnit\Framework\TestCase;
use ShopwarePerformance\ABTesting\Service\ExperimentService;
use ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * ExperimentServiceTest - Unit Tests für ExperimentService
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */
class ExperimentServiceTest extends TestCase
{
    private ExperimentService $experimentService;
    private EntityRepository $experimentRepository;
    private RequestStack $requestStack;
    private PerformanceVariantCollector $collector;

    protected function setUp(): void
    {
        $this->experimentRepository = $this->createMock(EntityRepository::class);
        $this->requestStack = $this->createMock(RequestStack::class);
        $this->collector = $this->createMock(PerformanceVariantCollector::class);

        $this->experimentService = new ExperimentService(
            $this->experimentRepository,
            $this->requestStack,
            $this->collector
        );
    }

    public function testCreateExperiment(): void
    {
        $experimentData = [
            'name' => 'Test Experiment',
            'variants' => ['control', 'variant_a'],
            'traffic_split' => [50, 50],
            'performance_budget' => [
                'lcp' => 2500,
                'fid' => 100,
            ],
        ];

        $context = Context::createDefaultContext();

        $this->experimentRepository
            ->expects($this->once())
            ->method('create')
            ->willReturn($this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\Event\EntityWrittenContainerEvent::class));

        $experimentId = $this->experimentService->create($experimentData, $context);

        $this->assertIsString($experimentId);
    }

    public function testCreateExperimentWithInvalidData(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        $invalidData = [
            'name' => '',
            'variants' => ['control'],
            'traffic_split' => [100],
        ];

        $context = Context::createDefaultContext();

        $this->experimentService->create($invalidData, $context);
    }

    public function testTrafficSplitMustSumTo100(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Traffic split must sum to 100');

        $invalidData = [
            'name' => 'Test',
            'variants' => ['control', 'variant'],
            'traffic_split' => [40, 40],
        ];

        $context = Context::createDefaultContext();

        $this->experimentService->create($invalidData, $context);
    }

    public function testAssignVariantDeterministically(): void
    {
        // Derselbe User sollte immer dieselbe Variante bekommen
        $salesChannelContext = $this->createMock(\Shopware\Core\System\SalesChannel\SalesChannelContext::class);

        $salesChannelContext
            ->method('getCustomer')
            ->willReturn(null);

        $salesChannelContext
            ->method('getToken')
            ->willReturn('fixed-token-123');

        $request = $this->createMock(\Symfony\Component\HttpFoundation\Request::class);
        $request->cookies = new \Symfony\Component\HttpFoundation\ParameterBag();

        $this->requestStack
            ->method('getCurrentRequest')
            ->willReturn($request);

        // Mock Experiment
        $this->mockExperiment('test_experiment', [
            'id' => 'test-id',
            'status' => 'running',
            'variants' => [
                ['name' => 'control', 'traffic_percentage' => 50],
                ['name' => 'variant_a', 'traffic_percentage' => 50],
            ],
        ]);

        $variant1 = $this->experimentService->assignVariant('test_experiment', $salesChannelContext);
        $variant2 = $this->experimentService->assignVariant('test_experiment', $salesChannelContext);

        // Sollte deterministisch sein
        $this->assertSame($variant1, $variant2);
    }

    public function testAssignVariantRespectsTrafficSplit(): void
    {
        // Mit genügend Samples sollte Traffic-Split eingehalten werden
        $samples = 1000;
        $variants = [];

        for ($i = 0; $i < $samples; $i++) {
            $salesChannelContext = $this->createMock(\Shopware\Core\System\SalesChannel\SalesChannelContext::class);

            $salesChannelContext
                ->method('getToken')
                ->willReturn('token-' . $i);

            $request = $this->createMock(\Symfony\Component\HttpFoundation\Request::class);
            $request->cookies = new \Symfony\Component\HttpFoundation\ParameterBag();

            $this->requestStack
                ->method('getCurrentRequest')
                ->willReturn($request);

            $this->mockExperiment('test_experiment', [
                'id' => 'test-id',
                'status' => 'running',
                'variants' => [
                    ['name' => 'control', 'traffic_percentage' => 50],
                    ['name' => 'variant_a', 'traffic_percentage' => 50],
                ],
            ]);

            $variant = $this->experimentService->assignVariant('test_experiment', $salesChannelContext);
            $variants[] = $variant;
        }

        // Zähle Varianten
        $counts = array_count_values($variants);

        // Traffic sollte ungefähr 50/50 sein (mit Toleranz)
        $controlPercent = ($counts['control'] ?? 0) / $samples * 100;
        $variantPercent = ($counts['variant_a'] ?? 0) / $samples * 100;

        $this->assertGreaterThan(40, $controlPercent);
        $this->assertLessThan(60, $controlPercent);
        $this->assertGreaterThan(40, $variantPercent);
        $this->assertLessThan(60, $variantPercent);
    }

    public function testReturnControlWhenExperimentNotRunning(): void
    {
        $salesChannelContext = $this->createMock(\Shopware\Core\System\SalesChannel\SalesChannelContext::class);

        $this->mockExperiment('paused_experiment', [
            'id' => 'test-id',
            'status' => 'paused',
        ]);

        $variant = $this->experimentService->assignVariant('paused_experiment', $salesChannelContext);

        $this->assertSame('control', $variant);
    }

    public function testTrackMetric(): void
    {
        $salesChannelContext = $this->createMock(\Shopware\Core\System\SalesChannel\SalesChannelContext::class);

        $this->mockExperiment('test_experiment', [
            'id' => 'test-id',
            'status' => 'running',
            'performanceBudget' => [
                'lcp' => 2500,
            ],
        ]);

        $this->collector
            ->expects($this->once())
            ->method('collect')
            ->with(
                $this->equalTo('test-id'),
                $this->equalTo('control'),
                $this->equalTo('lcp'),
                $this->equalTo(2100.0),
                $this->equalTo($salesChannelContext)
            );

        $this->experimentService->trackMetric(
            'test_experiment',
            'control',
            'lcp',
            2100.0,
            $salesChannelContext
        );
    }

    public function testPauseExperimentWhenBudgetExceeded(): void
    {
        $salesChannelContext = $this->createMock(\Shopware\Core\System\SalesChannel\SalesChannelContext::class);
        $context = Context::createDefaultContext();

        $salesChannelContext
            ->method('getContext')
            ->willReturn($context);

        $this->mockExperiment('test_experiment', [
            'id' => 'test-id',
            'status' => 'running',
            'performanceBudget' => [
                'lcp' => 2500,
            ],
        ]);

        $this->experimentRepository
            ->expects($this->once())
            ->method('update')
            ->with($this->callback(function ($data) {
                return $data[0]['status'] === 'paused'
                    && str_contains($data[0]['pauseReason'], 'Performance budget exceeded');
            }));

        // Metrik über Budget
        $this->experimentService->trackMetric(
            'test_experiment',
            'variant_a',
            'lcp',
            3000.0,
            $salesChannelContext
        );
    }

    private function mockExperiment(string $key, array $data): void
    {
        $result = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\Search\EntitySearchResult::class);

        $result
            ->method('count')
            ->willReturn(1);

        $entity = $this->createMock(\Shopware\Core\Framework\DataAbstractionLayer\Entity::class);

        $entity
            ->method('jsonSerialize')
            ->willReturn($data);

        $result
            ->method('first')
            ->willReturn($entity);

        $this->experimentRepository
            ->method('search')
            ->willReturn($result);
    }
}
