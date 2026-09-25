#!/bin/bash
#
# Quarterly Performance Review Script
#
# Erzeugt den Quarterly-Review-Report (Markdown) aus einer Eingabedatei.
# Summen, Mittelwerte, Veränderungen und Stufen rechnet das Skript, die
# Rohwerte kommen aus Ihren Quellen:
#   cwv         p75 am Quartalsanfang und -ende: rum:report (Kapitel 12)
#   okrs        Score je Key Result (0-1): Ihr OKR-Tracker
#   incidents   Anzahl P0/P1/P2, Postmortems, MTTR: Ihr Incident-Tracker
#   tech_debt   Score am Anfang und Ende: tech-debt-report.sh --json
#   budget      Plan und Ist je Kategorie: Ihre Buchhaltung
#   sections    freie Markdown-Abschnitte (Highlights, Learnings, Planung)
# Das Error Budget für ein Key Result liefert
# chapters/14-performance-kultur/scripts/error-budget.php.
#
# Pflicht sind quarter (Q1-Q4) und year. Jeder Datenblock ist optional; fehlt
# er, sagt der Report "keine Daten" statt eine Zahl zu zeigen. Ist ein Block
# da, müssen seine Felder vollständig sein. Format: examples/quarterly-review.demo.json
# und README.md.
#
# Nur wenn die Eingabe auf .demo.json endet, kennzeichnen Konsole und Report
# sie als BEISPIELDATEN.
#
# Verwendung:
#   ./quarterly-review.sh q2-2026.json
#   ./quarterly-review.sh q2-2026.json --output /pfad/report.md
#   ./quarterly-review.sh ../examples/quarterly-review.demo.json   # Demo
#
# Ohne --output landet der Report in OUTPUT_DIR (Vorgabe: reports/ neben
# scripts/) als quarterly-review-<Quartal>-<Jahr>.md.
#
# Exit-Codes: 0 ok, 1 Aufruf falsch, 2 jq fehlt, 65 Eingabe ungültig,
# 66 Eingabe fehlt oder ist nicht lesbar.
#
# Voraussetzungen:
#   - jq ab 1.6

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/../reports}"
OUTPUT_FILE=""
INPUT_FILE=""

usage() {
    echo "Usage: $(basename "$0") [--output DATEI] EINGABE.json" >&2
    echo "  Demo: $(basename "$0") examples/quarterly-review.demo.json" >&2
}

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "Fehler: --output braucht einen Dateinamen" >&2
                usage
                exit 1
            fi
            if [[ -d "$2" || "$2" == */ ]]; then
                echo "Fehler: --output braucht einen Dateinamen, kein Verzeichnis (dafür OUTPUT_DIR)" >&2
                exit 1
            fi
            OUTPUT_DIR="$(dirname "$2")"
            OUTPUT_FILE="$(basename "$2")"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unbekanntes Argument: $1" >&2
            usage
            exit 1
            ;;
        Q[1-4])
            echo "Fehler: Quartal und Jahr stehen jetzt in der Eingabedatei (\"quarter\", \"year\")" >&2
            usage
            exit 1
            ;;
        *)
            if [[ -n "${INPUT_FILE}" ]]; then
                echo "Fehler: nur eine Eingabedatei" >&2
                usage
                exit 1
            fi
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "${INPUT_FILE}" ]]; then
    echo "Fehler: keine Eingabedatei" >&2
    usage
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Fehler: jq fehlt (apt install jq)" >&2
    exit 2
fi

if [[ ! -f "${INPUT_FILE}" || ! -r "${INPUT_FILE}" ]]; then
    echo "Fehler: ${INPUT_FILE} fehlt oder ist nicht lesbar" >&2
    exit 66
fi
# genau ein JSON-Wert: eine leere Datei ist für "jq empty" gültig
if [[ "$(jq -s 'length' "${INPUT_FILE}" 2>/dev/null)" != "1" ]]; then
    echo "Fehler: ${INPUT_FILE} ist kein gültiges JSON (genau ein Wert erwartet)" >&2
    exit 65
fi

# ============================================================
# Eingabe prüfen: jede Verletzung eine Zeile
# ============================================================

INPUT_ERRORS=$(jq -r '
    def g($p): try getpath($p) catch null;
    def num($p): if (g($p) | type) != "number" then "\($p | join(".")) fehlt oder ist keine Zahl" else empty end;
    def nonneg($p): num($p) // (if g($p) < 0 then "\($p | join(".")) ist negativ" else empty end);
    def pos($p): num($p) // (if g($p) <= 0 then "\($p | join(".")) muss > 0 sein" else empty end);
    def count($p): nonneg($p) // (if g($p) != (g($p) | floor) then "\($p | join(".")) muss eine ganze Zahl sein" else empty end);
    def list($p): if (g($p) | type) != "array" then "\($p | join(".")) muss eine Liste sein" else empty end;
    def obj($p): if (g($p) | type) != "object" then "\($p | join(".")) muss ein Objekt sein" else empty end;
    if type != "object" then "Die Eingabe muss ein JSON-Objekt sein, nicht \(type)"
    else
        (if (.quarter | IN("Q1", "Q2", "Q3", "Q4")) | not then "quarter muss Q1, Q2, Q3 oder Q4 sein" else empty end),
        (if (.year | type) != "number" or .year != (.year | floor) or .year < 2000 or .year > 2100
            then "year muss eine Jahreszahl sein" else empty end),
        (if has("cwv") then
            (obj(["cwv"]) // ((["lcp_ms", "inp_ms", "cls"][]) as $m | pos(["cwv", $m, "start"]), nonneg(["cwv", $m, "end"])))
        else empty end),
        (if has("okrs") then
            (list(["okrs"]) // (if (.okrs | length) == 0 then "okrs muss eine nicht leere Liste sein (oder weglassen)" else empty end)
             // (.okrs | to_entries[] | .key as $i
                | if (.value | type) != "object" then "okrs.\($i) muss ein Objekt sein"
                  else (if (.value.objective | type) != "string" or .value.objective == ""
                        then "okrs.\($i).objective fehlt oder ist kein Text" else empty end),
                       (if (.value.key_results | type) != "array" or (.value.key_results | length) == 0
                        then "okrs.\($i).key_results muss eine nicht leere Liste sein"
                        else .value.key_results | to_entries[] | .key as $k | .value
                            | if type != "object" then "okrs.\($i).key_results.\($k) muss ein Objekt sein"
                              elif (.title | type) != "string" then "okrs.\($i).key_results.\($k).title fehlt"
                              elif (.score | type) != "number" or .score < 0 or .score > 1
                                then "okrs.\($i).key_results.\($k).score muss eine Zahl von 0 bis 1 sein (0.7 = 70 %)"
                              elif has("weight") and ((.weight | type) != "number" or .weight <= 0)
                                then "okrs.\($i).key_results.\($k).weight muss eine Zahl > 0 sein"
                              else empty end
                        end)
                  end))
        else empty end),
        (if has("incidents") then
            (obj(["incidents"]) // (
                ((["p0", "p1", "p2"][]) as $p | count(["incidents", $p])),
                (if .incidents | has("postmortems_done") then
                    count(["incidents", "postmortems_done"])
                    // (if ([.incidents.p0, .incidents.p1, .incidents.p2] | map(numbers) | add // 0) < .incidents.postmortems_done
                        then "incidents.postmortems_done ist grösser als p0 + p1 + p2" else empty end)
                 else empty end),
                (if .incidents | has("mttr_hours") then nonneg(["incidents", "mttr_hours"]) else empty end),
                (if .incidents | has("root_causes") then
                    (list(["incidents", "root_causes"]) // (.incidents.root_causes | to_entries[] | .key as $k | .value
                        | if type != "object" or (.cause | type) != "string" or (.count | type) != "number"
                            or .count < 0 or .count != (.count | floor)
                          then "incidents.root_causes.\($k) braucht cause (Text) und count (ganze Zahl >= 0)" else empty end))
                 else empty end)))
        else empty end),
        (if has("tech_debt") then
            (obj(["tech_debt"]) // (
                ((["start", "end"][]) as $s | (["items", "hours", "score"][]) as $f | nonneg(["tech_debt", $s, $f])),
                (if .tech_debt | has("resolved") then
                    (list(["tech_debt", "resolved"]) // (.tech_debt.resolved | to_entries[] | .key as $k | .value
                        | if type != "object" or (.title | type) != "string" or (.hours | type) != "number"
                          then "tech_debt.resolved.\($k) braucht title (Text) und hours (Zahl)" else empty end))
                 else empty end)))
        else empty end),
        (if has("budget") then
            (obj(["budget"]) // (
                (if (.budget.categories | type) != "array" or (.budget.categories | length) == 0
                    then "budget.categories muss eine nicht leere Liste sein"
                 else .budget.categories | to_entries[] | .key as $k | .value
                    | if type != "object" or (.category | type) != "string"
                        or (.planned | type) != "number" or .planned <= 0
                        or (.spent | type) != "number" or .spent < 0
                      then "budget.categories.\($k) braucht category, planned (> 0) und spent (>= 0)" else empty end
                 end),
                (if (.budget | has("currency")) and ((.budget.currency | type) != "string" or .budget.currency == "")
                    then "budget.currency muss ein Text sein, z. B. \"CHF\"" else empty end),
                (if (.budget | has("annual_total")) != (.budget | has("spent_year_to_date"))
                    then "budget.annual_total und budget.spent_year_to_date nur zusammen"
                 elif .budget | has("annual_total") then pos(["budget", "annual_total"]), nonneg(["budget", "spent_year_to_date"])
                 else empty end)))
        else empty end),
        (if has("sections") then
            (list(["sections"]) // (.sections | to_entries[] | .key as $k | .value
                | if type != "object" or (.title | type) != "string" or (.markdown | type) != "string"
                  then "sections.\($k) braucht title und markdown (Text)" else empty end))
        else empty end)
    end' "${INPUT_FILE}")

if [[ -n "${INPUT_ERRORS}" ]]; then
    echo "Fehler: ${INPUT_FILE} ist keine gültige Quartalseingabe:" >&2
    echo "${INPUT_ERRORS}" | sed 's/^/  /' >&2
    exit 65
fi

# Beispieldaten erkennt das Skript am Dateinamen, nicht am Inhalt
if [[ "$(basename "${INPUT_FILE}")" == *.demo.json ]]; then
    DATA_NOTE="BEISPIELDATEN aus $(basename "${INPUT_FILE}"), keine Messung"
else
    DATA_NOTE=""
fi

QUARTER=$(jq -r '.quarter' "${INPUT_FILE}")
# floor: jq ab 1.7 behielte die Schreibweise der Eingabe ("2026.0")
YEAR=$(jq -r '.year | floor' "${INPUT_FILE}")

case ${QUARTER} in
    Q1) START_DATE="${YEAR}-01-01"; END_DATE="${YEAR}-03-31" ;;
    Q2) START_DATE="${YEAR}-04-01"; END_DATE="${YEAR}-06-30" ;;
    Q3) START_DATE="${YEAR}-07-01"; END_DATE="${YEAR}-09-30" ;;
    Q4) START_DATE="${YEAR}-10-01"; END_DATE="${YEAR}-12-31" ;;
esac

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "  Quarterly Performance Review"
echo "================================================"
echo ""
echo "Quartal: ${QUARTER} ${YEAR}"
echo "Zeitraum: ${START_DATE} bis ${END_DATE}"
echo "Eingabe: ${INPUT_FILE}"
echo "Datum: $(date)"
if [[ -n "${DATA_NOTE}" ]]; then
    echo -e "${YELLOW}HINWEIS: ${DATA_NOTE}${NC}"
fi
echo ""

# ============================================================
# Rechnungen und Formate, gemeinsam für Report und Konsole
# ============================================================

# Kapitel 15: Tech Debt Score < 200 gesund, 200-499 Aufmerksamkeit, ab 500
# kritisch. OKR-Stufen wie src/OkrProgressService.php, bewertet am
# angezeigten (gerundeten) Wert. CWV "Good": LCP <= 2500 ms, INP <= 200 ms,
# CLS <= 0.1
JQ_DEFS='
def fixed($d): (pow(10; $d)) as $f | (. * $f | round) as $n
    | (if $n < 0 then "-" else "" end) as $sign | ($n | fabs) as $a
    | ($a / $f | floor) as $int
    | if $d == 0 then "\($sign)\($int)"
      else ($a - $int * $f | floor | tostring) as $frac
        | "\($sign)\($int).\([range($d - ($frac | length)) | "0"] | join(""))\($frac)" end;
def signed($d): (if (. * pow(10; $d) | round) > 0 then "+" else "" end) + fixed($d);
def thousands: (round | tostring) as $s | ($s | length) as $l
    | [range(0; $l) | $s[.:.+1] + (if (($l - . - 1) % 3 == 0) and (. < $l - 1) then "'"'"'" else "" end)] | join("");
def change($a; $b): if $a == 0 then null else ($a - $b) * 100 / $a end;
def arrow($a; $b): if $b < $a then "↓" elif $b > $a then "↑" else "→" end;
def level: if . >= 0.9 then "Exceptional" elif . >= 0.7 then "Strong" elif . >= 0.5 then "On Track"
    elif . >= 0.3 then "At Risk" else "Off Track" end;
def debt_health: if . < 200 then "healthy" elif . < 500 then "attention" else "critical" end;
# wie PHP 8.4 round($x, 2): gerundet wird die kürzeste Dezimaldarstellung,
# halbe Stellen von null weg. 0.285 -> 0.29, aber (0.44 + 0.49) / 2 =
# 0.46499999999999997 -> 0.46. "* 100 | round" träfe beide Fälle falsch
def r2: tostring as $s
    | if ($s | test("[eE]")) then . * 100 | round / 100
      else ($s | startswith("-")) as $neg | ($s | ltrimstr("-") | split(".")) as $p
        | (($p[1] // "") + "000") as $f
        | ($p[0] + $f[0:2] | tonumber) + (if ($f[2:3] | tonumber) >= 5 then 1 else 0 end)
        | . / 100 * (if $neg then -1 else 1 end) end;
# Zahlen aus der Eingabe neu schreiben: jq ab 1.7 behielte "2.45E+3" oder
# "8.0", und Summen trügen Binärreste (0.30000000000000004)
def num: . * 1000 | round / 1000;
def cell: tostring | gsub("\\|"; "\\|");
def val: if type == "number" then num | tostring else cell end;
# wie OkrProgressService: gewichtetes Mittel je Objective (weight, Vorgabe 1),
# gerundet; Gesamtwert = Mittel der gerundeten Objective-Scores. Die Stufe
# hängt wie im Service am angezeigten Wert (MEM-331). Gleiche Fälle:
# tests/Unit/fixtures/ch15-okr-equivalence.json
def objective_score: ([.key_results[] | .score * (.weight // 1)] | add)
    / ([.key_results[] | .weight // 1] | add) | r2;
def okr_total: [.okrs[] | objective_score] | add / length | r2;
def cwv_improvement($m): change(.cwv[$m].start; .cwv[$m].end);
def incident_total: .incidents.p0 + .incidents.p1 + .incidents.p2;
def resolved_hours: [.tech_debt.resolved[]?.hours] | add // 0 | num;
def cur: .budget.currency // "CHF" | cell;
def no_data($field): "_Keine Daten in der Eingabe (Feld `\($field)`)._\n";
'

# ============================================================
# Report schreiben (erst in .part, dann umbenennen)
# ============================================================

mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_FILE:-quarterly-review-${QUARTER}-${YEAR}.md}"
REPORT_FILE="${OUTPUT_DIR}/${OUTPUT_FILE}"
# bricht jq ab, bleibt keine halbe Datei liegen
trap 'rm -f "${REPORT_FILE}.part"' EXIT

jq -r --arg created "$(date '+%Y-%m-%d %H:%M')" --arg qstart "${START_DATE}" --arg qend "${END_DATE}" \
    --arg note "${DATA_NOTE}" --arg source "$(basename "${INPUT_FILE}")" "${JQ_DEFS}"'
[
"# Quarterly Performance Review",
"",
"**Quartal**: \(.quarter) \(.year | floor)",
"**Zeitraum**: \($qstart) bis \($qend)",
"**Erstellt**: \($created)",
"**Eingabe**: \($source)",
"",
(if $note != "" then "> **\($note).** Die Zahlen zeigen nur den Aufbau des Reports.\n" else empty end),
"---",
"",
"## Executive Summary",
"",
"### Core Web Vitals Performance",
"",
(if has("cwv") then
    "| Metrik | Quartalsstart | Quartalsende | Verbesserung |",
    "|--------|---------------|--------------|--------------|",
    (. as $r | [["LCP", "lcp_ms", "ms"], ["INP", "inp_ms", "ms"], ["CLS", "cls", ""]][]
        | . as [$lbl, $m, $unit] | $r.cwv[$m] as $v
        | "| \($lbl) (p75) | \($v.start | num)\($unit) | \($v.end | num)\($unit) | **\($r | cwv_improvement($m) | fixed(1))%** \(arrow($v.start; $v.end)) |"),
    "",
    "**Bewertung**:",
    ([(if .cwv.lcp_ms.end > 2500 then "LCP (\(.cwv.lcp_ms.end | num)ms > 2500ms)" else empty end),
      (if .cwv.inp_ms.end > 200 then "INP (\(.cwv.inp_ms.end | num)ms > 200ms)" else empty end),
      (if .cwv.cls.end > 0.1 then "CLS (\(.cwv.cls.end | num) > 0.1)" else empty end)]
     | if length == 0 then "Alle Core Web Vitals im '"'"'Good'"'"' Bereich."
       else "Nicht im '"'"'Good'"'"' Bereich: \(join(", "))." end),
    ""
 else no_data("cwv") end),
"---",
"",
"## OKR Scoring",
"",
(if has("okrs") then
    (.okrs | to_entries[] |
        "### Objective \(.key + 1): \(.value.objective | cell)",
        "",
        "| Key Result | Baseline | Target | Erreicht | Score |",
        "|------------|----------|--------|----------|-------|",
        (.value.key_results[] | "| \(.title | cell) | \(.baseline // "–" | val) | \(.target // "–" | val) | \(.achieved // "–" | val) | **\(.score | fixed(2))**\(if has("weight") then " (Gewicht \(.weight | num))" else "" end) |"),
        "",
        "**Objective Score**: \(.value | objective_score | fixed(2)) (\(.value | objective_score | level))",
        ""),
    "### Gesamtbewertung",
    "",
    "| Objective | Score | Status |",
    "|-----------|-------|--------|",
    (.okrs[] | "| \(.objective | cell) | \(objective_score | fixed(2)) | \(objective_score | level) |"),
    "| **Durchschnitt** | **\(okr_total | fixed(2))** | **\(okr_total | level)** |",
    ""
 else no_data("okrs") end),
"---",
"",
"## Incident Summary",
"",
(if has("incidents") then
    "| Kategorie | Anzahl |",
    "|-----------|--------|",
    "| P0 (Critical) | \(.incidents.p0 | num) |",
    "| P1 (High) | \(.incidents.p1 | num) |",
    "| P2 (Medium) | \(.incidents.p2 | num) |",
    "| **Total** | **\(incident_total | num)** |",
    "",
    (if (.incidents | has("postmortems_done")) or (.incidents | has("mttr_hours")) then
        "### Postmortem Status",
        "",
        (if .incidents | has("postmortems_done") then
            "- Abgeschlossen: \(.incidents.postmortems_done | num)/\(incident_total | num)"
            + (if incident_total > 0 then " (\(.incidents.postmortems_done * 100 / incident_total | fixed(0))%)" else "" end)
         else empty end),
        (if .incidents | has("mttr_hours") then "- MTTR (Mean Time to Recovery): \(.incidents.mttr_hours | num) Stunden" else empty end),
        ""
     else empty end),
    (if (.incidents.root_causes // []) | length > 0 then
        "### Top Root Causes",
        "",
        (.incidents.root_causes | to_entries[]
            | "\(.key + 1). \(.value.cause) (\(.value.count | num) Incident\(if .value.count == 1 then "" else "s" end))"),
        ""
     else empty end)
 else no_data("incidents") end),
"---",
"",
"## Tech Debt Status",
"",
(if has("tech_debt") then
    .tech_debt as $t |
    "| Metrik | Quartalsstart | Quartalsende | Trend |",
    "|--------|---------------|--------------|-------|",
    "| Backlog Items | \($t.start.items | num) | \($t.end.items | num) | \(arrow($t.start.items; $t.end.items)) \(change($t.start.items; $t.end.items) | if . == null then "–" else fabs | fixed(0) + "%" end) |",
    "| Geschätzte Stunden | \($t.start.hours | num)h | \($t.end.hours | num)h | \(arrow($t.start.hours; $t.end.hours)) \(change($t.start.hours; $t.end.hours) | if . == null then "–" else fabs | fixed(0) + "%" end) |",
    "| Tech Debt Score (Severity-Punkte, Kapitel 15) | \($t.start.score | num) | \($t.end.score | num) | \(arrow($t.start.score; $t.end.score)) \($t.end.score | debt_health) (< 200 gesund) |",
    "",
    (if ($t.resolved // []) | length > 0 then
        "### Resolved Tech Debt",
        "",
        ($t.resolved[] | "- \(.title) (\(.hours | num)h)"),
        "",
        "**Total**: \(resolved_hours) Stunden Tech Debt abgebaut",
        ""
     else empty end)
 else no_data("tech_debt") end),
"---",
"",
"## Budget Status",
"",
(if has("budget") then
    cur as $c | .budget as $b |
    "| Kategorie | Geplant | Ausgegeben | Varianz |",
    "|-----------|---------|------------|---------|",
    ($b.categories[] | "| \(.category | cell) | \($c) \(.planned | thousands) | \($c) \(.spent | thousands) | \((.spent - .planned) * 100 / .planned | signed(0))% |"),
    ([$b.categories[].planned] | add) as $p | ([$b.categories[].spent] | add) as $s |
    "| **Total Q** | **\($c) \($p | thousands)** | **\($c) \($s | thousands)** | **\(($s - $p) * 100 / $p | signed(0))%** |",
    "",
    (if $b | has("annual_total") then
        "**Jahres-Budget Status**: \($b.spent_year_to_date * 100 / $b.annual_total | fixed(0))% verbraucht (Ziel: \((.quarter[1:] | tonumber) * 25)%)",
        ""
     else empty end)
 else no_data("budget") end),
(.sections // [] | .[] | "---", "", "## \(.title)", "", .markdown, ""),
"---",
"",
"*Report generiert von: quarterly-review.sh v2.0*"
] | .[]' "${INPUT_FILE}" > "${REPORT_FILE}.part"
mv "${REPORT_FILE}.part" "${REPORT_FILE}"

echo "================================================"
echo -e "${GREEN}Report erstellt: ${REPORT_FILE}${NC}"
echo "================================================"
echo ""

# Zusammenfassung anzeigen
if [[ -n "${DATA_NOTE}" ]]; then
    echo "Quick Summary (${DATA_NOTE}):"
else
    echo "Quick Summary:"
fi
jq -r "${JQ_DEFS}"'
    "  - CWV Improvement: " + (if has("cwv")
        then "LCP \(cwv_improvement("lcp_ms") | fixed(1))%, INP \(cwv_improvement("inp_ms") | fixed(1))%" else "keine Daten" end),
    "  - OKR Score: " + (if has("okrs") then "\(okr_total | fixed(2)) (\(okr_total | level))" else "keine Daten" end),
    "  - Incidents: " + (if has("incidents") then "\(.incidents.p0 | num) P0, \(.incidents.p1 | num) P1" else "keine Daten" end),
    "  - Tech Debt: " + (if has("tech_debt") then "\(resolved_hours)h abgebaut, Score \(.tech_debt.end.score | num) (\(.tech_debt.end.score | debt_health))" else "keine Daten" end)' \
    "${INPUT_FILE}"
echo ""

echo "Done."
