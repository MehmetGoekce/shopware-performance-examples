# Kapitel 21: Third-Party Scripts & Tag Management

Code-Beispiele für Woche 5 der 30-Tage-Roadmap. Getestet gegen Shopware 6.6.10.6 (Dockware, prod) mit Chromium; Blocknamen, Event und Twig-Variablen am Quelltext von 6.7.2.2 geprüft, Consent Mode zusätzlich live auf 6.7.2.2 (verhält sich dort anders, siehe unten).

## Dateien

Ein Plugin, `ThirdPartyScripts/`:

| Datei | Beschreibung |
|-------|--------------|
| `src/Framework/Cookie/GtmCookieProvider.php` | Eintrag «Google Tag Manager» im Shopware-Cookie-Banner (Gruppe «Statistik», Cookie `gtm-enabled`) |
| `src/Resources/views/storefront/layout/meta.html.twig` | GTM erst nach Einwilligung laden, bei Wiederkehrern erst bei der ersten Interaktion; optional im Web Worker (Partytown) |
| `src/Resources/views/storefront/component/analytics.html.twig` | Shopwares Google Analytics an einen eigenen Tagging-Server schicken (`server_container_url`) |
| `src/Resources/views/storefront/base.html.twig` | Fremdes Widget nur auf Produktseiten laden (`activeRoute`) |
| `src/Resources/config/config.xml` | Container-ID, Verzögerung, Partytown an/aus, URL des Tagging-Servers |
| `src/Resources/public/partytown/` | Partytown 0.14.4 (`@qwik.dev/partytown`, MIT), nur `lib/` ohne `debug/` |

## Installation

```bash
cp -r ThirdPartyScripts <shopware>/custom/plugins/
cd <shopware>
bin/console plugin:refresh
bin/console plugin:install --activate ThirdPartyScripts
bin/console system:config:set ThirdPartyScripts.config.gtmId GTM-XXXXXXX
bin/console assets:install     # nur für Partytown
bin/console cache:clear
```

Die Einstellungen stehen auch in der Administration unter Erweiterungen → Meine Erweiterungen → Third-Party Scripts → Konfigurieren.

## Wie der Loader entscheidet

Die Seite ist für alle Besucher gleich und darf im HTTP-Cache liegen. Entschieden wird im Browser:

| Fall | Was passiert (gemessen) |
|------|-------------------------|
| Erstbesuch, keine Entscheidung im Banner | nichts wird geladen |
| «Alle akzeptieren» | `gtm.js` nach 193 ms, Shopwares `gtag.js` parallel |
| «Nur technisch notwendige» | nichts wird geladen |
| Wiederkehrer mit `gtm-enabled=1`, ohne Interaktion | `gtm.js` nach 5065 ms (Vorgabe `gtmDelay` 5000) |
| Wiederkehrer, Scroll nach 1 s | `gtm.js` nach 1247 ms |

Chromium, Startseite, fremde Hosts gestubbt, je ein Lauf.

Consent Mode: Shopware setzt vor den Tracking-Skripten `gtag('consent', 'default', …)` mit `analytics_storage` und `ad_storage` aus den eigenen Cookies `google-analytics-enabled` und `google-ads-enabled`, nach der Zustimmung `gtag('consent', 'update', …)`. Die Einwilligung für GTM selbst (`gtm-enabled`) setzt keinen dieser Werte. Vollständig ist das nur mit **aktiver** Google-Analytics-Anbindung am Verkaufskanal:

| Shopware | GA-Anbindung aus (gemessen nach «Alle akzeptieren») |
|----------|------------------------------------------------------|
| 6.6.10.6 | Vorgabe `denied`, kein `update`; die Einträge `google-analytics-enabled`/`google-ads-enabled` fehlen im Banner (`CookieController`). Google-Tags im Container bleiben `denied` |
| 6.7.2.2 | gar keine Vorgabe (`component_head_analytics_gtag_consent` nur bei aktiver Anbindung). Google-Tags im Container laufen ohne Consent-Signale |

Wer Consent Mode für Tags im Container braucht, lässt die GA-Anbindung aktiv und entfernt ein GA4-Tag aus dem Container (sonst zählt GA4 doppelt).

Widerruf: Shopware löscht `gtm-enabled`. Ein schon geladener Container läuft bis zum nächsten Seitenaufruf weiter, Cookies der Tags bleiben liegen.

Ab 6.7 lädt Shopwares GA-Anbindung selbst `gtm.js`, wenn die Tracking-ID mit `GTM-` beginnt (hinter `google-analytics-enabled`). Das Plugin brauchen Sie dann nur für die Verzögerung bei Wiederkehrern, Partytown oder einen eigenen Banner-Eintrag.

## Partytown

`usePartytown` führt `gtm.js` in einem Web Worker aus. Eine Falle, gemessen: `partytown.lib` muss ein Pfad sein, der mit `/` beginnt. Shopwares `asset()` liefert eine absolute URL; damit startet Partytown nicht, ohne jede Meldung in der Konsole (im Netzwerk-Tab fehlt `partytown-sw.js`). `debug: false` ist die Vorgabe (`lib/debug/` nur mit `debug: true`), der Loader setzt es nur ausdrücklich.

Die Dateien müssen von derselben Domain kommen wie die Seite (Service Worker). Liegen die Bundles auf einem CDN (`shopware.filesystem.asset`), funktioniert das nicht.

`gtm.js` und `gtag/js` senden CORS-Header, `connect.facebook.net/…/fbevents.js` nicht: Der Facebook-Pixel braucht in Partytown einen Reverse-Proxy (`resolveUrl`).

## Tests

- `tests/Unit/GtmCookieProviderTest.php` – Eintrag in der Statistik-Gruppe, eigene Gruppe als Rückfall, Schlüssel anderer Decorators bleiben.
- Im Dockware-Shop (6.6.10.6): Banner-Eintrag, alle Fälle der Tabelle oben, Partytown (Worker lädt `gtm.js`, sieht `consent:default` im `dataLayer`), `server_container_url` im `gtag('config')`-Aufruf, Widget nur auf `frontend.detail.page`.

## Weiter in anderen Kapiteln

- Drittanbieter je Host auflisten, Coverage: Kapitel 5 (`chapters/05-css-javascript/scripts/third-party-audit.js`)
- Skripte ohne Einwilligungspflicht erst bei Interaktion laden: Kapitel 3 (`chapters/03-core-web-vitals/src/Resources/views/storefront/base.html.twig`)
- Budget für Drittanbieter in der CI (`resource-summary:third-party:count`): Kapitel 13 (`chapters/13-continuous-testing/config/lighthouserc.cjs`)

## Quellen

- [Shopware: Add cookie to manager](https://developer.shopware.com/docs/guides/plugins/plugins/storefront/add-cookie-to-manager.html)
- [Partytown](https://partytown.qwik.dev/) – [Proxying Requests](https://partytown.qwik.dev/proxying-requests), [Google Tag Manager](https://partytown.qwik.dev/google-tag-manager)
- [Google: Send data to server-side Tag Manager](https://developers.google.com/tag-platform/tag-manager/server-side/send-data)
