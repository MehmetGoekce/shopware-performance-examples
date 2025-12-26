<?php

declare(strict_types=1);

namespace PerformanceExamples\Service;

use Psr\Log\LoggerInterface;

/**
 * Redis Sentinel Connection Factory
 *
 * Kapitel 10: Redis High Availability
 *
 * Ermöglicht automatisches Failover durch Redis Sentinel.
 * Bei Ausfall des Masters verbindet sich die Factory
 * automatisch mit dem neuen Master.
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */
class RedisSentinelFactory
{
    private const DEFAULT_TIMEOUT = 2.0;
    private const RETRY_DELAY_MS = 100;
    private const MAX_RETRIES = 3;

    /**
     * @param array<string> $sentinelHosts Format: ['host1:port1', 'host2:port2', ...]
     */
    public function __construct(
        private readonly array $sentinelHosts,
        private readonly string $masterName,
        private readonly ?string $password = null,
        private readonly ?LoggerInterface $logger = null
    ) {}

    /**
     * Erstellt eine Verbindung zum aktuellen Redis Master
     *
     * @throws \RuntimeException Wenn kein Master gefunden wird
     */
    public function createConnection(): \Redis
    {
        $masterAddress = $this->getMasterAddress();

        if ($masterAddress === null) {
            throw new \RuntimeException(
                sprintf('Could not find master "%s" via Sentinel', $this->masterName)
            );
        }

        [$host, $port] = $masterAddress;

        $redis = new \Redis();

        $connected = $redis->connect(
            $host,
            (int) $port,
            self::DEFAULT_TIMEOUT
        );

        if (!$connected) {
            throw new \RuntimeException(
                sprintf('Could not connect to Redis master at %s:%s', $host, $port)
            );
        }

        if ($this->password !== null) {
            $redis->auth($this->password);
        }

        $this->logger?->info('Connected to Redis master', [
            'host' => $host,
            'port' => $port,
        ]);

        return $redis;
    }

    /**
     * Fragt alle Sentinels nach der Master-Adresse
     *
     * @return array{0: string, 1: string}|null [host, port] oder null
     */
    private function getMasterAddress(): ?array
    {
        foreach ($this->sentinelHosts as $sentinelHost) {
            try {
                $address = $this->queryMasterFromSentinel($sentinelHost);
                if ($address !== null) {
                    return $address;
                }
            } catch (\Exception $e) {
                $this->logger?->warning('Sentinel query failed', [
                    'sentinel' => $sentinelHost,
                    'error' => $e->getMessage(),
                ]);
                // Nächsten Sentinel versuchen
                continue;
            }
        }

        return null;
    }

    /**
     * Fragt einen einzelnen Sentinel nach dem Master
     *
     * @return array{0: string, 1: string}|null
     */
    private function queryMasterFromSentinel(string $sentinelHost): ?array
    {
        [$host, $port] = explode(':', $sentinelHost);

        $sentinel = new \Redis();

        for ($attempt = 1; $attempt <= self::MAX_RETRIES; $attempt++) {
            try {
                $connected = $sentinel->connect(
                    $host,
                    (int) $port,
                    self::DEFAULT_TIMEOUT
                );

                if (!$connected) {
                    continue;
                }

                // SENTINEL get-master-addr-by-name <master-name>
                $result = $sentinel->rawCommand(
                    'SENTINEL',
                    'get-master-addr-by-name',
                    $this->masterName
                );

                $sentinel->close();

                if (is_array($result) && count($result) === 2) {
                    return [$result[0], $result[1]];
                }

            } catch (\Exception $e) {
                $this->logger?->debug('Sentinel attempt failed', [
                    'attempt' => $attempt,
                    'sentinel' => $sentinelHost,
                    'error' => $e->getMessage(),
                ]);

                if ($attempt < self::MAX_RETRIES) {
                    usleep(self::RETRY_DELAY_MS * 1000);
                }
            }
        }

        return null;
    }

    /**
     * Prüft, ob der aktuelle Master erreichbar ist
     */
    public function isMasterHealthy(): bool
    {
        try {
            $redis = $this->createConnection();
            $pong = $redis->ping();
            $redis->close();

            return $pong === true || $pong === '+PONG';
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Gibt Informationen über alle Sentinels zurück
     *
     * @return array<string, array{host: string, port: int, reachable: bool}>
     */
    public function getSentinelStatus(): array
    {
        $status = [];

        foreach ($this->sentinelHosts as $sentinelHost) {
            [$host, $port] = explode(':', $sentinelHost);

            try {
                $sentinel = new \Redis();
                $connected = $sentinel->connect($host, (int) $port, self::DEFAULT_TIMEOUT);
                $sentinel->close();

                $status[$sentinelHost] = [
                    'host' => $host,
                    'port' => (int) $port,
                    'reachable' => $connected,
                ];
            } catch (\Exception $e) {
                $status[$sentinelHost] = [
                    'host' => $host,
                    'port' => (int) $port,
                    'reachable' => false,
                ];
            }
        }

        return $status;
    }
}
