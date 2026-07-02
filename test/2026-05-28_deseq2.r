#!/usr/bin/env r
#
# DESeq2 Differential Expression Analysis - Command Line Interface
# Author: Marc Broghammer
# Dependencies: littler, docopt, DESeq2, ggplot2, pheatmap

"DESeq2 Differential Expression Analysis

Usage:
  deseq2.r --counts=<file> --metadata=<file> --design=<formula> [--contrast=<spec>] [--outdir=<dir>] [--alpha=<num>] [--lfc=<num>] [--min-count=<num>] [--min-samples=<num>] [--save-dds] [--norm-counts] [--plots] [--rlog] [--vst]
  deseq2.r (-h | --help)
  deseq2.r --version

Options:
  -h --help              Show this help message
  --version              Show version
  --counts=<file>        Path to count matrix file (CSV or TSV format)
  --metadata=<file>      Path to sample metadata file (CSV or TSV format)
  --design=<formula>     Design formula (e.g., '~ condition' or '~ batch + condition')
  --contrast=<spec>      Contrast specification as 'factor,numerator,denominator' (e.g., 'condition,treated,control')
  --outdir=<dir>         Output directory [default: ./deseq2_results]
  --alpha=<num>          Adjusted p-value cutoff [default: 0.05]
  --lfc=<num>            Log2 fold change threshold for filtering [default: 0]
  --min-count=<num>      Minimum count threshold for pre-filtering [default: 10]
  --min-samples=<num>    Minimum number of samples that must meet min-count threshold [default: 1]
  --save-dds             Save DESeq2 object (dds) as RDS file for later use
  --norm-counts          Output normalized counts
  --plots                Generate diagnostic plots (PCA, dispersion, MA, volcano)
  --rlog                 Use rlog transformation for plots (slower, better for small datasets)
  --vst                  Use VST transformation for plots (faster, default)

Pre-filtering guide (--min-count / --min-samples):
    count=10 / samples=1   Keep genes with >= 10 total counts (default)
    count=10 / samples=3   Keep genes with >= 10 counts in >= 3 samples
    count=5  / samples=2   Keep genes with >= 5 counts in >= 2 samples
    count=0  / samples=0   No pre-filtering (not recommended)

Examples:
  # Using CSV files with default pre-filtering
  deseq2.r --counts=counts.csv --metadata=metadata.csv --design='~ condition' --contrast='condition,treated,control' --plots --save-dds

  # Using TSV files with stricter pre-filtering
  deseq2.r --counts=counts.tsv --metadata=samples.tsv --design='~ batch + treatment' --min-count=10 --min-samples=3 --alpha=0.01 --lfc=1 --save-dds

  # Minimal pre-filtering for low-count datasets
  deseq2.r --counts=counts.csv --metadata=metadata.csv --design='~ condition' --min-count=5 --min-samples=2 --save-dds

Input File Formats:
  Both CSV and TSV formats are supported!
  - Files ending in .csv are read as comma-separated
  - Files ending in .tsv, .txt, or other extensions are read as tab-separated

  Count matrix: First column = gene IDs, remaining columns = sample counts
                Header row with sample names required
  Metadata:     First column = sample IDs (must match count matrix columns)
                Additional columns = experimental factors/conditions

" -> doc

# Load required libraries with error handling
suppressMessages({
  if (!require("docopt", quietly = TRUE)) {
    stop("Package 'docopt' is required. Install with: install.packages('docopt')")
  }
  library(docopt)
})

# Parse arguments
opts <- docopt(doc, version = "DESeq2 CLI v0.3.0")

# Function to load packages with helpful error messages
load_package <- function(pkg, bioc = FALSE) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    if (bioc) {
      stop(
        sprintf("Bioconductor package '%s' is required but not installed.\n", pkg),
        "Install with: BiocManager::install('", pkg, "')\n",
        "If BiocManager is not installed: install.packages('BiocManager')"
      )
    } else {
      stop(
        sprintf("Package '%s' is required but not installed.\n", pkg),
        sprintf("Install with: install.packages('%s')", pkg)
      )
    }
  }
}

# Load required packages
suppressMessages({
  load_package("DESeq2", bioc = TRUE)
  load_package("ggplot2")
  if (opts$plots) {
    load_package("pheatmap")
  }
})

# Helper function for logging
log_message <- function(msg) {
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg))
}

# Helper function to create separator lines
log_separator <- function() {
  cat(paste(rep("=", 70), collapse = ""), "\n")
}

# Create output directory
if (!dir.exists(opts$outdir)) {
  dir.create(opts$outdir, recursive = TRUE)
  log_message(sprintf("Created output directory: %s", opts$outdir))
}

# Start analysis
log_separator()
log_message("DESeq2 Differential Expression Analysis")
log_separator()

# ============================================================================
# 1. Load and validate input data
# ============================================================================
log_message("STEP 1: Loading input data")
log_message(sprintf("  Count matrix: %s", opts$counts))
log_message(sprintf("  Metadata: %s", opts$metadata))

# Load count matrix
counts <- tryCatch(
  {
    # Detect separator
    if (grepl("\\.csv$", opts$counts, ignore.case = TRUE)) {
      read.csv(opts$counts, row.names = 1, check.names = FALSE)
    } else {
      read.table(opts$counts,
        header = TRUE, row.names = 1, sep = "\t",
        check.names = FALSE, comment.char = ""
      )
    }
  },
  error = function(e) {
    stop(sprintf("Error reading count matrix: %s", e$message))
  }
)

log_message(sprintf("  Loaded %d genes x %d samples", nrow(counts), ncol(counts)))

# Validate counts are numeric
if (!all(sapply(counts, is.numeric))) {
  stop("Count matrix must contain only numeric values")
}

# Check for negative values
if (any(counts < 0, na.rm = TRUE)) {
  stop("Count matrix contains negative values")
}

# Convert to integer matrix
counts <- as.matrix(counts)
mode(counts) <- "integer"

# Load metadata
metadata <- tryCatch(
  {
    if (grepl("\\.csv$", opts$metadata, ignore.case = TRUE)) {
      read.csv(opts$metadata, row.names = 1, check.names = FALSE)
    } else {
      read.table(opts$metadata,
        header = TRUE, row.names = 1, sep = "\t",
        check.names = FALSE, comment.char = ""
      )
    }
  },
  error = function(e) {
    stop(sprintf("Error reading metadata: %s", e$message))
  }
)

log_message(sprintf("  Loaded metadata for %d samples", nrow(metadata)))
log_message(sprintf("  Metadata columns: %s", paste(colnames(metadata), collapse = ", ")))

# Validate sample names match
samples_in_counts <- colnames(counts)
samples_in_metadata <- rownames(metadata)

if (!all(samples_in_counts %in% samples_in_metadata)) {
  missing <- setdiff(samples_in_counts, samples_in_metadata)
  stop(sprintf(
    "Samples in count matrix not found in metadata: %s",
    paste(missing, collapse = ", ")
  ))
}

# Reorder metadata to match count matrix
metadata <- metadata[samples_in_counts, , drop = FALSE]
log_message("  Sample names validated and metadata reordered to match count matrix")

# ============================================================================
# 2. Create DESeq2 dataset
# ============================================================================
log_separator()
log_message("STEP 2: Creating DESeq2 dataset")

# Parse design formula
design_formula <- tryCatch(
  {
    as.formula(opts$design)
  },
  error = function(e) {
    stop(sprintf("Invalid design formula '%s': %s", opts$design, e$message))
  }
)

log_message(sprintf("  Design formula: %s", opts$design))

# Validate that design formula variables exist in metadata
design_vars <- all.vars(design_formula)
missing_vars <- setdiff(design_vars, colnames(metadata))
if (length(missing_vars) > 0) {
  stop(
    sprintf(
      "Design formula variables not found in metadata: %s\n",
      paste(missing_vars, collapse = ", ")
    ),
    sprintf("Available columns: %s", paste(colnames(metadata), collapse = ", "))
  )
}

# Create DESeqDataSet
dds <- tryCatch(
  {
    DESeqDataSetFromMatrix(
      countData = counts,
      colData = metadata,
      design = design_formula
    )
  },
  error = function(e) {
    stop(sprintf("Error creating DESeq2 dataset: %s", e$message))
  }
)

log_message(sprintf(
  "  Created DESeqDataSet with %d genes and %d samples",
  nrow(dds), ncol(dds)
))

# Pre-filtering: remove genes with very low counts
min_count <- as.numeric(opts$min_count)
min_samples <- as.numeric(opts$min_samples)

if (min_count > 0 && min_samples > 0) {
  if (min_samples == 1) {
    # Keep genes with at least min_count total counts
    keep <- rowSums(counts(dds)) >= min_count
    log_message(sprintf("  Pre-filtering: keeping genes with >= %d total counts", min_count))
  } else {
    # Keep genes with at least min_count in at least min_samples samples
    keep <- rowSums(counts(dds) >= min_count) >= min_samples
    log_message(sprintf(
      "  Pre-filtering: keeping genes with >= %d counts in >= %d samples",
      min_count, min_samples
    ))
  }

  genes_before <- nrow(dds)
  dds <- dds[keep, ]
  genes_after <- nrow(dds)
  genes_removed <- genes_before - genes_after

  log_message(sprintf(
    "  Retained %d/%d genes (removed %d genes, %.1f%%)",
    genes_after, genes_before, genes_removed,
    100 * genes_removed / genes_before
  ))
} else {
  log_message("  Pre-filtering: DISABLED (min-count=0 or min-samples=0)")
  log_message("  WARNING: Running without pre-filtering is not recommended!")
}

# ============================================================================
# 3. Run DESeq2 analysis
# ============================================================================
log_separator()
log_message("STEP 3: Running DESeq2 differential expression analysis")
log_message("  This may take several minutes depending on dataset size...")

dds <- tryCatch(
  {
    DESeq(dds)
  },
  error = function(e) {
    stop(sprintf("Error running DESeq2 analysis: %s", e$message))
  }
)

log_message("  DESeq2 analysis complete")

# Save DESeq2 object if requested
if (opts$save_dds) {
  dds_file <- file.path(opts$outdir, "deseq2_object.rds")
  saveRDS(dds, file = dds_file)
  log_message(sprintf("  Saved DESeq2 object: %s", dds_file))
  log_message("  (Load later with: dds <- readRDS('deseq2_object.rds'))")
}

# ============================================================================
# 4. Extract and process results
# ============================================================================
log_separator()
log_message("STEP 4: Extracting results")

# Parse contrast if provided
if (!is.null(opts$contrast)) {
  contrast_parts <- strsplit(opts$contrast, ",")[[1]]
  if (length(contrast_parts) != 3) {
    stop("Contrast must be in format 'factor,numerator,denominator'")
  }
  contrast_vec <- c(
    trimws(contrast_parts[1]),
    trimws(contrast_parts[2]),
    trimws(contrast_parts[3])
  )

  # Validate contrast
  factor_name <- contrast_vec[1]
  if (!factor_name %in% colnames(colData(dds))) {
    stop(sprintf(
      "Contrast factor '%s' not found in metadata columns: %s",
      factor_name, paste(colnames(colData(dds)), collapse = ", ")
    ))
  }

  factor_levels <- levels(colData(dds)[[factor_name]])
  if (is.null(factor_levels)) {
    factor_levels <- unique(as.character(colData(dds)[[factor_name]]))
  }

  if (!contrast_vec[2] %in% factor_levels || !contrast_vec[3] %in% factor_levels) {
    stop(sprintf("Contrast levels must be in: %s", paste(factor_levels, collapse = ", ")))
  }

  log_message(sprintf(
    "  Contrast: %s vs %s (factor: %s)",
    contrast_vec[2], contrast_vec[3], contrast_vec[1]
  ))

  res <- results(dds, contrast = contrast_vec, alpha = as.numeric(opts$alpha))
  contrast_name <- sprintf("%s_%s_vs_%s", contrast_vec[1], contrast_vec[2], contrast_vec[3])
} else {
  # Use default comparison (last factor level vs first)
  res <- results(dds, alpha = as.numeric(opts$alpha))
  log_message("  Using default contrast (last vs first factor level)")
  contrast_name <- "default_contrast"
}

# Order by adjusted p-value
res <- res[order(res$padj), ]

# Print summary
log_message("  Results summary:")
summary(res)

# Get detailed counts
alpha_val <- as.numeric(opts$alpha)
lfc_threshold <- as.numeric(opts$lfc)

total_genes <- sum(!is.na(res$padj))
sig_genes <- sum(res$padj < alpha_val, na.rm = TRUE)
up_genes <- sum(res$padj < alpha_val & res$log2FoldChange > lfc_threshold, na.rm = TRUE)
down_genes <- sum(res$padj < alpha_val & res$log2FoldChange < -lfc_threshold, na.rm = TRUE)

log_message(sprintf("  Total genes tested: %d", total_genes))
log_message(sprintf(
  "  Significant genes (padj < %.3f): %d (%.1f%%)",
  alpha_val, sig_genes, 100 * sig_genes / total_genes
))
log_message(sprintf("  Upregulated (LFC > %.2f): %d", lfc_threshold, up_genes))
log_message(sprintf("  Downregulated (LFC < -%.2f): %d", lfc_threshold, down_genes))

# ============================================================================
# 5. Save results tables
# ============================================================================
log_separator()
log_message("STEP 5: Saving results tables")

# Prepare results dataframe
res_df <- as.data.frame(res)
res_df$gene <- rownames(res_df)
res_df <- res_df[, c("gene", "baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj")]

# All results
results_all_file <- file.path(opts$outdir, sprintf("%s_all_results.csv", contrast_name))
write.csv(res_df, file = results_all_file, row.names = FALSE)
log_message(sprintf("  All results: %s", results_all_file))

# Significant results
res_sig <- res_df[!is.na(res_df$padj) & res_df$padj < alpha_val, ]

if (nrow(res_sig) > 0) {
  # Apply LFC threshold if specified
  if (lfc_threshold > 0) {
    res_sig_filtered <- res_sig[abs(res_sig$log2FoldChange) >= lfc_threshold, ]
    sig_filtered_file <- file.path(
      opts$outdir,
      sprintf("%s_significant_lfc%.2f.csv", contrast_name, lfc_threshold)
    )

    if (nrow(res_sig_filtered) > 0) {
      write.csv(res_sig_filtered, file = sig_filtered_file, row.names = FALSE)
      log_message(sprintf("  Significant (|LFC| >= %.2f): %s", lfc_threshold, sig_filtered_file))
    } else {
      log_message(sprintf("  No genes pass LFC threshold of %.2f", lfc_threshold))
    }
  }

  # All significant (regardless of LFC)
  sig_file <- file.path(opts$outdir, sprintf("%s_significant.csv", contrast_name))
  write.csv(res_sig, file = sig_file, row.names = FALSE)
  log_message(sprintf("  All significant: %s", sig_file))

  # Top upregulated and downregulated
  res_up <- res_sig[res_sig$log2FoldChange > 0, ]
  res_down <- res_sig[res_sig$log2FoldChange < 0, ]

  if (nrow(res_up) > 0) {
    res_up <- res_up[order(-res_up$log2FoldChange), ]
    up_file <- file.path(opts$outdir, sprintf("%s_upregulated.csv", contrast_name))
    write.csv(res_up, file = up_file, row.names = FALSE)
    log_message(sprintf("  Upregulated genes: %s", up_file))
  }

  if (nrow(res_down) > 0) {
    res_down <- res_down[order(res_down$log2FoldChange), ]
    down_file <- file.path(opts$outdir, sprintf("%s_downregulated.csv", contrast_name))
    write.csv(res_down, file = down_file, row.names = FALSE)
    log_message(sprintf("  Downregulated genes: %s", down_file))
  }
} else {
  log_message("  No significant genes found - skipping filtered results files")
}

# Normalized counts if requested
if (opts$norm_counts) {
  log_message("  Saving normalized counts...")
  norm_counts <- counts(dds, normalized = TRUE)
  norm_file <- file.path(opts$outdir, "normalized_counts.csv")
  write.csv(norm_counts, file = norm_file)
  log_message(sprintf("  Normalized counts: %s", norm_file))
}

# ============================================================================
# 6. Generate diagnostic plots
# ============================================================================
if (opts$plots) {
  log_separator()
  log_message("STEP 6: Generating diagnostic plots")

  # Determine transformation method
  if (opts$rlog) {
    log_message("  Computing rlog transformation (this may take a while)...")
    rld <- rlog(dds, blind = FALSE)
    transform_data <- assay(rld)
    transform_obj <- rld
    transform_name <- "rlog"
  } else {
    log_message("  Computing VST transformation...")
    vsd <- vst(dds, blind = FALSE)
    transform_data <- assay(vsd)
    transform_obj <- vsd
    transform_name <- "VST"
  }

  # Get the first grouping variable for PCA coloring
  pca_group <- names(colData(dds))[1]
  log_message(sprintf("  Using '%s' for plot grouping", pca_group))

  # 1. PCA plot
  log_message("  Creating PCA plot...")
  pca_file <- file.path(opts$outdir, "pca_plot.pdf")
  pdf(pca_file, width = 8, height = 6)
  pca_plot <- plotPCA(transform_obj, intgroup = pca_group) +
    theme_bw(base_size = 12) +
    ggtitle(sprintf("PCA Plot (%s transformation)", transform_name)) +
    theme(plot.title = element_text(hjust = 0.5, face = "bold"))
  print(pca_plot)
  dev.off()
  log_message(sprintf("    Saved: %s", pca_file))

  # 2. Dispersion plot
  log_message("  Creating dispersion plot...")
  disp_file <- file.path(opts$outdir, "dispersion_plot.pdf")
  pdf(disp_file, width = 8, height = 6)
  plotDispEsts(dds, main = "Dispersion Estimates")
  dev.off()
  log_message(sprintf("    Saved: %s", disp_file))

  # 3. MA plot
  log_message("  Creating MA plot...")
  ma_file <- file.path(opts$outdir, "ma_plot.pdf")
  pdf(ma_file, width = 8, height = 6)
  plotMA(res,
    alpha = alpha_val,
    main = sprintf("MA Plot (padj < %.3f)", alpha_val),
    ylim = c(-5, 5)
  )
  dev.off()
  log_message(sprintf("    Saved: %s", ma_file))

  # 4. Volcano plot
  log_message("  Creating volcano plot...")
  volcano_file <- file.path(opts$outdir, "volcano_plot.pdf")

  volcano_df <- data.frame(
    log2FoldChange = res$log2FoldChange,
    pvalue = res$pvalue,
    padj = res$padj,
    gene = rownames(res)
  )
  volcano_df <- volcano_df[!is.na(volcano_df$pvalue), ]

  volcano_df$significant <- "Not significant"
  volcano_df$significant[volcano_df$padj < alpha_val &
    volcano_df$log2FoldChange > lfc_threshold] <- "Upregulated"
  volcano_df$significant[volcano_df$padj < alpha_val &
    volcano_df$log2FoldChange < -lfc_threshold] <- "Downregulated"

  volcano_plot <- ggplot(volcano_df, aes(
    x = log2FoldChange, y = -log10(pvalue),
    color = significant
  )) +
    geom_point(alpha = 0.4, size = 1.2) +
    scale_color_manual(values = c(
      "Upregulated" = "red",
      "Downregulated" = "blue",
      "Not significant" = "gray50"
    )) +
    geom_vline(
      xintercept = c(-lfc_threshold, lfc_threshold),
      linetype = "dashed", alpha = 0.5, color = "black"
    ) +
    geom_hline(
      yintercept = -log10(max(res$pvalue[res$padj < alpha_val], na.rm = TRUE)),
      linetype = "dashed", alpha = 0.5, color = "black"
    ) +
    theme_bw(base_size = 12) +
    labs(
      title = "Volcano Plot",
      x = "Log2 Fold Change",
      y = "-Log10 P-value",
      color = ""
    ) +
    theme(
      legend.position = "top",
      plot.title = element_text(hjust = 0.5, face = "bold")
    )

  ggsave(volcano_file, plot = volcano_plot, width = 8, height = 6)
  log_message(sprintf("    Saved: %s", volcano_file))

  # 5. Sample distance heatmap (only for reasonable number of samples)
  if (ncol(dds) <= 50) {
    log_message("  Creating sample distance heatmap...")
    sampleDists <- dist(t(transform_data))
    sampleDistMatrix <- as.matrix(sampleDists)

    heatmap_file <- file.path(opts$outdir, "sample_distance_heatmap.pdf")
    pdf(heatmap_file, width = 10, height = 8)
    pheatmap(sampleDistMatrix,
      clustering_distance_rows = sampleDists,
      clustering_distance_cols = sampleDists,
      main = "Sample-to-Sample Distance Heatmap",
      fontsize = 10
    )
    dev.off()
    log_message(sprintf("    Saved: %s", heatmap_file))
  } else {
    log_message("  Skipping sample distance heatmap (>50 samples)")
  }

  # 6. Top variable genes heatmap
  if (nrow(dds) >= 20) {
    log_message("  Creating heatmap of top variable genes...")
    topVarGenes <- head(order(rowVars(transform_data), decreasing = TRUE), 50)
    mat <- transform_data[topVarGenes, ]
    mat <- t(scale(t(mat))) # Z-score normalization

    topgenes_file <- file.path(opts$outdir, "top_variable_genes_heatmap.pdf")
    pdf(topgenes_file, width = 10, height = 12)
    pheatmap(mat,
      main = "Top 50 Most Variable Genes",
      fontsize_row = 8,
      fontsize_col = 10,
      show_rownames = TRUE,
      cluster_cols = TRUE,
      cluster_rows = TRUE
    )
    dev.off()
    log_message(sprintf("    Saved: %s", topgenes_file))
  }
}

# ============================================================================
# 7. Save session info
# ============================================================================
log_separator()
log_message("STEP 7: Saving session information")

session_file <- file.path(opts$outdir, "session_info.txt")
sink(session_file)
cat("DESeq2 Analysis Session Information\n")
cat("====================================\n\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")
cat("Command-line arguments:\n")
print(opts)
cat("\n\nSession Info:\n")
sessionInfo()
sink()

log_message(sprintf("  Session info: %s", session_file))

# ============================================================================
# 8. Final summary
# ============================================================================
log_separator()
log_message("ANALYSIS COMPLETE!")
log_separator()
log_message("Summary:")
log_message(sprintf("  Input: %d genes, %d samples", nrow(counts), ncol(counts)))
log_message(sprintf("  After filtering: %d genes", nrow(dds)))
log_message(sprintf("  Significant genes: %d", sig_genes))
log_message(sprintf("  Output directory: %s", opts$outdir))

if (opts$save_dds) {
  log_message("")
  log_message("DESeq2 object saved! You can reload it in R with:")
  log_message(sprintf("  dds <- readRDS('%s')", file.path(opts$outdir, "deseq2_object.rds")))
}

log_separator()
