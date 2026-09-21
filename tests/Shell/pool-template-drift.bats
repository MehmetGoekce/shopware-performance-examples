#!/usr/bin/env bats

# Regressionsgate zu MEM-285.
#
# Zwei Vorlagen zielen auf dieselbe Datei /etc/php/8.3/fpm/pool.d/shopware.conf:
#   chapters/09-php-performance/config/shopware-fpm.conf
#   chapters/anhang-c-konfigurationen/config/php-fpm-pool.conf
#
# Kapitel 9 versicherte im Kopfkommentar, beide seien wertgleich - sie waren es
# in sieben wirksamen Zeilen nicht. An die Stelle der falschen Behauptung ist
# eine praezise getreten ("Sieben wirksame Zeilen unterscheiden sich", mit
# Aufzaehlung), und die veraltet beim naechsten Eingriff auf genau dieselbe
# Weise - nur spaeter. Diese Datei haelt sie fest.
#
# Wer eine Direktive in einer der beiden Vorlagen aendert, muss hier UND in
# beiden Kopfkommentaren nachziehen. Das ist der Zweck: Drift soll wehtun.

CH9="./chapters/09-php-performance/config/shopware-fpm.conf"
ANHC="./chapters/anhang-c-konfigurationen/config/php-fpm-pool.conf"

# Wirksame Zeilen = alles ausser Kommentar- und Leerzeilen, sortiert.
wirksam() {
    grep -vE '^[[:space:]]*;|^[[:space:]]*$' "$1" | sed 's/[[:space:]]*$//' | sort
}

# Kopfkommentar als Fliesstext: ';' weg, Zeilen zu einem Strom verbunden.
# Noetig, weil die Prosa umbrochen ist - ein zeilenweises grep trifft sie nie.
fliesstext() {
    grep '^[[:space:]]*;' "$1" \
        | sed 's/^[[:space:]]*;[[:space:]]*//' \
        | tr '\n' ' ' \
        | tr -s '[:space:]' ' '
}

@test "die Pool-Vorlagen unterscheiden sich in genau den sieben bekannten Zeilen" {
    wirksam "$CH9"  > "$BATS_TEST_TMPDIR/ch9"
    wirksam "$ANHC" > "$BATS_TEST_TMPDIR/anhc"

    comm -23 "$BATS_TEST_TMPDIR/ch9" "$BATS_TEST_TMPDIR/anhc" > "$BATS_TEST_TMPDIR/nur_ch9"
    comm -13 "$BATS_TEST_TMPDIR/ch9" "$BATS_TEST_TMPDIR/anhc" > "$BATS_TEST_TMPDIR/nur_anhc"

    # Anzahl zuerst - sie ist die Zahl, die in beiden Kopfkommentaren steht.
    [ "$(wc -l < "$BATS_TEST_TMPDIR/nur_ch9")"  -eq 1 ]
    [ "$(wc -l < "$BATS_TEST_TMPDIR/nur_anhc")" -eq 6 ]

    # Dann die Zeilen selbst, reihenfolgeunabhaengig: die Sortierung von
    # env[TEMP]/env[TMP]/env[TMPDIR] haengt an der Locale, nicht an der Sache.
    run grep -qxF 'listen.backlog = 65535' "$BATS_TEST_TMPDIR/nur_ch9"
    [ "$status" -eq 0 ]

    for zeile in \
        'env[PATH] = /usr/local/bin:/usr/bin:/bin' \
        'env[TMP] = /tmp' \
        'env[TMPDIR] = /tmp' \
        'env[TEMP] = /tmp' \
        'php_value[upload_max_filesize] = 128M' \
        'php_value[post_max_size] = 128M'
    do
        run grep -qxF "$zeile" "$BATS_TEST_TMPDIR/nur_anhc"
        [ "$status" -eq 0 ]
    done
}

@test "beide Kopfkommentare nennen dieselbe Differenz, die wirklich besteht" {
    # Faengt den Fall, dass jemand die Direktiven angleicht und die Kommentare
    # stehenlaesst - oder umgekehrt.
    for f in "$CH9" "$ANHC"; do
        fliesstext "$f" > "$BATS_TEST_TMPDIR/k"

        for satz in \
            'Sieben wirksame Zeilen unterscheiden sich' \
            'listen.backlog = 65535' \
            'env[PATH], env[TMP], env[TMPDIR], env[TEMP]' \
            'php_value[upload_max_filesize] = 128M' \
            'php_value[post_max_size] = 128M'
        do
            run grep -qF "$satz" "$BATS_TEST_TMPDIR/k"
            [ "$status" -eq 0 ]
        done
    done
}

@test "beide Vorlagen warnen vor der gemeinsamen Zieldatei" {
    # Die Kollision selbst ist mit MEM-285 nicht behoben, nur bewarnt
    # (strukturell: MEM-282). Verschwindet die Warnung, ist der Leser wieder
    # ungeschuetzt.
    for f in "$CH9" "$ANHC"; do
        fliesstext "$f" > "$BATS_TEST_TMPDIR/k"
        for satz in \
            'Nehmen Sie eine von beiden' \
            'test is successful'
        do
            run grep -qF "$satz" "$BATS_TEST_TMPDIR/k"
            [ "$status" -eq 0 ]
        done
    done
}

@test "beide Vorlagen nennen den Vorrang je Direktivenart" {
    # MEM-292: Bei gleichem Poolnamen gewinnt nicht einheitlich die alphabetisch
    # erste Datei. Einzelwerte (pm.*, listen, slowlog ...) ueberschreibt die
    # spaetere Datei, Listen (php_value, php_admin_value, env[...]) behaelt FPM
    # aus der ersten. Gemessen mit beiden Vorlagen und vertauschten Dateinamen.
    for f in "$CH9" "$ANHC"; do
        fliesstext "$f" > "$BATS_TEST_TMPDIR/k"
        for satz in \
            'Einzelwerte - pm.*, listen, request_*, slowlog, user ...: die alphabetisch LETZTE Datei gewinnt' \
            'Listen - php_value, php_flag, php_admin_value, php_admin_flag, env[...]: die alphabetisch ERSTE Datei gewinnt'
        do
            run grep -qF "$satz" "$BATS_TEST_TMPDIR/k"
            [ "$status" -eq 0 ]
        done

        # Der alte, einheitliche Satz darf nicht zurueckkommen - auch nicht
        # umgestellt. Die Vorrangzeilen selbst schreiben ERSTE/LETZTE gross.
        run grep -qE 'gewinnt (immer |stets )?die alphabetisch (erste|letzte)|alphabetisch (erste|letzte) Datei gewinnt' "$BATS_TEST_TMPDIR/k"
        [ "$status" -ne 0 ]
    done
}

@test "die Kapitel-9-Vorlage behauptet keine Gleichheit mehr" {
    # Der Originalsatz, der MEM-285 ausgeloest hat.
    run grep -qF 'es ist dieselbe Datei' "$CH9"
    [ "$status" -ne 0 ]
}

@test "www.conf wird nicht mehr mit einer Verdopplung begruendet" {
    # MEM-298: Ubuntus www.conf bringt pm.max_children = 5 mit, ab Werk sind
    # es 50 + 5, nicht 100 - und pm.max_children reserviert ohnehin keinen
    # Speicher. Der Rat zum Abschalten bleibt, die Begruendung ist eine andere.
    for f in "$CH9" "$ANHC" "./chapters/09-php-performance/README.md"; do
        # Kommentar- und Zitatmarken weg, damit umbrochene Saetze zusammenkommen.
        sed -E 's/^[[:space:]]*[;>][[:space:]]*//' "$f" | tr '\n' ' ' | tr -s '[:space:]' ' ' > "$BATS_TEST_TMPDIR/k"
        run grep -qiE 'doppelt|verdoppel|100 Worker' "$BATS_TEST_TMPDIR/k"
        [ "$status" -ne 0 ]
        run grep -qF 'RAM-Rechnung' "$BATS_TEST_TMPDIR/k"
        [ "$status" -eq 0 ]
    done
}

@test "die Anhang-C-Vorlage begruendet den conf.d-Vorrang nicht mit der hoeheren Nummer" {
    # MEM-298, Rest aus MEM-282: conf.d sortiert Zeichenketten, 100-b.ini
    # landet vor 99-a.ini.
    fliesstext "$ANHC" > "$BATS_TEST_TMPDIR/k"
    run grep -qiE 'h(oe|ö)here[rn]? Nummer' "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
}

@test "beide Vorlagen und das README nennen den Abschaltbefehl fuer www.conf" {
    # MEM-299: Buch und Vorlagen sagten "abschalten", aber nicht wie. Die CI
    # (Job php-fpm-pool) misst, dass der Befehl wirkt; hier steht, dass er da ist.
    # Auf die ganze Befehlszeile geankert: ein Befehl in Prosa oder mit
    # Zusatz ("(optional)") zaehlt nicht. Vorlagen: als ;-Kommentar.
    local cmd='sudo mv /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/www.conf.disabled'
    for f in "$CH9" "$ANHC"; do
        sed -E 's/^;[[:space:]]+//' "$f" > "$BATS_TEST_TMPDIR/k"
        run grep -qxF "$cmd" "$BATS_TEST_TMPDIR/k"
        [ "$status" -eq 0 ]
    done
    run grep -qxF "$cmd" "./chapters/09-php-performance/README.md"
    [ "$status" -eq 0 ]
}
