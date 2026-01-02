#!/bin/bash
#
# [SCRIPT_NAME] - [KURZE_BESCHREIBUNG]
#
# [LÄNGERE_BESCHREIBUNG]
#
# Verwendung:
#   ./[script-name].sh --option1 value
#   ./[script-name].sh --test
#
# Voraussetzungen:
#   - [VORAUSSETZUNG_1]
#   - [VORAUSSETZUNG_2]
#
# Umgebungsvariablen:
#   [VAR_NAME]  [BESCHREIBUNG]

set -euo pipefail

# Konfiguration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Farben
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging-Funktionen
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Hilfe anzeigen
usage() {
    cat << EOF
Verwendung: $SCRIPT_NAME [OPTIONEN]

[BESCHREIBUNG]

Optionen:
  --option1 <value>   [BESCHREIBUNG]
  --test              Testmodus (keine Änderungen)
  --verbose           Ausführliche Ausgabe
  -h, --help          Diese Hilfe anzeigen

Beispiele:
  $SCRIPT_NAME --option1 value
  $SCRIPT_NAME --test --verbose

EOF
    exit 0
}

# Argumente parsen
parse_args() {
    OPTION1=""
    TEST_MODE=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --option1)
                OPTION1="$2"
                shift 2
                ;;
            --test)
                TEST_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unbekannte Option: $1"
                usage
                ;;
        esac
    done
}

# Voraussetzungen prüfen
check_requirements() {
    local missing=()

    # Beispiel: Prüfen ob curl installiert ist
    command -v curl >/dev/null 2>&1 || missing+=("curl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Fehlende Abhängigkeiten: ${missing[*]}"
        exit 1
    fi
}

# Hauptfunktion
main() {
    log_info "Starte $SCRIPT_NAME..."

    if $TEST_MODE; then
        log_warn "Testmodus aktiv - keine Änderungen werden durchgeführt"
    fi

    # TODO: Implementierung hier

    log_success "Fertig!"
}

# Cleanup bei Abbruch
cleanup() {
    log_info "Aufräumen..."
    # TODO: Cleanup-Logik
}
trap cleanup EXIT

# Script starten
parse_args "$@"
check_requirements
main
