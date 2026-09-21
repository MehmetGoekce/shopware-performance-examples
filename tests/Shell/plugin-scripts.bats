#!/usr/bin/env bats
#
# Kapitel 17: profile-plugin.sh und analyze-subscribers.sh
#
# bin/console und curl sind per Env-Variable ersetzbar (CONSOLE, CURL).
# Der Console-Stub merkt sich den Plugin-Zustand in einer Datei und
# protokolliert jeden Aufruf. Beide Skripte werten JSON mit php aus -
# ohne php (bats/bats-Image) werden diese Tests übersprungen.

setup() {
    SCRIPTS="$BATS_TEST_DIRNAME/../../chapters/17-shopware-plugins/scripts"
    STUB="$BATS_TEST_TMPDIR"
    echo active > "$STUB/state"
    : > "$STUB/console.log"
    : > "$STUB/urls.log"

    cat > "$STUB/console" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB/console.log"
case "$1" in
    plugin:list)
        [ "${CONSOLE_FAIL:-}" = list ] && exit 1
        [ "${CONSOLE_FAIL:-}" = json ] && { echo "PHP Deprecated: irgendwas"; exit 0; }
        if [ "$(cat "$STUB/state")" = active ]; then a=true; else a=false; fi
        printf '[{"name":"OtherPlugin","active":true,"extensions":{"x":{}}},{"name":"MyPlugin","active":%s}]\n' "$a"
        ;;
    plugin:deactivate) echo inactive > "$STUB/state" ;;
    plugin:activate) echo active > "$STUB/state" ;;
    cache:clear|cache:clear:all) ;;
    list)
        echo "cache:clear                  Clear the cache"
        [ "${CONSOLE_CLEAR_ALL:-}" = 1 ] && echo "cache:clear:all              Clear all caches/pools"
        ;;
    debug:event-dispatcher)
        [ "${CONSOLE_FAIL:-}" = dispatcher ] && exit 1
        cat <<'JSON'
{"product.written":[{"type":"function","name":"onWritten","class":"Swag\\PayPal\\Subscriber\\A","priority":0},{"type":"function","name":"log","class":"Shopware\\Core\\X","priority":10}],
 "kernel.request":[{"type":"function","name":"onRequest","class":"Swag\\PayPal\\Subscriber\\B","priority":-5},{"type":"function","name":"r","class":"Shopware\\Core\\Y","priority":0},{"type":"function","name":"s","class":"Shopware\\Storefront\\Z","priority":0}]}
JSON
        ;;
    *) exit 1 ;;
esac
EOF

    # curl-Stub: 150 ms mit Plugin, 80 ms ohne; HTTP-Code per Env.
    # Liegt eine Datei times_active/times_inactive vor, kommt je Aufruf
    # der nächste Wert daraus (Median und Streuung prüfen).
    cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
url="${!#}"
echo "$url" >> "$STUB/urls.log"
code="${CURL_CODE:-200}"
state="$(cat "$STUB/state")"
if [ "$state" = active ]; then t=0.150; else t=0.080; code="${CURL_CODE_OFF:-$code}"; fi
if [ -s "$STUB/times_$state" ]; then
    t="$(head -n 1 "$STUB/times_$state")"
    sed -i '1d' "$STUB/times_$state"
fi
printf '%s %s' "$code" "$t"
EOF
    chmod +x "$STUB/console" "$STUB/curl"
    export STUB CONSOLE="$STUB/console" CURL="$STUB/curl" RUNS=3 WARMUP=1
}

need_php() {
    command -v php >/dev/null || skip "php nicht installiert"
}

# --- profile-plugin.sh ----------------------------------------------------

@test "profile-plugin: --help zeigt Usage, Exit 0" {
    run "$SCRIPTS/profile-plugin.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "profile-plugin: ohne Plugin-Namen Exit 2" {
    run "$SCRIPTS/profile-plugin.sh"
    [ "$status" -eq 2 ]
}

@test "profile-plugin: RUNS=0 ist ein falscher Aufruf" {
    RUNS=0 run "$SCRIPTS/profile-plugin.sh" MyPlugin
    [ "$status" -eq 2 ]
    [[ "$output" == *"RUNS"* ]]
}

@test "profile-plugin: inaktives Plugin wird nicht angefasst" {
    need_php
    echo inactive > "$STUB/state"
    run "$SCRIPTS/profile-plugin.sh" MyPlugin
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht aktiv (Status: inactive)"* ]]
    [ "$(grep -c 'plugin:deactivate\|plugin:activate' "$STUB/console.log")" -eq 0 ]
}

@test "profile-plugin: ungültiges JSON aus plugin:list -> eigene Meldung" {
    need_php
    CONSOLE_FAIL=json run "$SCRIPTS/profile-plugin.sh" MyPlugin
    [ "$status" -eq 1 ]
    [[ "$output" == *"kein gültiges JSON"* ]]
}

@test "profile-plugin: unbekanntes Plugin -> Exit 1" {
    need_php
    run "$SCRIPTS/profile-plugin.sh" NoSuchPlugin
    [ "$status" -eq 1 ]
    [[ "$output" == *"Status: missing"* ]]
}

@test "profile-plugin: plugin:list scheitert -> Exit 1 mit Meldung" {
    need_php
    CONSOLE_FAIL=list run "$SCRIPTS/profile-plugin.sh" MyPlugin
    [ "$status" -eq 1 ]
    [[ "$output" == *"plugin:list ist fehlgeschlagen"* ]]
}

@test "profile-plugin: A-B-A misst den Unterschied und aktiviert wieder" {
    need_php
    run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mit Plugin (Mittel A1/A2): 150.0 ms"* ]]
    [[ "$output" == *"Ohne Plugin:               80.0 ms"* ]]
    [[ "$output" == *"Unterschied:               +70.0 ms"* ]]
    [[ "$output" == *"grösser als die Streuung"* ]]
    [ "$(cat "$STUB/state")" = active ]
    # Reihenfolge: deaktivieren vor aktivieren, je Phase ein cache:clear
    [ "$(grep -c '^cache:clear' "$STUB/console.log")" -eq 3 ]
    grep -n 'plugin:' "$STUB/console.log" | tr '\n' ' ' | grep -q 'deactivate MyPlugin.*activate MyPlugin'
}

@test "profile-plugin: Median bei gerader Anzahl, Mittel der A-Phasen" {
    need_php
    printf '%s\n' 0.100 0.400 0.200 0.300 0.260 0.240 0.250 0.250 > "$STUB/times_active"
    printf '%s\n' 0.100 0.100 0.100 0.100 > "$STUB/times_inactive"
    RUNS=4 WARMUP=0 run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 0 ]
    [[ "$output" == *"A1-mit: Median 250.0 ms"* ]]
    [[ "$output" == *"A2-mit: Median 250.0 ms"* ]]
    [[ "$output" == *"Ohne Plugin:               100.0 ms"* ]]
    [[ "$output" == *"Unterschied:               +150.0 ms (+150.0 %)"* ]]
    [[ "$output" == *"Streuung A1 gegen A2:      0.0 ms"* ]]
}

@test "profile-plugin: Unterschied innerhalb der Streuung -> nicht belastbar" {
    need_php
    # A1 Median 150, A2 Median 90 (Streuung 60), B 60: Unterschied +60,
    # genau auf der Grenze - "gleich der Streuung" zählt als nicht belastbar
    printf '%s\n' 0.150 0.150 0.150 0.090 0.090 0.090 > "$STUB/times_active"
    printf '%s\n' 0.060 0.060 0.060 > "$STUB/times_inactive"
    RUNS=3 WARMUP=0 run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unterschied:               +60.0 ms"* ]]
    [[ "$output" == *"Streuung A1 gegen A2:      60.0 ms"* ]]
    [[ "$output" == *"innerhalb der Streuung - nicht belastbar"* ]]
}

@test "profile-plugin: cache:clear:all nur, wenn der Shop es kennt" {
    need_php
    run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 0 ]
    [ "$(grep -c '^cache:clear:all' "$STUB/console.log")" -eq 0 ]
    : > "$STUB/console.log"
    CONSOLE_CLEAR_ALL=1 run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 0 ]
    [ "$(grep -c '^cache:clear:all' "$STUB/console.log")" -eq 3 ]
}

@test "profile-plugin: jeder Aufruf hat eine eigene URL (am HTTP-Cache vorbei)" {
    need_php
    run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 0 ]
    # 3 Phasen x (WARMUP 1 + RUNS 3) = 12 Aufrufe, alle verschieden
    [ "$(wc -l < "$STUB/urls.log")" -eq 12 ]
    [ "$(sort -u "$STUB/urls.log" | wc -l)" -eq 12 ]
    grep -q '^http://localhost/seite?plugin_profile=' "$STUB/urls.log"
}

@test "profile-plugin: Pfad mit Query bekommt & statt ?" {
    need_php
    run "$SCRIPTS/profile-plugin.sh" MyPlugin '/suche?search=a'
    [ "$status" -eq 0 ]
    grep -q '^http://localhost/suche?search=a&plugin_profile=' "$STUB/urls.log"
}

@test "profile-plugin: keine HTTP-200-Antwort bricht ab" {
    need_php
    CURL_CODE=301 run "$SCRIPTS/profile-plugin.sh" MyPlugin /detail/abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"antwortet mit HTTP 301"* ]]
}

@test "profile-plugin: Abbruch in der B-Phase aktiviert das Plugin wieder" {
    need_php
    CURL_CODE_OFF=500 run "$SCRIPTS/profile-plugin.sh" MyPlugin /seite
    [ "$status" -eq 1 ]
    [[ "$output" == *"HTTP 500"* ]]
    [ "$(cat "$STUB/state")" = active ]
    grep -q '^plugin:activate --clearCache MyPlugin' "$STUB/console.log"
}

# --- analyze-subscribers.sh -----------------------------------------------

@test "analyze-subscribers: --help zeigt Usage, Exit 0" {
    run "$SCRIPTS/analyze-subscribers.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "analyze-subscribers: unbekannte Option -> Exit 2" {
    run "$SCRIPTS/analyze-subscribers.sh" --foo
    [ "$status" -eq 2 ]
}

@test "analyze-subscribers: zählt Listener je Namespace" {
    need_php
    run "$SCRIPTS/analyze-subscribers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ Swag\\PayPal\ +2 ]]
    [[ "$output" =~ Shopware\\Core\ +2 ]]
    [[ "$output" =~ Shopware\\Storefront\ +1 ]]
    [[ "$output" == *"5 Listener auf 2 Events"* ]]
}

@test "analyze-subscribers: Namespace-Filter listet Event und Priorität" {
    need_php
    run "$SCRIPTS/analyze-subscribers.sh" 'Swag\PayPal'
    [ "$status" -eq 0 ]
    [[ "$output" == *"product.written"*"Swag\\PayPal\\Subscriber\\A::onWritten"* ]]
    [[ "$output" == *"-5  kernel.request"* ]]
    [[ "$output" != *"Shopware\\Core"* ]]
}

@test "analyze-subscribers: Namespace ohne Listener -> Exit 1" {
    need_php
    run "$SCRIPTS/analyze-subscribers.sh" 'Acme\Nothing'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Keine Listener für Acme\Nothing"* ]]
}

@test "analyze-subscribers: debug:event-dispatcher scheitert -> Exit 1" {
    CONSOLE_FAIL=dispatcher run "$SCRIPTS/analyze-subscribers.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"debug:event-dispatcher ist fehlgeschlagen"* ]]
}
