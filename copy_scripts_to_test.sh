#!/usr/bin/env bash
set -euo pipefail

BASE="/mnt/c/Users/mbroghammer/NextcloudBIO3/Documents/software/projects"
DEST="${BASE}/pre-commit/test"
DATE=$(date +%Y-%m-%d)

SCRIPTS=(
  "annotation_manager/annotation_manager.sh"
  "bedgraph2grp/bedgraph2grp.sh"
  "CyanoBiscot/00_cell_gate_fcs_files.py"
  "CyanoBulkRNAseq_PE_workflow/Snakefile"
  "deseq2.r/deseq2.r"
  "deseq2_rgeneda/analyze_gene_counts.sh"
  "deseq2_rgeneda/analyze_transcript_counts.sh"
  "gene_view.r/gene_viewe.r"
  "gff3/merge_and_deduceUTRs.sh"
  "metaboanalyst.r/metaboanalyst.r"
  "metabolites_clean_xlsx/clean_metabolites_xlsx.py"
  "normalize_grps/normalize_grps.sh"
  "proBAM.r/pipeline.sh"
  "replicon_copy_number_variation/replicon_number_analysis.sh"
  "RGenEDA.r/rgeneda.r"
  "RNAplotte.r/RNAplotter.R"
  "tpm_normalize_htseq_counts/tpm_normalize_htseq_counts.py"
  "volcano_plot.r/volcano_plot.r"
)

mkdir -p "$DEST"

for rel_path in "${SCRIPTS[@]}"; do
  src="${BASE}/${rel_path}"
  filename=$(basename "$rel_path")
  dst="${DEST}/${DATE}_${filename}"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    echo "OK      $filename"
  else
    echo "MISSING $src"
  fi
done
