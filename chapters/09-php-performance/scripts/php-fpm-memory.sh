#!/bin/bash
#
# PHP-FPM Memory Analysis
# Misst den durchschnittlichen Speicherverbrauch pro Worker
#
# Verwendung: ./php-fpm-memory.sh
#
# Ergebnis: Durchschnittlicher RAM pro Worker fuer
# die Berechnung von pm.max_children

echo "=== PHP-FPM Memory Analysis ==="
echo ""

# Pruefen ob PHP-FPM laeuft
if ! pgrep -x "php-fpm" > /dev/null 2>&1; then
    echo "FEHLER: PHP-FPM laeuft nicht!"
    exit 1
fi

# RSS-Werte aller PHP-FPM Worker (in KB)
echo "Worker-Statistiken:"
echo ""

ps -ylC php-fpm --sort:rss | awk '
NR==1 { print "  PID    RSS (MB)    Status" }
NR>1 {
    rss_mb = $8/1024
    total += $8
    count++
    if (rss_mb > max) max = rss_mb
    if (min == 0 || rss_mb < min) min = rss_mb
}
END {
    if (count > 0) {
        avg = total/count/1024
        print ""
        print "=== Zusammenfassung ==="
        print "  Anzahl Worker:  " count
        print "  Durchschnitt:   " sprintf("%.0f", avg) " MB"
        print "  Minimum:        " sprintf("%.0f", min) " MB"
        print "  Maximum:        " sprintf("%.0f", max) " MB"
        print ""
        print "=== Empfehlung fuer calculate-max-children.sh ==="
        print "  AVG_WORKER_MB=" sprintf("%.0f", avg + 10) "  # (Durchschnitt + 10MB Puffer)"
    } else {
        print "Keine Worker gefunden."
    }
}'

echo ""
echo "Hinweis: Messen Sie nach einigen Minuten Last erneut"
echo "         fuer realistischere Werte."
