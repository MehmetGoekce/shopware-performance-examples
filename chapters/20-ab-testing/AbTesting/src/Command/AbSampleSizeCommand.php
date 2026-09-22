<?php

declare(strict_types=1);

namespace AbTesting\Command;

use AbTesting\Stats\StatisticalAnalyzer;
use RumMonitoring\Rum\RumLogReader;
use RumMonitoring\Rum\RumStatistics;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * Seitenaufrufe je Variante, bevor der Test startet.
 *
 *   bin/console ab:sample-size --effect=210 --sd=320
 *   bin/console ab:sample-size --effect=210 --metric=LCP --days=7   # Standardabweichung aus den RUM-Logs
 */
#[AsCommand(name: 'ab:sample-size', description: 'Stichprobengroesse je Variante (zweiseitiger Test)')]
class AbSampleSizeCommand extends Command
{
    public function __construct(
        private readonly RumLogReader $rumReader,
        private readonly StatisticalAnalyzer $analyzer,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption('effect', null, InputOption::VALUE_REQUIRED, 'kleinster Unterschied, der gefunden werden soll (ms, bei CLS ohne Einheit)')
            ->addOption('sd', null, InputOption::VALUE_REQUIRED, 'Standardabweichung; ohne Angabe aus den RUM-Logs')
            ->addOption('metric', null, InputOption::VALUE_REQUIRED, 'Metrik fuer die Standardabweichung aus den RUM-Logs', 'LCP')
            ->addOption('days', null, InputOption::VALUE_REQUIRED, 'Zeitfenster fuer die Standardabweichung', '7')
            ->addOption('alpha', null, InputOption::VALUE_REQUIRED, 'Signifikanzniveau', '0.05')
            ->addOption('power', null, InputOption::VALUE_REQUIRED, 'Teststaerke', '0.8');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $effect = filter_var($input->getOption('effect'), \FILTER_VALIDATE_FLOAT);
        $alpha = filter_var($input->getOption('alpha'), \FILTER_VALIDATE_FLOAT);
        $power = filter_var($input->getOption('power'), \FILTER_VALIDATE_FLOAT);
        $metric = (string) $input->getOption('metric');
        $days = filter_var($input->getOption('days'), \FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);

        if (
            $effect === false || $effect <= 0 || $alpha === false || $alpha <= 0 || $alpha >= 1 || $power === false || $power <= 0 || $power >= 1
            || !isset(RumStatistics::THRESHOLDS[$metric]) || $days === false
        ) {
            $output->writeln('<error>--effect > 0 ist Pflicht; --alpha und --power in (0, 1), --metric LCP|INP|CLS|FCP|TTFB, --days >= 1</error>');

            return Command::INVALID;
        }

        $sd = $input->getOption('sd');
        if ($sd !== null) {
            $sd = filter_var($sd, \FILTER_VALIDATE_FLOAT);
            if ($sd === false || $sd <= 0) {
                $output->writeln('<error>--sd muss > 0 sein</error>');

                return Command::INVALID;
            }
        } else {
            $values = $this->baseline($metric, new \DateTimeImmutable(sprintf('-%d days', $days)));
            if (\count($values) < 2) {
                $output->writeln(sprintf('<error>Zu wenig RUM-Daten fuer %s in den letzten %d Tagen, --sd angeben</error>', $metric, $days));

                return Command::FAILURE;
            }
            $mean = array_sum($values) / \count($values);
            $sd = sqrt(array_sum(array_map(static fn (float $v): float => ($v - $mean) ** 2, $values)) / (\count($values) - 1));
            $output->writeln(sprintf('Standardabweichung %s aus %d Seitenaufrufen (%d Tage): %.4g', $metric, \count($values), $days, $sd));
        }

        $n = $this->analyzer->requiredSampleSize($effect, $sd, $alpha, $power);
        $output->writeln(sprintf('Seitenaufrufe je Variante: %d (zwei Varianten: %d)', $n, 2 * $n));

        return Command::SUCCESS;
    }

    /**
     * Letzter Wert je Seitenaufruf (id), wie RumStatistics::aggregate().
     *
     * @return list<float>
     */
    private function baseline(string $metric, \DateTimeImmutable $since): array
    {
        $latest = [];
        $n = 0;
        foreach ($this->rumReader->read($since) as $record) {
            if (($record['metric'] ?? null) === $metric && is_numeric($record['value'] ?? null)) {
                $latest[\is_string($record['id'] ?? null) ? $record['id'] : '#' . $n++] = (float) $record['value'];
            }
        }

        return array_values($latest);
    }
}
