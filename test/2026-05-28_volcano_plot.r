#!/usr/bin/env r
# volcano_plot.r v0.1.0
# Author: Marc Broghammer
# Email: marc.broghammer@gmx.de

doc <- "Volcano Plot Generator

Creates a volcano plot from differential expression results.

The input TSV file must contain at minimum the following columns
(names configurable via --col_* options):
  - A numeric column for x-axis values (log2 fold change)
  - A numeric column for y-axis values (-log10 adjusted p-value)
  - A categorical column with class labels: 'DOWN', 'no', or 'UP'
  - A text column with gene/protein names (used for labeling)

Usage:
  volcano_plot.r --input <input> --output <output> [options]
  volcano_plot.r --output <output> [options]
  volcano_plot.r (-h | --help)
  volcano_plot.r --version

Required:
  --input <input>                     Input TSV file (or pass via stdin)
  --output <output>                   Output file (.pdf, .png, or .svg)

Plot thresholds:
  --pval_line <y>          p-value dashed line y-intercept [default: 2]
  --fc_lines <lo,hi>      Fold-change vertical lines [default: -2,2]
  --label_pval <y>        -log10(p) threshold for labels, both sides
                          (no labels if omitted)
  --label_fc <x>          log2(FC) threshold for labels, both sides
                          (no labels if omitted)
  --label_pval_up <y>     -log10(p) threshold for UP labels
                          (overrides --label_pval for + side)
  --label_pval_dn <y>     -log10(p) threshold for DOWN labels
                          (overrides --label_pval for - side)
  --label_fc_up <x>       log2(FC) threshold for UP labels; points with
                          FC >= x are labelled (overrides --label_fc)
  --label_fc_dn <x>       log2(FC) threshold for DOWN labels; points with
                          FC <= -x are labelled (overrides --label_fc)
  --annotate <genes>      Always label these genes regardless of thresholds
                          (comma-separated)

Axis limits and labels:
  --xlim <lo,hi>           X-axis limits (default: auto from data +-20%)
  --ylim <lo,hi>           Y-axis limits (default: auto from data +-20%)
  --title <title>           Plot title [default: Volcano Plot]
  --xlab <label>           X-axis label [default: log2 fold change]
  --ylab <label>           Y-axis label [default: -log10(adj p-value)]

Column names:
  --col_x <name>           X column [default: log2_ratio]
  --col_y <name>           Y column [default: log10_pValue]
  --col_class <name>       Class column [default: class_0]
  --col_label <name>       Gene label column [default: Genes]
  --col_class_mapping <m>  Remap class values as 'UP=other,DOWN=other,no=no'
                           (partial ok)

Legend:
  --legend <text>          Arbitrary legend annotation string to add to plot
  --legend_pos <pos>       Legend annotation position: top-left, top-right,
                           bottom-left, bottom-right [default: top-right]

Output dimensions:
  --width <inches>         Width [default: 10]
  --height <inches>        Height [default: 7]
  --dpi <dpi>              DPI for PNG [default: 300]

Appearance:
  --color_up <color>       Color for UP points [default: blue]
  --color_dn <color>       Color for DOWN points [default: lightgreen]
  --color_ns <color>       Color for non-significant points [default: grey]
  --point_size <size>      Point size [default: 2]
  --point_alpha <alpha>    Point opacity, 0-1 [default: 1]
  --label_size <size>      Label text size [default: 2.5]
  --boxed_labels           Box gene labels (uses geom_label_repel)
  --shape_up <pch>         Point shape for UP class (R pch integer) [default: 20]
  --shape_dn <pch>         Point shape for DOWN class [default: 20]
  --shape_ns <pch>         Point shape for non-significant class [default: 20]

Output mode:
  --interactive            Produce an interactive HTML plot
                           (requires --output *.html)
  --quiet                  Suppress startup banner (use with --version)
"

script_version <- "0.1.0"

.argv <- commandArgs(trailingOnly = TRUE)
if ("--version" %in% .argv) {
  if (!("--quiet" %in% .argv)) {
    r_ver <- paste0(R.version$major, ".", R.version$minor)
    rest <- .argv[!.argv %in% c("--version", "--quiet")]
    args_str <- if (length(rest) > 0) paste(rest, collapse = " ") else "(none)"
    cat(paste0(
      "This is volcano_plot.r v", script_version,
      " running R ", r_ver,
      " with args: ", args_str, "\n"
    ))
  }
  quit(status = 0)
}

args <- docopt::docopt(doc)

# --- Helper: parse comma-separated string list ---
parse_csv_arg <- function(s) {
  if (is.null(s) || !nzchar(s)) {
    return(character(0))
  }
  trimws(strsplit(s, ",")[[1]])
}

# --- Helper: parse comma-separated numeric pair ---
parse_pair <- function(s, name) {
  parts <- strsplit(s, ",")[[1]]
  if (length(parts) != 2) {
    stop(paste0(
      "--", name, " requires exactly two comma-separated values, got: ", s
    ))
  }
  vals <- suppressWarnings(as.numeric(parts))
  if (any(is.na(vals))) {
    stop(paste0("--", name, " values must be numeric, got: ", s))
  }
  vals
}

# --- Parse and validate arguments ---
input_file <- args$input
output_file <- args$output
use_stdin <- is.null(input_file)

if (!use_stdin && !file.exists(input_file)) {
  stop(paste0("Input file not found: ", input_file))
}

interactive_mode <- isTRUE(args$interactive)

ext <- tolower(tools::file_ext(output_file))
if (interactive_mode) {
  if (ext != "html") {
    stop("--interactive requires an --output file with .html extension")
  }
} else {
  if (!ext %in% c("pdf", "png", "svg")) {
    stop(paste0("Unsupported output format '.", ext, "'. Use .pdf, .png, or .svg"))
  }
}

pval_line <- as.numeric(args$pval_line)
fc_lines <- parse_pair(args$fc_lines, "fc_lines")
xlim_arg <- if (!is.null(args$xlim)) parse_pair(args$xlim, "xlim") else NULL
ylim_arg <- if (!is.null(args$ylim)) parse_pair(args$ylim, "ylim") else NULL
width <- as.numeric(args$width)
height <- as.numeric(args$height)
dpi <- as.numeric(args$dpi)

plot_title <- args$title
xlab <- args$xlab
ylab <- args$ylab

col_x <- args$col_x
col_y <- args$col_y
col_class <- args$col_class
col_label <- args$col_label

# Symmetric shorthand (fallback for both sides)
label_pval <- if (!is.null(args$label_pval)) as.numeric(args$label_pval) else NULL
label_fc <- if (!is.null(args$label_fc)) as.numeric(args$label_fc) else NULL

# Per-direction overrides (fall back to symmetric if not provided)
pval_up <- if (!is.null(args$label_pval_up)) as.numeric(args$label_pval_up) else label_pval
pval_dn <- if (!is.null(args$label_pval_dn)) as.numeric(args$label_pval_dn) else label_pval
fc_up <- if (!is.null(args$label_fc_up)) as.numeric(args$label_fc_up) else label_fc
fc_dn <- if (!is.null(args$label_fc_dn)) as.numeric(args$label_fc_dn) else label_fc

annotate_genes <- parse_csv_arg(args$annotate)

do_labels_up <- !is.null(pval_up) && !is.null(fc_up)
do_labels_dn <- !is.null(pval_dn) && !is.null(fc_dn)
do_labels <- do_labels_up || do_labels_dn || length(annotate_genes) > 0

# Parse --col_class_mapping e.g. "UP=other,DOWN=other,no=no"
class_mapping <- NULL
if (!is.null(args$col_class_mapping)) {
  pairs <- strsplit(args$col_class_mapping, ",")[[1]]
  class_mapping <- list()
  for (pair in pairs) {
    kv <- strsplit(pair, "=")[[1]]
    if (length(kv) != 2) stop(paste0("Invalid --col_class_mapping entry: ", pair))
    class_mapping[[trimws(kv[1])]] <- trimws(kv[2])
  }
}

legend_text <- args$legend
legend_pos <- if (!is.null(args$legend_pos)) args$legend_pos else "top-right"

color_up <- if (!is.null(args$color_up)) args$color_up else "blue"
color_dn <- if (!is.null(args$color_dn)) args$color_dn else "lightgreen"
color_ns <- if (!is.null(args$color_ns)) args$color_ns else "grey"
point_size  <- as.numeric(if (!is.null(args$point_size))  args$point_size  else 2)
point_alpha <- as.numeric(if (!is.null(args$point_alpha)) args$point_alpha else 1)
label_size  <- as.numeric(if (!is.null(args$label_size))  args$label_size  else 2.5)
shape_up <- as.integer(if (!is.null(args$shape_up)) args$shape_up else 20L)
shape_dn <- as.integer(if (!is.null(args$shape_dn)) args$shape_dn else 20L)
shape_ns <- as.integer(if (!is.null(args$shape_ns)) args$shape_ns else 20L)
use_shape_enc <- !(shape_up == 20L && shape_dn == 20L && shape_ns == 20L)

# --- Load plotting libraries ---
library(ggplot2) # nolint: object_usage_linter.

# --- Read and filter data ---
if (use_stdin) {
  df <- read.delim(file("stdin"))
} else {
  df <- read.delim(input_file)
}

required_cols <- c(col_x, col_y, col_class)
if (do_labels) required_cols <- c(required_cols, col_label)
missing_cols <- setdiff(required_cols, colnames(df))
if (length(missing_cols) > 0) {
  stop(paste0("Missing column(s) in input file: ", paste(missing_cols, collapse = ", ")))
}

df_filtered <- df[df[[col_class]] %in% c("DOWN", "no", "UP"), ]

# Apply class mapping if provided
if (!is.null(class_mapping)) {
  for (from in names(class_mapping)) {
    df_filtered[[col_class]][df_filtered[[col_class]] == from] <- class_mapping[[from]]
  }
}

# --- Compute axis limits (auto if not specified) ---
auto_limits <- function(vals, pad = 0.2, floor0 = FALSE) {
  r <- range(vals, na.rm = TRUE)
  span <- r[2] - r[1]
  lo <- r[1] - pad * span
  hi <- r[2] + pad * span
  if (floor0) lo <- max(0, lo)
  c(lo, hi)
}
xlim <- if (!is.null(xlim_arg)) xlim_arg else auto_limits(df_filtered[[col_x]])
ylim <- if (!is.null(ylim_arg)) {
  ylim_arg
} else {
  auto_limits(df_filtered[[col_y]], floor0 = TRUE)
}

# Determine the set of class levels present after mapping
class_levels <- unique(df_filtered[[col_class]])
default_colors <- c("DOWN" = color_dn, "no" = color_ns, "UP" = color_up)
# For any new level not in default palette, assign a neutral color
point_colors <- setNames(
  sapply(class_levels, function(lv) {
    if (lv %in% names(default_colors)) default_colors[[lv]] else "orange"
  }),
  class_levels
)

default_shapes <- c("DOWN" = shape_dn, "no" = shape_ns, "UP" = shape_up)
shape_values <- setNames(
  sapply(class_levels, function(lv) {
    if (lv %in% names(default_shapes)) default_shapes[[lv]] else 20L
  }),
  class_levels
)

# --- Open graphics device (static output only) ---
if (!interactive_mode) {
  if (ext == "pdf") {
    pdf(output_file, width = width, height = height)
  } else if (ext == "png") {
    png(output_file, width = width, height = height, units = "in", res = dpi)
  } else if (ext == "svg") {
    svg(output_file, width = width, height = height)
  }
}

# --- Build plot ---
base_aes <- if (use_shape_enc) {
  aes(x = .data[[col_x]], y = .data[[col_y]],
      color = .data[[col_class]], shape = .data[[col_class]])
} else {
  aes(x = .data[[col_x]], y = .data[[col_y]], color = .data[[col_class]])
}
geom_pt <- if (use_shape_enc) {
  geom_point(size = point_size, alpha = point_alpha)
} else {
  geom_point(size = point_size, shape = 20L, alpha = point_alpha)
}

p <- ggplot(data = df_filtered) +
  base_aes +
  geom_pt +
  scale_color_manual(
    values = point_colors,
    guide = guide_legend(title = NULL)
  ) +
  geom_hline(yintercept = pval_line, linetype = "dashed", color = "black") +
  geom_vline(xintercept = fc_lines, linetype = "dashed", color = "black") +
  annotate("text",
    x = xlim[2] - 2,
    y = pval_line - 0.25,
    label = paste0("p = ", 10^(-pval_line)),
    size = 5, hjust = 0
  ) +
  coord_cartesian(xlim = xlim, ylim = ylim) +
  labs(x = xlab, y = ylab) +
  theme_minimal() +
  ggtitle(plot_title)

if (use_shape_enc) {
  p <- p + scale_shape_manual(
    values = shape_values,
    guide = guide_legend(title = NULL)
  )
}

if (do_labels) {
  label_data_up <- if (do_labels_up) {
    df_filtered[df_filtered[[col_x]] >= fc_up & df_filtered[[col_y]] >= pval_up, ]
  } else {
    df_filtered[0, ]
  }
  label_data_dn <- if (do_labels_dn) {
    df_filtered[df_filtered[[col_x]] <= -fc_dn & df_filtered[[col_y]] >= pval_dn, ]
  } else {
    df_filtered[0, ]
  }
  label_data <- unique(rbind(label_data_up, label_data_dn))
  if (length(annotate_genes) > 0) {
    is_ann <- !is.na(df_filtered[[col_label]]) &
      df_filtered[[col_label]] %in% annotate_genes
    label_data <- unique(rbind(label_data, df_filtered[is_ann, ]))
  }
  repel_args <- list(
    data         = label_data,
    mapping      = aes(label = .data[[col_label]]),
    size         = label_size,
    color        = "black",
    max.overlaps = 30,
    max.iter     = 100000,
    nudge_x      = 0.5,
    force        = 3,
    segment.size = 0.25
  )
  repel_fn <- if (isTRUE(args$boxed_labels)) ggrepel::geom_label_repel
              else                            ggrepel::geom_text_repel
  p <- p + do.call(repel_fn, repel_args)
}

# Add arbitrary legend annotation if requested
if (!is.null(legend_text)) {
  pos_map <- list(
    "top-left"     = c(x = -Inf, y = Inf, hjust = -0.1, vjust = 1.5),
    "top-right"    = c(x = Inf, y = Inf, hjust = 1.1, vjust = 1.5),
    "bottom-left"  = c(x = -Inf, y = -Inf, hjust = -0.1, vjust = -0.5),
    "bottom-right" = c(x = Inf, y = -Inf, hjust = 1.1, vjust = -0.5)
  )
  if (!legend_pos %in% names(pos_map)) {
    stop(paste0(
      "Invalid --legend_pos '", legend_pos, "'. Choose from: ",
      paste(names(pos_map), collapse = ", ")
    ))
  }
  lp <- pos_map[[legend_pos]]
  p <- p +
    annotate("text",
      x = lp[["x"]], y = lp[["y"]],
      label = legend_text,
      hjust = lp[["hjust"]], vjust = lp[["vjust"]],
      size = 4, color = "black"
    )
}

if (interactive_mode) {
  library(plotly) # nolint: object_usage_linter.
  ip <- ggplotly(p, tooltip = c("x", "y", if (do_labels) col_label else NULL))
  htmlwidgets::saveWidget(ip, output_file, selfcontained = TRUE)
} else {
  print(p) # nolint: no_print_linter.
  dev.off()
}

message(paste0("Wrote ", ext, " to ", output_file))

sessionInfo()
