# Varnish VCL für Shopware 6.6 / 6.7 mit xkey-Invalidierung
# Kapitel 6: HTTP-Caching — Shop-Performance in 30 Tagen
#
# Voraussetzungen:
#   - Varnish 7.x oder 8.x mit den vmods "xkey" (varnish-modules) und
#     "cookie" (Teil von Varnish Cache), beide im Image ghcr.io/shopware/varnish
#   - Shopware-Konfiguration: config/varnish.yaml aus diesem Ordner
#
# Installation:
#   1. Backend (.host/.port) und ACL "purgers" an deine Umgebung anpassen
#   2. Syntax prüfen:   varnishd -C -f /etc/varnish/default.vcl > /dev/null
#   3. Laden:           systemctl reload varnish
#
# Für den Produktivbetrieb empfehlen wir das offizielle Image
# https://github.com/shopware/varnish-shopware — diese Datei ist eine
# kommentierte, gekürzte Lern-Version mit demselben Grundverhalten.
#
# Getestet mit ghcr.io/shopware/varnish:6.7 (Varnish 8.0.2) gegen Shopware 6.6.10.6:
# HIT/MISS, xkey-PURGE nach Preisänderung, BAN bei cache:clear:http,
# Währungs-Cookie, Pass bei Login/Warenkorb, ESI, Tracking-Parameter.
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

vcl 4.1;

import std;
import xkey;
import cookie;

backend default {
    .host = "127.0.0.1";   # Webserver hinter Varnish (Nginx/Apache)
    .port = "8080";
    .first_byte_timeout = 60s;
}

# Nur diese Adressen dürfen invalidieren (App-Server eintragen!)
acl purgers {
    "127.0.0.1";
    "::1";
}

sub vcl_recv {
    # Interne Hilfs-Header nie vom Client übernehmen (sonst könnte ein Client
    # über eigene X-Sw-*-Header beliebig viele Cache-Varianten erzeugen)
    unset req.http.X-Sw-Cache-Hash;
    unset req.http.X-Sw-Currency;
    unset req.http.X-Sw-States;

    # --------------------------------------------------------
    # Invalidierung durch Shopware
    # --------------------------------------------------------
    # Tag-Invalidierung: Shopware schickt PURGE mit Header "xkey: tag1 tag2 ..."
    # Einzel-URL: PURGE ohne xkey-Header
    if (req.method == "PURGE") {
        if (client.ip !~ purgers) {
            return (synth(403, "Forbidden"));
        }
        if (req.http.xkey) {
            set req.http.n-gone = xkey.purge(req.http.xkey);
            return (synth(200, "Invalidated " + req.http.n-gone + " objects"));
        }
        return (purge);
    }

    # Kompletter Cache (bin/console cache:clear:http bzw. cache:clear): BAN auf "/"
    if (req.method == "BAN") {
        if (client.ip !~ purgers) {
            return (synth(403, "Forbidden"));
        }
        ban("req.url ~ " + req.url);
        return (synth(200, "Banned"));
    }

    # --------------------------------------------------------
    # Was nie aus dem Cache kommt
    # --------------------------------------------------------
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    if (req.http.Authorization) {
        return (pass);
    }

    # Abkürzung ohne Cache-Lookup. Sprachpräfixe (/en/checkout) greifen hier
    # nicht — die fängt Shopware über sw-states / no-cache-Header ab.
    if (req.url ~ "^/(checkout|account|admin|api)(/.*)?$") {
        return (pass);
    }

    # Statische Dateien brauchen keine Cookies -> ein Cache-Eintrag für alle
    if (req.url ~ "^/(media|thumbnail|theme|bundles)/") {
        unset req.http.Cookie;
        return (hash);
    }

    # --------------------------------------------------------
    # Shopware-Cookies für Cache-Key und Bypass auslesen
    # --------------------------------------------------------
    cookie.parse(req.http.Cookie);
    set req.http.X-Sw-Cache-Hash = cookie.get("sw-cache-hash");
    set req.http.X-Sw-Currency = cookie.get("sw-currency");
    set req.http.X-Sw-States = cookie.get("sw-states");

    # Tracking-Parameter entfernen, damit ?utm_source=... keinen eigenen
    # Cache-Eintrag erzeugt. Kurze Liste — die vollständige steht im
    # offiziellen VCL. shopware.http_cache.ignored_url_parameters wirkt hinter
    # Varnish NICHT, eigene Parameter hier ergänzen.
    # (?<=[?&]) prüft nur den Namensanfang, ohne das Zeichen zu verbrauchen:
    # ?foo_gl=1 bleibt stehen, mehrere Parameter hintereinander werden entfernt.
    if (req.url ~ "[?&](utm_[a-z_]+|gclid|gbraid|wbraid|fbclid|msclkid|mc_cid|mc_eid|pk_[a-z_]+|mtm_[a-z_]+|srsltid|_gl)=") {
        set req.url = regsuball(req.url, "(?<=[?&])(utm_[a-z_]+|gclid|gbraid|wbraid|fbclid|msclkid|mc_cid|mc_eid|pk_[a-z_]+|mtm_[a-z_]+|srsltid|_gl)=[^&]*(&|$)", "");
        set req.url = regsub(req.url, "[?&]$", "");
    }
    set req.url = std.querysort(req.url);

    # Shopware rendert render_esi() nur als <esi:include>, wenn der Proxy ESI kann
    set req.http.Surrogate-Capability = "shopware=ESI/1.0";

    return (hash);
}

sub vcl_hash {
    # URL + Host hasht die eingebaute vcl_hash danach automatisch.
    # Kontext wie in Shopwares HttpCacheKeyGenerator:
    # sw-cache-hash (Kundengruppe, Regeln, Währung, Steuern ...) hat Vorrang,
    # sonst sw-currency (Gast hat nur die Währung gewechselt).
    if (req.http.X-Sw-Cache-Hash != "") {
        hash_data("context:" + req.http.X-Sw-Cache-Hash);
    } elseif (req.http.X-Sw-Currency != "") {
        hash_data("currency:" + req.http.X-Sw-Currency);
    }
}

sub vcl_hit {
    # Shopware markiert Seiten mit "sw-invalidation-states: logged-in,cart-filled".
    # Hat der Besucher einen dieser Zustände (Cookie sw-states), am Cache vorbei.
    if (req.http.X-Sw-States) {
        if (req.http.X-Sw-States ~ "logged-in" && obj.http.sw-invalidation-states ~ "logged-in") {
            return (pass);
        }
        if (req.http.X-Sw-States ~ "cart-filled" && obj.http.sw-invalidation-states ~ "cart-filled") {
            return (pass);
        }
    }
}

sub vcl_backend_fetch {
    unset bereq.http.X-Sw-Cache-Hash;
    unset bereq.http.X-Sw-Currency;
    unset bereq.http.X-Sw-States;
}

sub vcl_backend_response {
    # Grace: veraltete Objekte bis 24h ausliefern, während im Hintergrund
    # neu geladen wird oder das Backend ausfällt
    set beresp.grace = 24h;

    # ESI-Fragmente zusammensetzen (vor jedem return)
    if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
        unset beresp.http.Surrogate-Control;
        set beresp.do_esi = true;
    }

    # Cachebare Antworten dürfen kein Session-Cookie an andere Besucher verteilen
    if (beresp.ttl > 0s && (bereq.method == "GET" || bereq.method == "HEAD")) {
        unset beresp.http.Set-Cookie;
    }
}

sub vcl_deliver {
    # Der Browser soll HTML nicht selbst cachen: nach einem Purge in Varnish
    # hätte er sonst noch die alte Seite. Statische Dateien bleiben cachebar.
    if (resp.http.Cache-Control !~ "private" && req.url !~ "^/(theme|media|thumbnail|bundles|store-api)/") {
        set resp.http.Cache-Control = "no-store, no-cache, must-revalidate, max-age=0";
    }

    # Debug-Header für Hit-Rate-Messung (in Produktion ggf. auf interne IPs beschränken)
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Interne Header nicht nach aussen geben
    unset resp.http.sw-invalidation-states;
    unset resp.http.xkey;
    unset resp.http.Via;
    unset resp.http.X-Varnish;
}
