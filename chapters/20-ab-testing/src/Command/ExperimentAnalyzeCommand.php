<?php

declare(strict_types=1);

namespace ShopwarePerformance\ABTesting\Command;

use ShopwarePerformance\ABTesting\Service\PerformanceVariantCollector;
use ShopwarePerformance\ABTesting\Service\StatisticalAnalyzer;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

/**
 * ExperimentAnalyzeCommand - CLI Command für Experiment-Analyse
 *
 * @description
 * Analysiert Experiment-Ergebnisse direkt aus Shopware CLI.
 *
 * @usage
 * bin/console experiment:analyze checkout_optimization --confidence=0.95
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */
#[AsCommand(
    name: 'experiment:analyze',
    description: 'Analyze A/B test results and calculate statistical significance'
)]
class ExperimentAnalyzeCommand extends Command
{
    public function __construct(
        private readonly PerformanceVariantCollector $collector,
        private readonly StatisticalAnalyzer $analyzer
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addArgument(
                'experiment-id',
                InputArgument::REQUIRED,
                'Experiment ID or key'
            )
            ->addOption(
                'confidence',
                'c',
                InputOption::VALUE_OPTIONAL,
                'Confidence level (0.90, 0.95, 0.99)',
                '0.95'
            )
            ->addOption(
                'metric',
                'm',
                InputOption::VALUE_OPTIONAL,
                'Specific metric to analyze (lcp, fid, cls, etc.)'
            )
            ->addOption(
                'bayesian',
                'b',
                InputOption::VALUE_NONE,
                'Use Bayesian analysis instead of frequentist'
            )
            ->addOption(
                'export',
                'e',
                InputOption::VALUE_OPTIONAL,
                'Export results to file'
            );
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);

        $experimentId = $input->getArgument('experiment-id');
        $confidence = (float) $input->getOption('confidence');
        $metric = $input->getOption('metric');
        $bayesian = $input->getOption('bayesian');
        $exportFile = $input->getOption('export');

        $io->title("Analyzing Experiment: {$experimentId}");

        // Daten laden
        $io->section('Loading Data');

        $aggregated = $this->collector->getAggregatedMetrics($experimentId);

        if (empty($aggregated)) {
            $io->error('No data found for this experiment');
            return Command::FAILURE;
        }

        // Varianten identifizieren
        $variants = array_keys($aggregated);
        $io->info(sprintf('Found %d variants: %s', count($variants), implode(', ', $variants)));

        if (count($variants) < 2) {
            $io->error('Need at least 2 variants for comparison');
            return Command::FAILURE;
        }

        // Control = erste Variante
        $controlName = $variants[0];
        $io->info("Control: {$controlName}");

        // Metriken analysieren
        $metrics = $metric ? [$metric] : array_keys($aggregated[$controlName]);

        $results = [];

        foreach ($metrics as $metricName) {
            $io->section("Metric: " . strtoupper($metricName));

            // Daten für Control
            $controlData = $this->extractMetricValues($experimentId, $controlName, $metricName);

            if (empty($controlData)) {
                $io->warning("No data for {$metricName}");
                continue;
            }

            $controlStats = $aggregated[$controlName][$metricName];

            $io->writeln([
                "Control ({$controlName}):",
                "  Mean: {$controlStats['mean']}",
                "  Std Dev: {$controlStats['stddev']}",
                "  Samples: {$controlStats['sample_count']}",
                "",
            ]);

            // Vergleiche mit anderen Varianten
            foreach ($variants as $variantName) {
                if ($variantName === $controlName) {
                    continue;
                }

                $variantData = $this->extractMetricValues($experimentId, $variantName, $metricName);

                if (empty($variantData)) {
                    continue;
                }

                $variantStats = $aggregated[$variantName][$metricName];

                $io->writeln([
                    "{$variantName}:",
                    "  Mean: {$variantStats['mean']}",
                    "  Std Dev: {$variantStats['stddev']}",
                    "  Samples: {$variantStats['sample_count']}",
                ]);

                // Statistische Analyse
                if ($bayesian) {
                    $result = $this->analyzer->bayesianAnalysis($controlData, $variantData);

                    $io->writeln([
                        "",
                        "  Bayesian Analysis:",
                        "  Probability to be best: " . number_format($result->getProbabilityToBeBest() * 100, 2) . "%",
                        "  Expected loss: {$result->toArray()['expected_loss']}",
                        "",
                    ]);

                    if ($result->shouldDeploy(0.95)) {
                        $io->success("✓ DEPLOY - High confidence winner");
                    } else {
                        $io->warning("⚠ Continue testing");
                    }
                } else {
                    $result = $this->analyzer->calculateSignificance(
                        $controlData,
                        $variantData,
                        $confidence
                    );

                    $improvement = $result->getImprovement();

                    $io->writeln([
                        "",
                        "  Statistical Analysis:",
                        "  Improvement: " . ($improvement > 0 ? '+' : '') . number_format($improvement, 2) . "%",
                        "  p-value: " . number_format($result->getPValue(), 4),
                        "  Effect size: " . number_format($result->toArray()['effect_size'], 3),
                        "  Statistical power: " . number_format($result->getStatisticalPower(), 2),
                        "",
                    ]);

                    if ($result->isSignificant()) {
                        if ($result->getWinner() === 'variant') {
                            $io->success("✓ SIGNIFICANT - Variant is better");
                        } else {
                            $io->error("✗ SIGNIFICANT - Variant is worse");
                        }
                    } else {
                        $io->warning("⚪ NOT SIGNIFICANT - Continue testing");
                    }
                }

                $results[] = [
                    'metric' => $metricName,
                    'variant' => $variantName,
                    'result' => $bayesian ? $result->toArray() : $result->toArray(),
                ];

                $io->newLine();
            }
        }

        // Export
        if ($exportFile) {
            file_put_contents($exportFile, json_encode($results, JSON_PRETTY_PRINT));
            $io->success("Results exported to {$exportFile}");
        }

        $io->success('Analysis complete');

        return Command::SUCCESS;
    }

    /**
     * Extrahiert Metrik-Werte für Analyse
     *
     * @param string $experimentId Experiment-ID
     * @param string $variant Varianten-Name
     * @param string $metric Metrik-Name
     * @return array<float> Metrik-Werte
     */
    private function extractMetricValues(string $experimentId, string $variant, string $metric): array
    {
        $raw = $this->collector->getRawMetrics($experimentId);

        $values = [];

        foreach ($raw as $row) {
            if ($row['variant'] === $variant && $row['metric'] === $metric) {
                $values[] = (float) $row['value'];
            }
        }

        return $values;
    }
}
