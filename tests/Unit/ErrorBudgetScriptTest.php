<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Kapitel 14: scripts/error-budget.php gegen ein nachgebautes Shopware-Verzeichnis
 * (Plugin-Klassen aus Kapitel 12 unter custom/plugins, Logs unter var/log).
 */
class ErrorBudgetScriptTest extends TestCase
{
    private const SCRIPT = __DIR__ . '/../../chapters/14-performance-kultur/scripts/error-budget.php';

    private string $shop;

    protected function setUp(): void
    {
        $this->shop = sys_get_temp_dir() . '/budget-shop-' . bin2hex(random_bytes(4));
        $rum = $this->shop . '/custom/plugins/RumMonitoring/src/Rum';
        mkdir($rum, 0777, true);
        mkdir($this->shop . '/var/log', 0777, true);
        foreach (['RumLogReader.php', 'RumStatistics.php'] as $file) {
            copy(__DIR__ . '/../../chapters/12-real-user-monitoring/RumMonitoring/src/Rum/' . $file, "$rum/$file");
        }
    }

    protected function tearDown(): void
    {
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($this->shop, \FilesystemIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($it as $file) {
            $file->isDir() ? rmdir($file->getPathname()) : unlink($file->getPathname());
        }
        rmdir($this->shop);
    }

    /**
     * @param array{0: string, 1: int, 2: int} ...$metrics [Metrik, gut, ueber der Schwelle]
     */
    private function writeLog(string $ago, array ...$metrics): void
    {
        $time = new \DateTimeImmutable($ago);
        $lines = '';
        foreach ($metrics as [$metric, $good, $over]) {
            $threshold = ['LCP' => 2500, 'INP' => 200, 'CLS' => 0.1][$metric];
            for ($i = 0; $i < $good + $over; $i++) {
                $lines .= json_encode([
                    'message' => 'rum',
                    'context' => ['metric' => $metric, 'id' => "v5-$ago-$metric-$i", 'value' => $i < $good ? $threshold : $threshold * 2],
                    'channel' => 'rum',
                    'datetime' => $time->format('Y-m-d\TH:i:s.uP'),
                ]) . "\n";
            }
        }
        file_put_contents($this->shop . '/var/log/rum-' . $time->format('Y-m-d') . '.log', $lines, \FILE_APPEND);
    }

    /**
     * @return array{int, string, string}
     */
    private function runScript(string ...$args): array
    {
        $cmd = array_merge([\PHP_BINARY, self::SCRIPT], $args);
        $proc = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
        self::assertIsResource($proc);
        $out = (string) stream_get_contents($pipes[1]);
        $err = (string) stream_get_contents($pipes[2]);

        return [proc_close($proc), $out, $err];
    }

    public function testHelpPrintsUsage(): void
    {
        [$rc, $out] = $this->runScript('--help');

        self::assertSame(0, $rc);
        self::assertStringContainsString('Usage:', $out);
    }

    public function testMissingShopDirIsAnError(): void
    {
        [$rc, , $err] = $this->runScript();

        self::assertSame(2, $rc);
        self::assertStringContainsString('Usage:', $err);
    }

    public function testInvalidDaysIsAnError(): void
    {
        self::assertSame(2, $this->runScript($this->shop, '--days=0')[0]);
        self::assertSame(2, $this->runScript($this->shop, '--min-samples=x')[0]);
    }

    public function testMissingPluginIsAnError(): void
    {
        unlink($this->shop . '/custom/plugins/RumMonitoring/src/Rum/RumLogReader.php');

        [$rc, , $err] = $this->runScript($this->shop);

        self::assertSame(2, $rc);
        self::assertStringContainsString('RumMonitoring', $err);
    }

    public function testHealthyBudgetExitsZero(): void
    {
        $this->writeLog('-1 hour', ['LCP', 90, 10], ['INP', 100, 0], ['CLS', 95, 5]);

        [$rc, $out] = $this->runScript($this->shop);

        self::assertSame(0, $rc, $out);
        self::assertMatchesRegularExpression('/^LCP\s+100\s+10\s+40\.0 %\s+60\.0 %\s+green$/m', $out);
        self::assertMatchesRegularExpression('/^CLS\s+100\s+5\s+20\.0 %\s+80\.0 %\s+green$/m', $out);
        self::assertStringContainsString('Gesamt: green', $out);
    }

    public function testBrokenSloExitsOne(): void
    {
        $this->writeLog('-1 hour', ['LCP', 70, 30], ['INP', 100, 0]);

        [$rc, $out] = $this->runScript($this->shop);

        self::assertSame(1, $rc, $out);
        self::assertMatchesRegularExpression('/^LCP\s+100\s+30\s+120\.0 %\s+-20\.0 %\s+red$/m', $out);
        self::assertStringContainsString('Gesamt: red', $out);
    }

    public function testTooFewPageViewsExitsThree(): void
    {
        $this->writeLog('-1 hour', ['LCP', 10, 40]);

        [$rc, $out] = $this->runScript($this->shop);

        self::assertSame(3, $rc, $out);
        self::assertStringContainsString('zu wenig Daten (< 100)', $out);
        self::assertSame(1, $this->runScript($this->shop, '--min-samples=50')[0]);
    }

    public function testOnlyTheTimeWindowCounts(): void
    {
        $this->writeLog('-1 hour', ['LCP', 100, 0]);
        $this->writeLog('-40 days', ['LCP', 0, 500]);

        [$rc, $out] = $this->runScript($this->shop);
        self::assertSame(0, $rc, $out);
        self::assertMatchesRegularExpression('/^LCP\s+100\s+0\s/m', $out);

        self::assertSame(1, $this->runScript($this->shop, '--days=45')[0]);
    }
}
