#!/usr/bin/env bash
#
# profile-cart.sh
#
# Problem 9: Grosse Warenkorb-Berechnungen.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Zum Datenmodell, weil hier viel Falsches kursiert:
#
#   Die Tabelle "rule" hat KEINE Spalte "active". Ihre Spalten sind id, name,
#   description, priority, payload, invalid, areas, module_types,
#   custom_fields, created_at, updated_at. Es gibt also auch keinen
#   Aktiv/Inaktiv-Schalter fuer Regeln in der Administration, und
#   "DELETE FROM rule WHERE active = 0" ist schlicht ungueltiges SQL.
#
#   Was der RuleLoader wirklich laedt: alle Regeln mit invalid = 0 und einem
#   nicht leeren payload. Die 500 in RuleLoader.php sind die Seitengroesse
#   eines RepositoryIterator, keine Obergrenze — die Schleife holt Seite um
#   Seite, bis eine Seite weniger als 500 Treffer liefert. Es faellt nichts
#   unter den Tisch.
#
#   Und: Regeln loescht man nicht per SQL. 14 Fremdschluessel zeigen auf die
#   Tabelle, sieben davon mit ON DELETE RESTRICT (Produktpreise, Versand- und
#   Zahlarten, Steuerdienstleister, Flows). Ein Massen-DELETE bricht deshalb
#   fuer das ganze Statement ab. Die sieben CASCADE-Beziehungen — fuenf
#   Promotion-Zuordnungen sowie rule_condition und rule_tag — wuerden
#   dagegen still mitloeschen, was daran haengt.
#
# Dieses Skript misst und zaehlt. Es aendert nichts.
#
# Verwendung:
#   ./profile-cart.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = nichts Auffaelliges
#   1 = Auffaelligkeiten gefunden
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: profile-cart.sh [SHOP_URL] [SHOP_PATH]

Misst die Antwortzeit der Warenkorbseite und zaehlt, wie viele Regeln und
Promotions bei jeder Warenkorbberechnung ausgewertet werden.

Argumente:
  SHOP_URL    Basis-URL des Shops. Default: http://localhost
  SHOP_PATH   Wurzel der Shopware-Installation (fuer die Datenbankabfragen).
              Default: aktuelles Verzeichnis

Umgebungsvariablen:
  ROUNDS      Messrunden fuer die Antwortzeit. Default: 5
  CART_MS     Ab dieser Zeit gilt die Warenkorbseite als langsam. Default: 500
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

SHOP_URL="${1:-http://localhost}"
SHOP_URL="${SHOP_URL%/}"
SHOP_PATH="${2:-.}"

# >>> dotenv_get (wortgleich in allen Skripten dieses Kapitels, siehe BATS)
# Liest eine Variable so, wie Symfonys Dotenv::bootEnv() sie fuer die CLI
# (bin/console) ermittelt. Setzt DOTENV_VALUE und DOTENV_SOURCE; beide leer,
# wenn die Variable nirgends steht. Reihenfolge (symfony/dotenv 7.2-7.4):
#   1. Umgebung dieses Aufrufs — schlaegt jede Datei.
#   2. .env.local.php (composer dump-env) — ersetzt ALLE .env-Dateien,
#      ausser die Umgebung setzt ein anderes APP_ENV als die Datei.
#   3. .env, .env.local, .env.<APP_ENV>, .env.<APP_ENV>.local; die spaetere
#      Datei gewinnt, auch fuer APP_ENV selbst. Die Dateiwahl folgt dem
#      APP_ENV nach .env/.env.local (ohne Angabe: dev); bei APP_ENV=test
#      entfaellt .env.local. Ohne .env, .env.dist und .env.local.php liest
#      Shopware gar keine Datei.
# DOTENV_NOTE ist gesetzt, wenn der Wert nicht sicher ist (Text: dotenv_note):
# "Verweis" = $VAR/${VAR} in der Datei, den Symfony einsetzt, diese Funktion
# nicht; "Format" = .env.local.php nicht im Format von composer dump-env.
# Eine vorhandene, aber nicht lesbare Datei beendet das Skript mit Exit 69.
# Die Umgebung des Webservers (FPM env[], Apache SetEnv, nginx fastcgi_param)
# sieht diese Funktion nicht; sie schlaegt im Web ebenfalls jede Datei.
dotenv_get() {
    local name="$1" root="${SHOP_PATH:-.}" f env_name line php_env
    DOTENV_VALUE="" DOTENV_SOURCE="" DOTENV_NOTE=""
    if line=$(printenv "$name"); then
        DOTENV_VALUE="$line" DOTENV_SOURCE="Umgebung"
        return 0
    fi
    if [[ -f "$root/.env.local.php" ]]; then
        dotenv_need "$root/.env.local.php"
        php_env=$(dotenv_php_value "$root/.env.local.php" APP_ENV)
        if ! env_name=$(printenv APP_ENV) || [[ -z "$php_env" || "$env_name" == "$php_env" ]]; then
            if grep -qE "^[[:space:]]*'${name}'[[:space:]]*=>" "$root/.env.local.php"; then
                DOTENV_SOURCE=".env.local.php"
                if grep -qE "^[[:space:]]*'${name}'[[:space:]]*=>[[:space:]]*'" "$root/.env.local.php"; then
                    DOTENV_VALUE=$(dotenv_php_value "$root/.env.local.php" "$name")
                else
                    DOTENV_NOTE="Format"
                fi
            fi
            return 0
        fi
    fi
    [[ -f "$root/.env" || -f "$root/.env.dist" ]] || return 0
    f="$root/.env"; [[ -f "$f" ]] || f="$root/.env.dist"
    dotenv_need "$f"
    env_name=$(printenv APP_ENV) || env_name=$(dotenv_file_value "$f" APP_ENV)
    local files=("$f")
    if [[ "${env_name:-dev}" != "test" && -f "$root/.env.local" ]]; then
        dotenv_need "$root/.env.local"
        files+=("$root/.env.local")
        printenv APP_ENV >/dev/null || env_name=$(dotenv_file_value "$root/.env.local" APP_ENV "$env_name")
    fi
    env_name="${env_name:-dev}"
    if [[ "$env_name" != "local" ]]; then
        files+=("$root/.env.$env_name" "$root/.env.$env_name.local")
    fi
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        dotenv_need "$f"
        if line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$f" | tail -n 1); then
            DOTENV_VALUE=$(dotenv_file_value "$f" "$name")
            DOTENV_SOURCE="${f##*/}"
            DOTENV_NOTE=""
            # In '...' setzt Symfony nichts ein, sonst schon.
            [[ "${line#*=}" != \'* && "$DOTENV_VALUE" == *'$'* ]] && DOTENV_NOTE="Verweis"
        fi
    done
    return 0
}
dotenv_need() {
    [[ -r "$1" ]] && return 0
    echo "Nicht lesbar: $1" >&2
    echo "Das Skript mit den Rechten des Shops starten, z. B. sudo -u www-data $0 ..." >&2
    exit 69
}
dotenv_note() {
    case "$DOTENV_NOTE" in
        Verweis) echo "enthaelt einen \$-Verweis, den Symfony einsetzt, dieses Skript nicht" ;;
        Format) echo "steht in .env.local.php nicht im Format von composer dump-env" ;;
    esac
}
# Letzte Zuweisung NAME=... einer .env-Datei; "export " davor erlaubt.
# Entfernt umschliessende Anfuehrungszeichen und einen Kommentar hinter
# einem Wert ohne Anfuehrungszeichen. ${VAR}-Verweise bleiben unaufgeloest.
# $3 = Rueckgabe, wenn die Datei die Variable nicht setzt.
dotenv_file_value() {
    local line v
    line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$1" | tail -n 1) || { printf '%s' "${3:-}"; return 0; }
    v="${line#*=}"
    case "$v" in
        \"*\"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*\'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *) v="${v%%[[:space:]]#*}"; v="${v%"${v##*[![:space:]]}"}" ;;
    esac
    printf '%s' "$v"
}
# Wert aus .env.local.php (var_export-Format von composer dump-env).
dotenv_php_value() {
    grep -E "^[[:space:]]*'$2'[[:space:]]*=>" "$1" | tail -n 1 \
        | sed -E "s/^[^=]*=>[[:space:]]*'(.*)',?[[:space:]]*$/\1/; s/\\\\'/'/g; s/\\\\\\\\/\\\\/g" || true
}
# <<< dotenv_get
ROUNDS="${ROUNDS:-5}"
CART_MS="${CART_MS:-500}"

COOKIE_JAR=$(mktemp)
trap 'rm -f "${COOKIE_JAR}"' EXIT

echo "=== Problem 9: Warenkorb-Berechnung ==="
echo

ISSUES=0

echo "1. Antwortzeit der Warenkorbseite (${ROUNDS} Runden, Median)"
# Mit Session, per GET. Ein HEAD-Request (curl -I) misst hier nichts
# Brauchbares: die Warenkorbberechnung laeuft, aber der Body entfaellt.
curl -sS -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -o /dev/null -L "${SHOP_URL}/" || {
    echo "   Shop nicht erreichbar: ${SHOP_URL}" >&2
    exit 1
}

measure_ms() {
    local url="$1" start end
    start=$(( $(date +%s%N) / 1000000 ))
    curl -sS -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" -o /dev/null -L "${url}"
    end=$(( $(date +%s%N) / 1000000 ))
    echo $(( end - start ))
}

TIMES=""
for _ in $(seq "${ROUNDS}"); do
    TIMES="${TIMES}$(measure_ms "${SHOP_URL}/checkout/cart")"$'\n'
done
CART_TIME=$(printf '%s' "${TIMES}" | sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }')

echo "   /checkout/cart: ${CART_TIME} ms"
if [[ "${CART_TIME}" -gt "${CART_MS}" ]]; then
    echo "   Ueber der Schwelle von ${CART_MS} ms."
    ISSUES=$((ISSUES + 1))
fi
echo "   Zum Vergleich die Startseite (die aus dem HTTP-Cache kommen kann):"
echo "   /: $(measure_ms "${SHOP_URL}/") ms"

# --- Datenbank ---
# DATABASE_URL wie bin/console sie sieht: Umgebung, .env.local.php, sonst
# .env-Dateien in Symfonys Reihenfolge (spaetere gewinnt).
dotenv_get DATABASE_URL
DB_URL="${DOTENV_VALUE}"
if [[ -n "${DOTENV_NOTE}" ]]; then
    # Die Datenbank ist hier optional: Abschnitt auslassen statt abbrechen.
    echo "DATABASE_URL (aus ${DOTENV_SOURCE}) $(dotenv_note) — Datenbank-Teil entfaellt." >&2
    echo "Den Wert als Umgebungsvariable mitgeben: DATABASE_URL='mysql://...' $0 ..." >&2
    DB_URL=""
fi

if [[ -z "${DB_URL}" ]] || ! command -v mysql >/dev/null 2>&1; then
    echo
    echo "2. Regeln und Promotions"
    echo "   Uebersprungen: keine DATABASE_URL oder kein mysql-Client."
else
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
    DB_NAME="${DB_HOSTPART#*/}"; DB_NAME="${DB_NAME%%\?*}"
    DB_HOST="${DB_HOSTPORT%%:*}"
    DB_PORT="${DB_HOSTPORT#*:}"
    [[ "${DB_PORT}" == "${DB_HOST}" ]] && DB_PORT=3306

    q() {
        MYSQL_PWD="${DB_PASS}" mysql --default-character-set=utf8mb4 -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -N -B "${DB_NAME}" -e "$1" 2>/dev/null
    }

    echo
    echo "2. Was bei jeder Warenkorbberechnung ausgewertet wird"
    RULES_TOTAL=$(q "SELECT COUNT(*) FROM rule;")
    RULES_LOADED=$(q "SELECT COUNT(*) FROM rule WHERE invalid = 0 AND payload IS NOT NULL;")
    CONDITIONS=$(q "SELECT COUNT(*) FROM rule_condition;")
    PROMOS=$(q "SELECT COUNT(*) FROM promotion WHERE active = 1;")
    PROMOS_AUTO=$(q "SELECT COUNT(*) FROM promotion WHERE active = 1 AND use_codes = 0;")

    echo "   Regeln insgesamt:                 ${RULES_TOTAL:-?}"
    echo "   davon vom RuleLoader geladen:     ${RULES_LOADED:-?}   (invalid = 0, payload gesetzt)"
    echo "   Bedingungen ueber alle Regeln:    ${CONDITIONS:-?}"
    echo "   Aktive Promotions:                ${PROMOS:-?}"
    echo "   davon ohne Gutscheincode:         ${PROMOS_AUTO:-?}   (werden immer geprueft)"

    if [[ "${RULES_LOADED:-0}" -gt 100 ]]; then
        echo "   Viele Regeln. Jede wird bei jeder Warenkorbaenderung ausgewertet."
        ISSUES=$((ISSUES + 1))
    fi

    if [[ "${PROMOS_AUTO:-0}" -gt 20 ]]; then
        echo "   Viele automatische Promotions. Anders als codebasierte werden sie"
        echo "   bei jeder Berechnung geprueft."
        ISSUES=$((ISSUES + 1))
    fi

    echo
    echo "3. Regeln mit den meisten Bedingungen"
    TOP=$(q "
    SELECT r.name, COUNT(rc.id) AS conditions
    FROM rule r LEFT JOIN rule_condition rc ON rc.rule_id = r.id
    GROUP BY r.id, r.name
    ORDER BY conditions DESC
    LIMIT 5;")
    if [[ -z "${TOP}" ]]; then
        echo "   (keine)"
    else
        while IFS=$'\t' read -r name cnt; do
            printf '   %-52s %s Bedingung(en)\n' "${name:0:52}" "${cnt}"
        done <<< "${TOP}"
    fi

    echo
    echo "4. Regeln, die niemand benutzt"
    ORPHANS=$(q "
    SELECT COUNT(*) FROM rule r
    WHERE NOT EXISTS (SELECT 1 FROM product_price pp WHERE pp.rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM shipping_method_price sp WHERE sp.rule_id = r.id OR sp.calculation_rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM shipping_method sm WHERE sm.availability_rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM payment_method pm WHERE pm.availability_rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM tax_provider tp WHERE tp.availability_rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM flow_sequence fs WHERE fs.rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM promotion_cart_rule pcr WHERE pcr.rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM promotion_order_rule por WHERE por.rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM promotion_persona_rule ppr WHERE ppr.rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM promotion_discount_rule pdr WHERE pdr.rule_id = r.id)
      AND NOT EXISTS (SELECT 1 FROM promotion_setgroup_rule psr WHERE psr.rule_id = r.id);")
    echo "   Ohne jede Zuordnung: ${ORPHANS:-?}"
    if [[ "${ORPHANS:-0}" -gt 0 ]]; then
        echo "   Diese Regeln werden trotzdem geladen und ausgewertet. Sie lassen"
        echo "   sich gefahrlos entfernen — ueber die Administration oder die DAL,"
        echo "   nicht per DELETE-Statement."
        ISSUES=$((ISSUES + 1))
    fi
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Bei der Warenkorbberechnung faellt nichts auf."
    exit 0
fi

cat <<'EOF'
Was hier wirklich hilft:

  1. Weniger Regeln laden. Der RuleLoader holt alle Regeln mit invalid = 0
     und nicht leerem payload — in Seiten zu 500, aber vollstaendig — und
     wertet sie bei jeder Warenkorbaenderung aus. Nicht mehr benutzte Regeln
     gehoeren weg.

     Aber nicht per SQL: 14 Fremdschluessel zeigen auf die Tabelle, sieben
     davon mit ON DELETE RESTRICT. Ein DELETE bricht fuer das ganze Statement
     ab, und rohes SQL invalidiert weder die DAL-Indizes noch den
     cart_rules-Cache. Der Weg fuehrt ueber die Administration oder ueber
     $ruleRepository->delete(); dort meldet Shopware saubere
     RestrictDeleteViolationExceptions statt eines Fehlercodes 1451.

  2. Bedingungen vereinfachen. Teuer sind vor allem Bedingungen, die den
     Warenkorb Position fuer Position durchgehen, und Vergleiche auf
     Custom Fields.

  3. Promotions mit Gutscheincode statt automatischer Promotions. Codebasierte
     Promotions werden nur geprueft, wenn ein Code eingegeben wurde.

  4. Im Profiler nachsehen, wie viele Regeln im aktuellen Kontext ueberhaupt
     greifen. Das Panel heisst "Rules" und zeigt die ANZAHL der passenden
     Regeln — eine Zeitmessung pro Regel gibt es dort nicht. Der Profiler
     braucht APP_ENV=dev und shopware/dev-tools.

  Regeln werden uebrigens gecacht (CachedRuleLoader, Cache-Key cart_rules).
  Das Problem sind nicht die Datenbankzugriffe, sondern das Auswerten der
  Bedingungen bei jeder Berechnung.
EOF
exit 1
