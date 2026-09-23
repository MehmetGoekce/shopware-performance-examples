<?php

declare(strict_types=1);

/**
 * Baut aus dem gerenderten <head> einen Link-Header mit rel=preload
 * Kapitel 11: CDN-Integration (Early Hints)
 *
 * Warum aus dem HTML und nicht aus einer festen Liste: Shopware legt das
 * kompilierte Theme unter /theme/<seed>/css/all.css und
 * /theme/<seed>/js/<name>/<name>.js ab, und der Seed wechselt bei jedem
 * theme:compile (SeedingThemePathBuilder). Dazu haengt asset() einen
 * Versions-Parameter an. Ein fest eingetragener Pfad trifft deshalb nach dem
 * naechsten Compile eine alte Datei oder ein 404. Die Tags im <head> tragen
 * dagegen genau die URL, die der Browser gleich laden wird - und nur wenn die
 * Preload-URL Zeichen fuer Zeichen gleich ist, nutzt der Browser den Preload.
 *
 * Mitgenommen werden:
 * - <link rel="stylesheet" href="..."> -> as=style
 * - <script src="..."> ohne type="module" -> as=script
 * jeweils nur mit einem Pfad unter /theme/ - das sind die Dateien, die
 * Shopware selbst einbindet. Der Host bleibt, wie Shopware ihn rendert; liegt
 * das Theme auf einer CDN-Domain (config/shopware-cdn.yaml), zeigt der Header
 * dorthin, und der Browser nutzt den Preload trotzdem (gemessen). Modul-Skripte
 * (ab 6.7.11 aus /bundles/, per Importmap) brauchen rel=modulepreload - das
 * wertet Cloudflare fuer Early Hints nicht aus ("Link headers with preconnect
 * or preload rel types").
 *
 * Reine Logik ohne Shopware-Abhaengigkeit, damit sie ohne Shop testbar ist.
 *
 * @see https://developers.cloudflare.com/cache/advanced-configuration/early-hints/
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\Service;

class PreloadLinkBuilder
{
    private const THEME_PATH_PREFIX = '/theme/';

    /**
     * Liefert den Wert fuer den Link-Header oder null, wenn der <head> keine
     * passenden Assets enthaelt.
     */
    public function build(string $html): ?string
    {
        $headEnd = stripos($html, '</head>');

        if ($headEnd === false) {
            return null;
        }

        $head = substr($html, 0, $headEnd);

        // Kommentare zuerst entfernen, sonst zaehlt ein auskommentiertes Tag mit.
        $head = preg_replace('/<!--.*?-->/s', '', $head) ?? $head;

        preg_match_all('/<(link|script)\b([^>]*)>/i', $head, $tags, \PREG_SET_ORDER);

        $links = [];

        foreach ($tags as [, $tagName, $attributeString]) {
            $attributes = $this->parseAttributes($attributeString);

            if (strtolower($tagName) === 'link') {
                if (strtolower($attributes['rel'] ?? '') !== 'stylesheet' || !isset($attributes['href'])) {
                    continue;
                }

                $url = $attributes['href'];
                $as = 'style';
            } else {
                if (!isset($attributes['src']) || strtolower($attributes['type'] ?? '') === 'module') {
                    continue;
                }

                $url = $attributes['src'];
                $as = 'script';
            }

            if (!$this->isThemeAsset($url)) {
                continue;
            }

            $links[$url] = \sprintf('<%s>; rel=preload; as=%s', $url, $as);
        }

        return $links === [] ? null : implode(', ', $links);
    }

    /**
     * @return array<string, string>
     */
    private function parseAttributes(string $attributeString): array
    {
        preg_match_all('/([a-zA-Z][\w-]*)\s*=\s*(?:"([^"]*)"|\'([^\']*)\')/', $attributeString, $matches, \PREG_SET_ORDER);

        $attributes = [];

        foreach ($matches as $match) {
            $value = $match[3] ?? '';
            if ($match[2] !== '') {
                $value = $match[2];
            }

            // href="...?a=1&amp;b=2" steht im HTML kodiert, der Header braucht die echte URL.
            $attributes[strtolower($match[1])] = html_entity_decode($value, \ENT_QUOTES | \ENT_HTML5);
        }

        return $attributes;
    }

    private function isThemeAsset(string $url): bool
    {
        // Ein Link-Header darf keine Zeilenumbrueche, spitzen Klammern oder Kommas
        // in der URL tragen - solche URLs lieber auslassen als den Header brechen.
        if (preg_match('/[\s<>,]/', $url) === 1) {
            return false;
        }

        $path = parse_url($url, \PHP_URL_PATH);

        return \is_string($path) && str_starts_with($path, self::THEME_PATH_PREFIX);
    }
}
