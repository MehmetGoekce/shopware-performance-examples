#!/usr/bin/env bats

# BATS tests for the appendix C configuration templates.
#
# Die Vorlagen selbst werden in der CI gestartet (nginx, php-fpm, mysqld,
# supervisord). Hier steht das, was ein Startgate nicht faengt: Aussagen im
# Kopfkommentar, die dem Leser ein falsches Kommando in die Hand geben.

CONFIG="./chapters/anhang-c-konfigurationen/config"
# Die Pool-Vorlage, die Anhang C abdruckt, liegt seit MEM-288 bei Kapitel 9.
POOL="./chapters/09-php-performance/config/shopware-fpm.conf"

@test "die Pool-Vorlage misst RSS ohne den Master-Prozess" {
    # Regressionstest zu MEM-277: "-C php-fpm8.3" trifft auch den Master.
    # Gemessen (3 warme Worker): Master 6,7 MB gegen rund 55,6 MB je Worker,
    # der Schnitt ueber alle vier Prozesse liegt bei 43,4 statt 55,6 MB.
    # Der Fehler geht in die gefaehrliche Richtung - die Formel
    # (RAM / RSS) liefert dann mehr Worker, als die Maschine traegt.
    #
    # Muster mit fuehrendem Bindestrich brauchen -e, sonst liest grep sie
    # als Option.
    run grep -qe '-o rss -C php-fpm8.3' "$POOL"
    [ "$status" -ne 0 ]
    run grep -qe '-o rss,args -C php-fpm8.3' "$POOL"
    [ "$status" -eq 0 ]
    # Review MEM-290: "grep 'pool'" zaehlte die www.conf-Worker mit.
    run grep -q "grep 'pool shopware'" "$POOL"
    [ "$status" -eq 0 ]
}

@test "die Pool-Vorlage verweist auf die robuste Fassung im Companion" {
    # Der Einzeiler oben teilt bei n=0 durch null und meldet dann "-nan MB".
    # Das Skript aus Kapitel 9 faengt das ab und erkennt zusaetzlich den
    # versionierten Prozessnamen.
    run grep -q 'chapters/09-php-performance/scripts/php-fpm-memory.sh' "$POOL"
    [ "$status" -eq 0 ]
}
