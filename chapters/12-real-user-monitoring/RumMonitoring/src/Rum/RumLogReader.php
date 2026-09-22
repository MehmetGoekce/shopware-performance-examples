<?php

declare(strict_types=1);

namespace RumMonitoring\Rum;

/**
 * Liest die JSON-Zeilen des Kanals "rum" aus var/log/rum-YYYY-MM-DD.log.
 *
 * Nur Dateien, deren Datum ins Zeitfenster faellt, werden geoeffnet, und die
 * Zeilen werden einzeln gelesen - eine Monatsdatei landet nie ganz im Speicher.
 */
final class RumLogReader
{
    public function __construct(private readonly string $logDir)
    {
    }

    /**
     * @return \Generator<int, array<string, mixed>>
     */
    public function read(\DateTimeImmutable $since): \Generator
    {
        foreach ($this->files($since) as $file) {
            $handle = fopen($file, 'r');
            if ($handle === false) {
                continue;
            }

            try {
                while (($line = fgets($handle)) !== false) {
                    $entry = json_decode($line, true);
                    if (!\is_array($entry) || !\is_array($entry['context'] ?? null) || !\is_string($entry['datetime'] ?? null)) {
                        continue;
                    }

                    try {
                        $time = new \DateTimeImmutable($entry['datetime']);
                    } catch (\Exception) {
                        continue;
                    }

                    if ($time < $since) {
                        continue;
                    }

                    yield $entry['context'];
                }
            } finally {
                fclose($handle);
            }
        }
    }

    /**
     * @return list<string>
     */
    public function files(\DateTimeImmutable $since): array
    {
        // Monolog datiert die Dateien in der Zeitzone von PHP, deshalb einen Tag Puffer
        $firstDay = $since->modify('-1 day')->format('Y-m-d');

        $files = [];
        foreach (glob($this->logDir . '/rum-*.log') ?: [] as $file) {
            if (preg_match('/rum-(\d{4}-\d{2}-\d{2})\.log$/', $file, $m) === 1 && $m[1] >= $firstDay) {
                $files[] = $file;
            }
        }
        sort($files);

        return $files;
    }
}
