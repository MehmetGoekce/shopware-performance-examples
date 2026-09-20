#!/bin/bash
#
# Section 18.5 — Build the German word list for dictionary_decompounder.
#
# Source: LibreOffice dictionaries. Die Datei heisst dort de_DE_frami.dic,
# nicht de_DE.dic — letztere gibt es im Repo nicht (gemessen: HTTP 404).
# Im Ordner de/ liegen de_DE_frami.dic, de_AT_frami.dic, de_CH_frami.dic.
# Licence GPL/LGPL/MPL (multi) — shipping the word list as a deployment
# asset (not inside a plugin package) is fine, as no ES code is modified.
#
# DREI DINGE, die die erste Fassung dieses Skripts unbrauchbar machten, alle
# gegen die echte Quelldatei gemessen:
#
# 1. DIE QUELLE IST NICHT UTF-8. de_DE_frami.dic ist ISO-8859-1 (file -i:
#    charset=iso-8859-1). Ohne Umkodierung ist das Ergebnis kein gueltiges
#    UTF-8 — und genau das verlangt Elasticsearch: «the file must be UTF-8
#    encoded». Deshalb laeuft jetzt iconv in der Pipeline, und die Gegenprobe
#    am Ende prueft das Ergebnis mit iconv statt nur auf Grossbuchstaben.
#
# 2. DIE HUNSPELL-KOPFZEILEN LANDETEN IN DER LISTE. Der alte awk-Filter warf
#    nur Zeile 1 und Leerzeilen; die 14 Kommentarzeilen (# This is the
#    dictionary file ...) standen danach als «Woerter» in der Wortliste.
#
# 3. DIE FEHLERMELDUNG ZEIGTE AUF DAS FALSCHE. Sie lautete «sed dieser
#    Maschine beherrscht \L auf UTF-8 nicht». Das stimmt nicht: dasselbe GNU
#    sed macht aus echtem UTF-8 zuverlaessig Ärmel -> ärmel. Die Ursache war
#    die Kodierung der Quelle, nicht das Werkzeug.
#
# DIE WORTLISTE MUSS KLEINGESCHRIEBEN SEIN. Der dictionary_decompounder
# baut sie als CharArraySet mit ignoreCase=false; in jeder brauchbaren
# Analyzer-Kette laeuft der lowercase-Filter VOR ihm. Deutsche Substantive
# stehen in der .dic gross ("Schuh") — mit der rohen Hunspell-Liste
# trifft der Decompounder deshalb nie ein einziges Teilwort.
#
# Gemessen gegen ES 8.15.3, Analyzer lowercase -> decompounder -> stemmer:
#   Liste gross:  "Kinderschuhe" -> [kinderschuh]
#   Liste klein:  "Kinderschuhe" -> [kinderschuh, kind, schuh, schuh]
#
# Die Datei enthaelt Hunspell-STAEMME, keine Wortformen: dort steht Schuh/N,
# nicht Schuhe. Die Pluralform entsteht erst ueber die Affix-Flags, die dieses
# Skript wegwirft. Fuer den Decompounder genuegen die Staemme.
#
# Usage:
#   ./extract-dictionary.sh                     # download + extract
#   ./extract-dictionary.sh path/to/de_DE.dic   # use a local .dic
#   ./extract-dictionary.sh --help
#
# Environment:
#   OUT            Ausgabedatei, Default de_dictionary.txt
#   LOWER_LOCALE   Locale fuer die Kleinschreibung, Default C.UTF-8
#   SRC_ENCODING   Kodierung der Quelle; Default: automatisch erkannt
#
# Exit codes:
#   0  Liste gebaut
#   1  Ergebnis unbrauchbar (Kodierung) oder Download fehlgeschlagen
#   2  Falscher Aufruf
#
# Output: de_dictionary.txt  (copy to <es-config>/analysis/ on the host)
set -euo pipefail

OUT="${OUT:-de_dictionary.txt}"
URL="https://raw.githubusercontent.com/LibreOffice/dictionaries/master/de/de_DE_frami.dic"
LOWER_LOCALE="${LOWER_LOCALE:-C.UTF-8}"

usage() {
    sed -n '/^# Usage:/,/^#   2  /p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -*) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
esac

SRC="${1:-}"
TMP=""
if [[ -z "$SRC" ]]; then
    TMP="$(mktemp)"
    # Ohne trap bleibt die ~4 MB grosse Zwischendatei nach jedem Lauf liegen.
    # Wird unten um die Zwischendatei erweitert.
    trap 'rm -f "$TMP"' EXIT
    SRC="$TMP"
    echo "Downloading de_DE_frami.dic from LibreOffice/dictionaries ..."
    if ! curl -fsSL "$URL" -o "$SRC"; then
        echo "FEHLER: Download von $URL fehlgeschlagen." >&2
        exit 1
    fi
fi

if [[ ! -r "$SRC" ]]; then
    echo "FEHLER: $SRC nicht lesbar." >&2
    exit 2
fi

# Kodierung bestimmen, statt sie anzunehmen: Ist die Quelle bereits gueltiges
# UTF-8, wird nicht umkodiert — ein iconv von ISO-8859-1 wuerde sie sonst
# doppelt kodieren. Sonst ISO-8859-1, die Kodierung der LibreOffice-Datei.
if [[ -n "${SRC_ENCODING:-}" ]]; then
    ENC="$SRC_ENCODING"
elif iconv -f UTF-8 -t UTF-8 "$SRC" > /dev/null 2>&1; then
    ENC="UTF-8"
else
    ENC="ISO-8859-1"
fi
echo "Quelle: $SRC (Kodierung: $ENC)"

# Hunspell-Zeile: "Wort/AFFIXFLAGS" — Stamm vor dem Schraegstrich behalten,
# Zaehler-Kopfzeile, Kommentarzeilen und Leerzeilen weg, dann kleinschreiben.
#
# Kleinschreibung NICHT mit `tr '[:upper:]' '[:lower:]'` — tr arbeitet
# byteweise und laesst jeden Umlaut stehen ("Ärmel" bleibt "Ärmel").
# GNU sed \L und gawk tolower() koennen es in einer UTF-8-Locale; hier sed,
# weil Debian/Ubuntu zwar GNU sed, aber per Default mawk mitbringen.
# Beim anschliessenden sort ist LC_ALL=C dagegen richtig, damit die
# Reihenfolge nicht von der Locale des Build-Hosts abhaengt.
# In eine Zwischendatei schreiben und erst nach den Gegenproben umbenennen.
# Sonst hinterlaesst ein Fehlschlag eine leere oder halbe Wortliste unter dem
# Zielnamen — und die faellt erst auf, wenn der Decompounder nichts findet.
WORK="${OUT}.part"
trap 'rm -f "$WORK" ${TMP:+"$TMP"}' EXIT

iconv -f "$ENC" -t UTF-8 "$SRC" \
    | awk -F'/' 'NR > 1 && $1 != "" && $0 !~ /^[#\t ]/ { print $1 }' \
    | LC_ALL="$LOWER_LOCALE" sed 's/.*/\L&/' \
    | LC_ALL=C sort -u > "$WORK"

# Gegenprobe statt Vertrauen, und zwar an der Eigenschaft, auf die es
# ankommt: Elasticsearch verlangt UTF-8.
if ! iconv -f UTF-8 -t UTF-8 "$WORK" > /dev/null 2>&1; then
    echo "FEHLER: $OUT ist kein gueltiges UTF-8." >&2
    echo "Die Quelle ist vermutlich anders kodiert als erkannt ($ENC)." >&2
    echo "Behelf: SRC_ENCODING=<kodierung> $0 $SRC" >&2
    exit 1
fi

# Zweite Gegenprobe: bleibt ein Grossbuchstabe stehen, kann das sed dieser
# Maschine kein \L auf Mehrbyte-Zeichen — dann trifft der Decompounder nie.
if LC_ALL="$LOWER_LOCALE" grep -qE '[[:upper:]]' "$WORK"; then
    echo "FEHLER: In $OUT stehen noch Grossbuchstaben." >&2
    echo "sed dieser Maschine beherrscht \\L auf UTF-8 nicht." >&2
    echo "Behelf: LC_ALL=$LOWER_LOCALE gawk '{print tolower(\$0)}'" >&2
    exit 1
fi

mv "$WORK" "$OUT"

echo "Wrote $(wc -l < "$OUT") words to $OUT"
echo "Deploy with e.g.:"
echo "  sudo cp $OUT /etc/elasticsearch/analysis/de_dictionary.txt"
echo "  # or OpenSearch: /etc/opensearch/analysis/de_dictionary.txt"
echo "Then a full reindex (see 18.11) so new analyzers take effect."
