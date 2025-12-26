<?php

declare(strict_types=1);

namespace PerformanceExamples\Command;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;
use Symfony\Component\Stopwatch\Stopwatch;

/**
 * Performance Benchmark Command
 *
 * Kapitel 2: Performance-Audit
 *
 * Misst die Ausführungszeit verschiedener Shopware-Operationen.
 *
 * Verwendung:
 *   bin/console performance:benchmark
 *   bin/console performance:benchmark --iterations=100
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
#[AsCommand(
    name: 'performance:benchmark',
    description: 'Runs performance benchmarks for common Shopware operations'
)]
class BenchmarkCommand extends Command
{
    public function __construct(
        private readonly \PerformanceExamples\Service\QueryOptimizer $queryOptimizer
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption(
                'iterations',
                'i',
                InputOption::VALUE_REQUIRED,
                'Number of iterations per benchmark',
                10
            );
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $iterations = (int) $input->getOption('iterations');
        $stopwatch = new Stopwatch();

        $io->title('Shopware Performance Benchmark');
        $io->text(sprintf('Running %d iterations per test...', $iterations));
        $io->newLine();

        $context = \Shopware\Core\Framework\Context::createDefaultContext();
        $results = [];

        // Benchmark 1: Unoptimierte Produktabfrage
        $io->section('1. Product Query (unoptimized)');
        $stopwatch->start('products_bad');
        for ($i = 0; $i < $iterations; $i++) {
            $this->queryOptimizer->getProductsBad($context);
        }
        $event = $stopwatch->stop('products_bad');
        $results['Products (unoptimized)'] = $event->getDuration() / $iterations;
        $io->text(sprintf('Average: %.2f ms', $results['Products (unoptimized)']));

        // Benchmark 2: Optimierte Produktabfrage
        $io->section('2. Product Query (optimized)');
        $stopwatch->start('products_good');
        for ($i = 0; $i < $iterations; $i++) {
            $this->queryOptimizer->getProductsGood($context, 100);
        }
        $event = $stopwatch->stop('products_good');
        $results['Products (optimized)'] = $event->getDuration() / $iterations;
        $io->text(sprintf('Average: %.2f ms', $results['Products (optimized)']));

        // Ergebnisse
        $io->newLine();
        $io->section('Results Summary');

        $tableData = [];
        foreach ($results as $name => $avgMs) {
            $tableData[] = [$name, sprintf('%.2f ms', $avgMs)];
        }

        $io->table(['Benchmark', 'Avg Time'], $tableData);

        // Verbesserung berechnen
        if (isset($results['Products (unoptimized)'], $results['Products (optimized)'])) {
            $improvement = (1 - $results['Products (optimized)'] / $results['Products (unoptimized)']) * 100;
            $io->success(sprintf(
                'Optimized queries are %.1f%% faster!',
                $improvement
            ));
        }

        return Command::SUCCESS;
    }
}
