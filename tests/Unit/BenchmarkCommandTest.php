<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../Stubs/ShopwareStubs.php';
require_once __DIR__ . '/../../src/Service/QueryOptimizer.php';
require_once __DIR__ . '/../../src/Command/BenchmarkCommand.php';

use PerformanceExamples\Command\BenchmarkCommand;
use PerformanceExamples\Service\QueryOptimizer;

/**
 * Unit Tests for BenchmarkCommand
 *
 * Tests the benchmark command configuration from Chapter 2.
 */
class BenchmarkCommandTest extends TestCase
{
    private BenchmarkCommand $command;

    protected function setUp(): void
    {
        $queryOptimizer = $this->createMock(QueryOptimizer::class);
        $this->command = new BenchmarkCommand($queryOptimizer);
    }

    /**
     * Test command name.
     */
    public function testCommandName(): void
    {
        $this->assertSame('performance:benchmark', $this->command->getName());
    }

    /**
     * Test command description.
     */
    public function testCommandDescription(): void
    {
        $this->assertSame(
            'Runs performance benchmarks for common Shopware operations',
            $this->command->getDescription()
        );
    }

    /**
     * Test iterations option exists and has correct default.
     */
    public function testIterationsOption(): void
    {
        $definition = $this->command->getDefinition();

        $this->assertTrue($definition->hasOption('iterations'));

        $option = $definition->getOption('iterations');
        $this->assertSame('i', $option->getShortcut());
        $this->assertSame(10, $option->getDefault());
        $this->assertTrue($option->isValueRequired());
    }

    /**
     * Test command is an instance of Symfony Command.
     */
    public function testIsSymfonyCommand(): void
    {
        $this->assertInstanceOf(
            \Symfony\Component\Console\Command\Command::class,
            $this->command
        );
    }
}
