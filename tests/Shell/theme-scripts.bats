#!/usr/bin/env bats
#
# Kapitel 16: analyze-bundle.sh und extract-critical-css.sh
#
# Fixtures bilden public/theme/<prefix>/ nach, wie theme:compile es anlegt.
# curl, npx und node sind per Env-Variable ersetzbar (CURL, NPX, NODE).

setup() {
    SCRIPTS="$BATS_TEST_DIRNAME/../../chapters/16-shopware-themes/scripts"
    ROOT="$BATS_TEST_TMPDIR/shop"
    PREFIX="c7629e6bf9db1d9c6b66f6f545d51be2"
    THEME="$ROOT/public/theme/$PREFIX"
    mkdir -p "$THEME/css" "$THEME/js/storefront" "$THEME/js/performance-theme"
    head -c 4000 /dev/zero | tr '\0' 'c' > "$THEME/css/all.css"
    head -c 5000 /dev/zero | tr '\0' 's' > "$THEME/js/storefront/storefront.js"
    head -c 300 /dev/zero | tr '\0' 'p' > "$THEME/js/performance-theme/performance-theme.js"
    head -c 2000 /dev/zero | tr '\0' 'h' > "$THEME/js/storefront/storefront.hammer.50cbec.js"
    head -c 700 /dev/zero | tr '\0' 'a' > "$THEME/js/performance-theme/performance-theme.async-slider.plugin.6cd542.js"
    export SHOPWARE_ROOT="$ROOT"
}

# ---------------------------------------------------------------------------
# analyze-bundle.sh
# ---------------------------------------------------------------------------

@test "analyze-bundle: --help zeigt Usage" {
    run bash "$SCRIPTS/analyze-bundle.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "analyze-bundle: unbekannte Option ergibt Exit 2" {
    run bash "$SCRIPTS/analyze-bundle.sh" --foo
    [ "$status" -eq 2 ]
}

@test "analyze-bundle: Budget muss ganze Zahl sein" {
    run bash "$SCRIPTS/analyze-bundle.sh" --budget-js abc
    [ "$status" -eq 2 ]
    [[ "$output" == *"ganze Zahl"* ]]
}

@test "analyze-bundle: ohne kompiliertes Theme Exit 2" {
    SHOPWARE_ROOT="$BATS_TEST_TMPDIR/leer" run bash "$SCRIPTS/analyze-bundle.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"theme:compile"* ]]
}

@test "analyze-bundle: trennt Einstieg und Chunks, sucht nicht in bundles/" {
    run bash "$SCRIPTS/analyze-bundle.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"public/theme/$PREFIX"* ]]
    [[ "$output" == *"js/storefront/storefront.js"* ]]
    [[ "$output" == *"js/performance-theme/performance-theme.js"* ]]
    # Chunks erscheinen nur als Summe, nicht als Einstieg
    [[ "$output" != *"storefront.hammer.50cbec.js"* ]]
    [[ "$output" == *"2 Dateien"* ]]
    # 5000 + 300 Byte Einstieg
    [[ "$output" == *"Jede Seite mindestens: JS-Einstieg 5.2 KB"* ]]
    [[ "$output" == *"Untergrenze"* ]]
    [[ "$output" != *"bundles/storefront"* ]]
}

@test "analyze-bundle: ab 6.7.11 zählt shopware.js zum Einstieg" {
    mkdir -p "$ROOT/public/bundles/storefront/storefront/shopware"
    head -c 1000 /dev/zero | tr '\0' 'r' > "$ROOT/public/bundles/storefront/storefront/shopware/shopware.js"
    run bash "$SCRIPTS/analyze-bundle.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shopware/shopware.js (ab 6.7.11)"* ]]
    # 5000 + 300 + 1000 Byte
    [[ "$output" == *"JS-Einstieg 6.2 KB"* ]]
}

@test "analyze-bundle: Budget überschritten ergibt Exit 1" {
    # Zufallsdaten komprimieren kaum: > 2 KB gzip
    head -c 4000 /dev/urandom > "$THEME/js/storefront/storefront.js"
    run bash "$SCRIPTS/analyze-bundle.sh" --budget-js 2
    [ "$status" -eq 1 ]
    [[ "$output" == *"BUDGET: Einstiegs-JS"* ]]
}

@test "analyze-bundle: Budget eingehalten ergibt Exit 0" {
    run bash "$SCRIPTS/analyze-bundle.sh" --budget-js 100 --budget-css 100
    [ "$status" -eq 0 ]
    [[ "$output" != *"BUDGET"* ]]
}

@test "analyze-bundle: --url nimmt das Theme aus dem HTML, nicht das neueste" {
    OTHER="$ROOT/public/theme/ffffffffffffffffffffffffffffffff"
    mkdir -p "$OTHER/css" && echo 'b{}' > "$OTHER/css/all.css"
    touch -d '2099-01-01' "$OTHER/css/all.css" 2>/dev/null || touch "$OTHER/css/all.css"
    stub="$BATS_TEST_TMPDIR/curl"
    printf '#!/bin/sh\necho "<link rel=\\"stylesheet\\" href=\\"http://shop/theme/%s/css/all.css?1\\">"\n' "$PREFIX" > "$stub"
    chmod +x "$stub"
    CURL="$stub" run bash "$SCRIPTS/analyze-bundle.sh" --url http://shop/
    [ "$status" -eq 0 ]
    [[ "$output" == *"public/theme/$PREFIX"* ]]
}

@test "analyze-bundle: --url ohne Theme-CSS im HTML ergibt Exit 2" {
    stub="$BATS_TEST_TMPDIR/curl"
    printf '#!/bin/sh\necho "<html>Sales Channel Not Found</html>"\n' > "$stub"
    chmod +x "$stub"
    CURL="$stub" run bash "$SCRIPTS/analyze-bundle.sh" --url http://shop/
    [ "$status" -eq 2 ]
    [[ "$output" == *"Domain des Sales Channels"* ]]
}

# ---------------------------------------------------------------------------
# extract-critical-css.sh
# ---------------------------------------------------------------------------

node_stub() {
    printf '#!/bin/sh\necho %s\n' "$1" > "$BATS_TEST_TMPDIR/node"
    chmod +x "$BATS_TEST_TMPDIR/node"
}

# npx-Stub: critical schreibt CSS mit relativer und absoluter Font-URL in
# die Datei nach -o; lightningcss-cli kopiert die Eingabe (letztes Argument)
# nach -o. Jeder Aufruf wird in npx-args protokolliert.
npx_stub() {
    local mode="$1"
    cat > "$BATS_TEST_TMPDIR/npx" <<STUB
#!/bin/bash
echo "\$@" >> "$BATS_TEST_TMPDIR/npx-args"
[ "$mode" = fail ] && exit 1
all="\$*"; last="\${@: -1}"; out=""
while [ \$# -gt 0 ]; do
    if [ "\$1" = "-o" ]; then out="\$2"; fi
    shift
done
case "\$all" in
    *lightningcss-cli*) cp "\$last" "\$out" ;;
    *) printf '.header{display:flex}@font-face{src:url(../../abc123/assets/font/a.woff2)}@font-face{src:url(http://shop.test:8080/theme/abc123/assets/font/a.woff2)}' > "\$out" ;;
esac
STUB
    chmod +x "$BATS_TEST_TMPDIR/npx"
}

@test "extract-critical: --help zeigt Usage" {
    run bash "$SCRIPTS/extract-critical-css.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "extract-critical: ohne URL Exit 2" {
    run bash "$SCRIPTS/extract-critical-css.sh"
    [ "$status" -eq 2 ]
}

@test "extract-critical: unbekannte Engine Exit 2" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views" --engine penthouse
    [ "$status" -eq 2 ]
}

@test "extract-critical: Node < 22.13 ergibt Exit 2" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 20.19.4
    NODE="$BATS_TEST_TMPDIR/node" run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views"
    [ "$status" -eq 2 ]
    [[ "$output" == *"22.13"* ]]
}

@test "extract-critical: schreibt Twig-Include in verbatim, ohne --inline/--base/--output" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 22.21.1
    npx_stub ok
    NODE="$BATS_TEST_TMPDIR/node" NPX="$BATS_TEST_TMPDIR/npx" \
        run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views"
    [ "$status" -eq 0 ]
    out="$BATS_TEST_TMPDIR/views/critical/critical.css.twig"
    [ -f "$out" ]
    grep -q '{% verbatim %}' "$out"
    grep -q '.header{display:flex}' "$out"
    grep -q '{% endverbatim %}' "$out"
    args="$(cat "$BATS_TEST_TMPDIR/npx-args")"
    [[ "$args" == *"critical@9"* ]]
    [[ "$args" == *"lightningcss-cli@"*"--targets safari 12"* ]]
    [[ "$args" == *"playwright@"* ]]
    [[ "$args" == *"-e render"* ]]
    [[ "$args" != *"--inline"* ]]
    [[ "$args" != *"--base"* ]]
    [[ "$args" != *"--output"* ]]
}

@test "extract-critical: --engine static braucht kein Playwright" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 22.21.1
    npx_stub ok
    NODE="$BATS_TEST_TMPDIR/node" NPX="$BATS_TEST_TMPDIR/npx" \
        run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views" --engine static
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/npx-args")" != *"playwright"* ]]
}

@test "extract-critical: Fehlschlag lässt keine Datei zurück" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 22.21.1
    npx_stub fail
    NODE="$BATS_TEST_TMPDIR/node" NPX="$BATS_TEST_TMPDIR/npx" \
        run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views"
    [ "$status" -eq 1 ]
    [ ! -e "$BATS_TEST_TMPDIR/views/critical/critical.css.twig" ]
    [ ! -e "$BATS_TEST_TMPDIR/views/critical/critical.css.twig.part" ]
}

@test "extract-critical: schreibt Font-URLs auf /theme/ um, ohne Extraktions-Host" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 22.21.1
    npx_stub ok
    NODE="$BATS_TEST_TMPDIR/node" NPX="$BATS_TEST_TMPDIR/npx" \
        run bash "$SCRIPTS/extract-critical-css.sh" http://shop.test:8080/ --views-dir "$BATS_TEST_TMPDIR/views"
    [ "$status" -eq 0 ]
    out="$BATS_TEST_TMPDIR/views/critical/critical.css.twig"
    [ "$(grep -o 'url(/theme/abc123/assets/font/a.woff2)' "$out" | wc -l)" -eq 2 ]
    ! grep -q 'url(\.\./' "$out"
    # Der Twig-Kommentar im Kopf nennt die URL; das ausgelieferte CSS nicht
    ! grep -v '^{#' "$out" | grep -q 'shop.test'
}

@test "extract-critical: lightningcss-Fehler ergibt Exit 1 ohne Datei" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 22.21.1
    cat > "$BATS_TEST_TMPDIR/npx" <<'STUB'
#!/bin/bash
case "$*" in
    *lightningcss-cli*) exit 1 ;;
    *) while [ $# -gt 0 ]; do [ "$1" = "-o" ] && printf 'a{}' > "$2"; shift; done ;;
esac
STUB
    chmod +x "$BATS_TEST_TMPDIR/npx"
    NODE="$BATS_TEST_TMPDIR/node" NPX="$BATS_TEST_TMPDIR/npx" \
        run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views"
    [ "$status" -eq 1 ]
    [ ! -e "$BATS_TEST_TMPDIR/views/critical/critical.css.twig" ]
}

@test "extract-critical: bricht ab, wenn die Seite schon Critical CSS enthält" {
    mkdir -p "$BATS_TEST_TMPDIR/views"
    node_stub 22.21.1
    npx_stub ok
    # Viel HTML nach der Markierung: Eine Pipeline `curl | grep -q` bekäme
    # hier SIGPIPE und würde die Markierung unter pipefail übersehen.
    printf '#!/bin/sh\necho "<style data-critical-css>a{}</style>"\nhead -c 2000000 /dev/zero | tr "\\\\0" x\n' > "$BATS_TEST_TMPDIR/curl"
    chmod +x "$BATS_TEST_TMPDIR/curl"
    CURL="$BATS_TEST_TMPDIR/curl" NODE="$BATS_TEST_TMPDIR/node" NPX="$BATS_TEST_TMPDIR/npx" \
        run bash "$SCRIPTS/extract-critical-css.sh" http://shop/ --views-dir "$BATS_TEST_TMPDIR/views"
    [ "$status" -eq 2 ]
    [[ "$output" == *"criticalCss"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/npx-args" ]
    [ ! -e "$BATS_TEST_TMPDIR/views/critical" ]
}
