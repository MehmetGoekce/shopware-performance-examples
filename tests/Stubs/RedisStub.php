<?php

declare(strict_types=1);

/**
 * Stub for Redis extension class.
 *
 * Allows testing Redis-dependent code without requiring the phpredis extension.
 */
if (!class_exists(\Redis::class, false)) {
    class Redis
    {
        public function connect(string $host, int $port = 6379, float $timeout = 0.0): bool
        {
            return false;
        }

        public function close(): bool
        {
            return true;
        }

        public function auth(string $password): bool
        {
            return true;
        }

        public function ping(): bool|string
        {
            return true;
        }

        public function rawCommand(string $command, string ...$args): mixed
        {
            return false;
        }
    }
}
