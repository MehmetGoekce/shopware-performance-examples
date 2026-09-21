#!/usr/bin/env bats

# BATS tests for the chapter 2 audit scripts (audit.sh, analyze-images.sh)
#
# audit.sh runs against a fake Shopware root whose bin/console is a stub.
# Fixture formats are copied from Shopware 6.6.10.6 (Dockware). Tests that
# parse JSON need php; the bats/bats image has none, so they skip there
# (the CI job checks that php is present, see .github/workflows/test.yml).

DIR="$PWD/chapters/02-performance-audit/scripts"

setup() {
    TMP="$(mktemp -d)"
    export FIX="$TMP/fix"
    mkdir -p "$FIX" "$TMP/shop/bin" "$TMP/shop/public/media/a"

    cat > "$TMP/shop/bin/console" <<'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Shopware 6.6.10.6 (env: prod, debug: false)" ;;
    plugin:list) cat "$FIX/plugins.json" ;;
    debug:dotenv) cat "$FIX/dotenv.txt" ;;
    debug:container) cat "$FIX/admin.json" ;;
    messenger:stats) cat "$FIX/stats.txt" >&2 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TMP/shop/bin/console"

    cat > "$FIX/plugins.json" <<'EOF'
[{"name":"SwagPlatformDemoData","version":"2.1.0","active":true},{"name":"OldPlugin","version":"1.0.0","active":false}]
EOF
    cat > "$FIX/dotenv.txt" <<'EOF'
  Variable                      Value   .env.local   .env
 ----------------------------- ------- ------------ ------
  SHOPWARE_ES_ENABLED           0       n/a          0
  SHOPWARE_HTTP_CACHE_ENABLED   1       n/a          1
  SHOPWARE_HTTP_DEFAULT_TTL     7200    n/a          7200
EOF
    printf '{\n    "shopware.admin_worker.enable_admin_worker": true\n}\n' > "$FIX/admin.json"
    cat > "$FIX/stats.txt" <<'EOF'
 -------------- -------
  Transport      Count
 -------------- -------
  failed         0
  async          19
  low_priority   0
 -------------- -------
EOF

    # php-fpm stub: -v and -i
    cat > "$TMP/fpm" <<'EOF'
#!/bin/bash
if [ "$1" = "-v" ]; then echo "PHP 8.3.23 (fpm-fcgi)"; exit 0; fi
cat "$FIX/fpm-i.txt"
EOF
    chmod +x "$TMP/fpm"
    cat > "$FIX/fpm-i.txt" <<'EOF'
opcache.enable => On => On
opcache.jit => no value => no value
opcache.jit_buffer_size => 0 => 0
opcache.memory_consumption => 128 => 128
opcache.validate_timestamps => On => On
EOF

    # ps stub: process list from $FIX/ps.txt (one command line per row)
    printf '%s\n' 'COMMAND' '/sbin/init' 'php-fpm: master process (/etc/php/8.3/fpm/php-fpm.conf)' > "$FIX/ps.txt"
    printf '#!/bin/bash\ncat "$FIX/ps.txt"\n' > "$TMP/ps"
    chmod +x "$TMP/ps"

    export PHP_FPM_CMD="$TMP/fpm"
    export PS_CMD="$TMP/ps"
    export REDIS_CLI_CMD="no-such-redis-cli"
    export AUDIT_WAIT=1
}

teardown() {
    rm -rf "$TMP"
}

needs_php() {
    command -v php > /dev/null 2>&1 || skip "php not installed"
}

# --- Aufruf ------------------------------------------------------------------

@test "both scripts show help with --help" {
    for script in audit.sh analyze-images.sh; do
        run "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "both scripts exit 2 on an unknown option" {
    for script in audit.sh analyze-images.sh; do
        run "$DIR/$script" --bogus
        [ "$status" -eq 2 ]
    done
}

@test "audit.sh exits 2 with more than one argument" {
    run "$DIR/audit.sh" a b
    [ "$status" -eq 2 ]
}

@test "audit.sh exits 1 outside a Shopware root" {
    run "$DIR/audit.sh" "$TMP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"kein Shopware-Verzeichnis"* ]]
}

@test "audit.sh runs all seven sections against the stub" {
    run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Shopware 6.6.10.6"* ]]
    for n in 1 2 3 4 5 6 7; do
        [[ "$output" == *"== ${n}."* ]]
    done
    [[ "$output" == *"Fertig."* ]]
}

# --- Plugins -----------------------------------------------------------------

@test "audit.sh counts only active plugins from plugin:list --json" {
    needs_php
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"1 von 2 installierten Plugins aktiv"* ]]
    [[ "$output" == *"SwagPlatformDemoData 2.1.0"* ]]
    [[ "$output" != *"OldPlugin"* ]]
}

# Code-Zeilen ohne Kommentare
code_lines() {
    grep -v -e '^[[:space:]]*#' "$DIR/audit.sh"
}

@test "audit.sh does not call plugin:list --active" {
    code_lines | grep -q -e 'plugin:list --json'
    run bash -c "grep -v -e '^[[:space:]]*#' '$DIR/audit.sh' | grep -c -e '--active'"
    [ "$output" = "0" ]
}

# --- HTTP-Cache --------------------------------------------------------------

@test "audit.sh reads the HTTP cache switch from debug:dotenv" {
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"SHOPWARE_HTTP_CACHE_ENABLED: 1"* ]]
    [[ "$output" == *"SHOPWARE_HTTP_DEFAULT_TTL:   7200"* ]]
    [[ "$output" != *"WARNUNG: HTTP-Cache"* ]]
}

@test "audit.sh warns when the HTTP cache is switched off" {
    sed -i 's/CACHE_ENABLED   1       n\/a          1/CACHE_ENABLED   0       n\/a          0/' "$FIX/dotenv.txt"
    grep -q 'CACHE_ENABLED   0' "$FIX/dotenv.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"WARNUNG: HTTP-Cache ist abgeschaltet."* ]]
}

@test "audit.sh does not claim a default when the variable is only missing from .env" {
    grep -v 'HTTP_CACHE_ENABLED' "$FIX/dotenv.txt" > "$FIX/d" && mv "$FIX/d" "$FIX/dotenv.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"in keiner .env-Datei (Vorgabe 1, sofern die Umgebung nichts setzt)"* ]]
}

@test "audit.sh says so when debug:dotenv fails" {
    rm "$FIX/dotenv.txt"
    sed -i 's|debug:dotenv) cat "$FIX/dotenv.txt" ;;|debug:dotenv) exit 1 ;;|' "$TMP/shop/bin/console"
    grep -q 'debug:dotenv) exit 1' "$TMP/shop/bin/console"
    run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"debug:dotenv nicht verfügbar"* ]]
    [[ "$output" == *"Suche: nicht ermittelbar"* ]]
    [[ "$output" != *"SHOPWARE_ES_ENABLED=0"* ]]
}

@test "audit.sh treats only 0 as off and explains other values" {
    sed -i 's/CACHE_ENABLED   1       n\/a          1/CACHE_ENABLED   false   n\/a          false/' "$FIX/dotenv.txt"
    grep -q 'CACHE_ENABLED   false' "$FIX/dotenv.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"SHOPWARE_HTTP_CACHE_ENABLED: false (wirkt als: an)"* ]]
    [[ "$output" == *"«false» gilt als an"* ]]
    [[ "$output" != *"WARNUNG: HTTP-Cache"* ]]
}

@test "audit.sh finds the variable in a long debug:dotenv output" {
    for i in $(seq 1 3000); do echo "  SOME_VARIABLE_$i   x   n/a   x"; done >> "$FIX/dotenv.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHOPWARE_HTTP_CACHE_ENABLED: 1"* ]]
}

@test "audit.sh does not use debug:config" {
    code_lines | grep -q -e 'debug:dotenv'
    run bash -c "grep -v -e '^[[:space:]]*#' '$DIR/audit.sh' | grep -c -e 'debug:config'"
    [ "$output" = "0" ]
}

# curl-Stub: Age-Werte je Abruf aus $FIX/ages (eine Zeile je Abruf)
age_curl() {
    printf '%s\n' "$@" > "$FIX/ages"
    cat > "$TMP/curl" <<'EOF'
#!/bin/bash
n=$(( $(cat "$FIX/calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FIX/calls"
printf 'HTTP/1.1 200 OK\r\ncache-control: no-cache, private\r\nage: %s\r\n\r\nttfb: 0.010\n' "$(sed -n "${n}p" "$FIX/ages")"
EOF
    chmod +x "$TMP/curl"
}

@test "audit.sh reports a hit when Age grows by at least the pause" {
    age_curl 0 2
    AUDIT_WAIT=2 CURL_CMD="$TMP/curl" SHOP_URL="http://shop.test" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Abruf 2 (Gast, ohne Cookies): TTFB 0.010 s, Age 2"* ]]
    [[ "$output" == *"Treffer: Age ist um mindestens die Pause (2 s) gewachsen."* ]]
}

@test "audit.sh does not count Age 0 as a hit" {
    age_curl 0 0
    CURL_CMD="$TMP/curl" SHOP_URL="http://shop.test" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Kein Treffer erkennbar"* ]]
    [[ "$output" != *"Treffer: Age"* ]]
}

@test "audit.sh does not count Age 0 -> 1 as a hit with a 2 s pause" {
    age_curl 0 1
    AUDIT_WAIT=2 CURL_CMD="$TMP/curl" SHOP_URL="http://shop.test" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Kein Treffer erkennbar"* ]]
}

@test "audit.sh no longer points to cache-debug.sh" {
    run bash -c "grep -v -e '^[[:space:]]*#' '$DIR/audit.sh' | grep -c -e 'cache-debug'"
    [ "$output" = "0" ]
}

@test "audit.sh does not count the Age of two slow misses as a hit" {
    # Symfony setzt beim Speichern Age = Renderdauer: zwei MISS mit je 3 s
    age_curl 3 3
    AUDIT_WAIT=2 CURL_CMD="$TMP/curl" SHOP_URL="http://shop.test" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Kein Treffer erkennbar"* ]]
    [[ "$output" != *"Treffer: Age"* ]]
}

@test "audit.sh exits 2 on an invalid AUDIT_WAIT" {
    AUDIT_WAIT=0 run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 2 ]
    AUDIT_WAIT=x run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 2 ]
}

@test "audit.sh exits 2 on an invalid IMAGE_MIN_KB" {
    IMAGE_MIN_KB=0,5 run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 2 ]
}

@test "audit.sh skips the request test without SHOP_URL" {
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Abruf-Test übersprungen"* ]]
}

# --- OPcache -----------------------------------------------------------------

@test "audit.sh reads OPcache from php-fpm -i, not php -i" {
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"opcache.enable              On"* ]]
    [[ "$output" == *"opcache.memory_consumption  128 MB"* ]]
    [[ "$output" == *"JIT                         aus"* ]]
    run grep -e 'php -i' -e '"${PHP\[@\]}" -i' "$DIR/audit.sh"
    [[ "$output" != *'"${PHP[@]}" -i'* ]]
}

@test "audit.sh treats a JIT mode with jit_buffer_size 0 as off" {
    sed -i 's/^opcache.jit => no value => no value/opcache.jit => tracing => tracing/' "$FIX/fpm-i.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"aus (jit_buffer_size = 0)"* ]]
}

@test "audit.sh reports JIT on with mode and buffer" {
    sed -i 's/^opcache.jit => no value => no value/opcache.jit => tracing => tracing/; s/^opcache.jit_buffer_size => 0 => 0/opcache.jit_buffer_size => 64M => 64M/' "$FIX/fpm-i.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"konfiguriert (tracing)"* ]]
    [[ "$output" != *"JIT                         an"* ]]
}

@test "audit.sh reads JIT off and disable as off" {
    for mode in off disable; do
        sed -i "s/^opcache.jit => .*/opcache.jit => $mode => $mode/; s/^opcache.jit_buffer_size => .*/opcache.jit_buffer_size => 64M => 64M/" "$FIX/fpm-i.txt"
        grep -q "^opcache.jit => $mode" "$FIX/fpm-i.txt"
        run "$DIR/audit.sh" "$TMP/shop"
        [[ "$output" == *"JIT                         aus"* ]]
    done
}

@test "audit.sh warns when OPcache is not loaded at all" {
    printf 'opcache.jit => no value => no value\n' > "$FIX/fpm-i.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"opcache.enable              nicht geladen"* ]]
    [[ "$output" == *"WARNUNG: OPcache ist für FPM nicht aktiv."* ]]
}

@test "audit.sh reports ini files the current user cannot read" {
    [ "$(id -u)" -ne 0 ] || skip "root reads every file"
    mkdir -p "$TMP/conf.d" && echo 'opcache.memory_consumption=333' > "$TMP/conf.d/99-x.ini" && chmod 000 "$TMP/conf.d/99-x.ini"
    echo "Scan this dir for additional .ini files => $TMP/conf.d" >> "$FIX/fpm-i.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"99-x.ini ist für"*"nicht lesbar"* ]]
}

@test "audit.sh marks which FPM version is running" {
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"[installiert, kein Master-Prozess gefunden]"* ]]
    cp "$TMP/fpm" "$TMP/php-fpm8.3"
    PHP_FPM_CMD="$TMP/php-fpm8.3" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"php-fpm8.3: PHP 8.3.23 (fpm-fcgi) [läuft]"* ]]
}

@test "audit.sh does not take opcache.enable_cli for opcache.enable" {
    printf 'opcache.enable_cli => On => On\nopcache.enable => Off => Off\n' > "$FIX/fpm-i.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"opcache.enable              Off"* ]]
    [[ "$output" == *"WARNUNG: OPcache ist für FPM nicht aktiv."* ]]
}

# --- Message Queue -----------------------------------------------------------

@test "audit.sh shows messenger:stats rows written to stderr" {
    sed -i 's/low_priority   0/low_priority   5/' "$FIX/stats.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Nachrichten je Transport"* ]]
    [[ "$output" == *"async          19"* ]]
    [[ "$output" == *"low_priority   5"* ]]
}

@test "audit.sh warns when only the admin worker processes the queue" {
    needs_php
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"messenger:consume-Prozesse:   0"* ]]
    [[ "$output" == *"Admin-Worker (enable_admin_worker):    an"* ]]
    [[ "$output" == *"solange jemand im Admin angemeldet ist"* ]]
}

@test "audit.sh warns when no worker at all runs on this host" {
    needs_php
    printf '{"shopware.admin_worker.enable_admin_worker": false}\n' > "$FIX/admin.json"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"WARNUNG: Kein CLI-Worker auf diesem Host und Admin-Worker aus"* ]]
}

@test "audit.sh counts CLI workers in all command line forms, not itself" {
    needs_php
    cat >> "$FIX/ps.txt" <<'EOF'
php /var/www/html/bin/console messenger:consume async low_priority --time-limit=3600
/usr/bin/php8.3 bin/console -e prod messenger:consume async
php -d memory_limit=512M /srv/shop/bin/console messenger:consume async
bash -c pgrep -fc 'bin/console messenger:consume'
grep bin/console messenger:consume
bash -c ps aux | grep 'php bin/console messenger:consume async'
EOF
    run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"messenger:consume-Prozesse:   3"* ]]
    [[ "$output" == *"davon mit low_priority:                1"* ]]
    [[ "$output" == *"Admin-Worker ist trotzdem an"* ]]
}

@test "audit.sh hints at low_priority when no worker consumes it" {
    echo 'php bin/console messenger:consume async' >> "$FIX/ps.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Kein Worker konsumiert low_priority"* ]]
}

@test "audit.sh accepts scheduler_shopware as a scheduler" {
    needs_php
    printf '{"shopware.admin_worker.enable_admin_worker": false}\n' > "$FIX/admin.json"
    echo 'php bin/console messenger:consume async low_priority' >> "$FIX/ps.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Kein laufender Scheduler gefunden"* ]]
    echo 'php bin/console messenger:consume scheduler_shopware' >> "$FIX/ps.txt"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" != *"Kein laufender Scheduler gefunden"* ]]
    [[ "$output" == *"scheduler_shopware): 1"* ]]
}

# --- Suche -------------------------------------------------------------------

@test "audit.sh points to chapter 18 when Elasticsearch is off" {
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Suche: MySQL (SHOPWARE_ES_ENABLED=0)"* ]]
    [[ "$output" == *"rund 30 000 Produkten"* ]]
}

@test "audit.sh reads the cluster status when Elasticsearch is on" {
    needs_php
    sed -i 's/SHOPWARE_ES_ENABLED           0       n\/a          0/SHOPWARE_ES_ENABLED           yes     n\/a          yes/' "$FIX/dotenv.txt"
    grep -q 'ES_ENABLED           yes' "$FIX/dotenv.txt"
    echo '  OPENSEARCH_URL                http://es.test:9200,http://es2.test:9200   n/a   x' >> "$FIX/dotenv.txt"
    printf '#!/bin/bash\necho %s\n' "'{\"cluster_name\":\"x\",\"status\":\"yellow\"}'" > "$TMP/curl"
    chmod +x "$TMP/curl"
    CURL_CMD="$TMP/curl" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"OpenSearch/Elasticsearch (http://es.test:9200): yellow"* ]]
}

# --- Bilder ------------------------------------------------------------------

@test "audit.sh lists large originals, largest first" {
    head -c 600000 /dev/zero > "$TMP/shop/public/media/a/small-big.jpg"
    head -c 900000 /dev/zero > "$TMP/shop/public/media/a/BIG.PNG"
    head -c 1000 /dev/zero > "$TMP/shop/public/media/a/tiny.jpg"
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Anzahl: 2"* ]]
    first=$(grep -n 'BIG.PNG' <<< "$output" | cut -d: -f1)
    second=$(grep -n 'small-big.jpg' <<< "$output" | cut -d: -f1)
    [ "$first" -lt "$second" ]
    [[ "$output" != *"tiny.jpg"* ]]
}

@test "audit.sh lists only the five largest originals" {
    for i in 1 2 3 4 5 6; do head -c $(( 600000 + i * 1000 )) /dev/zero > "$TMP/shop/public/media/a/img$i.jpg"; done
    run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Anzahl: 6"* ]]
    [ "$(grep -c '^  [0-9]* public/media' <<< "$output")" -eq 5 ]
    [[ "$output" != *"img1.jpg"* ]]
}

@test "audit.sh reports a Redis that answers" {
    printf '#!/bin/bash\necho PONG\n' > "$TMP/redis-cli" && chmod +x "$TMP/redis-cli"
    REDIS_CLI_CMD="$TMP/redis-cli" run "$DIR/audit.sh" "$TMP/shop"
    [[ "$output" == *"Redis: antwortet"* ]]
}

@test "audit.sh says so when public/media is missing" {
    rm -rf "$TMP/shop/public"
    run "$DIR/audit.sh" "$TMP/shop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"public/media nicht gefunden"* ]]
}

@test "analyze-images.sh counts formats case-insensitively" {
    touch "$TMP/a.JPG" "$TMP/b.jpeg" "$TMP/c.png" "$TMP/d.webp" "$TMP/e.AVIF"
    run "$DIR/analyze-images.sh" "$TMP" 500
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bilder gesamt: 5"* ]]
    [[ "$output" == *"JPEG: 2"* ]]
    [[ "$output" == *"AVIF: 1"* ]]
    [[ "$output" != *"Keine WebP/AVIF"* ]]
}

@test "analyze-images.sh lists at most 20 files, largest first" {
    for i in $(seq 1 25); do head -c $(( 600000 + i * 1000 )) /dev/zero > "$TMP/img$i.jpg"; done
    run "$DIR/analyze-images.sh" "$TMP" 500
    [ "$status" -eq 0 ]
    [[ "$output" == *"JPEG/PNG/GIF über 500 KB: 25 (100 % davon)"* ]]
    [ "$(grep -c '^  [0-9]* ' <<< "$output")" -eq 20 ]
    [[ "$(grep -m1 '^  [0-9]* ' <<< "$output")" == *"img25.jpg"* ]]
}

@test "analyze-images.sh explains missing WebP without claiming core support" {
    touch "$TMP/a.jpg"
    run "$DIR/analyze-images.sh" "$TMP"
    [[ "$output" == *"WebP entsteht aus WebP-Originalen"* ]]
    [[ "$output" != *"automatische WebP"* ]]
}

@test "analyze-images.sh handles an empty directory" {
    run "$DIR/analyze-images.sh" "$TMP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Keine Bilder gefunden"* ]]
}

@test "analyze-images.sh exits 1 on a missing directory" {
    run "$DIR/analyze-images.sh" "$TMP/nope"
    [ "$status" -eq 1 ]
}

@test "analyze-images.sh exits 2 on a non-numeric threshold" {
    run "$DIR/analyze-images.sh" "$TMP" abc
    [ "$status" -eq 2 ]
}
