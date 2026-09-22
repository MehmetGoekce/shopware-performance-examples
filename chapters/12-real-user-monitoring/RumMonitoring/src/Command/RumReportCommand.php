<?php

declare(strict_types=1);

namespace RumMonitoring\Command;

use RumMonitoring\Rum\RumLogReader;
use RumMonitoring\Rum\RumStatistics;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\Table;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * p50/p75/p90 je Metrik aus den RUM-Logs, optional je Route, Geraet oder Land.
 *
 *   bin/console rum:report                      # letzte 24 Stunden
 *   bin/console rum:report --hours=168 --by=route
 */
#[AsCommand(name: 'rum:report', description: 'Web-Vitals-Perzentile aus den RUM-Logs')]
class RumReportCommand extends Command
{
    private const GROUPS = ['route', 'device', 'country'];

    public function __construct(private readonly RumLogReader $reader)
    {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption('hours', null, InputOption::VALUE_REQUIRED, 'Zeitfenster in Stunden', '24')
            ->addOption('by', null, InputOption::VALUE_REQUIRED, 'Gruppieren nach: ' . implode(', ', self::GROUPS));
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $hours = filter_var($input->getOption('hours'), \FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
        $by = $input->getOption('by');

        if ($hours === false || ($by !== null && !\in_array($by, self::GROUPS, true))) {
            $output->writeln('<error>--hours braucht eine ganze Zahl >= 1, --by eines von: ' . implode(', ', self::GROUPS) . '</error>');

            return Command::INVALID;
        }

        $since = new \DateTimeImmutable(sprintf('-%d hours', $hours));
        $rows = RumStatistics::aggregate($this->reader->read($since), $by);

        if ($rows === []) {
            $output->writeln(sprintf('Keine RUM-Daten seit %s.', $since->format('Y-m-d H:i')));

            return Command::SUCCESS;
        }

        $table = [];
        foreach ($rows as $row) {
            $format = $row['metric'] === 'CLS' ? '%.3f' : '%.0f';
            $table[] = [
                $row['metric'],
                $row['group'],
                $row['samples'],
                sprintf($format, $row['p50']),
                sprintf($format, $row['p75']),
                sprintf($format, $row['p90']),
                $row['rating'],
            ];
        }

        $output->writeln(sprintf('RUM seit %s (Werte in ms, CLS ohne Einheit)', $since->format('Y-m-d H:i')));
        (new Table($output))
            ->setHeaders(['Metrik', $by ?? 'alle', 'Samples', 'p50', 'p75', 'p90', 'p75-Bewertung'])
            ->setRows($table)
            ->render();

        return Command::SUCCESS;
    }
}
