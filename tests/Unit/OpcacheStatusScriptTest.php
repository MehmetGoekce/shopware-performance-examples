<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Kapitel 9: scripts/opcache-status.php mit echtem OPcache in der CLI
 * (opcache.enable_cli=1). Die CLI hat ihren eigenen, frischen Cache - genau
 * der Zustand eines Pools direkt nach einem Reload (MEM-328).
 */
class OpcacheStatusScriptTest extends TestCase
{
    private const SCRIPT = __DIR__ . '/../../chapters/09-php-performance/scripts/opcache-status.php';

    private string $dir;

    protected function setUp(): void
    {
        $this->dir = sys_get_temp_dir() . '/opcache-status-' . bin2hex(random_bytes(4));
        mkdir($this->dir . '/sub', 0777, true);
    }

    protected function tearDown(): void
    {
        foreach (glob($this->dir . '/*.php') ?: [] as $file) {
            unlink($file);
        }
        rmdir($this->dir . '/sub');
        rmdir($this->dir);
    }

    /**
     * @param list<string> $ini
     * @return array{0: int, 1: list<string>}
     */
    private function runScript(array $ini, ?string $prepend = null): array
    {
        $args = [\PHP_BINARY];
        $probe = shell_exec(escapeshellarg(\PHP_BINARY) . ' -r "echo (int) extension_loaded(\'Zend OPcache\');"');
        if ($probe !== '1') {
            $args[] = '-dzend_extension=opcache';
        }
        foreach (array_merge(['opcache.enable=1', 'opcache.enable_cli=1', 'opcache.file_cache=', 'opcache.file_update_protection=0'], $ini) as $d) {
            $args[] = '-d' . $d;
        }
        if ($prepend !== null) {
            $args[] = '-dauto_prepend_file=' . $prepend;
        }
        $args[] = self::SCRIPT;

        exec(implode(' ', array_map('escapeshellarg', $args)) . ' 2>&1', $out, $rc);
        if (!in_array('=== OPcache Status ===', $out, true)) {
            $this->markTestSkipped('OPcache laesst sich in dieser CLI nicht aktivieren: ' . implode(' | ', $out));
        }

        return [$rc, $out];
    }

    public function testFrischerCacheNenntZaehlzeitUndKeinenValidateTimestampsRat(): void
    {
        [$rc, $out] = $this->runScript([]);

        self::assertSame(0, $rc);
        self::assertContains('  Cache voll: Nein', $out);
        self::assertContains('  Zaehlt seit: 0 h 0 min (Start oder letzter Reset)', $out);
        $warning = preg_grep('/^WARNUNG: Hit Rate nur /', $out);
        self::assertCount(1, $warning);
        self::assertStringContainsString('% seit 0 h 0 min. Kurz nach einem Neustart, Reload oder Reset ist das normal', (string) current($warning));
        self::assertSame([], preg_grep('/validate_timestamps/', $out));
        self::assertSame([], preg_grep('/OPcache ist voll/', $out));
    }

    public function testVollerSchluesselbereichWirdGemeldetObwohlDieSkriptzahlUnter90ProzentLiegt(): void
    {
        // Per include ueber sub/../ eingebunden belegt jede Datei zwei
        // Schluessel - wie Composers __DIR__ . '/..'. require_once loest den
        // Pfad auf und belegt nur einen. 150 Dateien = 300 Schluessel > 223.
        $prepend = $this->dir . '/prepend.php';
        $code = "<?php\n";
        for ($i = 0; $i < 150; $i++) {
            file_put_contents($this->dir . "/f$i.php", "<?php\nfunction mem328_f$i(): int { return $i; }\n");
            $code .= "include __DIR__ . '/sub/../f$i.php';\n";
        }
        file_put_contents($prepend, $code);

        [$rc, $out] = $this->runScript(['opcache.max_accelerated_files=200'], $prepend);

        self::assertSame(0, $rc);
        self::assertContains('  Cache voll: Ja', $out);
        self::assertContains('  Schluessel: 223 (100%)', $out);
        self::assertContains('  Maximum: 223 (eingetragen: 200, aufgerundet)', $out);
        self::assertCount(1, preg_grep('/^WARNUNG: OPcache ist voll /', $out));
        self::assertCount(1, preg_grep('/^WARNUNG: Schluessel-Limit bei 100% /', $out));

        $cached = preg_grep('/^  Gecached: \d+$/', $out);
        self::assertCount(1, $cached);
        self::assertLessThan(200, (int) substr((string) current($cached), 12), 'Skripte allein laegen unter 90 % von 223');
    }
}
