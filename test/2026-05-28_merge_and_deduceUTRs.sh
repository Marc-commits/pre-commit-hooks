#!/usr/bin/env bash
# Version: 0.1.0
# Author: Marc Broghammer
# Email: marc.broghammer@gmx.de
set -euo pipefail

VERSION="0.1.0"

usage() {
	cat <<EOF
Usage: merge_and_deduceUTRs.sh [--help] [--version|-V]

Pipeline: merge GFF3 gene/transcript annotations, view stats, deduce UTRs, view final stats.

Steps:
  1. merge_gff3.py   -- merge gene and transcript GFF files
  2. view_gff3.py    -- inspect merged result
  3. deduce_UTRs.py  -- deduce UTR boundaries from transcript TSS data
  4. view_gff3.py    -- inspect final GFF3 with UTRs

Input/output paths are hardcoded for the current project layout.
EOF
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		usage
		exit 0
		;;
	--version | -V)
		echo "merge_and_deduceUTRs.sh $VERSION"
		exit 0
		;;
	esac
done

merge_gff3.py --genes ../2025-03-11_gff/anotacion_definitiva_plus_ncRNA_120225.gff --transcripts ../NC_003272.1_transcripts.gff --fill-missing-transcripts --unmatched-genes genes_transcripts_unmatched_genes.gff3 --unmatched-transcripts genes_transcripts_unmatched_transcripts.gff3 -o genes_transcripts.gff3 |& tee genes_transcripts_merge.log

view_gff3.py genes_transcripts.gff3 --tree --show-attrs -v --stats-csv genes_transcripts_stats.csv |& tee genes_transcripts.stats

deduce_UTRs.py genes_transcripts.gff3 --transcripts ../NC_003272.1_transcripts.gff -o genes_transcripts_UTRs.gff3 --stats-csv genes_transcripts_UTRs.csv -v |& tee genes_transcripts_UTRs.log

view_gff3.py genes_transcripts_UTRs.gff3 --tree --show-attrs -v --stats-csv genes_transcripts_deduceUTRs_stats.csv |& tee genes_transcripts_UTRs_view.stats
