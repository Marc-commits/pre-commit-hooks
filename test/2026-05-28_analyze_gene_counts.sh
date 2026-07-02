#!/bin/bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_DESEQ2=flirtini.cyanolab.biologie.privat:5000/deseq2:latest
IMAGE_RGENEDA=flirtini.cyanolab.biologie.privat:5000/rgeneda-analysis:latest

mkdir -p "${WORKDIR}/09_deseq2/gene_results" "${WORKDIR}/10_rgeneda/gene_results"

echo "=== DESeq2: gene counts ==="
docker run --rm \
  -v "${WORKDIR}/09_deseq2:/data" \
  "${IMAGE_DESEQ2}" \
  --counts=/data/gene_counts_matrix.tsv \
  --metadata=/data/metadata.tsv \
  --design='~ strain * timepoint' \
  --contrast='strain,asl3888as,pMBA51' \
  --outdir=/data/gene_results \
  --alpha=0.05 --lfc=1 \
  --min-count=10 --min-samples=3 \
  --save-dds --plots --vst --norm-counts \
  |& tee "${WORKDIR}/09_deseq2/gene_results/deseq2.log"

echo "=== rgeneda: gene dds.rds ==="
docker run --rm \
  -v "${WORKDIR}/09_deseq2:/data" \
  -v "${WORKDIR}/10_rgeneda:/rgeneda" \
  "${IMAGE_RGENEDA}" \
  --input=/data/gene_results/deseq2_object.rds \
  --output-dir=/rgeneda/gene_results \
  --group-var=strain \
  --comparison-num=asl3888as \
  --comparison-den=pMBA51 \
  --n-hvgs=2000 --alpha=0.05 --lfc-threshold=1 \
  --verbose --skip-dashboard \
  |& tee "${WORKDIR}/10_rgeneda/gene_results/rgeneda.log"
