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
# drop the count header (first line) and any blank lines.
awk -F'/' 'NR > 1 && $1 != "" { print $1 }' "$SRC" \
    | LC_ALL=C sort -u > "$OUT"

echo "Wrote $(wc -l < "$OUT") words to $OUT"
echo "Deploy with e.g.:"
echo "  sudo cp $OUT /etc/elasticsearch/analysis/de_dictionary.txt"
echo "  # or OpenSearch: /etc/opensearch/analysis/de_dictionary.txt"
echo "Then a full reindex (see 18.11) so new analyzers take effect."
