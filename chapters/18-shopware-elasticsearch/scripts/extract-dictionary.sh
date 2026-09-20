#!/bin/bash
#
# Section 18.5 — Build the German word list for dictionary_decompounder.
#
# Source: LibreOffice dictionaries (de_DE.dic, Hunspell format). ES needs
# the bare stems WITHOUT the Hunspell affix flags after the slash, one
# UTF-8 word per line. Licence GPL/LGPL/MPL (multi) — shipping the word
# list as a deployment asset (not inside a plugin package) is fine, as no
# ES code is modified.
#
# DIE WORTLISTE MUSS KLEINGESCHRIEBEN SEIN. Der dictionary_decompounder
# baut sie als CharArraySet mit ignoreCase=false; in jeder brauchbaren
# Analyzer-Kette laeuft der lowercase-Filter VOR ihm. Deutsche Substantive
# stehen in de_DE.dic gross ("Schuhe") — mit der rohen Hunspell-Liste
# trifft der Decompounder deshalb nie ein einziges Teilwort.
#
# Gemessen gegen ES 8.15.3, Analyzer lowercase -> decompounder -> stemmer:
#   Liste gross:  "Kinderschuhe" -> [kinderschuh]
#   Liste klein:  "Kinderschuhe" -> [kinderschuh, kind, schuh, schuh]
#
# Usage:
#   ./extract-dictionary.sh                 # download + extract
#   ./extract-dictionary.sh path/to/de_DE.dic   # use a local .dic
#
# Output: de_dictionary.txt  (copy to <es-config>/analysis/ on the host)
set -euo pipefail

OUT="${OUT:-de_dictionary.txt}"
SRC="${1:-}"
URL="https://raw.githubusercontent.com/LibreOffice/dictionaries/master/de/de_DE.dic"

if [[ -z "$SRC" ]]; then
    SRC="$(mktemp)"
    echo "Downloading de_DE.dic from LibreOffice/dictionaries ..."
    curl -fsSL "$URL" -o "$SRC"
fi

# Hunspell line: "Wort/AFFIXFLAGS" — keep the stem before the slash,
# drop the count header (first line) and any blank lines, then lowercase.
#
# Kleinschreibung: NICHT mit `tr '[:upper:]' '[:lower:]'` — tr arbeitet
# byteweise und laesst jeden Umlaut stehen ("Ärmel" bleibt "Ärmel").
# GNU sed \L und gawk tolower() koennen es in einer UTF-8-Locale; hier sed,
# weil Debian/Ubuntu zwar GNU sed, aber per Default mawk mitbringen.
# Beim anschliessenden sort ist LC_ALL=C dagegen richtig, damit die
# Reihenfolge nicht von der Locale des Build-Hosts abhaengt.
LOWER_LOCALE="${LOWER_LOCALE:-C.UTF-8}"

awk -F'/' 'NR > 1 && $1 != "" { print $1 }' "$SRC" \
    | LC_ALL="$LOWER_LOCALE" sed 's/.*/\L&/' \
    | LC_ALL=C sort -u > "$OUT"

# Gegenprobe statt Vertrauen: bleibt ein Grossbuchstabe stehen, kann das sed
# dieser Maschine kein \L auf Mehrbyte-Zeichen — dann ist die Liste fuer den
# Decompounder unbrauchbar, und zwar lautlos.
if LC_ALL="$LOWER_LOCALE" grep -qE '[[:upper:]]' "$OUT"; then
    echo "FEHLER: In $OUT stehen noch Grossbuchstaben." >&2
    echo "sed dieser Maschine beherrscht \\L auf UTF-8 nicht." >&2
    echo "Behelf: LC_ALL=$LOWER_LOCALE gawk '{print tolower(\$0)}'" >&2
    exit 1
fi

echo "Wrote $(wc -l < "$OUT") words to $OUT"
echo "Deploy with e.g.:"
echo "  sudo cp $OUT /etc/elasticsearch/analysis/de_dictionary.txt"
echo "  # or OpenSearch: /etc/opensearch/analysis/de_dictionary.txt"
echo "Then a full reindex (see 18.11) so new analyzers take effect."
