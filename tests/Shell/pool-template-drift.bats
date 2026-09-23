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
#   HTTP/3: chapters/24-ausblick/config/nginx-http3.conf (nur das Delta, per
#           include im vHost - kein eigener server-Block, MEM-318)
#
# Wer eine zweite Vorlage anlegt, muss hier eine Ausnahme mit Ticket eintragen.
# Das ist der Zweck: Doppelung soll wehtun.

POOL="./chapters/09-php-performance/config/shopware-fpm.conf"
VHOST="./chapters/anhang-c-konfigurationen/config/nginx-shopware.conf"
INI="./chapters/09-php-performance/config/99-shopware.ini"
HTTP3="./chapters/24-ausblick/config/nginx-http3.conf"

# Kopfkommentar als Fliesstext: ';' bzw. '#' weg, Zeilen zu einem Strom verbunden.
# Noetig, weil die Prosa umbrochen ist - ein zeilenweises grep trifft sie nie.
fliesstext() {
    grep -E '^[[:space:]]*[;#]' "$1" \
        | sed -E 's/^[[:space:]]*[;#][[:space:]]*//' \
        | tr '\n' ' ' \
        | tr -s '[:space:]' ' '
}

# Alle Dateien des Repos ausser installierten Abhaengigkeiten, .git und
# tests/ (die Tests nennen die Muster selbst). Review MEM-290: nur chapters/
# liess eine zweite Vorlage unter templates/ durch.
dateien() {
    find . -type f -not -path '*/node_modules/*' -not -path '*/vendor/*' \
        -not -path './.git/*' -not -path './tests/*' | sed 's|^\./||' | sort
}

@test "genau eine Companion-Datei definiert den Pool [shopware]" {
    # find statt git ls-files: laeuft auch im bats-Image ohne git.
    dateien | while read -r f; do
        # FPM akzeptiert auch "[shopware] ; Kommentar" (gemessen mit -tt).
        grep -lE '^[[:space:]]*\[shopware\][[:space:]]*(;.*)?$' "$f" 2>/dev/null || true
    done > "$BATS_TEST_TMPDIR/pools"
    cat "$BATS_TEST_TMPDIR/pools"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/pools")" -eq 1 ]
    [ "$(cat "$BATS_TEST_TMPDIR/pools")" = "${POOL#./}" ]
}

@test "genau ein Companion-vHost beansprucht shop.example.com auf 443" {
    # Aktive Zeilen, nicht Kommentare: Der kanonische vHost nennt den
    # Konflikt im Kopf selbst.
    dateien | while read -r f; do
            # server_name mit weiteren Namen und listen *:443 zaehlen mit.
            if grep -qE '^[[:space:]]*server_name[[:space:]][^;]*\bshop\.example\.com\b' "$f" \
               && grep -qE '^[[:space:]]*listen[[:space:]]+([^;]*:)?443\b' "$f"; then
                echo "$f"
            fi
        done > "$BATS_TEST_TMPDIR/vhosts"
    cat "$BATS_TEST_TMPDIR/vhosts"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/vhosts")" -eq 1 ]
    [ "$(cat "$BATS_TEST_TMPDIR/vhosts")" = "${VHOST#./}" ]
}

@test "Pool und vHost nennen denselben Socket" {
    # Review MEM-290: Kein Test verband die beiden Pfade; ein Upstream auf
    # den www.conf-Socket blieb gruen und haette nach dem Abschalten von
    # www.conf 502 geliefert.
    local pool_sock vhost_sock
    pool_sock=$(sed -nE 's/^listen = (.*)$/\1/p' "$POOL")
    vhost_sock=$(sed -nE 's/^[[:space:]]*server unix:([^;]*);.*/\1/p' "$VHOST")
    [ -n "$pool_sock" ]
    [ "$pool_sock" = "$vhost_sock" ]
}

@test "genau eine Companion-Datei bringt den QUIC-Listener" {
    # MEM-318: Zwei Dateien mit `listen ... quic reuseport` im selben Baum
    # starten nicht ("duplicate listen options"), und zwei Fassungen desselben
    # Deltas laufen auseinander.
    # Bekannte Ausnahme: Kapitel 11 bringt noch ein eigenes HTTP/3-Fragment mit
    # `listen 443 ssl;` mit, das neben Anhang C nicht startet - MEM-323. Mit
    # dem Ticket faellt die Ausnahme weg.
    # Gezaehlt werden Zeilen, nicht Dateien (Review MEM-318): eine doppelte
    # quic-Zeile im Delta selbst startet ebenso wenig.
    dateien | grep -v '^chapters/11-cdn-integration/config/nginx-http3.conf$' \
        | while read -r f; do
            grep -HE '^[[:space:]]*listen[[:space:]][^;#]*\bquic\b' "$f" 2>/dev/null || true
        done > "$BATS_TEST_TMPDIR/quic"
    cat "$BATS_TEST_TMPDIR/quic"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/quic")" -eq 2 ]
    [ "$(cut -d: -f1 "$BATS_TEST_TMPDIR/quic" | sort -u)" = "${HTTP3#./}" ]
    [ "$(sed 's/^[^:]*://' "$BATS_TEST_TMPDIR/quic" | tr -s ' ' | sort -u | wc -l)" -eq 2 ]
}

@test "die Ausnahme fuer Kapitel 11 ist noch noetig" {
    # Schlaegt an, sobald MEM-323 erledigt ist - dann die Ausnahme oben
    # entfernen, statt eine tote Zeile stehen zu lassen.
    run grep -qE '^[[:space:]]*listen[[:space:]][^;#]*\bquic\b' \
        ./chapters/11-cdn-integration/config/nginx-http3.conf
    [ "$status" -eq 0 ]
}

@test "das HTTP/3-Delta ist kein eigener vHost" {
    # MEM-318: Als eigener server-Block neben Anhang C lief jede HTTP/3-Anfrage
    # in diesen Block und auf einen Upstream, auf dem niemand hoert (502).
    # Das Delta darf deshalb nur ergaenzen, was der vHost aus Anhang C nicht hat.
    # Aktiv verboten sind ausserdem 0-RTT (Replay ueber TCP sofort, auf jeder
    # Version) und quic_retry (ein Roundtrip mehr je Verbindung) - beide stehen
    # nur als Kommentar mit Begruendung darin.
    for muster in '^[[:space:]]*server([[:space:]{]|$)' '^[[:space:]]*server_name[[:space:]]' \
                  '^[[:space:]]*upstream[[:space:]]' '^[[:space:]]*location[[:space:]]' \
                  '^[[:space:]]*listen[[:space:]][^;#]*\bssl\b' '^[[:space:]]*ssl_protocols[[:space:]]' \
                  '^[[:space:]]*ssl_early_data[[:space:]]' '^[[:space:]]*quic_retry[[:space:]]' \
                  '^[[:space:]]*http3[[:space:]]+off'; do
        run grep -qE "$muster" "$HTTP3"
        [ "$status" -ne 0 ]
    done
    # Beide Adressfamilien: der vHost hoert auf 443 und [::]:443.
    grep -qxE '[[:space:]]*listen 443 quic reuseport;' "$HTTP3"
    grep -qxE '[[:space:]]*listen \[::\]:443 quic reuseport;' "$HTTP3"
    grep -qE "^[[:space:]]*add_header Alt-Svc 'h3=\":443\"; ma=86400' always;" "$HTTP3"
    grep -qxE '[[:space:]]*http3 on;' "$HTTP3"
    # Einbindung wie im Kopf beschrieben (eigene Kommentarzeile), und der vHost
    # hat die Stelle dafuer. Zieldatei im Kopf, include-Pfad und README-cp
    # muessen dieselbe Datei nennen.
    grep -qxE '#[[:space:]]+include snippets/shopware-http3\.conf;' "$HTTP3"
    grep -qxF '# Datei: /etc/nginx/snippets/shopware-http3.conf' "$HTTP3"
    grep -qxF 'sudo cp config/nginx-http3.conf /etc/nginx/snippets/shopware-http3.conf' \
        ./chapters/24-ausblick/README.md
    grep -qE '^[[:space:]]*listen \[::\]:443 ssl;' "$VHOST"
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
        "sudo nginx -t 2>&1 | grep -E 'emerg|conflicting server name'" \
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
