<?php

declare(strict_types=1);

namespace Memotech\ShopwarePerformance\Tests\Unit;

use PHPUnit\Framework\TestCase;
use YourPlugin\Service\PreloadLinkBuilder;

require_once __DIR__ . '/../../chapters/11-cdn-integration/src/Service/PreloadLinkBuilder.php';

/**
 * Tests fuer den Link-Header aus Kapitel 11 (Early Hints).
 * Der Subscriber selbst ist im Dockware-Shop getestet (Shopware 6.6.10.6):
 * Header bei MISS und HIT, keiner bei 404/302/204, Browser laedt jede Datei einmal.
 */
class PreloadLinkBuilderTest extends TestCase
{
    private const CSS = '/theme/5e5189ac3f2a3ed428329dd708c019ad/css/all.css?1790181791';
    private const JS = '/theme/5e5189ac3f2a3ed428329dd708c019ad/js/storefront/storefront.js?1790181791';

    private PreloadLinkBuilder $builder;

    protected function setUp(): void
    {
        $this->builder = new PreloadLinkBuilder();
    }

    public function testRealStorefrontHeadGivesExactlyTheRenderedUrls(): void
    {
        $html = (string) file_get_contents(__DIR__ . '/fixtures/ch11-storefront-head-6.6.10.6.html');

        self::assertSame(
            '<http://localhost' . self::CSS . '>; rel=preload; as=style, '
            . '<http://localhost' . self::JS . '>; rel=preload; as=script',
            $this->builder->build($html)
        );
    }

    public function testPluginScriptsAndOtherThemeFilesStayOut(): void
    {
        $html = '<head>'
            . '<link rel="stylesheet" href="' . self::CSS . '">'
            . '<script type="text/javascript" src="' . self::JS . '" defer></script>'
            . '<script type="text/javascript" src="/theme/5e5189ac/js/swag-paypal/swag-paypal.js?1" defer></script>'
            . '<script type="text/javascript" src="/theme/5e5189ac/js/my-theme/my-theme.js?1" defer></script>'
            . '<link rel="stylesheet" href="/theme/5e5189ac/css/other.css">'
            . '</head>';

        self::assertSame(
            '<' . self::CSS . '>; rel=preload; as=style, <' . self::JS . '>; rel=preload; as=script',
            $this->builder->build($html)
        );
    }

    public function testThemeSegmentMayFollowAPathPrefix(): void
    {
        $html = '<head><link rel="stylesheet" href="https://cdn.example.com/shop1/theme/abc/css/all.css?1"></head>';

        self::assertSame('<https://cdn.example.com/shop1/theme/abc/css/all.css?1>; rel=preload; as=style', $this->builder->build($html));
    }

    public function testOnlyTheHeadCounts(): void
    {
        $html = '<html><head><title>x</title></head><body>'
            . '<link rel="stylesheet" href="' . self::CSS . '"><script src="' . self::JS . '"></script>'
            . '</body></html>';

        self::assertNull($this->builder->build($html));
    }

    public function testWithoutClosingHeadNothingIsBuilt(): void
    {
        self::assertNull($this->builder->build('<link rel="stylesheet" href="' . self::CSS . '">'));
    }

    public function testSkipsAssetsOutsideTheThemeFolder(): void
    {
        $html = '<head>'
            . '<link rel="stylesheet" href="https://fonts.example.com/inter.css">'
            . '<link rel="stylesheet" href="/bundles/storefront/css/all.css">'
            . '<script src="https://cdn.example.com/js/storefront/storefront.js"></script>'
            . '</head>';

        self::assertNull($this->builder->build($html));
    }

    public function testSkipsModuleScriptsInlineScriptsAndOtherLinkTypes(): void
    {
        $html = '<head>'
            . '<script type="module" src="' . self::JS . '"></script>'
            . '<script>window.x = 1;</script>'
            . '<link rel="preload" href="' . self::CSS . '" as="style">'
            . '<link rel="icon" href="' . self::CSS . '">'
            . '</head>';

        self::assertNull($this->builder->build($html));
    }

    public function testSkipsTagsTheBrowserWouldNotLoadNow(): void
    {
        $html = '<head>'
            . '<link rel="stylesheet" media="print" href="' . self::CSS . '">'
            . '<link rel="stylesheet" disabled href="' . self::CSS . '">'
            . '<script nomodule src="' . self::JS . '"></script>'
            . '</head>';

        self::assertNull($this->builder->build($html));
    }

    public function testMediaAllAndScreenCount(): void
    {
        $html = '<head><link rel="stylesheet" media="screen" href="' . self::CSS . '"></head>';

        self::assertSame('<' . self::CSS . '>; rel=preload; as=style', $this->builder->build($html));
    }

    public function testIgnoresCommentedOutTags(): void
    {
        $html = '<head><!-- <link rel="stylesheet" href="' . self::CSS . '"> --></head>';

        self::assertNull($this->builder->build($html));
    }

    public function testDecodesEntitiesAcceptsSingleQuotesUppercaseAndAnyAttributeOrder(): void
    {
        $html = "<HEAD><LINK href='/theme/abc/css/all.css?a=1&amp;b=2' REL='STYLESHEET'>"
            . '<SCRIPT defer src="/theme/abc/js/storefront/storefront.js?9" TYPE="text/javascript"></SCRIPT></HEAD>';

        self::assertSame(
            '</theme/abc/css/all.css?a=1&b=2>; rel=preload; as=style, '
            . '</theme/abc/js/storefront/storefront.js?9>; rel=preload; as=script',
            $this->builder->build($html)
        );
    }

    public function testOtherElementsWithSimilarNamesDoNotCount(): void
    {
        $html = '<head><links rel="stylesheet" href="' . self::CSS . '"></links><scripts src="' . self::JS . '"></scripts></head>';

        self::assertNull($this->builder->build($html));
    }

    public function testUppercaseModuleTypeIsStillAModule(): void
    {
        self::assertNull($this->builder->build('<head><script type="MODULE" src="' . self::JS . '"></script></head>'));
    }

    public function testFirstOfDuplicateAttributesWins(): void
    {
        $html = '<head><link rel="stylesheet" href="' . self::CSS . '" href="/theme/x/css/all.css"></head>';

        self::assertSame('<' . self::CSS . '>; rel=preload; as=style', $this->builder->build($html));
    }

    public function testDuplicateUrlsAppearOnce(): void
    {
        $html = '<head><link rel="stylesheet" href="' . self::CSS . '"><link rel="stylesheet" href="' . self::CSS . '"></head>';

        self::assertSame('<' . self::CSS . '>; rel=preload; as=style', $this->builder->build($html));
    }

    /**
     * @return array<string, array{string}>
     */
    public static function urlsThatMustNotReachTheHeader(): array
    {
        return [
            'Zeilenumbruch (Header-Injection)' => ['/theme/a/css/all.css?x&#10;Set-Cookie:%20a=b'],
            'Wagenruecklauf roh' => ["/theme/a/css/all.css?x\r"],
            'Zeilenumbruch roh' => ["/theme/a/css/all.css?x\nSet-Cookie: a=b"],
            'Leerzeichen' => ['/theme/a/css/all.css?x y'],
            'geschuetztes Leerzeichen' => ['/theme/a/css/all.css?x&nbsp;'],
            'Komma' => ['/theme/a/css/all.css?x,y'],
            'spitze Klammer auf' => ['/theme/a/css/all.css?x&lt;y'],
            'spitze Klammer zu' => ['/theme/a/css/all.css?x&gt;y'],
            'javascript:' => ['javascript:/theme/a/css/all.css'],
            'Punkt-Segment' => ['/theme/../css/all.css'],
        ];
    }

    /**
     * @dataProvider urlsThatMustNotReachTheHeader
     */
    public function testUrlsThatWouldBreakTheHeaderAreSkipped(string $href): void
    {
        self::assertNull($this->builder->build('<head><link rel="stylesheet" href="' . $href . '"></head>'));
    }
}
