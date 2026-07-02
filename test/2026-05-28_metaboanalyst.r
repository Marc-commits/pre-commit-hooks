#!/usr/bin/env r
# metaboanalyst.r — Metabolomics downstream processing pipeline
# Author:  Marc
# Email:   marc.broghammer@gmx.de
# Version: v0.1.1
#
# Typical usage:
#   ./metaboanalyst.r -c Class -o test/output --input data.csv
#   ./metaboanalyst.r -c Class -o test/output < data.csv

VERSION <- "v0.1.1"

DOC <- "Metabolomics downstream processing pipeline using MetaboAnalystR.
Input: CSV file or stdin. Result files go to --output; stdout silent.

Usage:
  metaboanalyst.r [options] [<input>]
  metaboanalyst.r (-h | --help)
  metaboanalyst.r (-V | --version)

Arguments:
  <input>               Input CSV (rows = samples, columns = metabolites).
                        Omit or use '-' to read from stdin.

Options:
  Input / output:
  -i FILE, --input=FILE    Input CSV file (overrides positional <input>).
  -o DIR, --output=DIR     Output directory for all results [default: test/output].
  -c COL, --class=COL      Column name for group/class labels [default: Class].

  Workflow steps (all enabled by default; use --no-X to skip):
  --no-normalize        Skip normalization, transformation and scaling.
  --no-pca              Skip PCA analysis and plots.
  --no-anova            Skip ANOVA analysis.
  --no-heatmap          Skip heatmap (also skipped when --no-anova is set).
  --no-pairwise         Skip all pairwise FC + t-test comparisons.

  Comparisons:
  --comparisons=STR     Comma-separated pairs as G1:G2 (e.g. WT:mut,WT:cKO),
                        or 'auto' to run all unique group pairs [default: auto].

  Normalization:
  --norm=STR            Sample normalization: MedianNorm|SumNorm|QuantileNorm|NULL
                        [default: MedianNorm].
  --transform=STR       Data transformation: LogNorm|CrNorm|NULL [default: LogNorm].
  --scale=STR           Data scaling: AutoNorm|ParetoNorm|MeanCenter|NULL
                        [default: AutoNorm].

  Feature filtering:
  --filter=STR          Filter method: iqr|mad|none [default: iqr].
  --filter-pct=INT      Percentage of low-variance features to remove [default: 25].

  Missing values:
  --impute=STR          Imputation method: lod|half|bpca|knn|min|mean|median
                        [default: lod].

  Pairwise thresholds:
  --fc=FLOAT            Fold-change threshold [default: 2.0].
  --pval=FLOAT          p-value cutoff for t-tests [default: 0.05].

  Output formatting:
  --dpi=INT             Image resolution in DPI [default: 72].
  --format=STR          Image format: png|pdf|svg [default: png].
  --label-strip=REGEX   Regex stripped from feature names for plot labels.
                        Use '' to disable. [default:  / .*$].

  -h, --help            Show this help message and exit.
  -V, --version         Show version number and exit.
"

# ── Package bootstrap ──────────────────────────────────────────────────────────
# Packages are installed on first run if missing; no renv dependency required.
# Note: MetaboAnalystR requires qs <= 0.25.5 on some systems.
#   If you hit qs-related errors: remotes::install_version("qs", "0.25.5")
#   See https://github.com/xia-lab/MetaboAnalystR/issues/371

pkg_load <- function(pkg, gh = NULL) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    if (!is.null(gh)) {
      if (!requireNamespace("remotes", quietly = TRUE)) {
        install.packages("remotes", repos = "https://cloud.r-project.org")
      }
      remotes::install_github(gh,
        build = TRUE, build_vignettes = FALSE,
        upgrade = "never"
      )
    } else {
      install.packages(pkg, repos = "https://cloud.r-project.org")
    }
  }
  library(pkg, character.only = TRUE, warn.conflicts = FALSE)
}

pkg_load("docopt")
pkg_load("MetaboAnalystR", gh = "xia-lab/MetaboAnalystR")

# Handle -V/--version before docopt: print startup banner and exit.
# Must precede docopt() which would quit() without running this code.
.argv <- commandArgs(trailingOnly = TRUE)
if (any(c("-V", "--version") %in% .argv)) {
  if (!"--quiet" %in% .argv) {
    .extra <- .argv[!.argv %in% c("-V", "--version")]
    message(sprintf(
      "This is metaboanalyst.r running R %s with args: %s",
      paste(R.version$major, R.version$minor, sep = "."),
      paste(.extra, collapse = " ")
    ))
  }
  cat(VERSION, "\n")
  quit(status = 0)
}
rm(.argv)

# Required by MetaboAnalystR plot functions as a global default.
# Value is overwritten after argument parsing (see below).
default.dpi <- 72

# MetaboAnalystR's .set.mSet() was designed for Rserve/web mode: it stores the
# mSet globally but returns a numeric status code instead of the object.
# Patch it so it always stores AND returns the mSet, making the pipeline work
# in a standalone (non-Rserve) context without changing any other behaviour.
assignInNamespace(".set.mSet", function(mSetObj) {
  mSet <<- mSetObj
  mSetObj
}, ns = "MetaboAnalystR")

# Retrieve the mSet after any MetaboAnalystR call that may return a status code.
get_ms <- function(x) {
  if (is.list(x)) {
    return(x)
  }
  if (exists("mSet", envir = .GlobalEnv) && is.list(.GlobalEnv$mSet)) {
    return(.GlobalEnv$mSet)
  }
  stop("MetaboAnalystR state lost after call returning: ", x)
}

# ── Argument parsing ───────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (!is.null(a)) a else b

args <- docopt(DOC, version = VERSION)

# Resolve input source: --input > positional <input> > stdin
input_src <- args[["--input"]] %||% args[["input"]]
is_stdin <- is.null(input_src) || identical(input_src, "-")

outdir <- args[["--output"]]
class_col <- args[["--class"]]
comparisons <- args[["--comparisons"]]
norm <- args[["--norm"]]
transform <- args[["--transform"]]
scale <- args[["--scale"]]
fc_thr <- as.numeric(args[["--fc"]])
pval_thr <- as.numeric(args[["--pval"]])
filter_mth <- args[["--filter"]]
filter_pct <- as.integer(args[["--filter-pct"]])
impute <- args[["--impute"]]
dpi <- as.integer(args[["--dpi"]])
img_fmt <- args[["--format"]]
label_strip <- args[["--label-strip"]]

do_normalize <- !isTRUE(args[["--no-normalize"]])
do_pca <- !isTRUE(args[["--no-pca"]])
do_anova <- !isTRUE(args[["--no-anova"]])
do_heatmap <- !isTRUE(args[["--no-heatmap"]]) && do_anova
do_pairwise <- !isTRUE(args[["--no-pairwise"]])

# Update global DPI default used by MetaboAnalystR plot functions.
default.dpi <- dpi

# When normalization is skipped pass NULL to all three params
eff_norm <- if (do_normalize) norm else "NULL"
eff_transform <- if (do_normalize) transform else "NULL"
eff_scale <- if (do_normalize) scale else "NULL"

# ── Validation & setup ─────────────────────────────────────────────────────────

if (!is_stdin) {
  input_abs <- normalizePath(input_src, mustWork = FALSE)
  if (!file.exists(input_abs)) stop("Input file not found: ", input_src)
}

# Create output dir first so normalizePath can resolve to an absolute path.
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
outdir_abs <- normalizePath(outdir)

# MetaboAnalystR writes all output to the working directory.
# NOTE: on.exit(setwd()) must NOT be used at the top level of a littler script
# because littler fires on.exit after each top-level statement, not at script
# exit — this would immediately undo the setwd before any files are written.
# on.exit inside helper functions is fine (fires at function return, not per-statement).
setwd(outdir_abs)

# Create output subdirectories.
#   _state/       MetaboAnalystR intermediate .qs files and working data (safe to delete)
#   normalization/ norm plots and exported data CSVs
#   pca/          PCA plots and score/loadings CSVs
#   anova/        ANOVA CSV and heatmap
#   pairwise/     FC + t-test plots and result CSVs (flat, one level)
for (.d in c("_state", "normalization", "pca", "anova", "pairwise")) {
  dir.create(.d, showWarnings = FALSE)
}
rm(.d)

# ── Load and reformat input CSV ────────────────────────────────────────────────
# MetaboAnalystR "rowu" layout: col1 = sample name, col2 = class, col3+ = features.

message("── Reading input ──")
input_path <- if (is_stdin) "/dev/stdin" else input_abs
raw <- read.csv(input_path, check.names = FALSE, stringsAsFactors = FALSE)

if (!class_col %in% colnames(raw)) {
  stop(
    "Class column '", class_col, "' not found.\n",
    "Available columns: ", paste(colnames(raw), collapse = ", ")
  )
}

# Identify sample-name column: first non-numeric, non-class column.
sample_col <- NULL
for (col in setdiff(colnames(raw), class_col)) {
  if (!is.numeric(raw[[col]])) {
    sample_col <- col
    break
  }
}
if (is.null(sample_col)) {
  raw[["Sample"]] <- paste0("Sample_", seq_len(nrow(raw)))
  sample_col <- "Sample"
}

feature_cols <- setdiff(colnames(raw), c(sample_col, class_col))

ma_data <- data.frame(
  Name = raw[[sample_col]],
  Class = raw[[class_col]],
  raw[, feature_cols, drop = FALSE],
  check.names = FALSE,
  stringsAsFactors = FALSE
)

# Strip unit suffixes from feature names for cleaner plot labels.
if (nchar(label_strip) > 0) {
  feat_idx <- seq(3, ncol(ma_data))
  colnames(ma_data)[feat_idx] <- gsub(label_strip, "", colnames(ma_data)[feat_idx], perl = TRUE)
}

groups <- unique(ma_data$Class)
message("Groups detected: ", paste(groups, collapse = ", "))

# ── Resolve comparisons ────────────────────────────────────────────────────────

if (is.null(comparisons) || comparisons == "auto") {
  pairs <- combn(groups, 2, simplify = FALSE)
} else {
  pairs <- lapply(strsplit(comparisons, ",")[[1]], function(p) {
    parts <- strsplit(p, ":")[[1]]
    if (length(parts) != 2) {
      stop("Invalid comparison '", p, "'. Format: G1:G2")
    }
    for (g in parts) {
      if (!g %in% groups) {
        stop(
          "Group '", g, "' not found in class column. Available: ",
          paste(groups, collapse = ", ")
        )
      }
    }
    as.list(parts)
  })
}

message(
  "Comparisons planned: ",
  paste(vapply(pairs, function(p) paste(p[[1]], p[[2]], sep = ":"), ""),
    collapse = ", "
  )
)

# ── Helpers ────────────────────────────────────────────────────────────────────

write_ma_csv <- function(df) {
  tmp <- tempfile(fileext = ".csv")
  write.csv(df, tmp, row.names = FALSE, quote = FALSE)
  tmp
}

# Move a file to a subdirectory if it exists (for MetaboAnalystR files with hardcoded names).
move_if <- function(src, dst_dir) {
  if (file.exists(src)) file.rename(src, file.path(dst_dir, basename(src)))
}

run_pipeline <- function(df, nm, tr, sc, fmth, fpct, imp) {
  tmp <- write_ma_csv(df)
  on.exit(unlink(tmp), add = TRUE)
  ms <- get_ms(InitDataObjects("conc", "stat", FALSE, default.dpi = default.dpi))
  ms <- get_ms(Read.TextData(ms, tmp, "rowu", "disc"))
  ms <- get_ms(SanityCheckData(ms))
  ms <- get_ms(ImputeMissingVar(ms, method = imp))
  if (fmth != "none") {
    ms <- get_ms(FilterVariable(ms, var.filter = fmth, var.cutoff = fpct))
  }
  ms <- get_ms(PreparePrenormData(ms))
  ms <- get_ms(Normalization(ms, nm, tr, sc, ratio = FALSE, ratioNum = 20))
  ms
}

export_result <- function(obj, filename) {
  tryCatch(
    write.csv(as.data.frame(obj), filename, quote = FALSE),
    error = function(e) {
      warning("Could not export ", filename, ": ", conditionMessage(e))
    }
  )
}

run_pairwise <- function(ma_data, g1, g2, nm, tr, sc, fc_thr, pval_thr, fmth, fpct, imp) {
  tag <- paste0(
    gsub("[^A-Za-z0-9]", "_", g1), "_vs_",
    gsub("[^A-Za-z0-9]", "_", g2)
  )
  message("\n── Pairwise: ", g1, " vs ", g2, " ──")
  sub_df <- ma_data[ma_data$Class %in% c(g1, g2), , drop = FALSE]
  ms <- run_pipeline(sub_df, nm, tr, sc, fmth, fpct, imp)
  ms <- get_ms(FC.Anal(ms, fc.thresh = fc_thr, cmp.type = 0))
  ms <- get_ms(PlotFC(ms, paste0("pairwise/fc_", tag, "_"), img_fmt, dpi, width = NA))
  ms <- get_ms(Ttests.Anal(ms, FALSE, pval_thr, FALSE, TRUE))
  ms <- get_ms(PlotTT(ms, paste0("pairwise/tt_", tag, "_"), img_fmt, dpi, width = NA))
  if (!is.null(ms$analSet$tt)) {
    export_result(ms$analSet$tt, paste0("pairwise/ttest_", tag, ".csv"))
  }
  invisible(ms)
}

# ── Full-dataset pipeline ──────────────────────────────────────────────────────

message("\n── Processing (all groups) ──")
mSet <- run_pipeline(
  ma_data, eff_norm, eff_transform, eff_scale,
  filter_mth, filter_pct, impute
)

if (do_normalize) {
  mSet <- get_ms(PlotNormSummary(mSet, "normalization/norm_feature", img_fmt, dpi, width = NA))
  mSet <- get_ms(PlotSampleNormSummary(mSet, "normalization/norm_sample", img_fmt, dpi, width = NA))
} else {
  message("  (normalization skipped)")
}

if (do_pca) {
  message("\n── PCA ──")
  mSet <- get_ms(PCA.Anal(mSet))
  # PCA.Anal writes pca_loadings.csv and pca_score.csv; move before plotting.
  for (.pf in c("pca_loadings.csv", "pca_score.csv")) move_if(.pf, "pca")
  mSet <- get_ms(PlotPCAScree(mSet, "pca/pca_scree", img_fmt, dpi, width = NA, 5))
  mSet <- get_ms(PlotPCA2DScore(mSet, "pca/pca_score2d", img_fmt, dpi, width = NA, 1, 2, 0.95, 1, 0))
  # PlotPCA2DScore writes pca_pairwise_permanova.csv.
  move_if("pca_pairwise_permanova.csv", "pca")
} else {
  message("\n── PCA skipped ──")
}

if (do_anova) {
  message("\n── ANOVA ──")
  mSet <- get_ms(ANOVA.Anal(mSet))
  # ANOVA.Anal writes anova_all_results.csv to cwd.
  move_if("anova_all_results.csv", "anova")
  if (!is.null(mSet$analSet$aov)) {
    export_result(mSet$analSet$aov, "anova/anova_results.csv")
  }
} else {
  message("\n── ANOVA skipped ──")
}

if (do_heatmap) {
  message("\n── Heatmap ──")
  mSet <- get_ms(PlotHeatMap(mSet, "anova/heatmap", img_fmt,
    dpi = dpi, width = NA,
    dataOpt = "norm", scaleOpt = "row",
    smplDist = "euclidean", clstDist = "ward.D",
    palette = "bwm", fzCol = 8, fzRow = 8,
    fzAnno = 8, annoPer = 15,
    unitCol = 30, unitRow = 15
  ))
  # PlotHeatMap writes heatmap.json and heatmap_stats.rds to cwd.
  move_if("heatmap.json", "anova")
  move_if("heatmap_stats.rds", "anova")
} else {
  message("\n── Heatmap skipped ──")
}

message("\n── Saving normalized data ──")
get_ms(SaveTransformedData(mSet))
# SaveTransformedData writes data_normalized.csv, data_original.csv, data_processed.csv to cwd.
for (.nf in c("data_normalized.csv", "data_original.csv", "data_processed.csv")) {
  move_if(.nf, "normalization")
}

# Move stray R graphics file if present.
move_if("Rplots.pdf", "_state")

# ── Pairwise comparisons ───────────────────────────────────────────────────────

if (do_pairwise) {
  for (pair in pairs) {
    run_pairwise(
      ma_data, pair[[1]], pair[[2]],
      eff_norm, eff_transform, eff_scale,
      fc_thr, pval_thr, filter_mth, filter_pct, impute
    )
  }
} else {
  message("\n── Pairwise comparisons skipped ──")
}

# ── Move MetaboAnalystR internals to _state/ ──────────────────────────────────
# These files are written by MetaboAnalystR with fixed names to the cwd and are
# not needed for downstream analysis.
for (.sf in list.files(pattern = "\\.qs$")) move_if(.sf, "_state")
for (.sf in list.files(pattern = "^data_prefilter_")) move_if(.sf, "_state")
for (.sf in c(
  "raw_dataview.csv", "fold_change.csv", "t_test.csv",
  "heatmap_stats.rds", "Rplots.pdf"
)) {
  move_if(.sf, "_state")
}

message("\nDone. Results in: ", outdir_abs)

sessionInfo()
