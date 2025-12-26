# Varnish VCL für Shopware 6
# Kapitel 6: HTTP-Caching
#
# Installation:
#   1. Kopieren nach /etc/varnish/default.vcl
#   2. Varnish neu starten: systemctl restart varnish
#   3. Shopware für Reverse Proxy konfigurieren (shopware.yaml)
#
# Empfohlen ab: >100.000 Seitenaufrufe/Tag
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

vcl 4.1;

import std;

# ============================================================
# Backend Definition
# ============================================================
backend default {
    .host = "127.0.0.1";
    .port = "8080";                    # Nginx/Apache Port
    .first_byte_timeout = 60s;
    .connect_timeout = 5s;
    .between_bytes_timeout = 60s;

    # Health Check (optional aber empfohlen)
    .probe = {
        .url = "/admin/health";
        .timeout = 2s;
        .interval = 5s;
        .window = 5;
        .threshold = 3;
    }
}

# ============================================================
# ACL für Cache Purge/Ban
# ============================================================
acl purge {
    "localhost";
    "127.0.0.1";
    # "10.0.0.0"/8;                   # Internes Netzwerk
}

# ============================================================
# vcl_recv - Request verarbeiten
# ============================================================
sub vcl_recv {
    # BAN-Request von Shopware
    if (req.method == "BAN") {
        if (!client.ip ~ purge) {
            return (synth(403, "Not allowed"));
        }

        # URL-basiertes Ban
        if (req.http.X-Shopware-Invalidates) {
            ban("obj.http.X-Shopware-Cache-Id ~ " + req.http.X-Shopware-Invalidates);
            return (synth(200, "Banned"));
        }

        # Fallback: Alles bannen
        ban("req.url ~ .");
        return (synth(200, "Banned all"));
    }

    # PURGE-Request
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
            return (synth(403, "Not allowed"));
        }
        return (purge);
    }

    # Nur GET und HEAD cachen
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # --------------------------------------------------------
    # Statische Assets IMMER cachen
    # --------------------------------------------------------
    if (req.url ~ "\.(css|js|jpg|jpeg|png|gif|ico|webp|woff2?|svg|ttf|eot|mp4|webm|pdf)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
    }

    # --------------------------------------------------------
    # Diese Pfade NIE cachen
    # --------------------------------------------------------

    # Admin-Bereich
    if (req.url ~ "^/admin") {
        return (pass);
    }

    # API
    if (req.url ~ "^/api" || req.url ~ "^/store-api") {
        return (pass);
    }

    # Checkout und Account (benutzer-spezifisch)
    if (req.url ~ "^/(checkout|account|widgets/checkout)") {
        return (pass);
    }

    # --------------------------------------------------------
    # Session-Cookie Check
    # --------------------------------------------------------

    # sw-states Cookie = eingeloggter User oder Warenkorb
    if (req.http.Cookie ~ "sw-states=") {
        # Prüfen ob nur leerer Warenkorb
        if (req.http.Cookie ~ "sw-states=cart-filled") {
            return (pass);
        }
        if (req.http.Cookie ~ "sw-states=logged-in") {
            return (pass);
        }
    }

    # --------------------------------------------------------
    # Marketing-Parameter entfernen (Cache-Key normalisieren)
    # --------------------------------------------------------
    if (req.url ~ "\?") {
        set req.url = regsuball(req.url, "([\?&])(utm_[^&]+|gclid|fbclid|msclkid|mc_[ce]id|pk_[^&]+)(&|$)", "\1");
        set req.url = regsuball(req.url, "[\?&]+$", "");
    }

    # Unnötige Cookies entfernen für besseres Caching
    if (req.http.Cookie) {
        # Nur Shopware-relevante Cookies behalten
        set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_ga[^=]*|_gid|_fbp|_gcl_[^=]*)=[^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

        # Leeren Cookie-Header entfernen
        if (req.http.Cookie == "") {
            unset req.http.Cookie;
        }
    }

    return (hash);
}

# ============================================================
# vcl_backend_response - Backend-Antwort verarbeiten
# ============================================================
sub vcl_backend_response {
    # Grace Period: Stale Content für 24h bei Backend-Fehlern
    set beresp.grace = 24h;

    # Keep: Wie lange Objekt im Cache bleiben darf (für Grace)
    set beresp.keep = 48h;

    # --------------------------------------------------------
    # Statische Assets
    # --------------------------------------------------------
    if (bereq.url ~ "\.(css|js|jpg|jpeg|png|gif|ico|webp|woff2?|svg|ttf|eot|mp4|webm|pdf)(\?.*)?$") {
        set beresp.ttl = 7d;
        unset beresp.http.Set-Cookie;
        set beresp.http.Cache-Control = "public, max-age=604800";
        return (deliver);
    }

    # --------------------------------------------------------
    # HTML-Seiten
    # --------------------------------------------------------
    if (beresp.http.Content-Type ~ "text/html") {
        # Set-Cookie = nicht cachen
        if (beresp.http.Set-Cookie) {
            set beresp.uncacheable = true;
            return (deliver);
        }

        # Kein Cache-Control Header = Standard TTL
        if (!beresp.http.Cache-Control) {
            set beresp.ttl = 2h;
            set beresp.http.Cache-Control = "public, max-age=7200, stale-while-revalidate=14400";
        }

        # Stale-While-Revalidate hinzufügen wenn nicht vorhanden
        if (beresp.http.Cache-Control !~ "stale-while-revalidate") {
            set beresp.http.Cache-Control = beresp.http.Cache-Control + ", stale-while-revalidate=14400";
        }
    }

    # --------------------------------------------------------
    # Fehler nicht cachen
    # --------------------------------------------------------
    if (beresp.status >= 400) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }

    return (deliver);
}

# ============================================================
# vcl_deliver - Response an Client
# ============================================================
sub vcl_deliver {
    # Debug-Header (in Production entfernen oder einschränken)
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Age-Header zeigt wie lange im Cache
    # (wird automatisch von Varnish gesetzt)

    # Backend-Server verstecken
    unset resp.http.X-Powered-By;
    unset resp.http.Server;

    # Für Production: Debug-Header entfernen
    # unset resp.http.X-Cache;
    # unset resp.http.X-Cache-Hits;
    # unset resp.http.X-Shopware-Cache-Id;

    return (deliver);
}

# ============================================================
# vcl_hit - Cache Hit
# ============================================================
sub vcl_hit {
    # Grace Mode: Stale Content ausliefern wenn Backend langsam
    if (obj.ttl >= 0s) {
        return (deliver);
    }

    # Objekt ist stale aber noch in Grace Period
    if (obj.ttl + obj.grace > 0s) {
        return (deliver);
    }

    return (miss);
}

# ============================================================
# vcl_hash - Cache Key generieren
# ============================================================
sub vcl_hash {
    hash_data(req.url);

    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }

    # Shopware Cache-Hash Cookie (für Preis-Gruppen etc.)
    if (req.http.Cookie ~ "sw-cache-hash=") {
        hash_data(regsub(req.http.Cookie, ".*sw-cache-hash=([^;]+).*", "\1"));
    }

    return (lookup);
}
