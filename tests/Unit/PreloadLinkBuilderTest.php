<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;
use YourPlugin\Service\PreloadLinkBuilder;

require_once __DIR__ . '/../../chapters/11-cdn-integration/src/Service/PreloadLinkBuilder.php';

/**
 * Tests fuer den Link-Header aus Kapitel 11 (Early Hints).
 * Der Subscriber selbst ist im Dockware-Shop getestet (Shopware 6.6.10.6):
 * Header bei MISS und HIT, keiner bei 404/302, Browser laedt jede Datei einmal.
 */
class PreloadLinkBuilderTest extends TestCase
{
    private PreloadLinkBuilder $builder;

    protected function setUp(): void
    {
        $this->builder = new PreloadLinkBuilder();
    }

    public function testRealStorefrontHeadGivesExactlyTheRenderedUrls(): void
    {
        $html = (string) file_get_contents(__DIR__ . '/fixtures/ch11-storefront-head-6.6.10.6.html');

        self::assertSame(
            '<http://localhost/theme/5e5189ac3f2a3ed428329dd708c019ad/css/all.css?1790181791>; rel=preload; as=style, '
            . '<http://localhost/theme/5e5189ac3f2a3ed428329dd708c019ad/js/storefront/storefront.js?1790181791>; rel=preload; as=script',
            $this->builder->build($html)
        );
    }

    public function testOnlyTheHeadCounts(): void
    {
        $html = '<html><head><title>x</title></head><body>'
            . '<link rel="stylesheet" href="/theme/a/css/all.css"><script src="/theme/a/js/x/x.js"></script>'
            . '</body></html>';

        self::assertNull($this->builder->build($html));
    }

    public function testWithoutClosingHeadNothingIsBuilt(): void
    {
        self::assertNull($this->builder->build('<link rel="stylesheet" href="/theme/a/css/all.css">'));
    }

    public function testSkipsAssetsOutsideTheThemeFolder(): void
    {
        $html = '<head>'
            . '<link rel="stylesheet" href="https://fonts.example.com/inter.css">'
            . '<link rel="stylesheet" href="/bundles/someplugin/style.css">'
            . '<script src="https://cdn.example.com/widget.js"></script>'
            . '<link rel="stylesheet" href="/theme/abc/css/all.css?1">'
            . '</head>';

        self::assertSame('</theme/abc/css/all.css?1>; rel=preload; as=style', $this->builder->build($html));
    }

    public function testSkipsModuleScriptsInlineScriptsAndOtherLinkTypes(): void
    {
        $html = '<head>'
            . '<script type="module" src="/theme/abc/js/m/m.js"></script>'
            . '<script>window.x = 1;</script>'
            . '<link rel="preload" href="/theme/abc/assets/font/Inter.woff2" as="font">'
            . '<link rel="icon" href="/theme/abc/assets/favicon.png">'
            . '</head>';

        self::assertNull($this->builder->build($html));
    }

    public function testIgnoresCommentedOutTags(): void
    {
        $html = '<head><!-- <link rel="stylesheet" href="/theme/old/css/all.css"> --></head>';

        self::assertNull($this->builder->build($html));
    }

    public function testDecodesHtmlEntitiesAndAcceptsSingleQuotesAndAnyAttributeOrder(): void
    {
        $html = "<head><link href='/theme/abc/css/all.css?a=1&amp;b=2' rel='STYLESHEET'>"
            . '<script defer src="/theme/abc/js/storefront/storefront.js?9" type="text/javascript"></script></head>';

        self::assertSame(
            '</theme/abc/css/all.css?a=1&b=2>; rel=preload; as=style, '
            . '</theme/abc/js/storefront/storefront.js?9>; rel=preload; as=script',
            $this->builder->build($html)
        );
    }

    public function testDuplicateUrlsAppearOnce(): void
    {
        $html = '<head><link rel="stylesheet" href="/theme/a/css/all.css"><link rel="stylesheet" href="/theme/a/css/all.css"></head>';

        self::assertSame('</theme/a/css/all.css>; rel=preload; as=style', $this->builder->build($html));
    }

    public function testUrlsThatWouldBreakTheHeaderAreSkipped(): void
    {
        $html = '<head><link rel="stylesheet" href="/theme/a/css/x,y.css"><link rel="stylesheet" href="/theme/a/css/a&gt;b.css"></head>';

        self::assertNull($this->builder->build($html));
    }
}
