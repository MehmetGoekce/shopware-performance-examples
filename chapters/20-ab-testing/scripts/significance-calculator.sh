#!/bin/bash

##
# Significance Calculator - CLI Tool für schnelle Signifikanz-Tests
#
# @description
# Berechnet statistische Signifikanz aus CSV-Daten oder direkten Eingaben.
# Unterstützt t-Test, Chi-Square und Power Analysis.
#
# @usage
# ./significance-calculator.sh --control=2100,2050,2200 --variant=1800,1750,1900
# ./significance-calculator.sh --csv=experiment_data.csv --metric=lcp
#
# @author Mehmet Gökçe
# @since 1.0.0
##

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default-Werte
CONFIDENCE=0.95
MIN_SAMPLE_SIZE=30
ALERT_WEBHOOK=""

# Funktionen

function print_usage() {
    cat <<EOF
Usage: significance-calculator.sh [OPTIONS]

Options:
    --control=VALUE1,VALUE2,...    Control group values (comma-separated)
    --variant=VALUE1,VALUE2,...    Variant group values (comma-separated)
    --csv=FILE                     Load data from CSV file
    --metric=METRIC                Metric name (for CSV mode)
    --confidence=0.95              Confidence level (default: 0.95)
    --budget=VALUE                 Performance budget threshold
    --alert-webhook=URL            Webhook URL for alerts
    --help                         Show this help

Examples:
    # Direct values
    ./significance-calculator.sh \\
        --control=2100,2050,2200,2150 \\
        --variant=1800,1750,1900,1850

    # From CSV
    ./significance-calculator.sh \\
        --csv=metrics.csv \\
        --metric=lcp \\
        --budget=2500

    # With Slack alert
    ./significance-calculator.sh \\
        --control=2100,2050 \\
        --variant=2600,2700 \\
        --budget=2500 \\
        --alert-webhook=https://hooks.slack.com/...

EOF
}

function parse_args() {
    for arg in "$@"; do
        case $arg in
            --control=*)
                CONTROL_VALUES="${arg#*=}"
                ;;
            --variant=*)
                VARIANT_VALUES="${arg#*=}"
                ;;
            --csv=*)
                CSV_FILE="${arg#*=}"
                ;;
            --metric=*)
                METRIC="${arg#*=}"
                ;;
            --confidence=*)
                CONFIDENCE="${arg#*=}"
                ;;
            --budget=*)
                BUDGET="${arg#*=}"
                ;;
            --alert-webhook=*)
                ALERT_WEBHOOK="${arg#*=}"
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $arg${NC}"
                print_usage
                exit 1
                ;;
        esac
    done
}

function load_from_csv() {
    local csv_file=$1
    local metric=$2

    if [[ ! -f "$csv_file" ]]; then
        echo -e "${RED}Error: CSV file not found: $csv_file${NC}"
        exit 1
    fi

    # Extrahiere Werte für Control (erste Variante)
    CONTROL_VALUES=$(awk -F',' -v metric="$metric" '
        NR>1 && $2==metric && NR<=100 { printf "%s,", $3 }
    ' "$csv_file" | sed 's/,$//')

    # Extrahiere Werte für Variant (zweite Variante)
    VARIANT_VALUES=$(awk -F',' -v metric="$metric" '
        NR>100 && $2==metric { printf "%s,", $3 }
    ' "$csv_file" | sed 's/,$//')
}

function calculate_stats() {
    local values=$1

    # Konvertiere zu Array
    IFS=',' read -ra arr <<< "$values"

    # Anzahl
    local n=${#arr[@]}

    # Summe
    local sum=0
    for val in "${arr[@]}"; do
        sum=$(echo "$sum + $val" | bc -l)
    done

    # Mean
    local mean
    mean=$(echo "scale=2; $sum / $n" | bc -l)

    # Variance
    local var_sum=0
    local diff sq
    for val in "${arr[@]}"; do
        diff=$(echo "$val - $mean" | bc -l)
        sq=$(echo "$diff * $diff" | bc -l)
        var_sum=$(echo "$var_sum + $sq" | bc -l)
    done

    local variance
    variance=$(echo "scale=2; $var_sum / ($n - 1)" | bc -l)

    # Standard Deviation
    local stddev
    stddev=$(echo "scale=2; sqrt($variance)" | bc -l)

    # Standard Error
    local stderr
    stderr=$(echo "scale=2; $stddev / sqrt($n)" | bc -l)

    echo "$n,$mean,$stddev,$stderr"
}

function calculate_t_statistic() {
    local mean1=$1
    local mean2=$2
    local se1=$3
    local se2=$4

    local se_pooled t
    se_pooled=$(echo "scale=4; sqrt($se1 * $se1 + $se2 * $se2)" | bc -l)
    t=$(echo "scale=4; ($mean1 - $mean2) / $se_pooled" | bc -l)

    # Absolute value
    t=$(echo "$t" | tr -d '-')

    echo "$t"
}

function get_critical_value() {
    local confidence=$1

    # Lookup Table für häufige Konfidenz-Levels
    case $confidence in
        0.90)
            echo "1.645"
            ;;
        0.95)
            echo "1.960"
            ;;
        0.99)
            echo "2.576"
            ;;
        *)
            echo "1.960" # Default: 95%
            ;;
    esac
}

function calculate_p_value() {
    local t=$1

    # Approximierte p-value basierend auf t-Wert
    if (( $(echo "$t < 1.645" | bc -l) )); then
        echo ">0.10"
    elif (( $(echo "$t < 1.960" | bc -l) )); then
        echo "<0.10"
    elif (( $(echo "$t < 2.576" | bc -l) )); then
        echo "<0.05"
    else
        echo "<0.01"
    fi
}

function send_alert() {
    local message=$1

    if [[ -z "$ALERT_WEBHOOK" ]]; then
        return
    fi

    # Slack Webhook
    curl -X POST "$ALERT_WEBHOOK" \
        -H 'Content-Type: application/json' \
        -d "{\"text\":\"$message\"}" \
        2>/dev/null

    echo -e "${BLUE}Alert sent to webhook${NC}"
}

function main() {
    parse_args "$@"

    # Banner
    echo -e "${BLUE}"
    echo "┌─────────────────────────────────────────────┐"
    echo "│   Significance Calculator for A/B Tests    │"
    echo "└─────────────────────────────────────────────┘"
    echo -e "${NC}"

    # Daten laden
    if [[ -n "$CSV_FILE" ]]; then
        echo -e "${YELLOW}Loading data from CSV: $CSV_FILE${NC}"
        load_from_csv "$CSV_FILE" "$METRIC"
    fi

    # Validierung
    if [[ -z "$CONTROL_VALUES" ]] || [[ -z "$VARIANT_VALUES" ]]; then
        echo -e "${RED}Error: Both --control and --variant required${NC}"
        print_usage
        exit 1
    fi

    # Statistiken berechnen
    echo -e "\n${BLUE}Calculating statistics...${NC}\n"

    IFS=',' read -r control_n control_mean control_std control_se <<< "$(calculate_stats "$CONTROL_VALUES")"
    IFS=',' read -r variant_n variant_mean variant_std variant_se <<< "$(calculate_stats "$VARIANT_VALUES")"

    # Sample Size Check
    if (( control_n < MIN_SAMPLE_SIZE )) || (( variant_n < MIN_SAMPLE_SIZE )); then
        echo -e "${YELLOW}⚠️  Warning: Sample size below minimum ($MIN_SAMPLE_SIZE)${NC}"
        echo "   Control: $control_n, Variant: $variant_n"
        echo ""
    fi

    # Ausgabe
    echo "Control Group:"
    echo "  Samples: $control_n"
    echo "  Mean: $control_mean"
    echo "  Std Dev: $control_std"
    echo "  Std Error: $control_se"
    echo ""

    echo "Variant Group:"
    echo "  Samples: $variant_n"
    echo "  Mean: $variant_mean"
    echo "  Std Dev: $variant_std"
    echo "  Std Error: $variant_se"
    echo ""

    # Improvement
    improvement=$(echo "scale=2; (($control_mean - $variant_mean) / $control_mean) * 100" | bc -l)

    echo "─────────────────────────────────────────────"
    echo ""
    echo "Improvement: $improvement%"
    echo ""

    # t-Test
    t_stat=$(calculate_t_statistic "$control_mean" "$variant_mean" "$control_se" "$variant_se")
    critical_value=$(get_critical_value "$CONFIDENCE")
    p_value=$(calculate_p_value "$t_stat")

    echo "Statistical Test Results:"
    echo "  t-statistic: $t_stat"
    echo "  Critical value (${CONFIDENCE}): $critical_value"
    echo "  p-value: $p_value"
    echo ""

    # Signifikanz
    if (( $(echo "$t_stat > $critical_value" | bc -l) )); then
        echo -e "${GREEN}✅ SIGNIFICANT at ${CONFIDENCE} confidence level${NC}"

        if (( $(echo "$improvement > 0" | bc -l) )); then
            echo -e "${GREEN}🏆 Variant is better than control${NC}"
            recommendation="DEPLOY"
        else
            echo -e "${RED}❌ Variant is worse than control${NC}"
            recommendation="REJECT"
        fi
    else
        echo -e "${YELLOW}⚪ NOT SIGNIFICANT - continue testing${NC}"
        recommendation="CONTINUE"
    fi

    echo ""

    # Performance Budget Check
    if [[ -n "$BUDGET" ]]; then
        echo "─────────────────────────────────────────────"
        echo ""
        echo "Performance Budget: $BUDGET"

        if (( $(echo "$variant_mean > $BUDGET" | bc -l) )); then
            echo -e "${RED}❌ BUDGET EXCEEDED: $variant_mean > $BUDGET${NC}"

            send_alert "🚨 Performance Budget Exceeded: Variant mean ($variant_mean) > Budget ($BUDGET)"

            recommendation="REJECT - Budget exceeded"
        else
            echo -e "${GREEN}✅ Within budget${NC}"
        fi

        echo ""
    fi

    # Finale Empfehlung
    echo "─────────────────────────────────────────────"
    echo ""
    echo -e "${BLUE}Recommendation: $recommendation${NC}"
    echo ""
}

# Run
main "$@"
