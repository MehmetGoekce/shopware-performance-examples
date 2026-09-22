<?php

declare(strict_types=1);

namespace AbTesting\Log;

/**
 * Zaehlt die Zuweisungen aus var/log/ab_testing-YYYY-MM-DD.log
 * (Kanal "ab_testing", eine JSON-Zeile je neu zugewiesenem Besucher).
 */
final class AssignmentLogReader
{
    public function __construct(private readonly string $logDir)
    {
    }

    /**
     * @return array<string, int> Variante => Anzahl Zuweisungen seit $since
     */
    public function count(string $experiment, \DateTimeImmutable $since): array
    {
        // Monolog datiert die Dateien in der Zeitzone von PHP, deshalb einen Tag Puffer
        $firstDay = $since->modify('-1 day')->format('Y-m-d');
        $counts = [];

        // Ein nicht lesbares Verzeichnis saehe sonst aus wie "keine Zuweisungen"
        if (is_dir($this->logDir) && !is_readable($this->logDir)) {
            throw new \RuntimeException(sprintf('%s ist nicht lesbar', $this->logDir));
        }

        foreach (glob($this->logDir . '/ab_testing-*.log') ?: [] as $file) {
            if (preg_match('/ab_testing-(\d{4}-\d{2}-\d{2})\.log$/', $file, $m) !== 1 || $m[1] < $firstDay) {
                continue;
            }

            $handle = is_readable($file) ? fopen($file, 'r') : false;
            if ($handle === false) {
                throw new \RuntimeException(sprintf('%s ist nicht lesbar', $file));
            }

            try {
                while (($line = fgets($handle)) !== false) {
                    $entry = json_decode($line, true);
                    $context = \is_array($entry) ? ($entry['context'] ?? null) : null;

                    if (!\is_array($context) || ($context['experiment'] ?? null) !== $experiment || !\is_string($context['variant'] ?? null)) {
                        continue;
                    }

                    try {
                        if (new \DateTimeImmutable((string) ($entry['datetime'] ?? '')) < $since) {
                            continue;
                        }
                    } catch (\Exception) {
                        continue;
                    }

                    $counts[$context['variant']] = ($counts[$context['variant']] ?? 0) + 1;
                }
            } finally {
                fclose($handle);
            }
        }

        return $counts;
    }
}
