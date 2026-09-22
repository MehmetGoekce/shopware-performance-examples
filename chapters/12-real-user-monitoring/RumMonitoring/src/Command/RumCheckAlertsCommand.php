<?php

declare(strict_types=1);

namespace RumMonitoring\Command;

use RumMonitoring\Rum\RumAlertState;
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
 * Prueft das p75 von LCP, INP und CLS und meldet jede Aenderung der Bewertung.
 *
 *   bin/console rum:check-alerts                        # letzte Stunde, ab 100 Samples
 *   Cron alle 15 Minuten: siehe README (Zeile /etc/cron.d/rum-alerts)
 *
 * Gemeldet wird nur ein Wechsel (gut -> schlechter, Stufe steigt, wieder gut),
 * der letzte Stand liegt in var/rum-alert-state.json. --repeat meldet jede
 * Metrik, die nicht "good" ist, bei jedem Lauf.
 *
 * Mit RUM_ALERT_WEBHOOK gehen die Meldungen als {"text": ...} per POST dorthin
 * (Format der Slack Incoming Webhooks), sonst auf die Konsole. cron verschickt
 * jede Ausgabe per Mail - deshalb bleibt der Befehl still, solange sich nichts
 * aendert oder der Webhook angenommen hat. Scheitert der Webhook: Meldungen +
 * Fehler ausgeben, Exit 1, Zustand nicht speichern (naechster Lauf versucht es
 * erneut). Die Messwerte je Metrik zeigt -v.
 *
 * Ohne Daten bleibt der Befehl ebenfalls still - ein gesperrtes /api/rum saehe
 * dann aus wie "alles gut". --expect-data meldet, wenn im Zeitfenster kein
 * einziger Wert liegt.
 */
#[AsCommand(name: 'rum:check-alerts', description: 'Meldet, wenn sich die p75-Bewertung von LCP/INP/CLS aendert')]
class RumCheckAlertsCommand extends Command
{
    private const METRICS = ['LCP', 'INP', 'CLS'];

    public function __construct(
        private readonly RumLogReader $reader,
        private readonly HttpClientInterface $httpClient,
        private readonly ?string $webhookUrl,
        private readonly string $stateFile,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption('hours', null, InputOption::VALUE_REQUIRED, 'Zeitfenster in Stunden', '1')
            ->addOption('min-samples', null, InputOption::VALUE_REQUIRED, 'Unter dieser Zahl keine Bewertung', '100')
            ->addOption('repeat', null, InputOption::VALUE_NONE, 'Jede Metrik melden, die nicht "good" ist, nicht nur Wechsel')
            ->addOption('expect-data', null, InputOption::VALUE_NONE, 'Melden, wenn im Zeitfenster keine Daten liegen');
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

        $current = [];
        $text = [];
        $total = 0;
        foreach (RumStatistics::aggregate($this->reader->read($since)) as $row) {
            if (!\in_array($row['metric'], self::METRICS, true)) {
                continue;
            }
            $total += $row['samples'];

            if ($row['samples'] < $minSamples) {
                if ($output->isVerbose()) {
                    $output->writeln(sprintf('%s: nur %d Samples (< %d), keine Bewertung', $row['metric'], $row['samples'], $minSamples));
                }

                continue;
            }

            $p75 = $this->format($row['metric'], $row['p75']);
            if ($output->isVerbose()) {
                $output->writeln(sprintf('%s: p75 %s, %d Samples, %s', $row['metric'], $p75, $row['samples'], $row['rating']));
            }

            $current[$row['metric']] = $row['rating'];
            $text[$row['metric']] = sprintf(
                '[%s] %s p75 = %s (%d Samples, letzte %d h)',
                ['good' => 'OK', 'needs-improvement' => 'WARNUNG', 'poor' => 'KRITISCH'][$row['rating']],
                $row['metric'],
                $p75,
                $row['samples'],
                $hours
            );
        }

        if ($input->getOption('expect-data')) {
            $current['DATEN'] = $total === 0 ? RumAlertState::NO_DATA : 'good';
            $text['DATEN'] = $total === 0
                ? sprintf('[KEINE DATEN] Keine RUM-Werte seit %s - kommt POST /api/rum noch an?', $since->format('Y-m-d H:i T'))
                : '[OK] RUM-Daten kommen wieder an';
        }

        $previous = RumAlertState::load($this->stateFile);
        $alerts = array_map(
            static fn (string $metric): string => $text[$metric],
            RumAlertState::changes($previous, $current, (bool) $input->getOption('repeat'))
        );

        if ($alerts !== [] && $this->webhookUrl !== null && $this->webhookUrl !== '') {
            $error = $this->post($alerts);
            if ($error !== null) {
                $output->writeln($alerts);
                $output->writeln('<error>' . $error . '</error>');

                return Command::FAILURE;
            }

            if ($output->isVerbose()) {
                $output->writeln(sprintf('%d Meldung(en) an den Webhook geschickt', \count($alerts)));
            }
        } elseif ($alerts !== []) {
            $output->writeln($alerts);
        }

        RumAlertState::save($this->stateFile, array_merge($previous, $current));

        return Command::SUCCESS;
    }

    /**
     * @param list<string> $alerts
     */
    private function post(array $alerts): ?string
    {
        try {
            $status = $this->httpClient
                ->request('POST', (string) $this->webhookUrl, ['json' => ['text' => implode("\n", $alerts)], 'timeout' => 10])
                ->getStatusCode();
        } catch (ExceptionInterface $e) {
            // Die URL eines Slack-Webhooks ist ein Geheimnis und soll nicht in der cron-Mail stehen
            return 'Webhook nicht erreichbar: ' . str_replace((string) $this->webhookUrl, '<RUM_ALERT_WEBHOOK>', $e->getMessage());
        }

        return $status >= 200 && $status < 300 ? null : sprintf('Webhook antwortet mit HTTP %d', $status);
    }

    private function format(string $metric, float $value): string
    {
        return $metric === 'CLS' ? sprintf('%.3f', $value) : sprintf('%.0f ms', $value);
    }
}
