#!/usr/bin/env bash
#
# audit-themes.sh
#
# Problem 16: Theme-Probleme (Vererbungstiefe, Altlasten, grosse Bundles).
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Dieses Skript aendert nichts. Das ist keine Selbstverstaendlichkeit: ein
# "theme:compile" zur Messung der Kompilierzeit loescht ohne -k die
# vorhandenen Theme-Assets und erzeugt sie neu. Auf einem Live-Shop laufen in
# diesem Fenster alle Requests auf die alten Asset-Pfade ins Leere. Ein
# Diagnose-Skript hat das nicht zu tun.
#
# "theme:dump" taugt uebrigens nicht zur Vererbungsanalyse: der Befehl
# schreibt var/theme-files.json und gibt eine einzige Zeile aus. Die
# Vererbung steht in der Datenbank (theme.parent_theme_id).
#
# Verwendung:
#   ./audit-themes.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = nichts Auffaelliges
#   1 = Auffaelligkeiten gefunden
#   64 = Aufruffehler
#   69 = mysql-Client fehlt

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: audit-themes.sh [SHOP_URL] [SHOP_PATH]

Zeigt Themes, ihre Vererbung, die Zuordnung zu Sales Channels und die
Groesse der kompilierten Assets. Aendert nichts.

Argumente:
  SHOP_URL    Wird nicht ausgewertet; nur der Einheitlichkeit halber.
  SHOP_PATH   Wurzel der Shopware-Installation. Default: aktuelles Verzeichnis

Die Datenbank-Zugangsdaten werden aus DATABASE_URL in .env/.env.local gelesen.
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
# Dieses Skript braucht nur den Pfad; $1 wird bewusst nicht ausgewertet,
# damit run-all-diagnostics.sh alle Skripte gleich aufrufen kann.
SHOP_PATH="${2:-.}"

if ! command -v mysql >/dev/null 2>&1; then
    echo "mysql-Client wird benoetigt." >&2
    exit 69
fi

DB_URL=""
for f in "${SHOP_PATH}/.env" "${SHOP_PATH}/.env.local"; do
    [[ -f "$f" ]] || continue
    line=$(grep -E '^DATABASE_URL=' "$f" | tail -1 || true)
    [[ -n "${line}" ]] && DB_URL="${line#DATABASE_URL=}"
done
DB_URL="${DB_URL%\"}"; DB_URL="${DB_URL#\"}"

if [[ -z "${DB_URL}" ]]; then
    echo "Keine DATABASE_URL in ${SHOP_PATH}/.env gefunden." >&2
    exit 1
fi

# mysql://user:pass@host:port/name
# Benutzerteil am LETZTEN @ abtrennen: ein "@" im Passwort ist in der
# DSN prozentkodiert, manche Installationen schreiben es aber roh.
DB_REST="${DB_URL#*://}"
DB_CRED="${DB_REST%@*}"
DB_HOSTPART="${DB_REST##*@}"
DB_USER="${DB_CRED%%:*}"
DB_PASS="${DB_CRED#*:}"
# Prozentkodierung aufloesen (@ : / # stehen als %40 %3A %2F %23).
urldecode() { printf '%b' "${1//%/\\x}"; }
DB_USER=$(urldecode "${DB_USER}")
DB_PASS=$(urldecode "${DB_PASS}")
DB_HOSTPORT="${DB_HOSTPART%%/*}"
DB_NAME="${DB_HOSTPART#*/}"
DB_NAME="${DB_NAME%%\?*}"
DB_HOST="${DB_HOSTPORT%%:*}"
DB_PORT="${DB_HOSTPORT#*:}"
[[ "${DB_PORT}" == "${DB_HOST}" ]] && DB_PORT=3306

q() {
    MYSQL_PWD="${DB_PASS}" mysql --default-character-set=utf8mb4 -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -N -B "${DB_NAME}" -e "$1" 2>/dev/null
}

echo "=== Problem 16: Themes ==="
echo

ISSUES=0

echo "1. Themes und Vererbung"
THEMES=$(q "
SELECT t.technical_name, t.name, t.active,
       COALESCE(p.technical_name, p.name, '-') AS parent
FROM theme t
LEFT JOIN theme p ON p.id = t.parent_theme_id
ORDER BY t.technical_name;")

if [[ -z "${THEMES}" ]]; then
    echo "   Keine Themes gefunden — stimmen die Zugangsdaten?"
    exit 1
fi
printf '   %-28s %-34s %-7s %s\n' "TECHNISCHER NAME" "NAME" "AKTIV" "ERBT VON"
while IFS=$'\t' read -r tech name active parent; do
    printf '   %-28s %-34s %-7s %s\n' "${tech:-(ohne)}" "${name:0:32}" "${active}" "${parent}"
done <<< "${THEMES}"

# Vererbungstiefe: laengste Kette ueber parent_theme_id.
DEPTH=$(q "
SELECT MAX(d) FROM (
  SELECT 1 AS d FROM theme WHERE parent_theme_id IS NULL
  UNION ALL
  SELECT 2 FROM theme a JOIN theme b ON a.parent_theme_id = b.id WHERE b.parent_theme_id IS NULL
  UNION ALL
  SELECT 3 FROM theme a JOIN theme b ON a.parent_theme_id = b.id
                        JOIN theme c ON b.parent_theme_id = c.id WHERE c.parent_theme_id IS NULL
  UNION ALL
  SELECT 4 FROM theme a JOIN theme b ON a.parent_theme_id = b.id
                        JOIN theme c ON b.parent_theme_id = c.id
                        JOIN theme d ON c.parent_theme_id = d.id
) x;")
echo
echo "   Groesste Vererbungstiefe: ${DEPTH:-1}"
if [[ "${DEPTH:-1}" -ge 4 ]]; then
    echo "   Ab vier Ebenen wird die Kompilierung spuerbar langsamer, und die"
    echo "   Herkunft einer SCSS-Variablen ist kaum noch nachvollziehbar."
    ISSUES=$((ISSUES + 1))
fi

echo
echo "2. Zuordnung zu Sales Channels"
ASSIGN=$(q "
SELECT COALESCE(t.technical_name, t.name), COUNT(tsc.sales_channel_id)
FROM theme t
LEFT JOIN theme_sales_channel tsc ON tsc.theme_id = t.id
GROUP BY t.id, t.technical_name, t.name
ORDER BY 2 DESC;")
UNUSED=0
while IFS=$'\t' read -r tech count; do
    if [[ "${count}" -eq 0 ]]; then
        printf '   %-34s keinem Sales Channel zugewiesen\n' "${tech}"
        UNUSED=$((UNUSED + 1))
    else
        printf '   %-34s %s Sales Channel(s)\n' "${tech}" "${count}"
    fi
done <<< "${ASSIGN}"
if [[ "${UNUSED}" -gt 0 ]]; then
    echo "   ${UNUSED} Theme(s) ohne Zuweisung. Sie kosten keine Laufzeit, werden"
    echo "   aber bei jedem theme:compile mitgebaut."
    ISSUES=$((ISSUES + 1))
fi

echo
echo "3. Kompilierte Assets unter public/theme/"
THEME_DIR="${SHOP_PATH}/public/theme"
if [[ ! -d "${THEME_DIR}" ]]; then
    echo "   Verzeichnis fehlt — wurde nie kompiliert?"
    ISSUES=$((ISSUES + 1))
else
    DIRS=$(find "${THEME_DIR}" -mindepth 1 -maxdepth 1 -type d | sort)
    DIR_COUNT=$(printf '%s\n' "${DIRS}" | grep -c . || true)
    TOTAL_SIZE=$(du -sh "${THEME_DIR}" 2>/dev/null | cut -f1)
    echo "   Verzeichnisse: ${DIR_COUNT}, Gesamtgroesse: ${TOTAL_SIZE}"

    # Welcher Hash wird aktuell ausgeliefert?
    ACTIVE_HASH=""
    if [[ -f "${SHOP_PATH}/public/index.php" ]]; then
        ACTIVE_HASH=$(find "${THEME_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2)
    fi
    [[ -n "${ACTIVE_HASH}" ]] && echo "   Zuletzt geschrieben: ${ACTIVE_HASH}"

    ASSIGNED=$(q "SELECT COUNT(DISTINCT sales_channel_id) FROM theme_sales_channel;")
    ASSIGNED="${ASSIGNED:-0}"
    if [[ "${DIR_COUNT}" -gt $((ASSIGNED + 1)) ]]; then
        echo "   Mehr Asset-Verzeichnisse (${DIR_COUNT}) als zugewiesene Sales Channels"
        echo "   (${ASSIGNED}). Die ueberzaehligen stammen aus frueheren Kompilierungen"
        echo "   und werden nicht mehr ausgeliefert — sie belegen nur Platz."
        ISSUES=$((ISSUES + 1))
    fi

    echo
    echo "   Groesste Einzeldateien:"
    # head am Ende einer langen Pipeline schickt sort ein SIGPIPE; unter
    # "set -euo pipefail" bricht das Skript dann mit 141 ab, bevor das
    # Ergebnis steht. Deshalb erst vollstaendig sortieren, dann kuerzen.
    THEME_FILES=$(find "${THEME_DIR}" -type f \( -name '*.css' -o -name '*.js' \) \
        -printf '%s %p\n' 2>/dev/null | sort -rn || true)
    printf '%s\n' "${THEME_FILES}" | head -5 | while read -r bytes path; do
        [[ -z "${bytes}" ]] && continue
        printf '     %6s KB  %s\n' "$(( bytes / 1024 ))" "${path#"${THEME_DIR}"/}"
    done
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Bei den Themes faellt nichts auf."
    exit 0
fi

cat <<'EOF'
Ansatzpunkte — mit den Befehlen, die es wirklich gibt:

  Theme eines Sales Channels wechseln. Der Sales Channel ist eine OPTION,
  kein zweites Argument; "theme:change Storefront <id>" bricht mit
  "Too many arguments" ab:

    bin/console theme:change Storefront --sales-channel=<SALES_CHANNEL_ID>
    bin/console theme:change Storefront --all

  Ein Theme entfernt man nicht mit theme:change, sondern ueber sein Plugin:

    bin/console plugin:deactivate <ThemePlugin>
    bin/console plugin:uninstall <ThemePlugin>
    bin/console theme:refresh

  Neu kompilieren. Die Option heisst --keep-assets (kurz -k), nicht
  --keep-all; letztere existiert nicht:

    bin/console theme:compile --keep-assets --sync

  Das -k ueberspringt den Asset-Schritt ganz: public/theme/<theme-id>/ wird
  weder geloescht noch neu befuellt. Ohne -k loescht der Befehl das
  Verzeichnis zuerst und schreibt es dann neu — in diesem Fenster laufen
  Schrift- und Icon-Requests ins Leere. Wer an den Assets etwas geaendert
  hat, muss also ohne -k kompilieren, am besten ausserhalb der Stosszeit.
  Das kompilierte CSS/JS ist davon nicht betroffen: es landet ohnehin unter
  einem neuen Seed-Pfad. Das --sync erzwingt die synchrone Kompilierung;
  ohne das laeuft sie je nach Systemeinstellung
  core.storefrontSettings.asyncThemeCompilation ueber die Queue und braucht
  einen laufenden Worker.

  Kurz: -k ist schnell und beruehrt die Assets nicht, ohne -k werden sie
  neu geschrieben — mit einer Luecke dazwischen.
EOF
exit 1
