#!/usr/bin/env bash
# =============================================================================
# Title:       normalize_grps.sh
# Description: Normalizes .grp coverage matrix files (TSV: replicon + per-sample
#              coverage columns) by scaling read counts across samples. Supports
#              reference-based scaling (per-replicon or global) and auto-scaling
#              to the largest (up) or smallest (down) grand total. Processes
#              multiple files in parallel via GNU parallel when available.
# Author:      Marc Broghammer
# Email:       marc.broghammer@gmx.de
# Version:     0.0.1
# Usage:       ./normalize_grps.sh [options] <grp_file1> <grp_file2> ...
# =============================================================================

set -euo pipefail

# === Default values ===
declare -a input_files=()
output_dir="./scaled_grp"
num_processes=0
id_col_auto_detect=true
id_col=true
count_start_col=2
mode_ref=""
mode_auto=""
mode_print_sums=false

# === Usage ===
print_usage() {
    echo ""
    echo "Usage: $0 [options] <grp_file1> <grp_file2> ..."
    echo ""
    echo "Options:"
    echo "  -r, --ref <file>          Reference file for scaling"
    echo "  -a, --auto <up|down>      Auto scale to largest or smallest sum"
    echo "  -n, --print-counts-sums   Only print counts sums per file and exit"
    echo "  -o, --output <dir>        Output directory (default: scaled_grp)"
    echo "  -p, --processes <N>       Number of parallel processes"
    echo "      --no-id               Input has no replicon ID column"
    echo "  -h, --help                Show this help message"
    exit 1
}

# === Parse args ===
TEMP=$(getopt -o r:a:no:p:h --long ref:,auto:,no-id,output:,processes:,print-counts-sums,help -n "$0" -- "$@")
eval set -- "$TEMP"

while true; do
    case "$1" in
        -r|--ref) mode_ref="$2"; shift 2 ;;
        -a|--auto) mode_auto="$2"; shift 2 ;;
        --no-id) id_col=false; id_col_auto_detect=false; count_start_col=1; shift ;;
        -n|--print-counts-sums) mode_print_sums=true; shift ;;
        -o|--output) output_dir="$2"; shift 2 ;;
        -p|--processes) num_processes="$2"; shift 2 ;;
        -h|--help) print_usage ;;
        --) shift; break ;;
        *) print_usage ;;
    esac
done

# === Remaining args are input files ===
if [ "$#" -lt 1 ]; then
    echo "Error: No input .grp files provided."
    print_usage
fi
input_files=("$@")
mkdir -p "$output_dir"

# === Auto-detect ID column ===
if [ "$id_col_auto_detect" = true ]; then
    first_line=$(head -n1 "${input_files[0]}")
    first_col=$(echo "$first_line" | awk '{print $1}')
    if [[ "$first_col" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        id_col=false
        count_start_col=1
    else
        id_col=true
        count_start_col=2
    fi
fi

# === Determine number of columns ===
cols_ref=$(awk '{print NF}' "${input_files[0]}" | sort -u)
# Check ragged first file
if [ "$(echo "$cols_ref" | wc -l)" -gt 1 ]; then
    echo "Error: File ${input_files[0]} has inconsistent column counts (ragged)."
    exit 1
fi
rows_ref=$(wc -l < "${input_files[0]}")

# === Print counts sums mode ===
print_counts_sums() {
    for file in "${input_files[@]}"; do
        echo "File: $file"
        if [ "$id_col" = true ]; then
            replicons=$(awk '{print $1}' "$file" | sort -u)
            for rep in $replicons; do
                line="Replicon $rep sums:"
                for ((i=count_start_col;i<=cols_ref;i++)); do
                    col_sum=$(awk -v r="$rep" -v col="$i" '$1==r{sum+=$col} END{print sum+0}' "$file")
                    line="$line $col_sum"
                done
                echo "$line"
            done
        else
            line="Total sums per column:"
            for ((i=1;i<=cols_ref;i++)); do
                col_sum=$(awk -v col="$i" '{sum+=$col} END{print sum+0}' "$file")
                line="$line $col_sum"
            done
            echo "$line"
        fi
        echo ""
    done
}

[ "$mode_print_sums" = true ] && print_counts_sums && exit 0

# === Check all files have same shape ===
all_files_to_check=("${input_files[@]}")
[ -n "$mode_ref" ] && all_files_to_check+=("$mode_ref")

for file in "${all_files_to_check[@]}"; do
    cols=$(awk '{print NF}' "$file" | sort -u)
    if [ "$(echo "$cols" | wc -l)" -gt 1 ]; then
        echo "Error: File $file has inconsistent column counts (ragged)."
        exit 1
    fi
    if [ "$file" != "${input_files[0]}" ]; then
        if [ "$cols" != "$cols_ref" ]; then
            echo "Error: File $file has different number of columns ($cols vs $cols_ref)."
            exit 1
        fi
        rows=$(wc -l < "$file")
        if [ "$rows" -ne "$rows_ref" ]; then
            echo "Error: File $file has different number of rows ($rows vs $rows_ref)."
            exit 1
        fi
    fi
done

# === Validate mode ===
if [ -z "$mode_ref" ] && [ -z "$mode_auto" ]; then
    echo "Error: Must specify either -r/--ref or -a/--auto mode."
    exit 1
fi

if [ -n "$mode_auto" ] && [ "$mode_auto" != "up" ] && [ "$mode_auto" != "down" ]; then
    echo "Error: --auto mode must be 'up' or 'down', got '$mode_auto'."
    exit 1
fi

# === Compute scale targets ===
scale_mode=""
scale_targets_serial=""

compute_file_total() {
    local file="$1"
    local start="$2"
    awk -v start="$start" '{for(i=start;i<=NF;i++) s+=$i} END{print s+0}' "$file"
}

if [ -n "$mode_ref" ]; then
    echo "Scaling to reference file: $mode_ref"
    if [ "$id_col" = true ]; then
        # Per-replicon scaling: produce "rep1:sum1,rep2:sum2,..."
        scale_mode="per_replicon"
        scale_targets_serial=$(awk -v start="$count_start_col" '
        {
            rep=$1
            for(i=start;i<=NF;i++) sums[rep]+=$i
        }
        END {
            first=1
            for(rep in sums) {
                if(!first) printf ","
                printf "%s:%s", rep, sums[rep]
                first=0
            }
        }' "$mode_ref")
    else
        # Global scaling: single number
        scale_mode="global"
        scale_targets_serial=$(compute_file_total "$mode_ref" 1)
    fi
elif [ -n "$mode_auto" ]; then
    scale_mode="global"
    # Compute grand total for each input file
    declare -a file_totals=()
    for file in "${input_files[@]}"; do
        total=$(compute_file_total "$file" "$count_start_col")
        file_totals+=("$total")
    done

    # Pick max or min
    if [ "$mode_auto" = "up" ]; then
        target=$(printf '%s\n' "${file_totals[@]}" | awk 'BEGIN{m=-1} {if($1+0>m) m=$1+0} END{print m}')
    else
        target=$(printf '%s\n' "${file_totals[@]}" | awk 'BEGIN{m=-1} {if(m<0 || $1+0<m) m=$1+0} END{print m}')
    fi
    scale_targets_serial="$target"
    echo "Auto mode ($mode_auto): scaling all files to grand total $target"
fi

# === Scaling function ===
scale_file() {
    local file="$1"
    local output_file="$2"

    if [ "$SCALE_MODE" = "per_replicon" ]; then
        awk -v start="$COUNT_START_COL" -v OFS="\t" -v targets_serial="$SCALE_TARGETS_SERIAL" '
        BEGIN {
            n = split(targets_serial, pairs, ",")
            for(i=1; i<=n; i++) {
                split(pairs[i], kv, ":")
                targets[kv[1]] = kv[2]
            }
        }
        NR == FNR {
            key = $1
            for(i=start; i<=NF; i++) file_sums[key] += $i
            next
        }
        {
            key = $1
            target = (key in targets) ? targets[key] : 0
            fs = (key in file_sums) ? file_sums[key] : 0
            scale = (fs > 0) ? target / fs : 0
            printf "%s", $1
            for(i=start; i<=NF; i++) printf "\t%.10f", $i * scale
            print ""
        }' "$file" "$file" > "$output_file"
    else
        # Global scaling: two-pass (compute total, then scale)
        file_total=$(awk -v start="$COUNT_START_COL" '{for(i=start;i<=NF;i++) s+=$i} END{print s+0}' "$file")
        awk -v start="$COUNT_START_COL" -v target="$SCALE_TARGETS_SERIAL" -v file_total="$file_total" -v OFS="\t" -v id_col="$ID_COL" '
        BEGIN {
            scale = (file_total > 0) ? target / file_total : 0
        }
        {
            if(id_col == "true") {
                printf "%s", $1
                for(i=start; i<=NF; i++) printf "\t%.10f", $i * scale
                print ""
            } else {
                for(i=1; i<=NF; i++) {
                    if(i > 1) printf "\t"
                    printf "%.10f", $i * scale
                }
                print ""
            }
        }' "$file" > "$output_file"
    fi
}

# === Export for parallel ===
export -f scale_file
export SCALE_TARGETS_SERIAL="$scale_targets_serial"
export SCALE_MODE="$scale_mode"
export ID_COL="$id_col"
export COUNT_START_COL="$count_start_col"

# === Run scaling ===
if command -v parallel >/dev/null 2>&1 && [ "$num_processes" -gt 0 ]; then
    parallel -j "$num_processes" scale_file {} "$output_dir/{/}" ::: "${input_files[@]}"
elif command -v parallel >/dev/null 2>&1 && [ "${#input_files[@]}" -gt 1 ]; then
    parallel scale_file {} "$output_dir/{/}" ::: "${input_files[@]}"
else
    for f in "${input_files[@]}"; do
        scale_file "$f" "$output_dir/$(basename "$f")"
    done
fi

echo "Done. Scaled files saved in $output_dir"
