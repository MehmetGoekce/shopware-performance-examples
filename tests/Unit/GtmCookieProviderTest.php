<?php

declare(strict_types=1);

namespace Shopware\Storefront\Framework\Cookie {
    // Minimaler Ersatz fuer das Shopware-Interface (6.6/6.7: nur getCookieGroups()).
    if (!interface_exists(CookieProviderInterface::class)) {
        interface CookieProviderInterface
        {
            /** @return array<string|int, mixed> */
            public function getCookieGroups(): array;
        }
    }
}

namespace Memotech\ShopwarePerformance\Tests\Unit {
    use PHPUnit\Framework\TestCase;
    use Shopware\Storefront\Framework\Cookie\CookieProviderInterface;
    use ThirdPartyScripts\Framework\Cookie\GtmCookieProvider;

    require_once __DIR__ . '/../../chapters/21-third-party-scripts/ThirdPartyScripts/src/Framework/Cookie/GtmCookieProvider.php';

    /**
     * Tests fuer den Cookie-Eintrag des Kapitel-21-Plugins (ohne Shopware).
     * Banner, Event CookieConfiguration_Update und der GTM-Loader sind im
     * Dockware-Shop getestet (Shopware 6.6.10.6), siehe README "Tests".
     */
    class GtmCookieProviderTest extends TestCase
    {
        public function testAddsEntryToStatisticalGroup(): void
        {
            $groups = $this->provider([
                ['snippet_name' => 'cookie.groupRequired', 'entries' => [['cookie' => 'session-']]],
                ['snippet_name' => 'cookie.groupStatistical', 'entries' => [['cookie' => 'google-analytics-enabled', 'value' => '1']]],
                ['snippet_name' => 'cookie.groupMarketing', 'entries' => [['cookie' => 'google-ads-enabled', 'value' => '1']]],
            ])->getCookieGroups();

            self::assertCount(3, $groups);
            self::assertSame(
                ['google-analytics-enabled', 'gtm-enabled'],
                array_column($groups[1]['entries'], 'cookie')
            );
            self::assertSame('1', $groups[1]['entries'][1]['value']);
        self::assertSame('30', $groups[1]['entries'][1]['expiration']);
            self::assertSame(['session-'], array_column($groups[0]['entries'], 'cookie'));
            self::assertSame(['google-ads-enabled'], array_column($groups[2]['entries'], 'cookie'));
        }

        public function testCreatesOwnGroupWhenStatisticalGroupIsMissing(): void
        {
            $groups = $this->provider([
                ['snippet_name' => 'cookie.groupRequired', 'entries' => [['cookie' => 'session-']]],
            ])->getCookieGroups();

            self::assertCount(2, $groups);
            self::assertSame('cookie.groupStatistical', $groups[1]['snippet_name']);
            self::assertSame(['gtm-enabled'], array_column($groups[1]['entries'], 'cookie'));
        }

        public function testKeepsStringKeysOfOtherDecorators(): void
        {
            $groups = $this->provider([
                'required' => ['snippet_name' => 'cookie.groupRequired', 'entries' => []],
                'statistics' => ['snippet_name' => 'cookie.groupStatistical', 'entries' => []],
            ])->getCookieGroups();

            self::assertSame(['required', 'statistics'], array_keys($groups));
            self::assertSame(['gtm-enabled'], array_column($groups['statistics']['entries'], 'cookie'));
        }

        /**
         * @param array<string|int, mixed> $groups
         */
        private function provider(array $groups): GtmCookieProvider
        {
            $inner = new class ($groups) implements CookieProviderInterface {
                /** @param array<string|int, mixed> $groups */
                public function __construct(private readonly array $groups)
                {
                }

                public function getCookieGroups(): array
                {
                    return $this->groups;
                }
            };

            return new GtmCookieProvider($inner);
        }
    }
}
