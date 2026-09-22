<?php

declare(strict_types=1);

namespace RumMonitoring\Command;

use RumMonitoring\Rum\RumLogReader;
use RumMonitoring\Rum\RumStatistics;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Contracts\HttpClient\Exception\ExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * Prueft das p75 von LCP, INP und CLS und meldet jede Metrik, die nicht "gut" ist.
 *
 *   bin/console rum:check-alerts                        # letzte Stunde, ab 100 Samples
 *   Cron alle 15 Minuten: siehe README (Zeile /etc/cron.d/rum-alerts)
 *
 * Mit RUM_ALERT_WEBHOOK gehen die Meldungen als {"text": ...} per POST dorthin
 * (Format der Slack Incoming Webhooks), sonst auf die Konsole. cron verschickt
 * jede Ausgabe per Mail - deshalb bleibt der Befehl still, solange alles gut ist
 * oder der Webhook angenommen hat. Scheitert der Webhook: Meldungen + Fehler
 * ausgeben, Exit 1. Die Messwerte je Metrik zeigt -v.
 */
#[AsCommand(name: 'rum:check-alerts', description: 'Meldet LCP/INP/CLS, deren p75 nicht "gut" ist')]
class RumCheckAlertsCommand extends Command
{
    private const METRICS = ['LCP', 'INP', 'CLS'];

    public function __construct(
        private readonly RumLogReader $reader,
        private readonly HttpClientInterface $httpClient,
        private readonly ?string $webhookUrl,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption('hours', null, InputOption::VALUE_REQUIRED, 'Zeitfenster in Stunden', '1')
            ->addOption('min-samples', null, InputOption::VALUE_REQUIRED, 'Unter dieser Zahl keine Meldung', '100');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $hours = filter_var($input->getOption('hours'), \FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
        $minSamples = filter_var($input->getOption('min-samples'), \FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);

        if ($hours === false || $minSamples === false) {
            $output->writeln('<error>--hours und --min-samples brauchen ganze Zahlen >= 1</error>');

            return Command::INVALID;
        }

        $since = new \DateTimeImmutable(sprintf('-%d hours', $hours));

        $alerts = [];
        foreach (RumStatistics::aggregate($this->reader->read($since)) as $row) {
            if (!\in_array($row['metric'], self::METRICS, true)) {
                continue;
            }

            if ($row['samples'] < $minSamples) {
                if ($output->isVerbose()) {
                    $output->writeln(sprintf('%s: nur %d Samples (< %d), keine Bewertung', $row['metric'], $row['samples'], $minSamples));
                }

                continue;
            }

            if ($output->isVerbose()) {
                $output->writeln(sprintf('%s: p75 %s, %d Samples, %s', $row['metric'], $this->format($row['metric'], $row['p75']), $row['samples'], $row['rating']));
            }

            if ($row['rating'] !== 'good') {
                $alerts[] = sprintf(
                    '[%s] %s p75 = %s (%d Samples, letzte %d h)',
                    $row['rating'] === 'poor' ? 'KRITISCH' : 'WARNUNG',
                    $row['metric'],
                    $this->format($row['metric'], $row['p75']),
                    $row['samples'],
                    $hours
                );
            }
        }

        if ($alerts === []) {
            return Command::SUCCESS;
        }

        if ($this->webhookUrl === null || $this->webhookUrl === '') {
            $output->writeln($alerts);

            return Command::SUCCESS;
        }

        try {
            $status = $this->httpClient
                ->request('POST', $this->webhookUrl, ['json' => ['text' => implode("\n", $alerts)], 'timeout' => 10])
                ->getStatusCode();
            $error = $status >= 200 && $status < 300 ? null : sprintf('Webhook antwortet mit HTTP %d', $status);
        } catch (ExceptionInterface $e) {
            $error = 'Webhook nicht erreichbar: ' . $e->getMessage();
        }

        if ($error !== null) {
            $output->writeln($alerts);
            $output->writeln('<error>' . $error . '</error>');

            return Command::FAILURE;
        }

        if ($output->isVerbose()) {
            $output->writeln(sprintf('%d Meldung(en) an den Webhook geschickt', \count($alerts)));
        }

        return Command::SUCCESS;
    }

    private function format(string $metric, float $value): string
    {
        return $metric === 'CLS' ? sprintf('%.3f', $value) : sprintf('%.0f ms', $value);
    }
}
