<?php

declare(strict_types=1);

/**
 * Uebersetzt Shopwares xkey-Header in einen Cache-Tag-Header fuers CDN
 * Kapitel 11: CDN-Integration
 *
 * Shopware sendet Cache-Tags nur bei aktiviertem Reverse Proxy und nur in der
 * Schreibweise des jeweiligen Gateways: Varnish bekommt "xkey" (space-separiert),
 * Fastly bekommt "surrogate-key". Einen "Cache-Tag"-Header - die Cloudflare-
 * Konvention - sendet Shopware nie. Wer am CDN per Tag purgen will, muss ihn
 * selbst setzen.
 *
 * Gemessen an Shopware 6.6.10.6: eine Produktseite traegt 139 Tags / 4963 Bytes,
 * die Startseite 95 Tags / 3192 Bytes. Cloudflare erlaubt 16 KB pro Header
 * (etwa 1.000 Tags) und keine Leerzeichen im Tag - deshalb wird hier auf Kommas
 * umgestellt und bei 16 KB abgeschnitten, statt einen zu langen Header zu riskieren.
 *
 * Der Hook ist BeforeSendResponseEvent, weil der xkey-Header erst beim Schreiben
 * in den Reverse-Proxy-Cache gesetzt wird (ReverseProxyCache::write), also nach
 * kernel.response.
 *
 * Voraussetzung: shopware.http_cache.reverse_proxy.enabled = true mit
 * use_varnish_xkey = true (siehe config/shopware-cdn.yaml). Ohne Reverse Proxy
 * gibt es keine Tags und dieser Subscriber tut nichts.
 *
 * @see https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-tags/
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\EventSubscriber;

use Shopware\Core\Framework\Event\BeforeSendResponseEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class CdnCacheTagSubscriber implements EventSubscriberInterface
{
    /**
     * Header, den Shopwares Varnish-Gateway setzt.
     */
    private const SOURCE_HEADER = 'xkey';

    /**
     * Header, den Cloudflare auswertet.
     */
    private const TARGET_HEADER = 'Cache-Tag';

    /**
     * "The aggregate Cache-Tag HTTP header cannot exceed 16 KB after the header
     * field name, which is approximately 1,000 unique tags."
     */
    private const MAX_HEADER_BYTES = 16384;

    public static function getSubscribedEvents(): array
    {
        return [
            BeforeSendResponseEvent::class => 'onBeforeSendResponse',
        ];
    }

    public function onBeforeSendResponse(BeforeSendResponseEvent $event): void
    {
        $response = $event->getResponse();

        $xkey = $response->headers->get(self::SOURCE_HEADER);

        if ($xkey === null || trim($xkey) === '') {
            return;
        }

        $tags = preg_split('/\s+/', trim($xkey), -1, \PREG_SPLIT_NO_EMPTY) ?: [];

        $header = '';

        foreach ($tags as $tag) {
            $candidate = $header === '' ? $tag : $header . ',' . $tag;

            // Lieber weniger Tags als ein Header, den Cloudflare verwirft.
            if (\strlen($candidate) > self::MAX_HEADER_BYTES) {
                break;
            }

            $header = $candidate;
        }

        if ($header !== '') {
            $response->headers->set(self::TARGET_HEADER, $header);
        }
    }
}
