#!/usr/bin/env bash
#
# pool-vhost-boot.sh - Kapitel-9-Pool, 99-shopware.ini und der vHost aus
# Anhang C zusammen gebootet, mit echten Antworten geprueft (MEM-289).
#
# Laeuft als root in ubuntu:24.04 (CI-Job php-fpm-pool):
#   docker run --rm -v "$PWD:/code:ro" ubuntu:24.04 bash /code/tests/Integration/pool-vhost-boot.sh
#
# Warum ein eigenes Skript: Die BATS-Tests pruefen Text, der Job
# php-fpm-pool den Pool allein. Ob Pool und vHost zusammenpassen - Socket,
# Upload-Grenze, Status-Listener, http2 auf nginx 1.24 - zeigt erst ein
# Request durch beide. Und der Vorrang zweier [shopware]-Dateien (MEM-292)
# stand bisher nur im Kommentar.
#
# Exit 0 = alle Zusicherungen gehalten, 1 = mindestens eine gebrochen.

set -euo pipefail

CODE="${CODE:-/code}"
POOL_SRC="$CODE/chapters/09-php-performance/config/shopware-fpm.conf"
INI_SRC="$CODE/chapters/09-php-performance/config/99-shopware.ini"
OPC_SRC="$CODE/chapters/09-php-performance/config/99-shopware-opcache.ini"
VHOST_SRC="$CODE/chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
VHOST=/etc/nginx/sites-available/shopware.conf
POOL_DIR=/etc/php/8.3/fpm/pool.d
DOCROOT=/var/www/shopware/public

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }

stop_fpm() {
    local pid
    pid="$(ps -eo pid,args | awk '$2 == "php-fpm:" && $3 == "master" {print $1}')"
    [ -z "$pid" ] || kill "$pid"
    sleep 1
}

if ! command -v nginx > /dev/null || ! command -v cgi-fcgi > /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null
    apt-get install -y -qq php8.3-fpm php8.3-opcache libfcgi-bin nginx curl openssl procps > /dev/null
fi

# --- Einspielen wie im README von Kapitel 9 --------------------------------
cp "$INI_SRC" /etc/php/8.3/fpm/conf.d/
cp "$OPC_SRC" /etc/php/8.3/fpm/conf.d/
chmod 644 /etc/php/8.3/fpm/conf.d/99-shopware*.ini
cp "$POOL_SRC" "$POOL_DIR/shopware.conf"
[ -e "$POOL_DIR/www.conf" ] && mv "$POOL_DIR/www.conf" "$POOL_DIR/www.conf.disabled"
mkdir -p /var/log/php-fpm /run/php && chown www-data:www-data /var/log/php-fpm

cp "$VHOST_SRC" "$VHOST"
# Genau der Befehl aus dem vHost-Kopf fuer nginx < 1.25.1. Steht er dort
# nicht mehr wortgleich, prueft dieses Gate etwas anderes als das Buch.
SED_E1='/^[[:space:]]*http2 on;/d'
SED_E2='s/^\([[:space:]]*listen .*443 ssl\);/\1 http2;/'
grep -qF -- "-e '$SED_E1'" "$VHOST_SRC" || fail "vHost-Kopf nennt den http2-sed nicht mehr (Teil 1)"
grep -qF -- "-e '$SED_E2'" "$VHOST_SRC" || fail "vHost-Kopf nennt den http2-sed nicht mehr (Teil 2)"
sed -i -e "$SED_E1" -e "$SED_E2" "$VHOST"
[ "$(grep -cE '^[[:space:]]*listen .*443 ssl http2;' "$VHOST")" -eq 2 ] || fail "http2 nicht an beiden listen-Zeilen"

# Docker schaltet IPv6 in Containern oft ab; dann startet nginx mit [::] nicht.
V6=1
if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" = "1" ]; then
    V6=0
    sed -i '/^[[:space:]]*listen \[::\]/d' "$VHOST"
    echo "hinweis: IPv6 im Container aus - [::]-Listen entfernt, v6-Probe uebersprungen"
fi

rm -f /etc/nginx/sites-enabled/default
ln -sf "$VHOST" /etc/nginx/sites-enabled/
mkdir -p /etc/letsencrypt/live/shop.example.com "$DOCROOT/theme" /var/www/html/.well-known/acme-challenge
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=shop.example.com \
    -keyout /etc/letsencrypt/live/shop.example.com/privkey.pem \
    -out /etc/letsencrypt/live/shop.example.com/fullchain.pem 2> /dev/null
cat > "$DOCROOT/index.php" <<'PHP'
<?php
foreach (['memory_limit', 'upload_max_filesize', 'post_max_size', 'max_execution_time'] as $k) {
    echo $k, '=', ini_get($k), "\n";
}
echo 'TMPDIR=', getenv('TMPDIR'), "\n", 'ROUTE=', $_SERVER['REQUEST_URI'], "\n";
PHP
echo 'body{}' > "$DOCROOT/theme/all.css"

# Der Pruefbefehl aus Kopf, README und Buch muss leer bleiben.
CHECK="$(nginx -t 2>&1 | grep -E 'emerg|conflicting server name' || true)"
[ -z "$CHECK" ] || fail "nginx -t: $CHECK"
ok "nginx -t sauber, Pruefbefehl leer"

php-fpm8.3 -D
nginx
sleep 1

R=(-sk --resolve shop.example.com:443:127.0.0.1)
U=https://shop.example.com

# --- Pool + conf.d + vHost -------------------------------------------------
OUT="$(curl "${R[@]}" "$U/some/route")"
for want in memory_limit=512M upload_max_filesize=128M post_max_size=128M \
            max_execution_time=300 TMPDIR=/tmp ROUTE=/some/route; do
    grep -qx "$want" <<< "$OUT" || fail "Request meldet nicht $want: $(tr '\n' ' ' <<< "$OUT")"
done
ok "Werte aus Pool und 99-shopware.ini kommen ueber nginx an, Routing ueber index.php"

[ "$(curl "${R[@]}" -o /dev/null -w '%{http_version}' "$U/")" = "2" ] || fail "IPv4 nicht HTTP/2"
if [ "$V6" = "1" ]; then
    [ "$(curl -skg -o /dev/null -w '%{http_version}' --resolve 'shop.example.com:443:[::1]' "$U/")" = "2" ] \
        || fail "IPv6 nicht HTTP/2 - http2 fehlt an listen [::]:443"
    ok "HTTP/2 ueber IPv4 und IPv6"
else
    ok "HTTP/2 ueber IPv4"
fi

head -c $((2 * 1024 * 1024)) /dev/zero > /tmp/up2
head -c $((130 * 1024 * 1024)) /dev/zero > /tmp/up130
[ "$(curl "${R[@]}" -o /dev/null -w '%{http_code}' -F f=@/tmp/up2 "$U/up")" = "200" ] || fail "2-MB-Upload nicht 200"
[ "$(curl "${R[@]}" -o /dev/null -w '%{http_code}' -F f=@/tmp/up130 "$U/up")" = "413" ] || fail "130-MB-Upload nicht 413"
ok "Upload 2 MB 200, 130 MB 413 (client_max_body_size 128M)"

grep -q '^pool: *shopware' <<< "$(curl -s http://127.0.0.1:8081/fpm-status)" || fail "8081/fpm-status antwortet nicht aus dem Pool"
[ "$(curl -s http://127.0.0.1:8081/fpm-ping)" = "pong" ] || fail "8081/fpm-ping nicht pong"
grep -qx 'ROUTE=/fpm-status' <<< "$(curl "${R[@]}" "$U/fpm-status")" || fail "/fpm-status auf 443 landet nicht in der Anwendung"
ok "Status nur auf 127.0.0.1:8081, auf 443 in der Anwendung"

[ "$(curl "${R[@]}" -D - -o /dev/null "$U/theme/all.css" | grep -ci '^cache-control:')" = "1" ] || fail "nicht genau ein Cache-Control"
ok "ein Cache-Control-Header auf /theme/"

# --- Vorrang zweier [shopware]-Dateien (MEM-292) ---------------------------
# Einzelwerte aus der alphabetisch letzten Datei, Listen aus der ersten.
# Werte, die beide Seiten setzen, verschieden und gueltig (Regeln 31, 35):
# pm.max_children muss ueber pm.max_spare_servers (20) liegen, sonst lehnt
# FPM die Konfiguration ab.
stop_fpm
rm -f "$POOL_DIR/shopware.conf"
sed -e 's/^pm.max_children = .*/pm.max_children = 70/' \
    -e 's/^php_value\[memory_limit\] = .*/php_value[memory_limit] = 111M/' "$POOL_SRC" > "$POOL_DIR/aa.conf"
sed -e 's/^pm.max_children = .*/pm.max_children = 90/' \
    -e 's/^php_value\[memory_limit\] = .*/php_value[memory_limit] = 222M/' "$POOL_SRC" > "$POOL_DIR/zz.conf"
# || true: Scheitert -tt (Exit 78), soll die Meldung unten kommen, nicht ein
# stiller Abbruch durch set -e in der Substitution.
MC="$(php-fpm8.3 -tt 2>&1 | sed -n 's/.*pm\.max_children = \([0-9]*\).*/\1/p' | tail -1 || true)"
[ "$MC" = "90" ] || fail "pm.max_children=$MC statt 90 (letzte Datei) - Vorrang im Pool-Kopf nachziehen"
php-fpm8.3 -D
sleep 1
grep -qx 'memory_limit=111M' <<< "$(curl "${R[@]}" "$U/")" || fail "memory_limit nicht 111M (erste Datei) - Vorrang im Pool-Kopf nachziehen"
ok "Vorrang: pm.max_children aus der letzten Datei (90), php_value aus der ersten (111M)"
stop_fpm
rm -f "$POOL_DIR/aa.conf" "$POOL_DIR/zz.conf"
cp "$POOL_SRC" "$POOL_DIR/shopware.conf"

echo "Alle Zusicherungen gehalten."
