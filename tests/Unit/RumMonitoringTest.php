<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;
use RumMonitoring\Rum\RumLogReader;
use RumMonitoring\Rum\RumPayload;
use RumMonitoring\Rum\RumStatistics;

require_once __DIR__ . '/../../chapters/12-real-user-monitoring/RumMonitoring/src/Rum/RumPayload.php';
require_once __DIR__ . '/../../chapters/12-real-user-monitoring/RumMonitoring/src/Rum/RumStatistics.php';
require_once __DIR__ . '/../../chapters/12-real-user-monitoring/RumMonitoring/src/Rum/RumLogReader.php';

/**
 * Tests fuer die reine Logik des Kapitel-12-Plugins (ohne Shopware).
 * Route, Monolog-Kanal, Twig und Commands sind im Dockware-Shop getestet
 * (reviews/ch12-rum-factcheck-2026-09.md, T9-T16).
 */
class RumMonitoringTest extends TestCase
{
    private string $logDir;

    protected function setUp(): void
    {
        $this->logDir = sys_get_temp_dir() . '/rum-test-' . bin2hex(random_bytes(4));
        mkdir($this->logDir);
    }

    protected function tearDown(): void
    {
        array_map('unlink', glob($this->logDir . '/*') ?: []);
        rmdir($this->logDir);
    }

    public function testPayloadKeepsOnlyKnownFieldsAndDropsQueryString(): void
    {
        $record = RumPayload::fromJson(json_encode([
            'name' => 'LCP',
            'value' => 1234.56,
            'rating' => 'good',
            'navigationType' => 'navigate',
            'route' => 'frontend.detail.page',
            'path' => '/Main-product/SWDEMO10001?email=a@b.c',
            'target' => 'img.product-image',
            'device' => 'mobile',
            'userAgent' => 'soll nicht ins Log',
        ], \JSON_THROW_ON_ERROR), 'CH');

        self::assertSame([
            'metric' => 'LCP',
            'value' => 1234.6,
            'rating' => 'good',
            'navigation_type' => 'navigate',
            'route' => 'frontend.detail.page',
            'path' => '/Main-product/SWDEMO10001',
            'target' => 'img.product-image',
            'device' => 'mobile',
            'country' => 'CH',
        ], $record);
    }

    public function testPayloadRejectsUnknownMetricsAndGarbage(): void
    {
        self::assertNull(RumPayload::fromJson('{"name":"FID","value":12}'));
        self::assertNull(RumPayload::fromJson('{"name":"LCP","value":"1200"}'));
        self::assertNull(RumPayload::fromJson('{"name":"LCP","value":-1}'));
        self::assertNull(RumPayload::fromJson('{"name":"LCP","value":60001}'));
        self::assertNull(RumPayload::fromJson('kein json'));
        self::assertNull(RumPayload::fromJson(''));
        self::assertNull(RumPayload::fromJson('{"name":"LCP","value":1,"target":"' . str_repeat('x', 2048) . '"}'));
    }

    public function testPayloadNullsInvalidOptionalFields(): void
    {
        $record = RumPayload::fromJson('{"name":"CLS","value":0.123456,"rating":"bad","route":"Frontend Detail","path":"https://evil","device":"tv"}', 'Schweiz');

        self::assertNotNull($record);
        self::assertSame(0.1235, $record['value']);
        self::assertNull($record['rating']);
        self::assertNull($record['route']);
        self::assertNull($record['path']);
        self::assertNull($record['device']);
        self::assertNull($record['country']);
    }

    public function testPercentileIsNearestRank(): void
    {
        $values = [1000.0, 2000.0, 2500.0, 3000.0];

        self::assertSame(2000.0, RumStatistics::percentile($values, 50));
        self::assertSame(2500.0, RumStatistics::percentile($values, 75));
        self::assertSame(3000.0, RumStatistics::percentile($values, 90));
        self::assertSame(7.0, RumStatistics::percentile([7.0], 75));

        $hundred = array_map('floatval', range(1, 100));
        self::assertSame(75.0, RumStatistics::percentile($hundred, 75));
    }

    public function testPercentileOfNothingThrows(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        RumStatistics::percentile([], 75);
    }

    public function testRatingTreatsThresholdAsGood(): void
    {
        self::assertSame('good', RumStatistics::rating('LCP', 2500));
        self::assertSame('needs-improvement', RumStatistics::rating('LCP', 2500.1));
        self::assertSame('needs-improvement', RumStatistics::rating('LCP', 4000));
        self::assertSame('poor', RumStatistics::rating('LCP', 4000.1));
        self::assertSame('good', RumStatistics::rating('CLS', 0.1));
        self::assertSame('poor', RumStatistics::rating('INP', 501));
    }

    public function testAggregateGroupsAndSkipsUnknownRecords(): void
    {
        $rows = RumStatistics::aggregate([
            ['metric' => 'INP', 'value' => 100, 'route' => 'frontend.detail.page'],
            ['metric' => 'INP', 'value' => 300, 'route' => 'frontend.detail.page'],
            ['metric' => 'INP', 'value' => 50, 'route' => 'frontend.home.page'],
            ['metric' => 'FID', 'value' => 10, 'route' => 'frontend.home.page'],
            ['metric' => 'LCP', 'value' => 'x'],
        ], 'route');

        self::assertCount(2, $rows);
        $detail = $rows["INP\0frontend.detail.page"];
        self::assertSame(2, $detail['samples']);
        self::assertSame(300.0, $detail['p75']);
        self::assertSame('needs-improvement', $detail['rating']);
    }

    public function testLogReaderReadsRotatedFilesInWindowOnly(): void
    {
        $now = new \DateTimeImmutable();
        $line = static fn (string $metric, int $value, string $ago): string => json_encode([
            'message' => 'rum',
            'context' => ['metric' => $metric, 'value' => $value],
            'channel' => 'rum',
            'datetime' => $now->modify($ago)->format(\DATE_ATOM),
        ], \JSON_THROW_ON_ERROR) . "\n";

        file_put_contents($this->logDir . '/rum-' . $now->format('Y-m-d') . '.log', $line('LCP', 1, '-10 minutes') . "kaputt\n" . $line('LCP', 2, '-3 hours'));
        file_put_contents($this->logDir . '/rum-' . $now->modify('-10 days')->format('Y-m-d') . '.log', $line('LCP', 3, '-10 days'));
        file_put_contents($this->logDir . '/rum.log', $line('LCP', 4, '-1 minute'));

        $reader = new RumLogReader($this->logDir);
        $records = iterator_to_array($reader->read($now->modify('-1 hour')), false);

        self::assertSame([['metric' => 'LCP', 'value' => 1]], $records);
        self::assertCount(1, $reader->files($now->modify('-1 hour')));
    }
}
