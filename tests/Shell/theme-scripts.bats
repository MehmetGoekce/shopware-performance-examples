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
    [[ "$output" == *"Pflichtanteil jeder Seite: JS 5.2 KB"* ]]
    [[ "$output" != *"bundles/storefront"* ]]
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
}

# ---------------------------------------------------------------------------
# extract-critical-css.sh
# ---------------------------------------------------------------------------

node_stub() {
    printf '#!/bin/sh\necho %s\n' "$1" > "$BATS_TEST_TMPDIR/node"
    chmod +x "$BATS_TEST_TMPDIR/node"
}

# npx-Stub: schreibt CSS in die Datei nach -o und protokolliert die Argumente
npx_stub() {
    cat > "$BATS_TEST_TMPDIR/npx" <<EOF
#!/bin/bash
echo "\$@" > "$BATS_TEST_TMPDIR/npx-args"
[ "$1" = fail ] && exit 1
while [ \$# -gt 0 ]; do
    if [ "\$1" = "-o" ]; then printf '.header{display:flex}' > "\$2"; fi
    shift
done
EOF
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
