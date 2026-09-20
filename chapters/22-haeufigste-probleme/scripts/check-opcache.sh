#!/usr/bin/env bash
#
# check-opcache.sh
#
# Problem 12: OPcache nicht aktiviert.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# WICHTIG: "php -i" zeigt die CLI-SAPI. Der Shop laeuft aber unter PHP-FPM,
# und das hat auf Debian/Ubuntu eine eigene php.ini
# (/etc/php/<version>/fpm/php.ini statt .../cli/php.ini). Dazu kommt, dass
# opcache.enable_cli standardmaessig 0 ist: in der CLI ist OPcache also
# praktisch nie aktiv, auch wenn opcache.enable auf 1 steht. Wer die CLI
# misst, bekommt ein falsches Ergebnis — in beide Richtungen.
#
# Dieses Skript liest deshalb primaer "php-fpm<version> -i".
#
# Verwendung:
#   ./check-opcache.sh [SHOP_URL] [SHOP_PATH]
#   PHP_FPM_BINARY=php-fpm8.3 ./check-opcache.sh
#
# Exit-Codes:
#   0 = OPcache aktiv und brauchbar konfiguriert
#   1 = OPcache aus oder Einstellungen fuer Shopware zu knapp
#   64 = Aufruffehler
#   69 = keine FPM-Binary gefunden, Pruefung nicht moeglich

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-opcache.sh [SHOP_URL] [SHOP_PATH]

Prueft die OPcache-Konfiguration der FPM-SAPI.

Argumente:
  SHOP_URL, SHOP_PATH   Werden nicht ausgewertet; nur der Einheitlichkeit halber.

Umgebungsvariablen:
  PHP_FPM_BINARY  Optional. Name oder Pfad der FPM-Binary, z. B. php-fpm8.3.
                  Ohne Angabe wird die hoechste gefundene Version benutzt.

Hinweis: "php-fpm -i" liest die FPM-php.ini, aber keine pool-spezifischen
php_admin_value-Ueberschreibungen aus der Pool-Konfiguration. Bei Abweichungen
zusaetzlich /etc/php/<version>/fpm/pool.d/*.conf pruefen.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

# Aufrufkonvention aller Skripte dieses Kapitels: $1 = SHOP_URL, $2 = SHOP_PATH.
# Dieses Skript braucht weder URL noch Pfad; $1 wird bewusst nicht ausgewertet,
# damit run-all-diagnostics.sh alle Skripte gleich aufrufen kann.
# Die FPM-Binary kommt per Umgebungsvariable.
FPM_BIN="${PHP_FPM_BINARY:-}"

if [[ -z "${FPM_BIN}" ]]; then
    # Hoechste verfuegbare Version waehlen.
    for candidate in $(compgen -c php-fpm 2>/dev/null | sort -Vru); do
        if command -v "${candidate}" >/dev/null 2>&1; then
            FPM_BIN="${candidate}"
            break
        fi
    done
fi

echo "=== Problem 12: OPcache Status ==="
echo

if [[ -z "${FPM_BIN}" ]] || ! command -v "${FPM_BIN}" >/dev/null 2>&1; then
    cat <<'HINT'
Keine php-fpm-Binary gefunden.

OPcache laesst sich dann nur ueber einen Web-Request messen. Dazu im
Web-Root kurzzeitig eine Datei anlegen, aufrufen und SOFORT wieder loeschen:

  <?php
  // Zugriff einschraenken, bevor das hier online geht!
  if (($_SERVER['REMOTE_ADDR'] ?? '') !== '203.0.113.7') { http_response_code(404); exit; }
  $s = opcache_get_status(false);   // false: ohne Dateiliste
  echo $s === false ? "OPcache aus\n" : "OPcache an\n";

opcache_get_status() ohne das "false" liefert die absoluten Pfade jeder
gecachten Datei — also Verzeichnisstruktur, Plugins und Versionsstaende.
Eine solche Datei gehoert nie ungeschuetzt in den Web-Root.
HINT
    exit 69
fi

echo "Gemessene SAPI: ${FPM_BIN}"
echo

FPM_INI=$("${FPM_BIN}" -i 2>/dev/null)

# Debian/Ubuntu nennen die Binary php-fpm8.3, den Dienst aber php8.3-fpm.
FPM_VERSION=$(printf '%s\n' "${FPM_BIN##*/}" | sed -n 's/^php-fpm\([0-9.]\+\)$/\1/p')
if [[ -n "${FPM_VERSION}" ]]; then
    FPM_SERVICE="php${FPM_VERSION}-fpm"
else
    FPM_SERVICE="php-fpm"
fi

ini_value() {
    printf '%s\n' "${FPM_INI}" | awk -v key="$1" -F' => ' \
        '$1 == key { print $2; exit }'
}

ENABLED=$(ini_value "opcache.enable")
MEMORY=$(ini_value "opcache.memory_consumption")
MAX_FILES=$(ini_value "opcache.max_accelerated_files")
INTERNED=$(ini_value "opcache.interned_strings_buffer")
VALIDATE_TS=$(ini_value "opcache.validate_timestamps")
REVALIDATE=$(ini_value "opcache.revalidate_freq")
JIT=$(ini_value "opcache.jit")

echo "1. Grundeinstellungen"
echo "   opcache.enable                  = ${ENABLED:-?}"
echo "   opcache.memory_consumption      = ${MEMORY:-?}"
echo "   opcache.interned_strings_buffer = ${INTERNED:-?}"
echo "   opcache.max_accelerated_files   = ${MAX_FILES:-?}"
echo "   opcache.validate_timestamps     = ${VALIDATE_TS:-?}"
echo "   opcache.revalidate_freq         = ${REVALIDATE:-?}"
echo "   opcache.jit                     = ${JIT:-?}"

PROBLEMS=0

echo
echo "2. Bewertung fuer Shopware 6.6"

if [[ "${ENABLED}" != "On" && "${ENABLED}" != "1" ]]; then
    echo "   OPcache ist AUS. Das ist mit Abstand der groesste Hebel hier."
    PROBLEMS=$((PROBLEMS + 1))
else
    echo "   OPcache ist an."
fi

# memory_consumption kommt als reine Zahl in MB.
if [[ "${MEMORY}" =~ ^[0-9]+$ ]] && [[ "${MEMORY}" -lt 256 ]]; then
    echo "   memory_consumption ${MEMORY} MB — fuer Shopware plus Plugins knapp, 256 MB sind ueblich."
    PROBLEMS=$((PROBLEMS + 1))
fi

if [[ "${INTERNED}" =~ ^[0-9]+$ ]] && [[ "${INTERNED}" -lt 16 ]]; then
    echo "   interned_strings_buffer ${INTERNED} MB — 16 MB sind fuer Shopware ueblich."
    PROBLEMS=$((PROBLEMS + 1))
fi

if [[ "${MAX_FILES}" =~ ^[0-9]+$ ]] && [[ "${MAX_FILES}" -lt 20000 ]]; then
    echo "   max_accelerated_files ${MAX_FILES} — Shopware plus Plugins liegt schnell darueber."
    echo "   PHP rundet den Wert auf die naechstgroessere Zahl einer festen Reihe auf"
    echo "   (223, 463, 983, 1979, 3907, 7963, 16229, 32531, 65407, ...). Der"
    echo "   konfigurierte Wert ist also nicht der wirksame; opcache_get_status()"
    echo "   zeigt den echten unter opcache_statistics.max_cached_keys."
    PROBLEMS=$((PROBLEMS + 1))
fi

if [[ "${VALIDATE_TS}" == "On" || "${VALIDATE_TS}" == "1" ]]; then
    echo "   validate_timestamps ist an — PHP prueft bei jedem Request die Dateizeiten."
    echo "   In Produktion auf 0 setzen, ABER nur zusammen mit einem Reset im Deployment:"
    echo "     systemctl reload ${FPM_SERVICE}   (oder cachetool opcache:reset --fcgi=...)"
    echo "   Ohne diesen Schritt laeuft nach einem Deploy weiter der alte Code."
    PROBLEMS=$((PROBLEMS + 1))
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${PROBLEMS}" -eq 0 ]]; then
    echo "OPcache ist aktiv und fuer Shopware brauchbar konfiguriert."
    exit 0
fi

echo "${PROBLEMS} Punkt(e) zu verbessern. Vorlage: config/php-opcache.ini"
echo
cat <<'EOF'
; /etc/php/8.3/fpm/conf.d/99-shopware-opcache.ini
; (nicht 10-opcache.ini — das ist der Symlink der Distribution)
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=32531

; Produktion: keine Dateisystem-Checks.
; Erfordert einen OPcache-Reset im Deployment, siehe oben.
opcache.validate_timestamps=0

; opcache.enable_cli bleibt aus. Die CLI startet je Aufruf einen neuen
; Prozess; der Cache waere beim Beenden wieder weg und kostet nur Speicher.
EOF
echo
echo "Danach: systemctl reload ${FPM_SERVICE}"
exit 1
