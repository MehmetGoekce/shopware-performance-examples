#!/usr/bin/env bats

# Regressionsgate zu MEM-285, MEM-288 und MEM-290: eine Vorlage je Zieldatei.
#
# Bis September 2026 lagen fuer den FPM-Pool und fuer den nginx-vHost je zwei
# Vorlagen im Companion (Kapitel 9 und Anhang C). Die Pools nannten dieselbe
# Zieldatei und ueberschrieben sich lautlos, die vHosts beanspruchten beide
# shop.example.com auf 443 - nginx ignoriert dann einen still. Die Regel aus
# Anhang Cs README: kanonisch ist die Vorlage des Kapitels, das die Sache
# erklaert, die anderen verweisen.
#
#   Pool:  chapters/09-php-performance/config/shopware-fpm.conf
#   vHost: chapters/anhang-c-konfigurationen/config/nginx-shopware.conf
#
# Wer eine zweite Vorlage anlegt, muss hier eine Ausnahme mit Ticket eintragen.
# Das ist der Zweck: Doppelung soll wehtun.

POOL="./chapters/09-php-performance/config/shopware-fpm.conf"
VHOST="./chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
INI="./chapters/09-php-performance/config/99-shopware.ini"

# Kopfkommentar als Fliesstext: ';' bzw. '#' weg, Zeilen zu einem Strom verbunden.
# Noetig, weil die Prosa umbrochen ist - ein zeilenweises grep trifft sie nie.
fliesstext() {
    grep -E '^[[:space:]]*[;#]' "$1" \
        | sed -E 's/^[[:space:]]*[;#][[:space:]]*//' \
        | tr '\n' ' ' \
        | tr -s '[:space:]' ' '
}

# Alle Dateien unter chapters/, ohne installierte Abhaengigkeiten.
dateien() {
    find chapters -type f -not -path '*/node_modules/*' -not -path '*/vendor/*' | sort
}

@test "genau eine Companion-Datei definiert den Pool [shopware]" {
    # find statt git ls-files: laeuft auch im bats-Image ohne git.
    dateien | while read -r f; do
        grep -lE '^[[:space:]]*\[shopware\][[:space:]]*$' "$f" 2>/dev/null || true
    done > "$BATS_TEST_TMPDIR/pools"
    cat "$BATS_TEST_TMPDIR/pools"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/pools")" -eq 1 ]
    [ "$(cat "$BATS_TEST_TMPDIR/pools")" = "${POOL#./}" ]
}

@test "genau ein Companion-vHost beansprucht shop.example.com auf 443" {
    # Aktive Zeilen, nicht Kommentare: Der kanonische vHost nennt den
    # Konflikt im Kopf selbst.
    # Bekannte Ausnahme: Kapitel 24 bringt HTTP/3 noch als eigenen server-Block
    # mit - MEM-318. Mit dem Ticket faellt die Ausnahme weg.
    dateien | grep -v '^chapters/24-ausblick/config/nginx-http3.conf$' \
        | while read -r f; do
            if grep -qE '^[[:space:]]*server_name[[:space:]]+shop\.example\.com;' "$f" \
               && grep -qE '^[[:space:]]*listen[[:space:]]+(\[::\]:)?443' "$f"; then
                echo "$f"
            fi
        done > "$BATS_TEST_TMPDIR/vhosts"
    cat "$BATS_TEST_TMPDIR/vhosts"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/vhosts")" -eq 1 ]
    [ "$(cat "$BATS_TEST_TMPDIR/vhosts")" = "${VHOST#./}" ]
}

@test "die Ausnahme fuer Kapitel 24 ist noch noetig" {
    # Schlaegt an, sobald MEM-318 erledigt ist - dann die Ausnahme oben
    # entfernen, statt eine tote Zeile stehen zu lassen.
    run grep -qE '^[[:space:]]*server_name[[:space:]]+shop\.example\.com;' \
        ./chapters/24-ausblick/config/nginx-http3.conf
    [ "$status" -eq 0 ]
}

@test "Pool, conf.d und vHost erlauben dieselbe Upload-Groesse" {
    # upload_max_filesize/post_max_size in PHP und client_max_body_size in
    # nginx muessen zusammenpassen, sonst antwortet nginx mit 413 (MEM-287).
    [ "$(sed -nE 's/^php_value\[upload_max_filesize\] = (.*)$/\1/p' "$POOL")" = "128M" ]
    [ "$(sed -nE 's/^php_value\[post_max_size\] = (.*)$/\1/p' "$POOL")" = "128M" ]
    [ "$(sed -nE 's/^upload_max_filesize = (.*)$/\1/p' "$INI")" = "128M" ]
    [ "$(sed -nE 's/^post_max_size = (.*)$/\1/p' "$INI")" = "128M" ]
    [ "$(sed -nE 's/^[[:space:]]*client_max_body_size (.*);$/\1/p' "$VHOST")" = "128M" ]
}

@test "der Pool-Kopf nennt den Vorrang je Direktivenart und die Pruefung" {
    # MEM-292: Bei gleichem Poolnamen gewinnt nicht einheitlich die alphabetisch
    # erste Datei. Einzelwerte ueberschreibt die spaetere Datei, Listen behaelt
    # FPM aus der ersten. Bleibt stehen, weil Leser frueherer Auflagen noch
    # eine zweite [shopware]-Datei liegen haben koennen.
    fliesstext "$POOL" > "$BATS_TEST_TMPDIR/k"
    for satz in \
        'Einzelwerte - pm.*, listen, request_*, slowlog, user ...: die alphabetisch LETZTE Datei gewinnt' \
        'Listen - php_value, php_flag, php_admin_value, php_admin_flag, env[...]: die alphabetisch ERSTE Datei gewinnt' \
        "grep -l '^\\[shopware\\]' /etc/php/8.3/fpm/pool.d/*.conf" \
        'test is successful'
    do
        run grep -qF "$satz" "$BATS_TEST_TMPDIR/k"
        [ "$status" -eq 0 ]
    done

    # Der alte, einheitliche Satz darf nicht zurueckkommen - auch nicht
    # umgestellt. Die Vorrangzeilen selbst schreiben ERSTE/LETZTE gross.
    run grep -qE 'gewinnt (immer |stets )?die alphabetisch (erste|letzte)|alphabetisch (erste|letzte) Datei gewinnt' "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
}

@test "der vHost-Kopf nennt die Pruefung auf den stillen server_name-Konflikt" {
    fliesstext "$VHOST" > "$BATS_TEST_TMPDIR/k"
    for satz in \
        "sudo nginx -t 2>&1 | grep 'conflicting server name'" \
        'duplicate upstream'
    do
        run grep -qF "$satz" "$BATS_TEST_TMPDIR/k"
        [ "$status" -eq 0 ]
    done
}

@test "die Pool-Vorlage behauptet keine Gleichheit mehr" {
    # Der Originalsatz, der MEM-285 ausgeloest hat.
    run grep -qF 'es ist dieselbe Datei' "$POOL"
    [ "$status" -ne 0 ]
}

@test "www.conf wird nicht mehr mit einer Verdopplung begruendet" {
    # MEM-298: Ubuntus www.conf bringt pm.max_children = 5 mit, ab Werk sind
    # es 50 + 5, nicht 100 - und pm.max_children reserviert ohnehin keinen
    # Speicher. Der Rat zum Abschalten bleibt, die Begruendung ist eine andere.
    for f in "$POOL" "./chapters/09-php-performance/README.md"; do
        # Kommentar- und Zitatmarken weg, damit umbrochene Saetze zusammenkommen.
        sed -E 's/^[[:space:]]*[;>][[:space:]]*//' "$f" | tr '\n' ' ' | tr -s '[:space:]' ' ' > "$BATS_TEST_TMPDIR/k"
        run grep -qiE 'doppelt|verdoppel|100 Worker' "$BATS_TEST_TMPDIR/k"
        [ "$status" -ne 0 ]
        run grep -qF 'RAM-Rechnung' "$BATS_TEST_TMPDIR/k"
        [ "$status" -eq 0 ]
    done
}

@test "die Pool-Vorlage begruendet den conf.d-Vorrang nicht mit der hoeheren Nummer" {
    # MEM-298, Rest aus MEM-282: conf.d sortiert Zeichenketten, 100-b.ini
    # landet vor 99-a.ini.
    fliesstext "$POOL" > "$BATS_TEST_TMPDIR/k"
    run grep -qiE 'h(oe|ö)here[rn]? Nummer' "$BATS_TEST_TMPDIR/k"
    [ "$status" -ne 0 ]
}

@test "Vorlage und README nennen den Abschaltbefehl fuer www.conf" {
    # MEM-299: Buch und Vorlagen sagten "abschalten", aber nicht wie. Die CI
    # (Job php-fpm-pool) misst, dass der Befehl wirkt; hier steht, dass er da ist.
    # Auf die ganze Befehlszeile geankert: ein Befehl in Prosa oder mit
    # Zusatz ("(optional)") zaehlt nicht. Vorlage: als ;-Kommentar.
    local cmd='sudo mv /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/www.conf.disabled'
    sed -E 's/^;[[:space:]]+//' "$POOL" > "$BATS_TEST_TMPDIR/k"
    run grep -qxF "$cmd" "$BATS_TEST_TMPDIR/k"
    [ "$status" -eq 0 ]
    run grep -qxF "$cmd" "./chapters/09-php-performance/README.md"
    [ "$status" -eq 0 ]
}
