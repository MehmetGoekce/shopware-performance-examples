<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../Stubs/RedisStub.php';
require_once __DIR__ . '/../../src/Service/RedisSentinelFactory.php';

use PerformanceExamples\Service\RedisSentinelFactory;

/**
 * Unit Tests for RedisSentinelFactory
 *
 * Tests the Sentinel connection logic from Chapter 10.
 * Uses Reflection to test private methods and constants.
 */
class RedisSentinelFactoryTest extends TestCase
{
    /**
     * Test default timeout constant value.
     */
    public function testDefaultTimeoutConstant(): void
    {
        $reflection = new \ReflectionClass(RedisSentinelFactory::class);
        $timeout = $reflection->getConstant('DEFAULT_TIMEOUT');

        $this->assertSame(2.0, $timeout);
    }

    /**
     * Test retry delay constant value.
     */
    public function testRetryDelayConstant(): void
    {
        $reflection = new \ReflectionClass(RedisSentinelFactory::class);
        $delay = $reflection->getConstant('RETRY_DELAY_MS');

        $this->assertSame(100, $delay);
    }

    /**
     * Test max retries constant value.
     */
    public function testMaxRetriesConstant(): void
    {
        $reflection = new \ReflectionClass(RedisSentinelFactory::class);
        $maxRetries = $reflection->getConstant('MAX_RETRIES');

        $this->assertSame(3, $maxRetries);
    }

    /**
     * Test getMasterAddress returns null when all sentinels are unreachable.
     */
    public function testGetMasterAddressReturnsNullWhenAllSentinelsFail(): void
    {
        $factory = new RedisSentinelFactory(
            sentinelHosts: ['invalid-host-1:26379', 'invalid-host-2:26379'],
            masterName: 'mymaster',
            password: null,
            logger: null
        );

        $reflection = new \ReflectionMethod($factory, 'getMasterAddress');
        $reflection->setAccessible(true);

        $result = $reflection->invoke($factory);

        $this->assertNull($result);
    }

    /**
     * Test createConnection throws RuntimeException when no master found.
     */
    public function testCreateConnectionThrowsWhenNoMaster(): void
    {
        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Could not find master');

        $factory = new RedisSentinelFactory(
            sentinelHosts: ['invalid-host:26379'],
            masterName: 'mymaster'
        );

        $factory->createConnection();
    }

    /**
     * Test isMasterHealthy returns false when connection fails.
     */
    public function testIsMasterHealthyReturnsFalseOnFailure(): void
    {
        $factory = new RedisSentinelFactory(
            sentinelHosts: ['invalid-host:26379'],
            masterName: 'mymaster'
        );

        $this->assertFalse($factory->isMasterHealthy());
    }

    /**
     * Test getSentinelStatus returns status for all configured sentinels.
     */
    public function testGetSentinelStatusReturnsAllHosts(): void
    {
        $factory = new RedisSentinelFactory(
            sentinelHosts: ['invalid-host-1:26379', 'invalid-host-2:26380'],
            masterName: 'mymaster'
        );

        $status = $factory->getSentinelStatus();

        $this->assertCount(2, $status);
        $this->assertArrayHasKey('invalid-host-1:26379', $status);
        $this->assertArrayHasKey('invalid-host-2:26380', $status);

        foreach ($status as $entry) {
            $this->assertArrayHasKey('host', $entry);
            $this->assertArrayHasKey('port', $entry);
            $this->assertArrayHasKey('reachable', $entry);
            $this->assertFalse($entry['reachable']);
        }
    }

    /**
     * Test constructor accepts optional password.
     */
    public function testConstructorAcceptsPassword(): void
    {
        $factory = new RedisSentinelFactory(
            sentinelHosts: ['localhost:26379'],
            masterName: 'mymaster',
            password: 'secret-password'
        );

        // If we get here without exception, constructor works
        $this->assertInstanceOf(RedisSentinelFactory::class, $factory);
    }
}
