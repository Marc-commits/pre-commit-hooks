#!/usr/bin/env r

"RGenEDA Analysis Pipeline - Post-DESeq2 Processing

This script performs exploratory data analysis on DESeq2-processed RNA-seq data
using the RGenEDA package. It expects a DESeqDataSet object saved as an RDS file.

Usage:
  rgeneda.r --input=<file> [options]
  rgeneda.r (-h | --help)
  rgeneda.r --version

Options:
  -h --help                         Show this help message and exit.
  --version                         Show version.
  
  Required:
  --input=<file>                    Path to RDS file containing DESeqDataSet object.
  
  Output:
  --output-dir=<dir>                Output directory for results [default: ./rgeneda_output].
  --prefix=<name>                   Prefix for output files [default: analysis].
  --save-geneda=<file>              Save GenEDA object to specified RDS file.
  
  GenEDA Object Setup:
  --group-var=<var>                 Main grouping variable from metadata [default: Genotype].
  --color-palette=<colors>          Comma-separated colors for groups (e.g., steelblue3,firebrick3).
  
  HVG Settings:
  --n-hvgs=<n>                      Number of highly variable genes to identify [default: 2000].
  
  PCA Settings:
  --pca-x=<pc>                      PC for x-axis in PCA plot [default: 1].
  --pca-y=<pc>                      PC for y-axis in PCA plot [default: 2].
  --n-pcs-corr=<n>                  Number of PCs for eigencorrelation [default: 5].
  
  DEG Settings:
  --alpha=<val>                     Adjusted p-value threshold [default: 0.05].
  --lfc-threshold=<val>             Log2 fold-change threshold [default: 1].
  --comparison-num=<level>          Numerator level for comparison.
  --comparison-den=<level>          Denominator (reference) level for comparison.
  --deg-assay=<name>                Name for DEG assay [default: deg_results].
  
  Heatmap Settings:
  --eigen-pc=<pc>                   PC for eigenvector heatmap [default: PC1].
  --eigen-top-n=<n>                 Number of top genes in eigenvector heatmap [default: 25].
  
  Figure Dimensions:
  --fig-width=<w>                   Figure width in inches [default: 8].
  --fig-height=<h>                  Figure height in inches [default: 6].
  --heatmap-width=<w>               Heatmap width in inches [default: 6].
  --heatmap-height=<h>              Heatmap height in inches [default: 8].
  
  Analysis Steps (use --skip-* to disable individual steps):
  --skip-count-dist                 Skip count distribution plot.
  --skip-distances                  Skip sample distance heatmap.
  --skip-hvg-variance               Skip HVG variance plot.
  --skip-find-hvgs                  Skip finding highly variable genes.
  --skip-pca                        Skip PCA calculation.
  --skip-pca-plot                   Skip PCA scatter plot.
  --skip-scree                      Skip scree plot.
  --skip-eigen-heatmap              Skip eigenvector heatmap.
  --skip-eigen-corr                 Skip eigencorrelation plot.
  --skip-deg-analysis               Skip all DEG analysis steps.
  --skip-pval-hist                  Skip p-value histogram.
  --skip-ma-plot                    Skip MA plot.
  --skip-volcano                    Skip volcano plot.
  --skip-dashboard                  Skip DE dashboard.
  
  Other:
  --verbose                         Print detailed progress messages.
  --seed=<n>                        Random seed for reproducibility [default: 42].

Examples:
  # Basic analysis with default settings
  rgeneda.r --input=dds.rds
  
  # Custom analysis with specific parameters
  rgeneda.r --input=dds.rds --output-dir=results --n-hvgs=3000 --alpha=0.01 --lfc-threshold=2
  
  # Save GenEDA object to custom location
  rgeneda.r --input=dds.rds --save-geneda=my_geneda.rds
  
  # Skip certain steps
  rgeneda.r --input=dds.rds --skip-dashboard --skip-eigen-heatmap
  
  # Specify comparison levels for volcano plot
  rgeneda.r --input=dds.rds --comparison-num=Snai1_KO --comparison-den=WT

Author:
  Converted from RGenEDA vignette (https://mikemartinez99.github.io/RGenEDA/)
  
" -> doc

# Load required libraries
suppressPackageStartupMessages({
  library(docopt)
  library(DESeq2)
  library(RGenEDA)
  library(ggplot2)
  library(pheatmap)
})

# Parse command line arguments
opts <- docopt(doc, version = "RGenEDA Analysis Pipeline v0.1.0")

# Helper function for verbose printing
vcat <- function(...) {
  if (opts$verbose) {
    cat("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", ..., "\n", sep = "")
  }
}

# Set random seed
set.seed(as.integer(opts$seed))

# Create output directory
output_dir <- opts$output_dir
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  vcat("Created output directory: ", output_dir)
}

prefix <- opts$prefix

# Helper function to construct output path
make_path <- function(filename) {
  file.path(output_dir, paste0(prefix, "_", filename))
}

# ============================================================================
# STEP 1: Load DESeqDataSet
# ============================================================================
vcat("Loading DESeqDataSet from: ", opts$input)

if (!file.exists(opts$input)) {
  stop("Input file does not exist: ", opts$input)
}

dds <- readRDS(opts$input)

if (!inherits(dds, "DESeqDataSet")) {
  stop("Input file must contain a DESeqDataSet object")
}

vcat("Loaded DESeqDataSet with ", nrow(dds), " genes and ", ncol(dds), " samples")

# ============================================================================
# STEP 2: Extract normalized counts and metadata
# ============================================================================
vcat("Extracting normalized counts using rlog transformation...")

# Check if DESeq has been run
if (!"results" %in% slotNames(dds) || is.null(mcols(dds)$dispersion)) {
  vcat("Running DESeq2 analysis...")
  dds <- DESeq(dds)
}

# Apply rlog transformation
rld <- rlog(dds, blind = FALSE)
mat <- assay(rld)

# Extract metadata
metadata <- as.data.frame(colData(dds))

vcat("Normalized matrix dimensions: ", nrow(mat), " genes x ", ncol(mat), " samples")

# ============================================================================
# STEP 3: Setup color palette
# ============================================================================
group_var <- opts$group_var

if (!group_var %in% colnames(metadata)) {
  stop("Group variable '", group_var, "' not found in metadata. Available columns: ", 
       paste(colnames(metadata), collapse = ", "))
}

# Factor the grouping variable
metadata[[group_var]] <- factor(metadata[[group_var]])
levels_group <- levels(metadata[[group_var]])

vcat("Grouping variable: ", group_var, " with levels: ", paste(levels_group, collapse = ", "))

# Setup colors
if (!is.null(opts$color_palette)) {
  colors <- unlist(strsplit(opts$color_palette, ","))
  if (length(colors) != length(levels_group)) {
    warning("Number of colors provided (", length(colors), 
            ") does not match number of groups (", length(levels_group), "). Using default colors.")
    colors <- NULL
  } else {
    names(colors) <- levels_group
  }
} else {
  colors <- NULL
}

# Create color list for RGenEDA
if (!is.null(colors)) {
  colorList <- list()
  colorList[[group_var]] <- colors
} else {
  colorList <- NULL
}

# ============================================================================
# STEP 4: Create GenEDA object
# ============================================================================
vcat("Creating GenEDA object...")

obj <- GenEDA(
  normalized = mat,
  metadata = metadata
)

vcat("GenEDA object created successfully")
print(obj)

# ============================================================================
# STEP 5: Count distribution plot
# ============================================================================
if (!opts$skip_count_dist) {
  vcat("Generating count distribution plot...")
  
  p <- PlotCountDist(obj, split_by = group_var)
  
  output_file <- make_path("count_distribution.png")
  ggsave(output_file, p, width = as.numeric(opts$fig_width), 
         height = as.numeric(opts$fig_height), dpi = 300)
  vcat("Saved: ", output_file)
}

# ============================================================================
# STEP 6: Sample distance heatmap
# ============================================================================
if (!opts$skip_distances) {
  vcat("Generating sample distance heatmap...")
  
  hm <- PlotDistances(
    obj,
    meta_cols = c(group_var),
    palettes = colorList,
    return = "plot"
  )
  
  output_file <- make_path("sample_distances.png")
  GenSave(hm, output_file, 
          width = as.numeric(opts$heatmap_width), 
          height = as.numeric(opts$heatmap_height))
  vcat("Saved: ", output_file)
}

# ============================================================================
# STEP 7: HVG variance plot
# ============================================================================
if (!opts$skip_hvg_variance) {
  vcat("Generating HVG variance plot...")
  
  p <- PlotHVGVariance(obj)
  
  output_file <- make_path("hvg_variance.png")
  ggsave(output_file, p, width = as.numeric(opts$fig_width), 
         height = as.numeric(opts$fig_height), dpi = 300)
  vcat("Saved: ", output_file)
}

# ============================================================================
# STEP 8: Find highly variable genes
# ============================================================================
if (!opts$skip_find_hvgs) {
  n_hvgs <- as.integer(opts$n_hvgs)
  vcat("Finding top ", n_hvgs, " highly variable genes...")
  
  obj <- FindVariableFeatures(obj, n_hvgs)
  
  vcat("Identified ", length(HVGs(obj)), " HVGs")
  
  # Save HVG list
  hvg_file <- make_path("hvg_list.txt")
  writeLines(HVGs(obj), hvg_file)
  vcat("Saved HVG list: ", hvg_file)
}

# ============================================================================
# STEP 9: Run PCA
# ============================================================================
if (!opts$skip_pca) {
  vcat("Running PCA...")
  
  obj <- RunPCA(obj)
  
  vcat("PCA completed")
  
  # Save PCA scores
  pca_scores <- DimReduction(obj)$Scores
  pca_file <- make_path("pca_scores.csv")
  write.csv(pca_scores, pca_file, row.names = TRUE)
  vcat("Saved PCA scores: ", pca_file)
}

# ============================================================================
# STEP 10: Scree plot
# ============================================================================
if (!opts$skip_scree && !opts$skip_pca) {
  vcat("Generating scree plot...")
  
  p <- PlotScree(obj)
  
  output_file <- make_path("scree_plot.png")
  ggsave(output_file, p, width = as.numeric(opts$fig_width), 
         height = as.numeric(opts$fig_height), dpi = 300)
  vcat("Saved: ", output_file)
}

# ============================================================================
# STEP 11: PCA scatter plot
# ============================================================================
if (!opts$skip_pca_plot && !opts$skip_pca) {
  vcat("Generating PCA scatter plot...")
  
  pc_x <- as.integer(opts$pca_x)
  pc_y <- as.integer(opts$pca_y)
  
  p <- PlotPCA(
    object = obj,
    x = pc_x,
    y = pc_y,
    color_by = group_var,
    colors = if (!is.null(colorList)) colorList[[group_var]] else NULL
  )
  
  output_file <- make_path(paste0("pca_plot_PC", pc_x, "_PC", pc_y, ".png"))
  ggsave(output_file, p, width = as.numeric(opts$fig_width), 
         height = as.numeric(opts$fig_height), dpi = 300)
  vcat("Saved: ", output_file)
}

# ============================================================================
# STEP 12: Eigenvector heatmap
# ============================================================================
if (!opts$skip_eigen_heatmap && !opts$skip_pca) {
  vcat("Generating eigenvector heatmap...")
  
  eigen_pc <- opts$eigen_pc
  eigen_n <- as.integer(opts$eigen_top_n)
  
  hm <- PlotEigenHeatmap(
    obj,
    pc = eigen_pc,
    n = eigen_n,
    annotate_by = group_var,
    annotate_colors = colorList
  )
  
  output_file <- make_path(paste0("eigenvector_heatmap_", eigen_pc, ".png"))
  GenSave(hm, output_file, 
          width = as.numeric(opts$heatmap_width), 
          height = as.numeric(opts$heatmap_height))
  vcat("Saved: ", output_file)
}

# ============================================================================
# STEP 13: Eigencorrelation plot
# ============================================================================
if (!opts$skip_eigen_corr && !opts$skip_pca) {
  vcat("Generating eigencorrelation plot...")
  
  n_pcs <- as.integer(opts$n_pcs_corr)
  
  ec <- PlotEigenCorr(obj, num_pcs = n_pcs)
  
  output_file <- make_path("eigencorrelation.png")
  ggsave(output_file, ec$plot, width = as.numeric(opts$fig_width), 
         height = as.numeric(opts$fig_height), dpi = 300)
  vcat("Saved: ", output_file)
  
  # Save correlation matrices
  cor_file <- make_path("eigencorrelation_values.csv")
  write.csv(ec$cor_matrix, cor_file, row.names = TRUE)
  vcat("Saved correlation matrix: ", cor_file)
}

# ============================================================================
# STEP 14: DEG Analysis
# ============================================================================
if (!opts$skip_deg_analysis) {
  vcat("Extracting differential expression results...")
  
  # Get DESeq2 results
  res <- results(dds) |> as.data.frame()
  
  vcat("Found ", nrow(res), " genes in DEG results")
  
  # Add to GenEDA object
  deg_assay <- opts$deg_assay
  obj <- SetDEGs(
    object = obj,
    deg_table = res,
    assay = deg_assay
  )
  
  # Save full results
  res_file <- make_path(paste0(deg_assay, "_full.csv"))
  write.csv(res, res_file, row.names = TRUE)
  vcat("Saved full DEG results: ", res_file)
  
  # Get thresholds
  alpha <- as.numeric(opts$alpha)
  lfc_thresh <- as.numeric(opts$lfc_threshold)
  
  # Summarize DEGs
  vcat("Summarizing DEGs with alpha=", alpha, " and LFC threshold=", lfc_thresh)
  deg_summary <- SummarizeDEGs(obj, alpha = alpha, lfc1 = lfc_thresh, lfc2 = lfc_thresh * 2)
  print(deg_summary)
  
  # Save summary
  summary_file <- make_path("deg_summary.txt")
  capture.output(print(deg_summary), file = summary_file)
  vcat("Saved DEG summary: ", summary_file)
  
  # Filter DEGs
  filtered_assay <- paste0(deg_assay, "_filtered")
  obj <- FilterDEGs(
    object = obj,
    assay = deg_assay,
    alpha = alpha,
    l2fc = lfc_thresh,
    saveAssay = filtered_assay
  )
  
  # Save filtered results
  filtered_res <- DEGs(obj, assay = filtered_assay)
  filtered_file <- make_path(paste0(filtered_assay, ".csv"))
  write.csv(filtered_res, filtered_file, row.names = TRUE)
  vcat("Saved filtered DEGs (", nrow(filtered_res), " genes): ", filtered_file)
  
  # ============================================================================
  # STEP 15: P-value histogram
  # ============================================================================
  if (!opts$skip_pval_hist) {
    vcat("Generating p-value histogram...")
    
    p <- PlotPValHist(obj, assay = deg_assay, alpha = alpha)
    
    output_file <- make_path("pvalue_histogram.png")
    ggsave(output_file, p, width = as.numeric(opts$fig_width), 
           height = as.numeric(opts$fig_height), dpi = 300)
    vcat("Saved: ", output_file)
  }
  
  # ============================================================================
  # STEP 16: MA plot
  # ============================================================================
  if (!opts$skip_ma_plot) {
    vcat("Generating MA plot...")
    
    p <- PlotMA(obj, assay = deg_assay, alpha = alpha, l2fc = lfc_thresh)
    
    output_file <- make_path("ma_plot.png")
    ggsave(output_file, p, width = as.numeric(opts$fig_width), 
           height = as.numeric(opts$fig_height), dpi = 300)
    vcat("Saved: ", output_file)
  }
  
  # ============================================================================
  # STEP 17: Volcano plot
  # ============================================================================
  if (!opts$skip_volcano) {
    vcat("Generating volcano plot...")
    
    # Determine comparison levels
    num_level <- opts$comparison_num
    den_level <- opts$comparison_den
    
    if (is.null(num_level)) {
      num_level <- levels_group[2]  # Assume second level is treatment
      vcat("Using default numerator level: ", num_level)
    }
    
    if (is.null(den_level)) {
      den_level <- levels_group[1]  # Assume first level is reference
      vcat("Using default denominator level: ", den_level)
    }
    
    p <- PlotVolcano(
      obj,
      assay = deg_assay,
      alpha = alpha,
      l2fc = lfc_thresh,
      num = num_level,
      den = den_level,
      title = paste0(num_level, " vs ", den_level)
    )
    
    output_file <- make_path("volcano_plot.png")
    ggsave(output_file, p, width = as.numeric(opts$fig_width), 
           height = as.numeric(opts$fig_height), dpi = 300)
    vcat("Saved: ", output_file)
  }
  
  # ============================================================================
  # STEP 18: DE Dashboard
  # ============================================================================
  if (!opts$skip_dashboard) {
    vcat("Generating differential expression dashboard...")
    
    output_file <- make_path("de_dashboard.png")
    
    png(output_file, 
        width = as.numeric(opts$fig_width) * 2, 
        height = as.numeric(opts$fig_height) * 2, 
        units = "in", 
        res = 300)
    
    DEDashboard(
      obj,
      assay = deg_assay,
      alpha = alpha,
      l2fc = lfc_thresh
    )
    
    dev.off()
    vcat("Saved: ", output_file)
  }
  
  # ============================================================================
  # STEP 19: Find hvDEGs (if HVGs were calculated)
  # ============================================================================
  if (!opts$skip_find_hvgs) {
    vcat("Finding highly variable DEGs...")
    
    hvdegs_neg <- FindHVDEGs(obj, assay = filtered_assay, direction = "negative")
    hvdegs_pos <- FindHVDEGs(obj, assay = filtered_assay, direction = "positive")
    
    # Save hvDEGs
    hvdeg_neg_file <- make_path("hvDEGs_downregulated.txt")
    hvdeg_pos_file <- make_path("hvDEGs_upregulated.txt")
    
    writeLines(hvdegs_neg, hvdeg_neg_file)
    writeLines(hvdegs_pos, hvdeg_pos_file)
    
    vcat("Saved downregulated hvDEGs (", length(hvdegs_neg), " genes): ", hvdeg_neg_file)
    vcat("Saved upregulated hvDEGs (", length(hvdegs_pos), " genes): ", hvdeg_pos_file)
  }
}

# ============================================================================
# STEP 20: Save GenEDA object
# ============================================================================
vcat("Saving GenEDA object...")

# Determine save path for GenEDA object
if (!is.null(opts$save_geneda)) {
  # Use user-specified path
  geneda_file <- opts$save_geneda
  
  # If not absolute path, make it relative to output directory
  if (!startsWith(geneda_file, "/") && !grepl("^[A-Za-z]:", geneda_file)) {
    geneda_file <- file.path(output_dir, geneda_file)
  }
} else {
  # Use default path with prefix
  geneda_file <- make_path("geneda_object.rds")
}

saveRDS(obj, geneda_file)
vcat("Saved GenEDA object: ", geneda_file)

# ============================================================================
# Analysis Complete
# ============================================================================
vcat("==============================================")
vcat("Analysis complete!")
vcat("All results saved to: ", output_dir)
vcat("GenEDA object saved to: ", geneda_file)
vcat("==============================================")

# Create summary file
summary_text <- c(
  "RGenEDA Analysis Summary",
  "========================",
  "",
  paste("Date:", Sys.time()),
  paste("Input file:", opts$input),
  paste("Output directory:", output_dir),
  paste("GenEDA object:", geneda_file),
  paste("Number of genes:", nrow(mat)),
  paste("Number of samples:", ncol(mat)),
  paste("Grouping variable:", group_var),
  paste("Group levels:", paste(levels_group, collapse = ", ")),
  "",
  "Analysis Parameters:",
  paste("  Number of HVGs:", opts$n_hvgs),
  paste("  Alpha threshold:", opts$alpha),
  paste("  LFC threshold:", opts$lfc_threshold),
  "",
  "Steps completed:",
  paste("  Count distribution:", !opts$skip_count_dist),
  paste("  Sample distances:", !opts$skip_distances),
  paste("  HVG variance plot:", !opts$skip_hvg_variance),
  paste("  Find HVGs:", !opts$skip_find_hvgs),
  paste("  PCA:", !opts$skip_pca),
  paste("  PCA plot:", !opts$skip_pca_plot),
  paste("  Scree plot:", !opts$skip_scree),
  paste("  Eigenvector heatmap:", !opts$skip_eigen_heatmap),
  paste("  Eigencorrelation:", !opts$skip_eigen_corr),
  paste("  DEG analysis:", !opts$skip_deg_analysis),
  paste("  P-value histogram:", !opts$skip_pval_hist),
  paste("  MA plot:", !opts$skip_ma_plot),
  paste("  Volcano plot:", !opts$skip_volcano),
  paste("  DE dashboard:", !opts$skip_dashboard)
)

summary_file <- make_path("analysis_summary.txt")
writeLines(summary_text, summary_file)
vcat("Saved analysis summary: ", summary_file)
