<?php declare(strict_types=1);

namespace ThirdPartyScripts\Framework\Cookie;

use Shopware\Storefront\Framework\Cookie\CookieProviderInterface;

/**
 * Eigener Eintrag «Google Tag Manager» im Shopware-Cookie-Banner
 * Kapitel 21: Third-Party Scripts & Tag Management
 *
 * Haengt den Cookie gtm-enabled in die Gruppe «Statistik» (cookie.groupStatistical).
 * Stimmt der Besucher zu, setzt Shopware gtm-enabled=1 und meldet die Aenderung
 * im Browser ueber das Event CookieConfiguration_Update. Darauf reagiert der
 * Loader in views/storefront/layout/meta.html.twig.
 *
 * Fehlt die Gruppe (ein anderes Plugin hat sie entfernt), bekommt der Eintrag
 * eine eigene Gruppe.
 *
 * @see https://developer.shopware.com/docs/guides/plugins/plugins/storefront/add-cookie-to-manager.html
 */
class GtmCookieProvider implements CookieProviderInterface
{
    public const COOKIE = 'gtm-enabled';

    private const ENTRY = [
        'snippet_name' => 'thirdPartyScripts.cookie.gtm',
        'snippet_description' => 'thirdPartyScripts.cookie.gtmDescription',
        'cookie' => self::COOKIE,
        'value' => '1',
        'expiration' => '30',
    ];

    public function __construct(private readonly CookieProviderInterface $inner)
    {
    }

    public function getCookieGroups(): array
    {
        $groups = $this->inner->getCookieGroups();

        foreach ($groups as $key => $group) {
            if (($group['snippet_name'] ?? null) === 'cookie.groupStatistical') {
                $groups[$key]['entries'][] = self::ENTRY;

                return $groups;
            }
        }

        $groups[] = [
            'snippet_name' => 'cookie.groupStatistical',
            'snippet_description' => 'cookie.groupStatisticalDescription',
            'entries' => [self::ENTRY],
        ];

        return $groups;
    }
}
