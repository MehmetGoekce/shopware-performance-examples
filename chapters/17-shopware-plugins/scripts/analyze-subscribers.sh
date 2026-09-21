#!/usr/bin/env bash
#
# Event-Listener je Namespace zählen - aus dem kompilierten Container.
#
# Quelle ist "bin/console debug:event-dispatcher --format=json": dieselben
# Listener, die Shopware zur Laufzeit aufruft, mit Priorität. Gezählt
# wird je Namespace (erste zwei Segmente, z. B. "Swag\PayPal").
#
# Die Zahl ist eine Orientierung, keine Messung: Ein Listener, der
# sofort zurückkehrt, kostet fast nichts, ein einziger mit einer
# Datenbankabfrage je Aufruf viel. Was ein Plugin wirklich kostet,
# zeigt profile-plugin.sh (mit/ohne) oder ein Profiler.
#
# Getestet gegen Shopware 6.6.10.6 (Dockware).
#
# @see Kapitel 17, "Subscriber-Analyse"

set -euo pipefail

SHOPWARE_ROOT="${SHOPWARE_ROOT:-/var/www/html}"
CONSOLE="${CONSOLE:-${SHOPWARE_ROOT}/bin/console}"
PHP="${PHP:-php}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [namespace]

Ohne Argument: Listener je Namespace, absteigend.
Mit Namespace (z. B. Swag\\\\PayPal): dessen Listener mit Event und Priorität.

Umgebungsvariablen:
  SHOPWARE_ROOT  Shopware-Verzeichnis (Vorgabe: /var/www/html)

Exit-Codes: 0 ok, 1 Fehler, 2 falscher Aufruf
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
esac

# Erst vollständig lesen, dann auswerten: kein Abbruch mitten in einer Pipe
if ! JSON="$("$CONSOLE" debug:event-dispatcher --format=json 2>/dev/null)"; then
    echo "Fehler: debug:event-dispatcher ist fehlgeschlagen." >&2
    exit 1
fi

printf '%s' "$JSON" | "$PHP" -r '
    $filter = $argv[1] ?? "";
    $events = json_decode(stream_get_contents(STDIN), true);
    if (!is_array($events)) {
        fwrite(STDERR, "Fehler: keine gültige JSON-Ausgabe.\n");
        exit(1);
    }

    $counts = [];
    $rows = [];
    foreach ($events as $event => $listeners) {
        foreach ($listeners as $l) {
            $class = $l["class"] ?? "(Closure)";
            $parts = explode("\\", $class);
            $ns = implode("\\", array_slice($parts, 0, 2));
            $counts[$ns] = ($counts[$ns] ?? 0) + 1;
            if ($filter !== "" && str_starts_with($class, $filter)) {
                $rows[] = sprintf("%6d  %-45s %s::%s", $l["priority"] ?? 0, $event, $class, $l["name"] ?? "?");
            }
        }
    }

    if ($filter !== "") {
        if ($rows === []) {
            fwrite(STDERR, "Keine Listener für $filter.\n");
            exit(1);
        }
        echo "Priorität  Event / Listener\n";
        echo implode("\n", $rows), "\n";
        exit(0);
    }

    arsort($counts);
    printf("%-40s %s\n", "Namespace", "Listener");
    foreach ($counts as $ns => $n) {
        printf("%-40s %d\n", $ns, $n);
    }
    printf("\n%d Listener auf %d Events\n", array_sum($counts), count($events));
' "${1:-}"
