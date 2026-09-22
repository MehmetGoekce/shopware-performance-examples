<?php

declare(strict_types=1);

namespace AbTesting\Command;

use AbTesting\Experiment\ExperimentConfig;
use AbTesting\Log\AssignmentLogReader;
use AbTesting\Log\ExperimentData;
use AbTesting\Stats\StatisticalAnalyzer;
use RumMonitoring\Rum\RumLogReader;
use RumMonitoring\Rum\RumStatistics;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\Table;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * Vergleicht die Varianten eines Experiments anhand der RUM-Logs aus Kapitel 12.
 *
 *   bin/console ab:analyze listing_images --metric=LCP --days=14
 *
 * Exit-Codes: 0 ausgewertet, 1 zu wenig Daten, 2 falscher Aufruf,
 * 3 Sample Ratio Mismatch (Ergebnis nicht verwenden).
 */
#[AsCommand(name: 'ab:analyze', description: 'Welch-t-Test je Variante auf den RUM-Logs, mit SRM-Pruefung')]
class AbAnalyzeCommand extends Command
{
    public const EXIT_SRM = 3;

    /** Strenge Schwelle: Der SRM-Test laeuft bei jeder Auswertung, falscher Alarm soll selten sein */
    private const SRM_ALPHA = 0.001;

    public function __construct(
        private readonly ExperimentConfig $config,
        private readonly RumLogReader $rumReader,
        private readonly AssignmentLogReader $assignments,
        private readonly StatisticalAnalyzer $analyzer,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addArgument('experiment', InputArgument::REQUIRED, 'Experiment-Key aus ab_testing.experiments')
            ->addOption('metric', null, InputOption::VALUE_REQUIRED, 'LCP, INP, CLS, FCP oder TTFB', 'LCP')
            ->addOption('days', null, InputOption::VALUE_REQUIRED, 'Zeitfenster in Tagen (volle Wochen)', '14')
            ->addOption('confidence', null, InputOption::VALUE_REQUIRED, 'Konfidenzniveau', '0.95')
            ->addOption('device', null, InputOption::VALUE_REQUIRED, 'nur mobile oder desktop');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $key = (string) $input->getArgument('experiment');
        $metric = (string) $input->getOption('metric');
        $days = filter_var($input->getOption('days'), \FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
        $confidence = filter_var($input->getOption('confidence'), \FILTER_VALIDATE_FLOAT);
        $device = $input->getOption('device');

        if (!isset($this->config->all()[$key])) {
            $output->writeln(sprintf('<error>Unbekanntes Experiment "%s". Konfiguriert: %s</error>', $key, implode(', ', array_keys($this->config->all()))));

            return Command::INVALID;
        }
        if (
            !isset(RumStatistics::THRESHOLDS[$metric]) || $days === false || $confidence === false || $confidence <= 0 || $confidence >= 1
            || ($device !== null && !\in_array($device, ['mobile', 'desktop'], true))
        ) {
            $output->writeln('<error>--metric LCP|INP|CLS|FCP|TTFB, --days ganze Zahl >= 1, --confidence in (0, 1), --device mobile|desktop</error>');

            return Command::INVALID;
        }

        $since = new \DateTimeImmutable(sprintf('-%d days', $days));
        $values = ExperimentData::valuesByVariant($this->rumReader->read($since), $this->config, $key, $metric, $device);
        $control = $this->config->control($key);
        $format = $metric === 'CLS' ? '%.3f' : '%.0f';

        // Mehr als eine Variante gegen die Kontrolle: Bonferroni, sonst steigt die Fehlerquote
        $comparisons = \count($values) - 1;
        $perComparison = 1 - (1 - $confidence) / $comparisons;

        $output->writeln(sprintf(
            'Experiment %s, %s%s, seit %s (%s)',
            $key,
            $metric,
            $device !== null ? ', ' . $device : '',
            $since->format('Y-m-d H:i T'),
            $metric === 'CLS' ? 'ohne Einheit' : 'Werte in ms'
        ));

        foreach ($values as $variant => $list) {
            if (\count($list) < 2) {
                $output->writeln(sprintf('<error>Zu wenig Daten: %s hat %d Seitenaufrufe mit %s</error>', $variant, \count($list), $metric));

                return Command::FAILURE;
            }
        }

        $rows = [];
        $verdicts = [];
        foreach ($values as $variant => $list) {
            $sorted = $list;
            sort($sorted);
            $row = [$variant, \count($list), sprintf($format, array_sum($list) / \count($list)), sprintf($format, RumStatistics::percentile($sorted, 75)), '', '', ''];

            if ($variant !== $control) {
                $r = $this->analyzer->compare($values[$control], $list, $perComparison);
                $row[4] = sprintf($format . ' (%+.1f %%)', $r->difference, $r->relativeChange);
                $row[5] = sprintf($format . ' bis ' . $format, $r->ciLow, $r->ciHigh);
                $row[6] = $r->pValue < 0.0001 ? '< 0.0001' : sprintf('%.4f', $r->pValue);
                $verdicts[] = match ($r->winner()) {
                    'variant' => sprintf('%s: signifikant besser als %s', $variant, $control),
                    'control' => sprintf('%s: signifikant schlechter als %s', $variant, $control),
                    default => sprintf('%s: kein Unterschied nachgewiesen', $variant),
                };
            }

            $rows[] = $row;
        }

        (new Table($output))
            ->setHeaders(['Variante', 'Seitenaufrufe', 'Mittel', 'p75', 'Differenz zu ' . $control, sprintf('%.4g %%-KI der Differenz', $perComparison * 100), 'p'])
            ->setRows($rows)
            ->render();

        $output->writeln(sprintf('Signifikanzniveau je Vergleich: %.4g', 1 - $perComparison));
        foreach ($verdicts as $verdict) {
            $output->writeln($verdict);
        }

        return $this->checkSampleRatio($key, $since, $output);
    }

    private function checkSampleRatio(string $key, \DateTimeImmutable $since, OutputInterface $output): int
    {
        $weights = $this->config->all()[$key]['variants'];
        $counts = $this->assignments->count($key, $since);

        if (array_sum($counts) === 0) {
            $output->writeln('<comment>SRM nicht geprueft: keine Zuweisungen im Log ab_testing-*.log</comment>');

            return Command::SUCCESS;
        }

        $parts = [];
        foreach ($weights as $variant => $weight) {
            $parts[] = sprintf('%s %d', $variant, $counts[$variant] ?? 0);
        }
        $p = $this->analyzer->sampleRatioMismatchP($counts, $weights);
        $output->writeln(sprintf('Zuweisungen: %s, SRM-Test p = %.4g', implode(', ', $parts), $p));

        if ($p < self::SRM_ALPHA) {
            $output->writeln('<error>Sample Ratio Mismatch: Die Zuweisung passt nicht zum Split. Ergebnis nicht verwenden, erst die Ursache finden.</error>');

            return self::EXIT_SRM;
        }

        return Command::SUCCESS;
    }
}
