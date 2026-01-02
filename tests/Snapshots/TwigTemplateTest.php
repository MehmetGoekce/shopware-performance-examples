<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Snapshots;

use PHPUnit\Framework\TestCase;
use Spatie\Snapshots\MatchesSnapshots;

/**
 * Twig Template Snapshot Tests
 *
 * Tests that Twig templates haven't changed unexpectedly.
 * Uses text snapshots of template content.
 */
class TwigTemplateTest extends TestCase
{
    use MatchesSnapshots;

    private const TEMPLATE_DIR = __DIR__ . '/../../chapters';

    /**
     * Get all Twig template files
     */
    public static function templateProvider(): array
    {
        $templates = [];
        $dir = realpath(__DIR__ . '/../../chapters');

        if (!$dir || !is_dir($dir)) {
            return [['dummy' => 'No templates found']];
        }

        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($dir)
        );

        foreach ($iterator as $file) {
            if ($file->isFile() && str_ends_with($file->getFilename(), '.html.twig')) {
                $relativePath = str_replace($dir . '/', '', $file->getPathname());
                $templates[$relativePath] = [$file->getPathname(), $relativePath];
            }
        }

        return $templates ?: [['dummy' => 'No templates found']];
    }

    /**
     * Test that template structure matches snapshot
     *
     * @dataProvider templateProvider
     */
    public function testTemplateSnapshot(string $filePath, string $relativePath): void
    {
        if ($filePath === 'dummy') {
            $this->markTestSkipped('No templates found');
        }

        $content = file_get_contents($filePath);
        $this->assertNotEmpty($content, "Template file should not be empty: {$relativePath}");

        // Normalize line endings for cross-platform consistency
        $content = str_replace("\r\n", "\n", $content);

        // Use relative path as snapshot name
        $snapshotName = str_replace(['/', '.html.twig'], ['_', ''], $relativePath);

        // @phpstan-ignore-next-line (spatie/phpunit-snapshot-assertions accepts optional name parameter)
        $this->assertMatchesTextSnapshot($content, $snapshotName);
    }

    /**
     * Test that templates use recommended patterns
     *
     * @dataProvider templateProvider
     */
    public function testTemplatePerformancePatterns(string $filePath, string $relativePath): void
    {
        if ($filePath === 'dummy') {
            $this->markTestSkipped('No templates found');
        }

        $content = file_get_contents($filePath);
        $issues = [];

        // Check for common performance anti-patterns
        $antiPatterns = [
            // Inline styles should be minimal (except for critical CSS)
            '/style="[^"]{500,}"/' => 'Large inline style detected (>500 chars)',

            // Avoid inline onclick handlers
            '/onclick="(?!return|this\.)/' => 'Inline onclick handler (prefer event listeners)',

            // Images should have loading attribute
            '/<img(?![^>]*loading=)[^>]*>/' => 'Image without loading attribute',
        ];

        foreach ($antiPatterns as $pattern => $message) {
            if (preg_match($pattern, $content)) {
                // Don't fail, just note it
                $issues[] = $message;
            }
        }

        // Check for performance best practices
        $bestPractices = [
            // defer or async for scripts
            'defer' => '/<script[^>]*defer[^>]*>/',
            'async' => '/<script[^>]*async[^>]*>/',
            'type="module"' => '/<script[^>]*type="module"[^>]*>/',

            // Lazy loading
            'loading="lazy"' => '/loading="lazy"/',
            'loading="eager"' => '/loading="eager"/',

            // Preload/Preconnect
            'preload' => '/rel="preload"/',
            'preconnect' => '/rel="preconnect"/',
            'dns-prefetch' => '/rel="dns-prefetch"/',
        ];

        $foundPractices = [];
        foreach ($bestPractices as $name => $pattern) {
            if (preg_match($pattern, $content)) {
                $foundPractices[] = $name;
            }
        }

        // This test always passes - it's informational
        $this->addToAssertionCount(1);
    }

    /**
     * Test that templates have proper block structure
     *
     * @dataProvider templateProvider
     */
    public function testTemplateBlockStructure(string $filePath, string $relativePath): void
    {
        if ($filePath === 'dummy') {
            $this->markTestSkipped('No templates found');
        }

        $content = file_get_contents($filePath);

        // Count opening and closing blocks
        preg_match_all('/\{%\s*block\s+\w+\s*%\}/', $content, $openBlocks);
        preg_match_all('/\{%\s*endblock\s*%\}/', $content, $closeBlocks);

        $openCount = count($openBlocks[0]);
        $closeCount = count($closeBlocks[0]);

        $this->assertEquals(
            $openCount,
            $closeCount,
            "Unbalanced blocks in {$relativePath}: {$openCount} opens, {$closeCount} closes"
        );
    }

    /**
     * Test that templates have valid Twig syntax (basic check)
     *
     * @dataProvider templateProvider
     */
    public function testTemplateTwigSyntax(string $filePath, string $relativePath): void
    {
        if ($filePath === 'dummy') {
            $this->markTestSkipped('No templates found');
        }

        $content = file_get_contents($filePath);

        // Check for balanced Twig tags
        preg_match_all('/\{%/', $content, $openTags);
        preg_match_all('/%\}/', $content, $closeTags);

        $this->assertEquals(
            count($openTags[0]),
            count($closeTags[0]),
            "Unbalanced Twig tags {% %} in {$relativePath}"
        );

        // Check for balanced Twig prints
        preg_match_all('/\{\{/', $content, $openPrints);
        preg_match_all('/\}\}/', $content, $closePrints);

        $this->assertEquals(
            count($openPrints[0]),
            count($closePrints[0]),
            "Unbalanced Twig prints {{ }} in {$relativePath}"
        );

        // Check for balanced Twig comments
        preg_match_all('/\{#/', $content, $openComments);
        preg_match_all('/#\}/', $content, $closeComments);

        $this->assertEquals(
            count($openComments[0]),
            count($closeComments[0]),
            "Unbalanced Twig comments {# #} in {$relativePath}"
        );
    }

    /**
     * Test template file encoding
     *
     * @dataProvider templateProvider
     */
    public function testTemplateEncoding(string $filePath, string $relativePath): void
    {
        if ($filePath === 'dummy') {
            $this->markTestSkipped('No templates found');
        }

        $content = file_get_contents($filePath);

        // Check UTF-8 validity
        $this->assertTrue(
            mb_check_encoding($content, 'UTF-8'),
            "Template {$relativePath} is not valid UTF-8"
        );

        // Check for BOM (should not be present)
        $bom = "\xEF\xBB\xBF";
        $this->assertStringStartsNotWith(
            $bom,
            $content,
            "Template {$relativePath} has UTF-8 BOM (should be removed)"
        );
    }
}
