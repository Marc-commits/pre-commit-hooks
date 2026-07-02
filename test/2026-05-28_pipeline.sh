#!/usr/bin/env bash
# DiaNN .parquet → proBAM pipeline orchestrator.
# version: 0.1.0
# author: Marc Broghammer
# email: marc.broghammer@gmx.de
#
# Usage:
#   pipeline.sh --parquet <file> --gff3 <file> --proteins <fasta>
#               --genome <fasta> --output <dir>
#               [--fdr 0.01] [--organism <name>] [--taxonomy-id <id>]
#               [--skip-analysis] [--score-col Q.Value] [--id-attr protein_id]
#               [--probamtools <dir>] [--jobs N] [--chunks N]
#               [--version | -V]
#
# --jobs N     Number of parallel workers for PSMtab2SAM (step 3).
#              Requires GNU parallel. Default: 1 (serial).
# --chunks N   Number of PSM chunks to create. Default: 4 × --jobs.
#              Decouples chunk count from worker count: smaller chunks limit
#              the O(n^1.8) rbind overhead inside proBAMr.
#
# Stdin:  not used
# Stdout: pipeline progress messages

VERSION="0.1.0"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
PARQUET=""
GFF3=""
PROTEINS=""
GENOME=""
OUTPUT=""
FDR="0.01"
ORGANISM="unknown"
TAXONOMY_ID=""
SKIP_ANALYSIS=false
SCORE_COL="Q.Value"
ID_ATTR="protein_id"
PROBAMTOOLS=""
JOBS=1
CHUNKS=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--parquet)
		PARQUET="$2"
		shift 2
		;;
	--gff3)
		GFF3="$2"
		shift 2
		;;
	--proteins)
		PROTEINS="$2"
		shift 2
		;;
	--genome)
		GENOME="$2"
		shift 2
		;;
	--output)
		OUTPUT="$2"
		shift 2
		;;
	--fdr)
		FDR="$2"
		shift 2
		;;
	--organism)
		ORGANISM="$2"
		shift 2
		;;
	--taxonomy-id)
		TAXONOMY_ID="$2"
		shift 2
		;;
	--score-col)
		SCORE_COL="$2"
		shift 2
		;;
	--id-attr)
		ID_ATTR="$2"
		shift 2
		;;
	--probamtools)
		PROBAMTOOLS="$2"
		shift 2
		;;
	--jobs)
		JOBS="$2"
		shift 2
		;;
	--chunks)
		CHUNKS="$2"
		shift 2
		;;
	--skip-analysis)
		SKIP_ANALYSIS=true
		shift
		;;
	-h | --help)
		sed -n '2,22p' "$0"
		exit 0
		;;
	--version | -V)
		echo "pipeline.sh $VERSION"
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		exit 1
		;;
	esac
done

for var in PARQUET GFF3 PROTEINS GENOME OUTPUT; do
	[[ -n "${!var}" ]] || {
		echo "ERROR: --${var,,} is required" >&2
		exit 1
	}
done

[[ -z "$CHUNKS" ]] && CHUNKS=$((JOBS * 4))

mkdir -p "$OUTPUT"
ANNO_DIR="$OUTPUT/annotation"
PSM_TSV="$OUTPUT/passedPSM.tsv"
SAM_FILE="$OUTPUT/out.sam"
BAM_PREFIX="$OUTPUT/out"

# ---------------------------------------------------------------------------
# Step 0: dependency check
# ---------------------------------------------------------------------------
echo "=== [0/5] Checking dependencies ==="
Rscript "${SCRIPT_DIR}/check_deps.r"

# ---------------------------------------------------------------------------
# Steps 1+2: Prepare annotation and convert parquet — run in parallel
# ---------------------------------------------------------------------------
echo ""
echo "=== [1/5] Preparing annotation (background) ==="
ANNO_ARGS=(--gff3 "$GFF3" --proteins "$PROTEINS" --genome "$GENOME"
	--output "$ANNO_DIR" --organism "$ORGANISM" --id-attr "$ID_ATTR")
[[ -n "$TAXONOMY_ID" ]] && ANNO_ARGS+=(--taxonomy-id "$TAXONOMY_ID")
Rscript "${SCRIPT_DIR}/prepare_annotation.r" "${ANNO_ARGS[@]}" &
ANNO_PID=$!

echo "=== [2/5] Converting DiaNN parquet → passedPSM TSV ==="
Rscript "${SCRIPT_DIR}/diann_to_psm.r" \
	--parquet "$PARQUET" \
	--output "$PSM_TSV" \
	--fdr "$FDR" \
	--score-col "$SCORE_COL"

wait "$ANNO_PID" || {
	echo "ERROR: prepare_annotation.r failed" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Step 3: PSMtab2SAM → SAM  (parallel chunks when --jobs N > 1)
# ---------------------------------------------------------------------------
echo ""
echo "=== [3/5] Running PSMtab2SAM → SAM (jobs=$JOBS, chunks=$CHUNKS) ==="
if [[ "$JOBS" -gt 1 ]]; then
	command -v parallel >/dev/null 2>&1 || {
		echo "ERROR: --jobs requires GNU parallel in PATH" >&2
		exit 1
	}
	CHUNK_DIR="$OUTPUT/.psm_chunks"
	rm -rf "$CHUNK_DIR"
	mkdir -p "$CHUNK_DIR"
	HEADER=$(head -1 "$PSM_TSV")
	NPSM=$(($(wc -l <"$PSM_TSV") - 1))
	CHUNK_SIZE=$(((NPSM + CHUNKS - 1) / CHUNKS))
	# Split data rows, prepend header to each chunk
	tail -n +2 "$PSM_TSV" |
		split -l "$CHUNK_SIZE" - "$CHUNK_DIR/chunk_"
	for f in "$CHUNK_DIR"/chunk_*; do
		{
			printf '%s\n' "$HEADER"
			cat "$f"
		} >"${f}.tsv"
		rm -f "$f"
	done
	parallel --line-buffer -j "$JOBS" \
		Rscript "${SCRIPT_DIR}/proBAMr_to_sam.r" \
		--psm '{}' \
		--annotation "$ANNO_DIR" \
		--output '{.}.sam' \
		--score-col mvh \
		::: "$CHUNK_DIR"/*.tsv
	cat "$CHUNK_DIR"/*.sam >"$SAM_FILE"
	rm -rf "$CHUNK_DIR"
else
	Rscript "${SCRIPT_DIR}/proBAMr_to_sam.r" \
		--psm "$PSM_TSV" \
		--annotation "$ANNO_DIR" \
		--output "$SAM_FILE" \
		--score-col "mvh"
fi

# ---------------------------------------------------------------------------
# Step 4: SAM → sorted proBAM
# ---------------------------------------------------------------------------
echo ""
echo "=== [4/5] SAM → sorted proBAM ==="
bash "${SCRIPT_DIR}/sam_to_bam.sh" --genome "$GENOME" "$SAM_FILE" "$BAM_PREFIX"

# ---------------------------------------------------------------------------
# Step 5: proBAMtools analysis
# ---------------------------------------------------------------------------
if [[ "$SKIP_ANALYSIS" == false ]]; then
	echo ""
	echo "=== [5/5] proBAMtools analysis ==="
	ANALYSIS_ARGS=(
		--probam "${BAM_PREFIX}_sorted.probam"
		--annotation "$ANNO_DIR"
		--output "$OUTPUT/analysis"
	)
	[[ -n "$PROBAMTOOLS" ]] && ANALYSIS_ARGS+=(--probamtools "$PROBAMTOOLS")
	Rscript "${SCRIPT_DIR}/proBAMtools_analysis.r" "${ANALYSIS_ARGS[@]}"
else
	echo ""
	echo "=== [5/5] Skipping proBAMtools analysis (--skip-analysis) ==="
fi

echo ""
echo "Pipeline complete. Outputs in: $OUTPUT"
