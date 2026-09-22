<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use AbTesting\Experiment\ExperimentConfig;
use AbTesting\Experiment\VariantPicker;
use AbTesting\Log\AssignmentLogReader;
use AbTesting\Log\ExperimentData;
use AbTesting\Stats\Distributions;
use AbTesting\Stats\StatisticalAnalyzer;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Experiment/ExperimentConfig.php';
require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Experiment/VariantPicker.php';
require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Log/AssignmentLogReader.php';
require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Log/ExperimentData.php';
require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Stats/Distributions.php';
require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Stats/SignificanceResult.php';
require_once __DIR__ . '/../../chapters/20-ab-testing/AbTesting/src/Stats/StatisticalAnalyzer.php';

/**
 * Tests fuer die reine Logik des Kapitel-20-Plugins (ohne Shopware).
 * Zuweisung, Cache-Key, Log-Processor und Commands sind im Dockware-Shop
 * getestet (Shopware 6.6.10.6), siehe README "Tests".
 *
 * Referenzwerte: SciPy 1.8 (stats.ttest_ind(equal_var=False), stats.t,
 * stats.norm, stats.chisquare).
 */
class AbTestingTest extends TestCase
{
    /** 40 bzw. 35 lognormal verteilte LCP-Werte (numpy, Seed 1) */
    private const CONTROL = [
        2496.099818, 3166.878544, 2477.266867, 1094.566866, 3302.287064, 2625.114807, 1605.540929, 2808.067142,
        2519.910898, 2432.70448, 2130.056415, 2760.174322, 1453.116124, 1935.725847, 1650.168969, 2833.068645,
        2142.125153, 1814.316784, 1420.463339, 1846.590978, 2108.566716, 1829.670493, 4010.713886, 3473.975107,
        541.3745586, 816.6299059, 1924.278897, 1700.363648, 2336.744785, 2341.047105, 6054.832553, 1204.334297,
        1738.695016, 5831.785117, 2901.676992, 2925.510604, 1624.068075, 921.1796144, 2283.409491, 2217.641821,
    ];

    private const VARIANT = [
        730.4808443, 1128.904895, 1840.789266, 915.7865863, 1802.569953, 2104.7902, 2006.312304, 1300.561437,
        3135.622848, 3977.93538, 2520.627847, 1013.333297, 3501.359073, 1305.619131, 3939.909948, 827.2895197,
        4052.780282, 1918.950859, 718.0832715, 1516.962219, 2036.252677, 2425.560044, 888.7661492, 804.0699065,
        2287.585739, 1342.360564, 2354.277443, 3580.294253, 521.4194262, 2390.111137, 5194.222481, 1536.96224,
        1019.362779, 3559.515479, 2388.311392,
    ];

    private const EXPERIMENTS = [
        'listing_images' => [
            'routes' => ['frontend.navigation.page'],
            'variants' => ['control' => 50, 'eager' => 50],
        ],
    ];

    private string $logDir;

    protected function setUp(): void
    {
        $this->logDir = sys_get_temp_dir() . '/ab-test-' . bin2hex(random_bytes(4));
        mkdir($this->logDir);
    }

    protected function tearDown(): void
    {
        foreach (glob($this->logDir . '/*') ?: [] as $file) {
            chmod($file, 0644);
            unlink($file);
        }
        chmod($this->logDir, 0755);
        rmdir($this->logDir);
    }

    public function testWelchMatchesScipy(): void
    {
        $r = (new StatisticalAnalyzer())->compare(self::CONTROL, self::VARIANT);

        // stats.ttest_ind(variant, control, equal_var=False)
        self::assertSame(40, $r->controlN);
        self::assertSame(35, $r->variantN);
        self::assertEqualsWithDelta(2332.518567, $r->controlMean, 1e-5);
        self::assertEqualsWithDelta(2073.935453, $r->variantMean, 1e-5);
        self::assertEqualsWithDelta(-0.974362, $r->tStatistic, 1e-6);
        self::assertEqualsWithDelta(70.6721, $r->degreesOfFreedom, 1e-4);
        self::assertEqualsWithDelta(0.333200, $r->pValue, 1e-6);
        // Differenz Variante - Kontrolle, 95 %-KI mit t(0.975, df)
        self::assertEqualsWithDelta(-258.583113, $r->difference, 1e-5);
        self::assertEqualsWithDelta(-787.792484, $r->ciLow, 1e-4);
        self::assertEqualsWithDelta(270.626257, $r->ciHigh, 1e-4);
        self::assertEqualsWithDelta(-11.0860, $r->relativeChange, 1e-4);
        self::assertFalse($r->isSignificant());
        self::assertSame('inconclusive', $r->winner());
    }

    public function testWinnerDependsOnDirectionAndSignificance(): void
    {
        $analyzer = new StatisticalAnalyzer();
        $faster = array_map(static fn (float $v): float => $v - 1500, self::CONTROL);
        $slower = array_map(static fn (float $v): float => $v + 1500, self::CONTROL);

        self::assertSame('variant', $analyzer->compare(self::CONTROL, $faster)->winner());
        self::assertSame('control', $analyzer->compare(self::CONTROL, $slower)->winner());
    }

    public function testSignificanceUsesStrictThreshold(): void
    {
        $analyzer = new StatisticalAnalyzer();
        $p = $analyzer->compare(self::CONTROL, self::VARIANT)->pValue;

        // p genau auf der Grenze ist nicht signifikant (p < alpha, nicht <=)
        self::assertFalse($analyzer->compare(self::CONTROL, self::VARIANT, 1 - $p)->isSignificant());
        self::assertTrue($analyzer->compare(self::CONTROL, self::VARIANT, 1 - $p - 1e-9)->isSignificant());
    }

    public function testCompareRejectsTooFewValuesAndNoSpread(): void
    {
        $analyzer = new StatisticalAnalyzer();

        try {
            $analyzer->compare([1.0], [1.0, 2.0]);
            self::fail('1 Wert muss scheitern');
        } catch (\InvalidArgumentException) {
        }

        $this->expectException(\InvalidArgumentException::class);
        $analyzer->compare([5.0, 5.0], [5.0, 5.0]);
    }

    /**
     * @return iterable<string, array{float, float, float}>
     */
    public static function tDistributionCases(): iterable
    {
        yield 'df 31, t 2.0 (Normal-Naeherung: 0.046)' => [2.0, 31, 0.0543272154];
        yield 'df 29.05, t 2.0' => [2.0, 29.05, 0.0549271811];
        yield 'df 29, t 0.5 (alte Tabelle: 0.10)' => [0.5, 29, 0.6208480842];
        yield 'df 10, t 3.5' => [3.5, 10, 0.0057265054];
        yield 'df 2.5, t 1.0' => [1.0, 2.5, 0.4040610273];
        yield 'df 70.67, t -0.974 (Vorzeichen egal)' => [-0.974362, 70.6721, 0.3332001947];
    }

    #[DataProvider('tDistributionCases')]
    public function testStudentTwoSidedPMatchesScipy(float $t, float $df, float $expected): void
    {
        self::assertEqualsWithDelta($expected, Distributions::studentTwoSidedP($t, $df), 1e-9);
    }

    public function testQuantilesMatchScipy(): void
    {
        foreach ([[0.8, 0.84162123], [0.9, 1.28155157], [0.975, 1.95996398], [0.995, 2.57582930]] as [$p, $z]) {
            self::assertEqualsWithDelta($z, Distributions::normalQuantile($p), 1e-8);
        }
        // Werte ausserhalb einer Tabelle: Bonferroni bei zwei Vergleichen, unteres Ende
        self::assertEqualsWithDelta(2.24140273, Distributions::normalQuantile(0.9875), 1e-8);
        self::assertEqualsWithDelta(-3.09023231, Distributions::normalQuantile(0.001), 1e-8);
        self::assertEqualsWithDelta(1.9941037, Distributions::studentQuantile(0.975, 70.6721), 1e-6);
    }

    public function testSampleSize(): void
    {
        $analyzer = new StatisticalAnalyzer();

        // 2 (z_0.975 + z_0.8)^2 * 320^2 / 210^2 = 36.45
        self::assertSame(37, $analyzer->requiredSampleSize(210, 320));
        self::assertSame(55, $analyzer->requiredSampleSize(210, 320, alpha: 0.01));
        self::assertSame(49, $analyzer->requiredSampleSize(210, 320, power: 0.9));

        $this->expectException(\InvalidArgumentException::class);
        $analyzer->requiredSampleSize(0, 320);
    }

    public function testSampleRatioMismatchMatchesScipyChisquare(): void
    {
        $analyzer = new StatisticalAnalyzer();
        $half = ['control' => 50, 'eager' => 50];

        self::assertEqualsWithDelta(1.0, $analyzer->sampleRatioMismatchP(['control' => 5000, 'eager' => 5000], $half), 1e-12);
        self::assertEqualsWithDelta(0.04550026, $analyzer->sampleRatioMismatchP(['control' => 5100, 'eager' => 4900], $half), 1e-8);
        self::assertEqualsWithDelta(6.3342e-5, $analyzer->sampleRatioMismatchP(['control' => 5200, 'eager' => 4800], $half), 1e-8);
        // Ungleicher Split 75/25 und drei Varianten
        self::assertEqualsWithDelta(2.6073e-4, $analyzer->sampleRatioMismatchP(['control' => 700, 'eager' => 300], ['control' => 75, 'eager' => 25]), 1e-8);
        self::assertEqualsWithDelta(0.36787944, $analyzer->sampleRatioMismatchP(['a' => 3400, 'b' => 3300, 'c' => 3300], ['a' => 1, 'b' => 1, 'c' => 1]), 1e-8);
        // Eine Variante ganz ohne Zuweisungen (Cache-Fehler: alle bekommen dieselbe)
        self::assertLessThan(1e-10, $analyzer->sampleRatioMismatchP(['eager' => 100], $half));
    }

    public function testConfigValidatesKeysVariantsAndWeights(): void
    {
        $config = new ExperimentConfig(self::EXPERIMENTS);

        self::assertSame('control', $config->control('listing_images'));
        self::assertTrue($config->isVariant('listing_images', 'eager'));
        self::assertFalse($config->isVariant('listing_images', 'x'));
        self::assertFalse($config->isVariant('listing_images', null));
        self::assertFalse($config->isVariant('other', 'eager'));
        self::assertSame(['listing_images'], array_keys($config->forRoute('frontend.navigation.page')));
        self::assertSame([], $config->forRoute('frontend.detail.page'));
        self::assertSame('exp_listing_images', ExperimentConfig::cookieName('listing_images'));

        foreach ([
            ['Listing' => self::EXPERIMENTS['listing_images']],
            ['a' => ['routes' => ['r'], 'variants' => ['control' => 50]]],
            ['a' => ['routes' => [], 'variants' => ['control' => 50, 'b' => 50]]],
            ['a' => ['routes' => ['r'], 'variants' => ['control' => 50, 'b' => 0]]],
            ['a' => ['routes' => ['r'], 'variants' => ['control' => 50, 'B C' => 50]]],
        ] as $broken) {
            try {
                new ExperimentConfig($broken);
                self::fail('Muss scheitern: ' . json_encode($broken));
            } catch (\InvalidArgumentException) {
            }
        }
    }

    public function testVariantPickerFollowsWeights(): void
    {
        $weights = ['control' => 50, 'eager' => 30, 'late' => 20];

        self::assertSame('control', VariantPicker::pick($weights, 0));
        self::assertSame('control', VariantPicker::pick($weights, 49));
        self::assertSame('eager', VariantPicker::pick($weights, 50));
        self::assertSame('eager', VariantPicker::pick($weights, 79));
        self::assertSame('late', VariantPicker::pick($weights, 80));
        self::assertSame('late', VariantPicker::pick($weights, 99));

        $this->expectException(\InvalidArgumentException::class);
        VariantPicker::pick($weights, 100);
    }

    public function testValuesByVariantCountsEachPageViewOnceWithItsLastValue(): void
    {
        $config = new ExperimentConfig(self::EXPERIMENTS);
        $records = [
            ['metric' => 'CLS', 'id' => 'v5-1-1', 'value' => 0.05, 'device' => 'mobile', 'exp_listing_images' => 'eager'],
            ['metric' => 'CLS', 'id' => 'v5-1-1', 'value' => 0.12, 'device' => 'mobile', 'exp_listing_images' => 'eager'],
            ['metric' => 'CLS', 'id' => 'v5-1-2', 'value' => 0.01, 'device' => 'desktop', 'exp_listing_images' => 'control'],
            ['metric' => 'CLS', 'id' => 'v5-1-3', 'value' => 0.02, 'device' => 'mobile', 'exp_listing_images' => 'x'],
            ['metric' => 'CLS', 'id' => 'v5-1-4', 'value' => 0.03, 'device' => 'mobile'],
            ['metric' => 'LCP', 'id' => 'v5-1-5', 'value' => 1800, 'device' => 'mobile', 'exp_listing_images' => 'control'],
            ['metric' => 'CLS', 'value' => 0.04, 'device' => 'mobile', 'exp_listing_images' => 'control'],
            ['metric' => 'CLS', 'value' => 0.06, 'device' => 'mobile', 'exp_listing_images' => 'control'],
        ];

        self::assertSame(
            ['control' => [0.01, 0.04, 0.06], 'eager' => [0.12]],
            ExperimentData::valuesByVariant($records, $config, 'listing_images', 'CLS')
        );
        self::assertSame(
            ['control' => [0.04, 0.06], 'eager' => [0.12]],
            ExperimentData::valuesByVariant($records, $config, 'listing_images', 'CLS', 'mobile')
        );
    }

    public function testAssignmentLogReaderCountsWithinWindow(): void
    {
        $now = new \DateTimeImmutable('2026-09-22T12:00:00+00:00');
        $line = static fn (string $time, string $experiment, string $variant): string => json_encode([
            'message' => 'assignment',
            'context' => ['experiment' => $experiment, 'variant' => $variant],
            'datetime' => $time,
        ], \JSON_THROW_ON_ERROR) . "\n";

        file_put_contents($this->logDir . '/ab_testing-2026-09-22.log', $line('2026-09-22T10:00:00+00:00', 'listing_images', 'control')
            . $line('2026-09-22T10:00:01+00:00', 'listing_images', 'eager')
            . $line('2026-09-22T10:00:02+00:00', 'listing_images', 'eager')
            . $line('2026-09-22T10:00:03+00:00', 'other', 'eager')
            . "kein json\n");
        file_put_contents($this->logDir . '/ab_testing-2026-09-20.log', $line('2026-09-20T10:00:00+00:00', 'listing_images', 'control'));
        file_put_contents($this->logDir . '/ab_testing-2026-09-10.log', $line('2026-09-10T10:00:00+00:00', 'listing_images', 'control'));

        $reader = new AssignmentLogReader($this->logDir);

        self::assertSame(['control' => 1, 'eager' => 2], $reader->count('listing_images', $now->modify('-1 day')));
        self::assertSame(['control' => 2, 'eager' => 2], $reader->count('listing_images', $now->modify('-3 days')));
        self::assertSame([], $reader->count('listing_images', $now->modify('+1 day')));
    }

    public function testUnreadableLogIsAnErrorNotZeroAssignments(): void
    {
        if (\function_exists('posix_geteuid') && posix_geteuid() === 0) {
            self::markTestSkipped('root liest jede Datei');
        }

        $file = $this->logDir . '/ab_testing-2026-09-22.log';
        file_put_contents($file, "{}\n");
        chmod($file, 0);

        $this->expectException(\RuntimeException::class);
        (new AssignmentLogReader($this->logDir))->count('listing_images', new \DateTimeImmutable('2026-09-21'));
    }

    public function testUnreadableLogDirIsAnError(): void
    {
        if (\function_exists('posix_geteuid') && posix_geteuid() === 0) {
            self::markTestSkipped('root liest jedes Verzeichnis');
        }

        chmod($this->logDir, 0100);

        $this->expectException(\RuntimeException::class);
        (new AssignmentLogReader($this->logDir))->count('listing_images', new \DateTimeImmutable('2026-09-21'));
    }
}
