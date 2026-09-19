#!/usr/bin/env bats

# BATS tests for the chapter 11 CDN scripts

DIR="./chapters/11-cdn-integration/scripts"

setup() {
    TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP"
}

@test "all cdn scripts show help with --help" {
    for script in cdn-test.sh cdn-warmup.sh cloudflare-purge.sh bunny-purge.sh; do
        run bash "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "all cdn scripts exit 2 without arguments" {
    # 2 = Aufruffehler, damit cdn-test.sh mit 1 melden kann, dass es Probleme
    # gefunden hat.
    for script in cdn-test.sh cdn-warmup.sh cloudflare-purge.sh bunny-purge.sh; do
        run bash "$DIR/$script"
        [ "$status" -eq 2 ]
    done
}

@test "purge scripts exit 2 with a message when a value option has no argument" {
    # Unter `set -u` bricht ein blosses "$2" mit einer Bash-Fehlermeldung und
    # Exit 1 ab, bevor die eigene Meldung erscheint - "${2:-}" ist Pflicht.
    # cloudflare-purge.sh nimmt Listen (--urls), bunny-purge.sh eine URL (--url).
    run bash "$DIR/cloudflare-purge.sh" --urls
    [ "$status" -eq 2 ]
    [[ "$output" == *"URLs erforderlich"* ]]

    run bash "$DIR/bunny-purge.sh" --url
    [ "$status" -eq 2 ]
    [[ "$output" == *"URL erforderlich"* ]]
    [[ "$output" != *"not set"* ]]
    [[ "$output" != *"nicht gesetzt"* ]]
}

@test "bunny-purge.sh documents every implemented option in its help" {
    run bash "$DIR/bunny-purge.sh" --help
    [ "$status" -eq 0 ]
    for opt in --all --url --test --stats; do
        [[ "$output" == *"$opt"* ]]
    done
}

@test "cdn-warmup.sh rejects an unknown mode" {
    run bash "$DIR/cdn-warmup.sh" https://shop.example.com --nonsense
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unbekannter Modus"* ]]
}

@test "cdn-test.sh resolves absolute, root-relative and relative urls" {
    # shellcheck disable=SC1090
    source "$DIR/cdn-test.sh"
    SHOP_URL="https://shop.example.com"

    run absolute_url "https://cdn.example.com/a.css"
    [ "$output" = "https://cdn.example.com/a.css" ]

    run absolute_url "/theme/abc/css/all.css"
    [ "$output" = "https://shop.example.com/theme/abc/css/all.css" ]

    run absolute_url "assets/font/Inter.woff2" "https://shop.example.com/theme/abc/css/all.css"
    [ "$output" = "https://shop.example.com/theme/abc/css/assets/font/Inter.woff2" ]
}

@test "cdn-test.sh resolves the ../ font paths shopware writes into theme css" {
    # Shopware schreibt in all.css Pfade wie
    # ../../<theme-hash>/assets/font/Inter-Regular-Roman.woff2 — relativ zur
    # CSS-Datei. Wer sie an die Shop-URL haengt, testet eine Adresse, die es
    # nicht gibt, und meldet faelschlich fehlendes CORS.
    # shellcheck disable=SC1090
    source "$DIR/cdn-test.sh"
    SHOP_URL="https://shop.example.com"

    run absolute_url "../../0198/assets/font/Inter-Regular-Roman.woff2" \
        "https://shop.example.com/theme/c762/css/all.css?1753443582"
    [ "$output" = "https://shop.example.com/theme/0198/assets/font/Inter-Regular-Roman.woff2" ]
}

@test "cdn-test.sh keeps the query string when resolving urls" {
    # shellcheck disable=SC1090
    source "$DIR/cdn-test.sh"
    SHOP_URL="https://shop.example.com"

    run absolute_url "/theme/abc/css/all.css?1753443582"
    [ "$output" = "https://shop.example.com/theme/abc/css/all.css?1753443582" ]
}

@test "cdn-test.sh counters survive a failing check under set -e" {
    # Das alte Skript nutzte ((PASS++)); bei PASS=0 liefert das Exit 1 und
    # beendet ein Skript mit set -e.
    # shellcheck disable=SC1090
    source "$DIR/cdn-test.sh"
    PASS=0
    WARN=0
    FAIL=0

    check_pass "erster Treffer" >/dev/null
    check_warn "eine Warnung" >/dev/null
    check_fail "ein Fehler" >/dev/null

    [ "$PASS" -eq 1 ]
    [ "$WARN" -eq 1 ]
    [ "$FAIL" -eq 1 ]
}

@test "cdn-test.sh header_value returns empty instead of failing for a missing header" {
    # shellcheck disable=SC1090
    source "$DIR/cdn-test.sh"

    headers=$'HTTP/1.1 200 OK\r\nCache-Control: public, s-maxage=7200\r\n'

    run header_value "$headers" "cache-control"
    [ "$status" -eq 0 ]
    [ "$output" = "public, s-maxage=7200" ]

    run header_value "$headers" "cf-cache-status"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "cdn-warmup.sh extracts loc entries from a sitemap" {
    # shellcheck disable=SC1090
    source "$DIR/cdn-warmup.sh"

    cat > "$TMP/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://shop.example.com/</loc></url>
  <url><loc>https://shop.example.com/Clothing/</loc></url>
</urlset>
XML

    run bash -c "source '$DIR/cdn-warmup.sh'; extract_locs < '$TMP/sitemap.xml'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"https://shop.example.com/"* ]]
    [[ "$output" == *"https://shop.example.com/Clothing/"* ]]
    [[ "$output" != *"<loc>"* ]]
}

@test "cloudflare-purge.sh rejects wildcards in url purge" {
    CLOUDFLARE_API_TOKEN=dummy CLOUDFLARE_ZONE_ID=dummy \
        run bash "$DIR/cloudflare-purge.sh" --urls 'https://shop.example.com/media/*'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Wildcards"* ]]
}

@test "cloudflare-purge.sh rejects urls without scheme" {
    CLOUDFLARE_API_TOKEN=dummy CLOUDFLARE_ZONE_ID=dummy \
        run bash "$DIR/cloudflare-purge.sh" --urls 'shop.example.com/media/a.jpg'
    [ "$status" -eq 1 ]
    [[ "$output" == *"vollqualifiziert"* ]]
}
