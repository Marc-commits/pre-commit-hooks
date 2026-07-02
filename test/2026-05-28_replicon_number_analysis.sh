#!/usr/bin/env bash
# Run the full replicon copy-number pipeline:
#   1. samtools idxstats on each BAM (01_run_idxstats.sh)
#   2. RPKM, chr-ratio, DESeq2, plots    (02_analyze_replicons.r)
#
# Usage: bash replicon_number_analysis.sh --bam-dir <DIR> --metadata <FILE> --outdir <DIR>
#        bash replicon_number_analysis.sh --bam-dir path/to/bams --metadata metadata.csv --outdir results
#
# stdin:  not used
# stdout: progress messages
# Version: 0.1.0
# Author: Marc Broghammer
# Email: marc.broghammer@gmx.de

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	cat <<EOF
Usage: $0 --bam-dir <DIR> --metadata <FILE> --outdir <DIR>

Options:
  --bam-dir   DIR    Directory containing *.bam files (required)
  --metadata  FILE   Metadata CSV with columns: sample, condition (required)
  --outdir    DIR    Output directory for idxstats/ and analysis results (required)
  -h, --help         Show this help and exit
  -V, --version      Show version and exit

EOF
}

VERSION="0.1.0"
BAM_DIR=""
METADATA=""
OUTDIR=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--bam-dir)
		BAM_DIR="$2"
		shift 2
		;;
	--metadata)
		METADATA="$2"
		shift 2
		;;
	--outdir)
		OUTDIR="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	-V | --version)
		echo "replicon_number_analysis.sh v${VERSION}"
		exit 0
		;;
	*)
		echo "ERROR: unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

if [[ -z "$BAM_DIR" || -z "$METADATA" || -z "$OUTDIR" ]]; then
	echo "ERROR: --bam-dir, --metadata and --outdir are all required" >&2
	usage >&2
	exit 1
fi

if [[ ! -d "$BAM_DIR" ]]; then
	echo "ERROR: BAM directory not found: $BAM_DIR" >&2
	exit 1
fi

if [[ ! -f "$METADATA" ]]; then
	echo "ERROR: metadata file not found: $METADATA" >&2
	exit 1
fi

mkdir -p "$OUTDIR"

# ── Step 1: idxstats ──────────────────────────────────────────────────────────
IDXSTATS_DIR="${OUTDIR}/idxstats"
mkdir -p "$IDXSTATS_DIR"

BAMS=("$BAM_DIR"/*.bam)
if [[ ${#BAMS[@]} -eq 0 || ! -f "${BAMS[0]}" ]]; then
	echo "ERROR: no *.bam files found in $BAM_DIR" >&2
	exit 1
fi

echo "==> Step 1: running idxstats on ${#BAMS[@]} BAM files"
bash "${SCRIPT_DIR}/01_run_idxstats.sh" "${BAMS[@]}"

# 01_run_idxstats.sh always writes to idxstats/ relative to CWD; move if needed
if [[ "$(realpath idxstats)" != "$(realpath "$IDXSTATS_DIR")" ]]; then
	mv idxstats/*.idxstats "$IDXSTATS_DIR/"
	rmdir --ignore-fail-on-non-empty idxstats
fi

# ── Step 2: R analysis ────────────────────────────────────────────────────────
echo ""
echo "==> Step 2: running replicon analysis"
Rscript "${SCRIPT_DIR}/02_analyze_replicons.r" \
	--idxstats-dir "$IDXSTATS_DIR" \
	--metadata "$METADATA" \
	--outdir "$OUTDIR"

echo ""
echo "==> Pipeline complete. Results in: $OUTDIR"
