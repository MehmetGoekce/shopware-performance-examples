<?php

declare(strict_types=1);

/**
 * Baut aus dem gerenderten <head> einen Link-Header mit rel=preload
 * Kapitel 11: CDN-Integration (Early Hints)
 *
 * Warum aus dem HTML und nicht aus einer festen Liste: Shopware legt das
 * kompilierte Theme unter /theme/<hash>/css/all.css und
 * /theme/<hash>/js/<name>/<name>.js ab. Der Hash (aus Theme, Verkaufskanal und
 * einem Seed) wechselt bei jedem theme:compile (SeedingThemePathBuilder), und
 * asset() haengt einen Versions-Parameter an. Ein fest eingetragener Pfad
 * trifft deshalb nach dem naechsten Compile eine alte Datei oder ein 404. Die
 * Tags im <head> tragen dagegen genau die URL, die der Browser gleich laden
 * wird - und nur wenn die Preload-URL Zeichen fuer Zeichen gleich ist, nutzt
 * der Browser den Preload.
 *
 * Mitgenommen werden genau die beiden Einstiegsdateien des Themes:
 * - <link rel="stylesheet" href=".../theme/<hash>/css/all.css?..."> -> as=style
 * - <script src=".../theme/<hash>/js/storefront/storefront.js?..."> -> as=script
 * Plugins mit Storefront-JS bekommen je ein eigenes <script> unter
 * /theme/<hash>/js/<plugin>/; die bleiben draussen, sonst waechst der Header
 * mit jedem Plugin, und ein vorgeladenes Skript laedt mit hoher statt
 * niedriger Prioritaet (Chromium, gemessen an storefront.js). Ab 6.7.11 kommen
 * ein Modul-Skript und Komponenten-CSS aus /bundles/ dazu (Importmap); auch die
 * bleiben draussen - Module braeuchten rel=modulepreload, und Cloudflare
 * uebernimmt nur "Link headers with preconnect or preload rel types".
 *
 * Der Host bleibt, wie Shopware ihn rendert, und das Theme-Segment darf
 * irgendwo im Pfad stehen: Liegt das Theme auf einer CDN-Domain
 * (config/shopware-cdn.yaml), auch mit Pfad davor, zeigt der Header dorthin.
 * Gemessen hat der Browser den Preload vom Link-Header der 200-Antwort auch
 * dann genutzt (ohne CDN, zweite Domain im Testshop).
 *
 * Der Parser ist auf die Tags zugeschnitten, die Shopwares meta.html.twig
 * rendert (Attribute in Anfuehrungszeichen), kein allgemeiner HTML-Parser.
 * Im Zweifel laesst er eine URL aus, statt einen falschen Hint zu senden.
 *
 * Reine Logik ohne Shopware-Abhaengigkeit, damit sie ohne Shop testbar ist.
 *
 * @see https://developers.cloudflare.com/cache/advanced-configuration/early-hints/
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\Service;

class PreloadLinkBuilder
{
    /**
     * /theme/<hash>/css/all.css bzw. /theme/<hash>/js/storefront/storefront.js
     * am Ende des Pfads; davor darf ein Pfad-Praefix stehen (CDN, Unterordner).
     */
    private const ENTRY_PATTERNS = [
        'style' => '#/theme/[A-Za-z0-9_-]+/css/all\.css$#',
        'script' => '#/theme/[A-Za-z0-9_-]+/js/storefront/storefront\.js$#',
    ];

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

            if (isset($attributes['disabled']) || isset($attributes['nomodule'])) {
                continue;
            }

            if (strtolower($tagName) === 'link') {
                if (strtolower($attributes['rel'] ?? '') !== 'stylesheet'
                    || !isset($attributes['href'])
                    || !\in_array(strtolower(trim($attributes['media'] ?? 'all')), ['', 'all', 'screen'], true)
                ) {
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

            if (!$this->isThemeEntry($url, $as)) {
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
        preg_match_all('/([a-zA-Z][\w-]*)(?:\s*=\s*(?:"([^"]*)"|\'([^\']*)\'))?/', $attributeString, $matches, \PREG_SET_ORDER);

        $attributes = [];

        foreach ($matches as $match) {
            $name = strtolower($match[1]);

            // HTML nimmt bei doppelten Attributen das erste.
            if (\array_key_exists($name, $attributes)) {
                continue;
            }

            $value = $match[3] ?? '';
            if (($match[2] ?? '') !== '') {
                $value = $match[2];
            }

            // href="...?a=1&amp;b=2" steht im HTML kodiert, der Header braucht die echte URL.
            $attributes[$name] = html_entity_decode($value, \ENT_QUOTES | \ENT_HTML5);
        }

        return $attributes;
    }

    private function isThemeEntry(string $url, string $as): bool
    {
        // Nur druckbares ASCII ohne Leerzeichen, spitze Klammern und Kommas:
        // Alles andere wuerde den Link-Header brechen (CR/LF: Header-Injection).
        if (preg_match('/[^\x21-\x7E]|[<>,]/', $url) === 1) {
            return false;
        }

        // Relative Pfade oder http(s) - kein javascript:, data: usw.
        if (!str_starts_with($url, '/') && preg_match('#^https?://#i', $url) !== 1) {
            return false;
        }

        $path = parse_url($url, \PHP_URL_PATH);

        return \is_string($path) && preg_match(self::ENTRY_PATTERNS[$as], $path) === 1;
    }
}
