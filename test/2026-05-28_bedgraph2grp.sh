#!/bin/bash
set -euo pipefail

# === Default values ===
declare -a replicons=()
output_file="merged_coverage_matrix.grp"
include_replicon_column=true
auto_detect_replicons=true

# === Usage message ===
print_usage() {
  echo ""
  echo "Usage: $0 [options] <bedgraph_file1> <bedgraph_file2> ..."
  echo ""
  echo "Options:"
  echo "  -r, --replicon <id>       Specify replicon ID (can be repeated)"
  echo "  -o, --output <file>       Output file name (default: merged_coverage_matrix.grp)"
  echo "      --no-replicon         Omit replicon ID column in the output"
  echo "  -h, --help                Show this help message"
  echo ""
  echo "If no -r is specified, replicons will be auto-detected from the BEDGRAPH files."
  exit "${1:-1}"
}

# === Parse command-line args with getopt ===
TEMP=$(getopt -o r:o:h --long replicon:,output:,no-replicon,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then print_usage; fi
eval set -- "$TEMP"

# === Handle options ===
while true; do
  case "$1" in
    -r|--replicon)
      replicons+=("$2")
      auto_detect_replicons=false
      shift 2 ;;
    -o|--output)
      output_file="$2"
      shift 2 ;;
    --no-replicon)
      include_replicon_column=false
      shift ;;
    -h|--help)
      print_usage 0 ;;
    --)
      shift
      break ;;
    *)
      print_usage ;;
  esac
done

# === Remaining args are input BEDGRAPH files ===
if [ "$#" -eq 0 ]; then
  echo "Error: No BEDGRAPH files provided."
  print_usage
fi
bedgraph_files=("$@")

# === Validate input files ===
for file in "${bedgraph_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Error: Input file not found: $file" >&2
    exit 1
  fi
done

# === Temporary directory ===
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# === Helper: canonical vector filename ===
vec_filename() {
  local file="$1" rep="$2"
  local base clean_base
  base=$(basename "$file" .bedgraph)
  clean_base=$(echo "$base" | sed 's/[^a-zA-Z0-9]/_/g')
  echo "$tmpdir/${clean_base}_${rep}.vec"
}

# === Auto-detect replicons if not provided ===
if [ "$auto_detect_replicons" = true ]; then
  echo "Auto-detecting replicons from input files..."
  mapfile -t replicons < <(awk '{print $1}' "${bedgraph_files[@]}" | sort -u)
  echo "Detected replicons: ${replicons[*]}"
fi

# === Determine max end position per replicon ===
declare -A replicon_lengths
for rep in "${replicons[@]}"; do
  max_len=$(awk -v rep="$rep" '$1==rep && $3>max {max=$3} END{print max}' "${bedgraph_files[@]}")
  if [ -z "$max_len" ]; then
    echo "Warning: Replicon '$rep' not found in any files. Skipping."
    continue
  fi
  replicon_lengths["$rep"]=$max_len
done

# === Generate per-replicon, per-file vectors ===
echo "Generating coverage vectors..."
for rep in "${replicons[@]}"; do
  [[ -z "${replicon_lengths[$rep]:-}" ]] && continue
  max_len=${replicon_lengths["$rep"]}
  for file in "${bedgraph_files[@]}"; do
    out_vector=$(vec_filename "$file" "$rep")
    awk -v rep="$rep" -v max_pos="$max_len" '
    BEGIN {
      for (i = 1; i <= max_pos; i++) vec[i] = 0
    }
    $1 == rep {
      for (i = $2 + 1; i <= $3; i++) {
        vec[i] = $4
      }
    }
    END {
      for (i = 1; i <= max_pos; i++) print vec[i]
    }' "$file" > "$out_vector"
  done
done

# === Merge vectors into output file ===
echo "Writing merged matrix to $output_file..."
any_written=false
> "$output_file"
for rep in "${replicons[@]}"; do
  [[ -z "${replicon_lengths[$rep]:-}" ]] && continue
  echo "  Merging replicon: $rep"
  vec_list=()
  for file in "${bedgraph_files[@]}"; do
    vec_list+=("$(vec_filename "$file" "$rep")")
  done
  if [ "$include_replicon_column" = true ]; then
    paste "${vec_list[@]}" | awk -v rep="$rep" '{print rep "\t" $0}' >> "$output_file"
  else
    paste "${vec_list[@]}" >> "$output_file"
  fi
  any_written=true
done

if [ "$any_written" = false ]; then
  echo "Error: No replicons were found in input files. Output is empty." >&2
  exit 1
fi

echo "Done. Output saved to $output_file"
