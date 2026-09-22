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
# Dieses Skript liest deshalb primaer "php-fpm<version> -i". Drei Grenzen
# davon faengt es selbst ab (MEM-293):
#   - Ist die Erweiterung gar nicht geladen (z. B. nach einem cp auf
#     10-opcache.ini), liefert -i KEINE opcache-Zeile, nicht "Off". Deshalb
#     zuerst "php-fpm -m".
#   - Eine conf.d-Datei, die der aufrufende Benutzer nicht lesen kann (0600),
#     laesst -i still aus und meldet Vorgabewerte. Das Skript bricht dann mit
#     Exit 77 ab, statt falsche Befunde zu melden.
#   - -i zeigt den EINGETRAGENEN Wert. Was wirklich gilt (gerundetes
#     max_accelerated_files, laeuft der JIT?), zeigt nur ein echter Request.
#     Ist cgi-fcgi installiert und der Socket erreichbar, stellt das Skript
#     einen (FPM_SOCKET, Vorgabe /run/php/php<version>-fpm-shopware.sock).
#
# Verwendung:
#   ./check-opcache.sh [SHOP_URL] [SHOP_PATH]
#   PHP_FPM_BINARY=php-fpm8.3 ./check-opcache.sh
#   sudo FPM_SOCKET=/run/php/php8.3-fpm-shopware.sock ./check-opcache.sh
#
# Exit-Codes:
#   0 = OPcache aktiv und brauchbar konfiguriert
#   1 = OPcache aus oder Einstellungen fuer Shopware zu knapp
#   64 = Aufruffehler
#   69 = keine FPM-Binary gefunden, Pruefung nicht moeglich
#   77 = eine conf.d-Datei ist fuer diesen Benutzer nicht lesbar - mit sudo
#        erneut aufrufen

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
  FPM_SOCKET      Optional. Socket des Shop-Pools fuer die Laufzeitmessung
                  (braucht cgi-fcgi). Vorgabe: /run/php/php<version>-fpm-shopware.sock

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

# Ohne geladene Erweiterung gibt -i keine einzige opcache-Zeile aus - ein
# grep darauf bleibt leer statt "Off" zu melden (MEM-293).
FPM_MODULES=$("${FPM_BIN}" -m 2>/dev/null || true)
if ! grep -q '^Zend OPcache$' <<< "${FPM_MODULES}"; then
    echo "OPcache ist in ${FPM_BIN} gar nicht geladen ('-m' nennt kein 'Zend OPcache')."
    echo "Haeufigste Ursache: eine eigene Datei wurde nach conf.d/10-opcache.ini"
    echo "kopiert und hat die Zeile zend_extension=opcache.so ueberschrieben."
    echo "Den Reparaturweg beschreibt Kapitel 9 (99-shopware-opcache.ini, Kopf)."
    exit 1
fi

FPM_INI=$("${FPM_BIN}" -i 2>/dev/null)

# conf.d-Dateien, die dieser Benutzer nicht lesen kann, laesst -i ohne
# Meldung aus - die Werte unten waeren dann Vorgaben, nicht Ihre.
SCAN_DIR=$(printf '%s\n' "${FPM_INI}" | sed -n 's/^Scan this dir for additional .ini files => //p')
if [[ -n "${SCAN_DIR}" && -d "${SCAN_DIR}" ]]; then
    UNREADABLE=()
    for f in "${SCAN_DIR}"/*.ini; do
        [[ -e "${f}" && ! -r "${f}" ]] && UNREADABLE+=("${f}")
    done
    if [[ ${#UNREADABLE[@]} -gt 0 ]]; then
        echo "Als $(id -un) nicht lesbar - ${FPM_BIN} -i laesst diese Dateien still aus:"
        printf '  %s\n' "${UNREADABLE[@]}"
        echo "Die Werte waeren Vorgaben, nicht Ihre Konfiguration. Mit sudo erneut aufrufen."
        exit 77
    fi
fi

# Debian/Ubuntu nennen die Binary php-fpm8.3, den Dienst aber php8.3-fpm.
FPM_VERSION=$(printf '%s\n' "${FPM_BIN##*/}" | sed -n 's/^php-fpm\([0-9.]\+\)$/\1/p')
if [[ -n "${FPM_VERSION}" ]]; then
    FPM_SERVICE="php${FPM_VERSION}-fpm"
else
    FPM_SERVICE="php-fpm"
fi

ini_value() {
    # Kein exit im awk: Er liest bis zum Ende, sonst stirbt printf an
    # SIGPIPE und pipefail beendet das Skript still (rc 141).
    printf '%s\n' "${FPM_INI}" | awk -v key="$1" -F' => ' \
        '$1 == key && !found { print $2; found = 1 }'
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

if [[ "${INTERNED}" =~ ^[0-9]+$ ]] && [[ "${INTERNED}" -lt 20 ]]; then
    echo "   interned_strings_buffer ${INTERNED} MB — Shopwares Performance-Doku empfiehlt 20 MB."
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
echo "3. Laufzeit (echter Request)"
FPM_SOCKET="${FPM_SOCKET:-/run/php/php${FPM_VERSION:-}-fpm-shopware.sock}"
if ! command -v cgi-fcgi >/dev/null 2>&1; then
    echo "   uebersprungen: cgi-fcgi fehlt (Paket libfcgi-bin)."
    echo "   -i zeigt nur eingetragene Werte: gerundetes max_accelerated_files und"
    echo "   den JIT-Zustand liefert opcache_get_status(false) in einem Request."
elif [[ ! -e "${FPM_SOCKET}" || ! -w "${FPM_SOCKET}" ]]; then
    echo "   uebersprungen: Socket ${FPM_SOCKET} fehlt oder ist fuer $(id -un)"
    echo "   nicht beschreibbar (FPM_SOCKET setzen, ggf. mit sudo)."
else
    PROBE=$(mktemp --suffix=.php)
    trap 'rm -f "${PROBE}"' EXIT
    chmod 644 "${PROBE}"
    cat > "${PROBE}" <<'PHP'
<?php
$s = function_exists('opcache_get_status') ? opcache_get_status(false) : false;
// Schaltet der Pool OPcache ab (php_admin_value[opcache.enable] = 0), kommt
// trotzdem ein Array zurueck - nur mit opcache_enabled = false.
$on = is_array($s) && !empty($s['opcache_enabled']);
echo 'RT OPCACHE=', $on ? 1 : 0,
     ' JIT=', ($s['jit']['enabled'] ?? false) ? 1 : 0,
     ' KEYS=', $s['opcache_statistics']['max_cached_keys'] ?? 0, "\n";
PHP
    # timeout: Ist der Pool voll ausgelastet, wartet cgi-fcgi sonst unbegrenzt.
    RT=$(SCRIPT_FILENAME="${PROBE}" SCRIPT_NAME=/check-opcache.php REQUEST_METHOD=GET \
         timeout 10 cgi-fcgi -bind -connect "${FPM_SOCKET}" 2>/dev/null | tr -d '\r' | grep '^RT ' || true)
    if [[ -z "${RT}" ]]; then
        echo "   keine Antwort ueber ${FPM_SOCKET} - Laufzeitwerte unbekannt."
    else
        RT_OPCACHE=$(sed -n 's/.*OPCACHE=\([01]\).*/\1/p' <<< "${RT}")
        RT_JIT=$(sed -n 's/.*JIT=\([01]\).*/\1/p' <<< "${RT}")
        RT_KEYS=$(sed -n 's/.*KEYS=\([0-9]*\).*/\1/p' <<< "${RT}")
        echo "   OPcache im Request:      $([[ "${RT_OPCACHE}" == 1 ]] && echo an || echo AUS)"
        echo "   JIT im Request:          $([[ "${RT_JIT}" == 1 ]] && echo an || echo aus)"
        echo "   max_cached_keys (wirksam): ${RT_KEYS}"
        if [[ "${RT_OPCACHE}" != 1 ]]; then
            echo "   OPcache arbeitet in diesem Pool nicht (opcache_enabled = false),"
            echo "   egal was -i meldet - z. B. php_admin_value[opcache.enable] = 0 im Pool."
            PROBLEMS=$((PROBLEMS + 1))
        fi
    fi
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${PROBLEMS}" -eq 0 ]]; then
    echo "OPcache ist aktiv und fuer Shopware brauchbar konfiguriert."
    exit 0
fi

echo "${PROBLEMS} Punkt(e) zu verbessern."
echo
cat <<'EOF'
Die Vorlage liegt bei Kapitel 9, das OPcache erklaert — dieses Kapitel
haelt keine zweite Fassung, damit beide nicht auseinanderlaufen:

  chapters/09-php-performance/config/99-shopware-opcache.ini

Sie ist kommentiert und begruendet jeden Wert. Zielpfad:

; /etc/php/8.3/fpm/conf.d/99-shopware-opcache.ini
; (nicht 10-opcache.ini — das ist der Symlink der Distribution und traegt
;  als einziger zend_extension=opcache.so)
EOF
echo
echo "Danach: systemctl reload ${FPM_SERVICE}"
exit 1
