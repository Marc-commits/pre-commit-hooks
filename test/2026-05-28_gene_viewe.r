#!/usr/bin/env r
# gene_viewe.r
# version: 0.1.0
# author: Marc Broghammer
# email: marc.broghammer@gmx.de
# CLI wrapper for geneviewer — interactive HTML gene-cluster visualization
# Usage: gene_viewe.r <subcommand> [flags]

VERSION <- "0.1.0"

.raw_args <- commandArgs(trailingOnly = TRUE)
.quiet <- "--quiet" %in% .raw_args
.display_args <- .raw_args[!.raw_args %in% c("--version", "-V", "--quiet")]

if (!.quiet) {
  cat(sprintf(
    "This is gene_viewe.r running R %s.%s with args: %s\n",
    R.version[["major"]], R.version[["minor"]],
    paste(.display_args, collapse = " ")
  ))
}

if ("--version" %in% .raw_args || "-V" %in% .raw_args) {
  cat("gene_viewe.r", VERSION, "\n")
  quit(status = 0, save = "no")
}

if (length(.raw_args) == 0 || .raw_args[1] %in% c("-h", "--help", "help")) {
  cat(sprintf(
    paste0(
      "gene_viewe.r v%s\nAuthor: Marc Broghammer\n\n",
      "Usage: gene_viewe.r <subcommand> [flags]\n\n",
      "Subcommands:\n  cluster\n  compare\n  links\n",
      "  hox\n  biosynthetic\n  blastp\n  gff\n\n",
      "Input:  GBK or GFF file(s)/folder via --input; use --input - to read a single file from stdin\n",
      "Output: HTML/PNG/PDF file via --output; use --output - to write HTML to stdout\n\n",
      "Run 'gene_viewe.r <subcommand> --help' for subcommand-specific flags.\n"
    ),
    VERSION
  ))
  quit(status = 0, save = "no")
}

suppressPackageStartupMessages({
  library(optparse)
  library(dplyr)
  library(htmlwidgets)
  library(geneviewer)
})

# ---------------------------------------------------------------------------
# Subcommand defaults
# ---------------------------------------------------------------------------
SUBCMD_DEFAULTS <- list(
  cluster = list(
    labels = TRUE, scale = FALSE, scale_type = "position",
    scale_bar = TRUE, scale_bar_unit = 1000,
    coordinates = TRUE, legend = TRUE,
    links = FALSE, curve_links = FALSE,
    overlap = FALSE, track_mouse = FALSE, sequence = FALSE,
    marker = "arrow", marker_size = "medium",
    tooltip = "<b>{gene}</b><br>{product}",
    height = 150
  ),
  compare = list(
    labels = TRUE, scale = FALSE, scale_type = "position",
    scale_bar = TRUE, scale_bar_unit = 1000,
    coordinates = FALSE, legend = TRUE,
    links = FALSE, curve_links = FALSE,
    overlap = FALSE, track_mouse = FALSE, sequence = FALSE,
    marker = "arrow", marker_size = "medium",
    tooltip = NULL,
    height = 150
  ),
  links = list(
    labels = TRUE, scale = FALSE, scale_type = "position",
    scale_bar = FALSE, scale_bar_unit = 1000,
    coordinates = FALSE, legend = FALSE,
    links = TRUE, curve_links = FALSE,
    overlap = FALSE, track_mouse = TRUE, sequence = FALSE,
    marker = "arrow", marker_size = "medium",
    tooltip = NULL,
    height = 150
  ),
  hox = list(
    labels = TRUE, scale = FALSE, scale_type = "position",
    scale_bar = FALSE, scale_bar_unit = 1000,
    coordinates = FALSE, legend = FALSE,
    links = FALSE, curve_links = FALSE,
    overlap = TRUE, track_mouse = FALSE, sequence = TRUE,
    marker = "boxarrow", marker_size = "medium",
    tooltip = NULL,
    height = 150
  ),
  biosynthetic = list(
    labels = FALSE, scale = TRUE, scale_type = "position",
    scale_bar = FALSE, scale_bar_unit = 1000,
    coordinates = FALSE, legend = TRUE,
    links = FALSE, curve_links = FALSE,
    overlap = FALSE, track_mouse = FALSE, sequence = FALSE,
    marker = "boxarrow", marker_size = "small",
    tooltip = "<b>{gene}</b><br>{product}<br>Kind: {gene_kind}",
    height = 150
  ),
  blastp = list(
    labels = FALSE, scale = FALSE, scale_type = "position",
    scale_bar = FALSE, scale_bar_unit = 1000,
    coordinates = FALSE, legend = FALSE,
    links = TRUE, curve_links = FALSE,
    overlap = FALSE, track_mouse = FALSE, sequence = FALSE,
    marker = "arrow", marker_size = "medium",
    tooltip = NULL,
    height = 150
  ),
  gff = list(
    labels = TRUE, scale = TRUE, scale_type = "range",
    scale_bar = FALSE, scale_bar_unit = 1000,
    coordinates = FALSE, legend = FALSE,
    links = FALSE, curve_links = FALSE,
    overlap = FALSE, track_mouse = FALSE, sequence = FALSE,
    marker = "arrow", marker_size = "medium",
    tooltip = "<b>{Name}</b><br>{type}",
    height = 150
  )
)

VALID_SUBCMDS <- names(SUBCMD_DEFAULTS)

# ---------------------------------------------------------------------------
# Option list builder (uses subcommand defaults)
# ---------------------------------------------------------------------------
build_option_list <- function(defs) {
  list(
    make_option(c("-i", "--input"),
      type = "character", default = NULL,
      help = "GBK/GFF file(s), folder, or - to read from stdin [required]"
    ),
    make_option(c("-f", "--feature"),
      type = "character", default = "CDS",
      help = "Comma-sep feature types [%default]"
    ),
    make_option("--keys",
      type = "character",
      default = "gene,locus_tag,product,gene_kind",
      help = "Extra GBK attributes [%default]"
    ),
    make_option(c("-l", "--locus"),
      type = "character", default = NULL,
      help = "Gene name to center on"
    ),
    make_option(c("-c", "--coords"),
      type = "character", default = NULL,
      help = "Region: start:end or seqid:start:end"
    ),
    make_option(c("-u", "--upstream"),
      type = "integer", default = 5000L,
      help = "bp upstream of locus center [%default]"
    ),
    make_option(c("-d", "--downstream"),
      type = "integer", default = 5000L,
      help = "bp downstream of locus center [%default]"
    ),

    # Grouping
    make_option("--group",
      type = "character", default = NULL,
      help = "Column for color grouping [auto]"
    ),
    make_option(c("-L", "--cluster-labels"),
      type = "character", default = NULL,
      help = "Comma-sep cluster label overrides"
    ),

    # Visual toggles — defaults come from subcommand preset
    make_option("--labels",
      action = "store_true", default = defs$labels,
      help = "Gene name labels [%default]"
    ),
    make_option("--no-labels",
      action = "store_false", dest = "labels",
      help = "Disable gene labels"
    ),
    make_option("--scale",
      action = "store_true", default = defs$scale,
      help = "Genomic scale axis [%default]"
    ),
    make_option("--no-scale",
      action = "store_false", dest = "scale",
      help = "Disable scale axis"
    ),
    make_option("--scale-type",
      type = "character", default = defs$scale_type,
      help = "position or range [%default]"
    ),
    make_option("--scale-bar",
      action = "store_true", default = defs$scale_bar,
      help = "Scale bar [%default]"
    ),
    make_option("--no-scale-bar",
      action = "store_false", dest = "scale_bar",
      help = "Disable scale bar"
    ),
    make_option("--scale-bar-unit",
      type = "integer", default = defs$scale_bar_unit,
      help = "Scale bar unit in bp [%default]"
    ),
    make_option("--coordinates",
      action = "store_true", default = defs$coordinates,
      help = "Coordinate track [%default]"
    ),
    make_option("--no-coordinates",
      action = "store_false", dest = "coordinates",
      help = "Disable coordinate track"
    ),
    make_option("--legend",
      action = "store_true", default = defs$legend,
      help = "Legend [%default]"
    ),
    make_option("--no-legend",
      action = "store_false", dest = "legend",
      help = "Disable legend"
    ),
    make_option("--links",
      action = "store_true", default = defs$links,
      help = "Homology links (GC_links) [%default]"
    ),
    make_option("--no-links",
      action = "store_false", dest = "links",
      help = "Disable links"
    ),
    make_option("--curve-links",
      action = "store_true", default = defs$curve_links,
      help = "Use curved links [%default]"
    ),
    make_option("--overlap",
      action = "store_true", default = defs$overlap,
      help = "Prevent gene overlap [%default]"
    ),
    make_option("--no-overlap",
      action = "store_false", dest = "overlap",
      help = "Disable overlap prevention"
    ),
    make_option("--track-mouse",
      action = "store_true", default = defs$track_mouse,
      help = "Mouse coordinate tracking [%default]"
    ),
    make_option("--no-track-mouse",
      action = "store_false", dest = "track_mouse",
      help = "Disable mouse tracking"
    ),
    make_option("--sequence",
      action = "store_true", default = defs$sequence,
      help = "Sequence track [%default]"
    ),
    make_option("--no-sequence",
      action = "store_false", dest = "sequence",
      help = "Disable sequence track"
    ),
    make_option("--marker",
      type = "character", default = defs$marker,
      help = "arrow|boxarrow|box|rbox|cbox [%default]"
    ),
    make_option("--marker-size",
      type = "character", default = defs$marker_size,
      help = "small|medium|large [%default]"
    ),

    # Styling
    make_option("--tooltip",
      type = "character", default = defs$tooltip,
      help = "HTML tooltip template, e.g. '<b>{gene}</b>: {product}'"
    ),
    make_option("--colors",
      type = "character", default = NULL,
      help = "type1=#hex,type2=#hex"
    ),
    make_option("--title",
      type = "character", default = NULL,
      help = "Plot title (HTML allowed)"
    ),
    make_option("--cluster-title",
      type = "character", default = NULL,
      help = "Column or string for per-cluster titles"
    ),
    make_option("--height",
      type = "integer", default = defs$height,
      help = "px per cluster for HTML output [%default]"
    ),

    # BLASTP-specific
    make_option("--query",
      type = "character", default = NULL,
      help = "Reference cluster name (blastp only)"
    ),
    make_option("--identity",
      type = "numeric", default = 30,
      help = "Min identity %% for BLASTP [%default]"
    ),
    make_option("--parallel",
      action = "store_true", default = TRUE,
      help = "Parallel BLASTP [%default]"
    ),

    # Output
    make_option(c("-o", "--output"),
      type = "character", default = "plot.html",
      help = "Output file: .html / .png / .pdf, or - to write HTML to stdout [%default]"
    ),
    make_option("--width",
      type = "integer", default = 1200L,
      help = "px width for image output [%default]"
    ),
    make_option("--selfcontained",
      action = "store_true", default = TRUE,
      help = "Embed JS/CSS in HTML [%default]"
    )
  )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

stop_usage <- function(msg, parser) {
  message("Error: ", msg)
  print_help(parser)
  quit(status = 1)
}

parse_colors <- function(colors_str) {
  if (is.null(colors_str)) {
    return(NULL)
  }
  pairs <- strsplit(colors_str, ",")[[1]]
  vals <- strsplit(pairs, "=")
  setNames(sapply(vals, `[[`, 2), sapply(vals, `[[`, 1))
}

parse_coords <- function(coords_str) {
  # Returns list(seqid, start, end) or NULL
  if (is.null(coords_str)) {
    return(NULL)
  }
  parts <- strsplit(coords_str, ":")[[1]]
  if (length(parts) == 2) {
    list(seqid = NULL, start = as.integer(parts[1]), end = as.integer(parts[2]))
  } else if (length(parts) == 3) {
    list(seqid = parts[1], start = as.integer(parts[2]), end = as.integer(parts[3]))
  } else {
    stop("--coords must be start:end or seqid:start:end")
  }
}

collect_files <- function(input, exts) {
  if (file.info(input)$isdir) {
    pattern <- paste0("\\.(", paste(exts, collapse = "|"), ")$")
    files <- list.files(input, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
    if (length(files) == 0) stop("No matching files found in folder: ", input)
    files
  } else {
    strsplit(input, ",")[[1]]
  }
}

# Read all of stdin into a temp file and return its path.
# The ext argument determines the file extension (e.g. "gbk" or "gff").
read_stdin_to_tmp <- function(ext) {
  tmp <- tempfile(pattern = "stdin", fileext = paste0(".", ext))
  writeLines(readLines("stdin"), tmp)
  tmp
}

cluster_name <- function(path) tools::file_path_sans_ext(basename(path))

# Load GBK file using geneviewer's read_gbk
load_gbk <- function(path, features, keys) {
  feat_vec <- trimws(strsplit(features, ",")[[1]])
  key_vec <- trimws(strsplit(keys, ",")[[1]])
  df <- read_gbk(path, feature_keys = feat_vec, keys = key_vec)
  df$cluster <- cluster_name(path)
  df
}

# Load GFF file using geneviewer's read_gff
load_gff <- function(path, features) {
  feat_vec <- trimws(strsplit(features, ",")[[1]])
  df <- read_gff(path, feature_keys = feat_vec)
  df$cluster <- cluster_name(path)
  df
}

# Filter by region (coords or locus + window)
filter_region <- function(df, opts) {
  coords <- parse_coords(opts$coords)

  if (!is.null(coords)) {
    if (!is.null(coords$seqid)) {
      seqid_col <- intersect(c("seqid", "sequence", "chromosome"), names(df))[1]
      if (!is.na(seqid_col)) df <- filter(df, .data[[seqid_col]] == coords$seqid)
    }
    df <- filter(df, start <= coords$end & end >= coords$start)
    return(df)
  }

  if (!is.null(opts$locus)) {
    id_cols <- intersect(c("gene", "locus_tag", "Name", "ID"), names(df))
    hit <- df |>
      filter(if_any(all_of(id_cols), ~ . == opts$locus)) |>
      slice(1)
    if (nrow(hit) == 0) {
      message("Warning: locus '", opts$locus, "' not found — showing full sequence")
      return(df)
    }
    center <- (hit$start[1] + hit$end[1]) / 2
    reg_start <- center - opts$upstream
    reg_end <- center + opts$downstream
    df <- filter(df, start <= reg_end & end >= reg_start)
  }

  df
}

# Auto-detect grouping column
auto_group <- function(df, subcmd) {
  if (subcmd == "gff") {
    return(if ("type" %in% names(df)) "type" else "Name")
  }
  if ("gene_kind" %in% names(df) && any(!is.na(df$gene_kind))) {
    return("gene_kind")
  }
  for (col in c("gene", "locus_tag", "Name")) {
    if (col %in% names(df) && any(!is.na(df[[col]]))) {
      return(col)
    }
  }
  names(df)[1]
}

# ---------------------------------------------------------------------------
# Chart builder
# ---------------------------------------------------------------------------
build_chart <- function(df, opts, subcmd) {
  grp <- if (!is.null(opts$group)) opts$group else auto_group(df, subcmd)

  colors <- parse_colors(opts$colors)

  # Base chart
  chart <- GC_chart(df,
    cluster  = "cluster",
    group    = grp,
    height   = opts$height
  )

  # Genes
  gene_args <- list(
    marker     = opts$marker,
    markerSize = opts$marker_size
  )
  chart <- do.call(GC_genes, c(list(chart), gene_args))

  # Labels
  if (opts$labels) {
    label_col <- if (grp %in% names(df)) grp else "gene"
    chart <- GC_labels(chart, label = label_col)
  }

  # Cluster labels
  cl_labels <- if (!is.null(opts[["cluster_labels"]])) {
    trimws(strsplit(opts[["cluster_labels"]], ",")[[1]])
  } else {
    NULL
  }

  if (subcmd %in% c("compare", "links", "hox", "biosynthetic", "blastp", "gff")) {
    if (!is.null(cl_labels)) {
      chart <- GC_clusterLabel(chart, label = cl_labels)
    } else {
      chart <- GC_clusterLabel(chart)
    }
  }

  # Scale axis
  if (opts$scale) {
    chart <- GC_scale(chart, type = opts$scale_type)
  }

  # Scale bar
  if (opts$scale_bar) {
    chart <- GC_scaleBar(chart, unit = opts$scale_bar_unit)
  }

  # Coordinates
  if (opts$coordinates) {
    chart <- GC_coordinates(chart)
  }

  # Legend
  if (opts$legend) {
    if (subcmd == "biosynthetic") {
      chart <- GC_legend(chart, TRUE)
    } else {
      chart <- GC_legend(chart)
    }
  } else if (subcmd == "blastp") {
    chart <- GC_legend(chart, FALSE)
  }

  # Links
  if (opts$links) {
    link_args <- list(curve = opts$curve_links)
    if (!is.null(colors)) link_args$colorScheme <- colors
    chart <- do.call(GC_links, c(list(chart), link_args))
    chart <- GC_annotation(chart)
  }

  # Colors
  if (!is.null(colors)) {
    chart <- GC_color(chart, customColors = colors)
  } else if (subcmd == "biosynthetic") {
    chart <- GC_color(chart, colorScheme = "gene_kind")
  }

  # Tooltip
  if (!is.null(opts$tooltip)) {
    chart <- GC_tooltip(chart, formatter = opts$tooltip)
  }

  # Title
  if (!is.null(opts$title)) {
    chart <- GC_title(chart, title = opts$title)
  } else if (!is.null(opts[["cluster_title"]])) {
    chart <- GC_title(chart, title = opts[["cluster_title"]])
  }

  # Sequence track
  if (opts$sequence) {
    chart <- GC_sequence(chart)
  }

  # Mouse tracking
  if (opts$track_mouse) {
    chart <- GC_trackMouse(chart)
  }

  # Overlap prevention
  if (opts$overlap) {
    chart <- GC_overlap(chart)
  }

  chart
}

# ---------------------------------------------------------------------------
# BLASTP subcommand
# ---------------------------------------------------------------------------
run_blastp <- function(opts) {
  has_biostrings <- requireNamespace("Biostrings", quietly = TRUE)
  has_pwalign <- requireNamespace("pwalign", quietly = TRUE)
  if (!has_biostrings || !has_pwalign) {
    message("BLASTP requires Bioconductor packages. Install with:")
    message("  BiocManager::install(c('Biostrings', 'pwalign'))")
    quit(status = 1)
  }

  if (is.null(opts$input)) stop("--input is required")
  files <- collect_files(opts$input, c("gb", "gbk", "genbank"))

  message("Loading ", length(files), " GBK files...")
  df_list <- lapply(files, load_gbk, features = opts$feature, keys = opts$keys)
  df <- bind_rows(df_list)
  df <- filter_region(df, opts)

  if (is.null(opts$query)) {
    opts$query <- cluster_name(files[1])
    message("--query not set; using '", opts$query, "' as reference")
  }

  message("Running BLASTP (identity >= ", opts$identity, "%)...")
  blast_df <- protein_blast(df,
    query    = opts$query,
    identity = opts$identity,
    parallel = opts$parallel
  )

  # Colour by BlastP hit
  opts$group <- "BlastP"
  chart <- build_chart(blast_df, opts, "blastp")
  save_output(chart, opts)
}

# ---------------------------------------------------------------------------
# GFF subcommand
# ---------------------------------------------------------------------------
run_gff <- function(opts) {
  if (!is.null(opts$input) && opts$input == "-") {
    tmp <- read_stdin_to_tmp("gff")
    on.exit(unlink(tmp), add = TRUE)
    files <- tmp
  } else {
    if (is.null(opts$input)) stop("--input is required (use - to read from stdin)")
    files <- collect_files(opts$input, c("gff", "gff3"))
  }

  df_list <- lapply(files, load_gff, features = opts$feature)
  df <- bind_rows(df_list)
  df <- filter_region(df, opts)

  chart <- build_chart(df, opts, "gff")
  save_output(chart, opts)
}

# ---------------------------------------------------------------------------
# Generic GBK subcommand runner
# ---------------------------------------------------------------------------
run_gbk <- function(opts, subcmd) {
  if (!is.null(opts$input) && opts$input == "-") {
    tmp <- read_stdin_to_tmp("gbk")
    on.exit(unlink(tmp), add = TRUE)
    files <- tmp
  } else {
    if (is.null(opts$input)) stop("--input is required (use - to read from stdin)")
    files <- collect_files(opts$input, c("gb", "gbk", "genbank"))
  }

  df_list <- lapply(files, load_gbk, features = opts$feature, keys = opts$keys)
  df <- bind_rows(df_list)
  df <- filter_region(df, opts)

  chart <- build_chart(df, opts, subcmd)
  save_output(chart, opts)
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
save_output <- function(chart, opts) {
  outfile <- opts$output

  if (outfile == "-") {
    tmp <- tempfile(fileext = ".html")
    on.exit(unlink(tmp), add = TRUE)
    saveWidget(chart, tmp, selfcontained = TRUE)
    cat(paste(readLines(tmp), collapse = "\n"), "\n", sep = "")
    return(invisible(NULL))
  }

  ext <- tolower(tools::file_ext(outfile))

  if (ext == "html") {
    saveWidget(chart, outfile, selfcontained = opts$selfcontained)
    message("Saved HTML: ", outfile)
  } else if (ext %in% c("png", "pdf")) {
    if (!requireNamespace("webshot2", quietly = TRUE)) {
      stop("webshot2 required for PNG/PDF output. Install with: install.packages('webshot2')")
    }
    tmp <- tempfile(fileext = ".html")
    saveWidget(chart, tmp, selfcontained = TRUE)
    webshot2::webshot(tmp, outfile, vwidth = opts$width)
    message("Saved image: ", outfile)
  } else {
    stop("Unsupported output format: .", ext, " — use .html, .png, or .pdf, or - for stdout")
  }
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
args <- .raw_args

subcmd <- args[1]
rest <- args[-1]

if (!subcmd %in% VALID_SUBCMDS) {
  cat(sprintf(
    "Unknown subcommand: '%s'\nValid subcommands: %s\n",
    subcmd, paste(VALID_SUBCMDS, collapse = ", ")
  ))
  quit(status = 1)
}

defs <- SUBCMD_DEFAULTS[[subcmd]]
parser <- OptionParser(
  usage       = sprintf("%%prog %s [options]", subcmd),
  option_list = build_option_list(defs),
  description = sprintf("geneviewer CLI — '%s' preset", subcmd)
)

opts <- tryCatch(
  parse_args(parser, args = rest),
  error = function(e) {
    message("Argument error: ", conditionMessage(e))
    print_help(parser)
    quit(status = 1)
  }
)

# Dispatch
tryCatch(
  {
    if (subcmd == "blastp") {
      run_blastp(opts)
    } else if (subcmd == "gff") {
      run_gff(opts)
    } else {
      run_gbk(opts, subcmd)
    }
  },
  error = function(e) {
    message("Error: ", conditionMessage(e))
    quit(status = 1)
  }
)
