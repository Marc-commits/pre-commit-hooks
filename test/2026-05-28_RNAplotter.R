#!/usr/bin/env r
# RNAplotter.R v0.0.2
# Author: Marc Broghammer

# https://divingintogeneticsandgenomics.com/post/use-docopt-to-write-command-line-r-utilities/

doc <- "
Plot RNAseq data on genomic axis

Usage:
   RNAplotter.R (--window=<window> | (--start=<start> --end=<end>)) [options] <fwd_reads> <rev_reads> <map>
   
   RNAplotter.R --window=1-1000 fwd.grp rev.grp organism.gff3
   RNAplotter.R --start=1 --end=1000 -o graph.png fwd.grp rev.grp organism.gff3
   RNAplotter.R (--window=<window> | (--start=<start> --end=<end>)) [options] <fwd_reads> <rev_reads> <map>

Options:
    -h --help                                          Show this help.
    -v --version                                       Show version.
    -o <file> --output=<file>                          Output file [default: output.png].
    -w <window> --window=<window>                      Window of genome track to be shown.
    -s <start> --start=<start>                         If no window argument is given, set start of window.
    -e <end> --end=<end>                               If now window argument is given, set end of window.
    -n <names> --names=<names>                         Titling of line plots in legend.
    --out_width=<width>                                Width of output file in inch [default: 7].
    --out_height=<height>                              Height of output file in inch [default: 7].
    --out_format=<fmt>                                 Output file type (png|pdf|eps|ps|tex|jpeg|tiff|bmp|svg|wmf) if not in file extension.
    --fill_curve=<bool>                                Color area under curve [default: true].
    --transparency=<value>                             Transparency of plot [default: 0.8].
    --max_reads=<value>                                y-lim of plot.
    --display_subgenes=<bool>                          Display nested gene annotations [default: true].
    --label_fontsize=<size>                            Fontsize of locus tags in arrows [default: 6].
    --line_in_maps=<bool>                              Whether to include horizontal line anchoring arrows [default: true].
    --skip_label_nt_cutoff=<value>                         Skip labelling genes smaller than ... nucleotides.
    --incomplete_genes_label=<incomplete_genes_label>  How to label incomplete genes [default: _partial].
    --map_graph_ratio=<value>                          Ratio of genomic map versus line plots (small: gene arrows big) [default: 3].
    --arrowbody_height=<value>                         Height of arrow body [default: 7].
    --arrow_height=<value>                             Height of arrow [default: 10].
    --arrow_width=<value>                              Width of arrow [default: 7].
    --colors=<list>                                    Colors to use (list of hex values).

Arguments:
    <fwd_reads>                                        .grp file with forward-strand reads.
    <rev_reads>                                        .grp file with reverse-strand reads.
    <map>                                              Annotation track (csv|gff|gff3 format).
"

suppressPackageStartupMessages(library(docopt))

arguments <- docopt(doc, version = 'RNAplotter v0.0.2\n\n')

suppressPackageStartupMessages({
  library(dplyr)
  library(aplot)
  library(stringr)
  library(ggplot2)
  library(gggenes)
  library(ggeasy)
  library(RColorBrewer)
  library(labeling)
  library(rebus)
})
print(arguments)

col1 <- c(
  "#228b22", # forestgreen
  "#186118", # dark green
  "#4f94cd", # steelblue3
  "#95bfe1", # light blue
  "#666666", # gray40
  "#dbdbdb", # gray86
  "#e12f0a", # red
  "#ed826c", # light red
  "#01e8fe", # aquamarine
  "#018b98", # dark aquamarine
  "#d601e1", # violet
  "#96019e", # dark violet
  "#fe8601", # orange
  "#be4e0f", # brown
  "#000000", # black
  "#ffffff"
)

load_Gff3 <- function(input) {
  G <- ape::read.gff(input)
  G$ID <- str_extract(G$attributes, one_or_more(WRD) %R% DOT %R% DGT)
  G$Gen <- str_extract(G$attributes, "gene-" %R% one_or_more(WRD))
  G$Gen <- str_sub(G$Gen, 6, -1)
  G$strand <- sapply(G$strand, function(i) c(1, -1)[which(c("+", "-") == i)])
  b <- which(!duplicated(G[, c(4, 5, 7, 11)]) & !is.na(G$Gen))
  G <- G[b, c(1, 11, 3:5, 7)]
  colnames(G) <- c("molecule", "gene", "type", "start", "end", "orientation")

  h <- which(G$start > G$end)
  if (length(h) > 0) {
    g1 <- sapply(h, function(i) min(G$start[i], G$end[i]))
    g2 <- sapply(h, function(i) max(G$start[i], G$end[i]))
    G$start[h] <- g1
    G$end[h] <- g2
  }

  G$color <- "#4682B4"
  G$color[G$type != "gene"] <- "#D6DA18"
  G$from <- NA
  G$to <- NA
  G$subcolor <- NA
  G$label_type <- "bold"
  G$label_type[G$type == "gene"] <- "bold.italic"
  G$lane <- 1
  return(G)
}

load_Gff <- function(input) {
  G <- ape::read.gff(input)
  G$gene <- str_match(G$attributes, "ID=\\s*(.*?)\\s*;")[, 2]
  colnames(G)[which(colnames(G) == "strand")] <- "orientation"
  colnames(G)[which(colnames(G) == "seqid")] <- "molecule"

  h <- which(G$start > G$end)
  if (length(h) > 0) {
    g1 <- sapply(h, function(i) min(G$start[i], G$end[i]))
    g2 <- sapply(h, function(i) max(G$start[i], G$end[i]))
    G$start[h] <- g1
    G$end[h] <- g2
  }

  G$color <- "#4682B4"
  G$color[G$type != "gene"] <- "#D6DA18"
  G$from <- NA
  G$to <- NA
  G$subcolor <- NA
  G$label_type <- "bold"
  G$label_type[G$type == "gene"] <- "bold.italic"
  G$lane <- 1
  return(G)
}

load_csv <- function(input) {
  G <- read.csv(input, sep = ";")
  if (colnames(G)[1] == "X" & all(G[, 1] == 1:nrow(G))) {
    G <- G[, 2:ncol(G)]
  }
  o <- colnames(G)

  h <- which(G$start > G$end)
  if (length(h) > 0) {
    g1 <- sapply(h, function(i) min(G$start[i], G$end[i]))
    g2 <- sapply(h, function(i) max(G$start[i], G$end[i]))
    G$start[h] <- g1
    G$end[h] <- g2
  }

  if (!any(o %in% "color")) {
    G$color <- "#4682B4"
    G$color[G$type != "gene"] <- "#D6DA18"
  }
  G$color <- str_replace_all(G$color, SPC, "")
  G$color[is.na(G$color)] <- "#D6DA18"

  if (!any(o %in% "from"))     G$from <- NA
  if (!any(o %in% "to"))       G$to <- NA
  if (!any(o %in% "subcolor")) G$subcolor <- NA
  if (!any(o %in% "label_type")) {
    G$label_type <- "bold.italic"
  } else {
    G$label_type[is.na(G$label_type)] <- "bold.italic"
  }
  if (!any(o %in% "lane")) {
    G$lane <- 1
  } else {
    G$lane[is.na(G$lane)] <- 1
  }

  return(G)
}

if (endsWith(arguments$map, "gff3")) {
  annotation_track <- load_Gff3(arguments$map)
} else if (endsWith(arguments$map, "gff")) {
  annotation_track <- load_Gff(arguments$map)
} else if (endsWith(arguments$map, "csv")) {
  annotation_track <- load_csv(arguments$map)
}

read_data <- function(inFile1, inFile2, names) {
  if (is.null(inFile1) & is.null(inFile2)) {
    return(NULL)
  }
  Rf <- read.delim(inFile1, header = FALSE, comment.char = "#") # load first grp-file
  if (ncol(Rf) == 1) {
    Rf <- read.table(inFile1, quote = "\"", comment.char = "")
  }
  if (all(Rf[, 1] == 1:nrow(Rf))) {
    Rf <- Rf[, 2:ncol(Rf)]
  }
  Rr <- read.delim(inFile2, header = FALSE, comment.char = "#") # load second grp-file
  if (ncol(Rr) == 1) {
    Rr <- read.table(inFile2, quote = "\"", comment.char = "")
  }
  if (all(Rr[, 1] == 1:nrow(Rr))) {
    Rr <- Rr[, 2:ncol(Rr)]
  }
  
  r <- readLines(inFile1, n = 100)
  g <- length(str_extract_all(r[100], one_or_more(DGT))[[1]])
  N0 <- str_extract_all(r[1], one_or_more(WRD))[[1]]
  Nn <- str_extract_all(r[1], one_or_more(DGT))[[1]]
  r0 <- as.integer(str_extract(r[10:100], one_or_more(DGT)))
  base <- all(r0 == r0[1] + 0:90)
  name <- g == length(N0) & all(N0 != Nn)
  
  if (is.null(names)) {
    if (base & !name) {
      N <- str_c("Plot_", 1:(length(N0)))
    } else if (!base & !name) {
      N <- str_c("Plot_", 1:(length(N0)))
    } else if (base & name) {
      N <- N0[2:(length(N0))]
    } else if (!base & name) {
      N <- N0
    }
  } else {
    N <- readLines(input$Name)
  }
  colnames(Rf) <- str_c(N, "fwd")
  colnames(Rr) <- str_c(N, "rev")
  cbind(Rf, Rr)
}

data <- read_data(
  arguments$fwd_reads,
  arguments$rev_reads,
  names = arguments$names)


RNAplot <- function(Data, Gff, start, end, alpha = 0.8, graph_size = 3, color = c(),
                    subgenes = FALSE, incom_genes = "_partial", max_read = NA, filter = TRUE,
                    rename_graphs = NULL, line_visible = TRUE, arrow_body_height = 7,
                    arrowhead_height = 10, arrowhead_width = 8, Gfill = TRUE, Gsize = 1.2,
                    msize = 4, Mwidth = 7, ntlength = NA) {
  if (is.null(alpha)) alpha <- 0.8
  if (is.null(graph_size)) graph_size <- 3
  if (is.null(subgenes)) subgenes <- TRUE
  if (is.null(line_visible)) line_visible <- TRUE
  if (is.null(incom_genes)) incom_genes <- "_partial"
  if (is.null(arrow_body_height)) arrow_body_height <- 7
  if (is.null(arrowhead_height)) arrowhead_height <- 10
  if (is.null(arrowhead_width)) arrowhead_width <- 8
  if (is.null(max_read)) max_read <- NA
  if (is.null(ntlength)) ntlength <- NA
  
  #print("RNAplot called with")
  #print(start)
  #print(typeof(start))
  #print(end)
  
  Data2 <- Data
  N <- Gff[, which(colnames(Gff) %in% c("start", "end"))]
  Gff$start <- sapply(1:nrow(N), function(i) min(N[i, ]))
  Gff$end <- sapply(1:nrow(N), function(i) max(N[i, ]))
  N <- str_sub(colnames(Data2), 1, str_locate(colnames(Data2), or("fwd", "rev"))[, 1] - 1)
  N1 <- unique(N[!is.na(N)])
  
  # rename
  if (length(rename_graphs) == 0) {
    rename_graphs <- N1
  }
  
  # filter
  q <- filter
  if (is.null(q) || isTRUE(q)) {
    q <- N
  }
  Data2 <- Data2[, which(N %in% q)]
  N <- N1[which(N1 %in% q)]
  rename_graphs <- rename_graphs[which(N1 %in% q)]
  
  
  # prepare data.frame for further processing
  start1 <- min(c(start, end))
  end1 <- max(c(start, end))
  
  n <- start1:end1
  No <- rep(NA, length(colnames(Data2)) * length(n))
  si <- 13
  # Ensure Data2 is numeric
  Data2[] <- lapply(Data2, function(col) as.numeric(as.character(col)))
  
  # Build D safely
  D <- data.frame(
    Name = rep(colnames(Data2), each = length(n)),
    x = rep(n, times = ncol(Data2)),
    y = as.numeric(unlist(Data2[n, ]))  # force numeric
  )
  
  if (!is.logical(Gff$orientation)) {
    test <- c("+", "fwd", "fw", 1, "forward", "Forward", "f", "TRUE")
    Gff$orientation <- Gff$orientation %in% test
  }
  #print("D=")
  #print(D)
  z <- sort(sapply(unique(D$Name), function(i) sum(D$y[which(D$Name == i)])), decreasing = TRUE)
  D$Name <- factor(D$Name, levels = names(z)) # sorts samples by total number of reads
  
  f <- which(str_sub(D$Name, -3, -1) == "fwd") # which RNA-reads are forward
  
  Nf <- names(z)[which(str_detect(names(z), "fwd"))]
  Nf <- str_sub(Nf, 1, -4) # get Names of RNA-reads, without "fwd"
  
  
  
  
  
  
  if (length(color) == 0) {
    col <- col1[1:length(Nf)] # create colors for RNA-reads
    col <- as.character(sapply(Nf, function(i) col[which(N %in% i)]))
  } else {
    col <- as.character(sapply(Nf, function(i) color[which(N1 %in% i)]))
  }
  
  Nf1 <- rename_graphs[sapply(Nf, function(i) which(N == i))]
  
  if (!is.na(max_read)) {
    D$y[D$y > max_read] <- max_read
    D$y[D$y < (-max_read)] <- -max_read
  }
  
  p1 <- ggplot(D[f, ], aes(x = x, y = y)) +
    # geom_hline(yintercept = 0.1, size=10)+
    theme_bw(base_family = "sans") + # deletes background
    theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.border = element_blank(),
      panel.background = element_blank(),
      axis.line.x.bottom = element_line(size = 1),
      axis.line.y.left = element_line(size = 1),
      axis.text = element_text(size = si, face = "bold"),
      axis.title = element_blank(),
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.ticks.y.left = element_line(size = 1),
      plot.background = element_rect(fill = "transparent", color = NA)
    ) + # cosmetic
    scale_x_continuous(limits = c(start1, end1), expand = c(0, 0)) +
    scale_y_continuous(expand = c(0, 0), limits = c(0, max_read)) # y-axis starts at 0
  
  
  
  if (Gfill) {
    p1 <- p1 + geom_area(aes(fill = Name),
                         alpha = alpha,
                         position = "identity", color = "#000000", size = 0.4
    ) +
      labs(fill = "") + # no Name for legend
      scale_fill_manual(values = col, labels = Nf1)
  } else {
    p1 <- p1 + geom_line(aes(color = Name), size = Gsize) +
      labs(color = "") + # no Name for legend
      scale_color_manual(values = col, labels = Nf1)
  }
  
  
  zr <- rev(names(z))
  
  D$Name <- factor(D$Name, levels = zr) # reorder Names by size
  r <- which(str_sub(D$Name, -3, -1) == "rev") # which RNArun is reverse
  Nr <- zr[which(str_sub(zr, -3, -1) == "rev")]
  Nr <- str_sub(Nr, 1, -4)
  
  col2 <- as.character(sapply(Nr, function(i) col[which(Nf %in% i)])) # resort colors for plot 2
  
  p2 <- ggplot(D[r, ], aes(x = x, y = y)) + # lower lineplot
    geom_hline(yintercept = 0, color = "#000000", size = 1) +
    theme_bw() +
    theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.border = element_blank(),
      panel.background = element_blank(),
      axis.line.x.top = element_line(size = 1),
      axis.line.y.left = element_line(size = 1),
      axis.text = element_text(size = si, face = "bold"),
      axis.title = element_blank(),
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.ticks.y.left = element_line(size = 1),
      plot.background = element_rect(fill = "transparent", color = NA)
    ) +
    scale_x_continuous(position = "top", limits = c(start1, end1), expand = c(0, 0)) + # x-axis at top
    scale_y_continuous(expand = c(0, 0), limits = c(-max_read, 0), labels = abs) # y-axis starts at zero and shows absolut numbers
  
  if (Gfill) {
    p2 <- p2 + geom_area(aes(fill = Name),
                         alpha = alpha, show.legend = FALSE,
                         position = "identity", color = "#000000", size = 0.4
    ) +
      scale_fill_manual(values = col2, labels = Nr) # reorder color
  } else {
    p2 <- p2 + geom_line(aes(color = Name), size = Gsize, show.legend = FALSE) + # no Name for legend
      scale_color_manual(values = col2, labels = Nr)
  }
  
  g0 <- which((Gff$start >= start1 & Gff$end <= end1) |
                (Gff$start < start1 & Gff$end > start1) |
                (Gff$start < end1 & Gff$end > end1)) # get all relevant Gff-elements
  
  lb <- arrow_body_height # width of gene-arrow
  lh <- arrowhead_height
  lw <- arrowhead_width
  
  if (length(g0) > 0) {
    G <- Gff[g0, ]
    
    s <- which((G$start < start1 & !G$orientation) |
                 G$end > end1 & G$orientation) # which Gff-elements would have an arrow and over the edge
    s1 <- which(G$start < start1 | G$end > end1) # which Gff-elements are too long
    
    if (length(s1) > 0) {
      G$gene[s1] <- str_c(G$gene[s1], incom_genes)
    } # rename elements that are to long
    
    
    G$start <- sapply(G$start, function(i) max(i, start1)) # Gff-start is mininmal start of area of Interest
    G$end <- sapply(G$end, function(i) min(i, end1)) # Gff-end is maxinmal end of area of Interest
    
    G$start1 <- NA # get second category for Gff-elemnts with different arrow
    G$end1 <- NA
    G$startall <- G$start # get category for all Gff-elements for labeling
    G$endall <- G$end
    if (length(s) > 0) {
      G$start1[s] <- G$start[s]
      G$end1[s] <- G$end[s]
      G$start[s] <- NA
      G$end[s] <- NA
    }
    
    
    gf <- which(G$orientation) # which Gff-element is forward
    gr <- which(!G$orientation) # which Gff-element is reverse
  } else {
    G <- data.frame(matrix(NA, ncol = ncol(Gff)))
    colnames(G) <- colnames(Gff)
    gf <- NULL
    gr <- NULL
  }
  
  if (length(unique(G$lane)) > 1) {
    g <- unique(G$lane)
    l1 <- length(unique(G$lane))
    r1 <- 1:(l1 * 2) + nrow(G)
    gf <- c(gf, 1:(l1) + nrow(G))
    gr <- c(gr, 1:l1 + nrow(G) + l1)
    G[r1, ] <- NA
    G$orientation[r1] <- c(rep(TRUE, l1), rep(FALSE, l1))
    G$lane[r1] <- rep(g, 2)
    G$molecule[r1] <- G$molecule[1]
  }
  
  if (is.na(ntlength)) {
    G$gene[(G$endall - G$startall) / (end1 - start1) * Mwidth < strwidth(G$gene, units = "inches") * 1.5] <- ""
  } else {
    G$gene[abs(G$endall - G$startall) < ntlength] <- ""
  }
  
  
  if (length(gf) == 0) { # in case there is no forward Gff-element...
    
    p3 <- ggplot() + # write empty plot
      geom_gene_arrow()
  } else {
    col1 <- unique(G$color[gf])
    names(col1) <- unique(G$color[gf])
    
    p3 <- ggplot(G[gf, ], aes(y = as.character(lane))) +
      geom_gene_arrow(
        aes(
          forward = orientation, fill = color, # write Gene-map
          xmin = as.integer(start), xmax = as.integer(end)
        ),
        arrowhead_height = unit(lh, "mm"),
        arrowhead_width = unit(max(0, lw), "mm"),
        arrow_body_height = unit(lb, "mm")
      ) + # first Gff-elements inside totally in area with regular arrowheads
      geom_gene_arrow(
        aes(
          forward = orientation, xmin = as.integer(start1),
          xmax = as.integer(end1), fill = color
        ),
        arrowhead_height = unit(lb * 0.6, "mm"),
        arrowhead_width = unit(lb * 0.3, "mm"),
        arrow_body_height = unit(lb, "mm")
      ) + # secound Gff-elements with ending outside area with irregular arrowheads
      scale_fill_manual(values = col1)
  }
  
  if (line_visible) {
    p3 <- p3 + theme_genes()
  } else {
    p3 <- p3 + theme_void()
  }
  
  p3 <- p3 + scale_x_continuous(limits = c(start1, end1), expand = c(0, 0)) +
    theme(
      panel.background = element_blank(),
      axis.line.x.bottom = element_line(size = 1),
      axis.text = element_text(size = si, face = "bold"), # x-axis is plotted
      axis.title = element_blank(),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      legend.position = "none",
      plot.background = element_rect(fill = "transparent", color = NA)
    )
  
  if (length(gf) > 0) {
    if (any(!is.na(G$from[gf]))) {
      if (subgenes) {
        p3 <- p3 + geom_subgene_arrow(
          aes(
            xmin = as.integer(startall), xmax = as.integer(endall),
            y = as.character(lane), xsubmin = as.integer(from),
            xsubmax = as.integer(to)
          ),
          color = "black",
          fill = G$subcolor[gf],
          arrowhead_height = unit(lb, "mm"),
          arrowhead_width = unit(0, "mm"),
          arrow_body_height = unit(lb, "mm")
        )
      }
    }
    p3 <- p3 + geom_text(aes(x = (startall + endall) / 2, label = gene, fontface = label_type),
                         size = msize
    )
  }
  
  
  
  if (length(gr) == 0) { # in case there is no reverse Gff-element...
    p4 <- ggplot() +
      geom_gene_arrow() # write empty plot
  } else {
    col1 <- unique(G$color[gr])
    names(col1) <- unique(G$color[gr])
    p4 <- ggplot(G[gr, ], aes(y = as.character(10 - as.integer(lane)))) + # write Gene-map (reverse)
      geom_gene_arrow(
        aes(
          forward = orientation, xmin = as.integer(start),
          xmax = as.integer(end), fill = color
        ),
        arrowhead_height = unit(lh, "mm"),
        arrowhead_width = unit(lw, "mm"),
        arrow_body_height = unit(lb, "mm")
      ) + # first Gff-elements inside totally in area with regular arrowheads
      geom_gene_arrow(
        aes(
          forward = orientation, xmin = as.integer(start1),
          xmax = as.integer(end1), fill = color
        ),
        arrowhead_height = unit(lb * 0.6, "mm"),
        arrowhead_width = unit(lb * 0.3, "mm"),
        arrow_body_height = unit(lb, "mm")
      ) + # secound Gff-elements with ending outside area with irregular arrowheads
      scale_fill_manual(values = col1) # colorization
  }
  
  if (line_visible) {
    p4 <- p4 + theme_genes()
  } else {
    p4 <- p4 + theme_void()
  }
  
  p4 <- p4 +
    scale_x_continuous(limits = c(start1, end1), expand = c(0, 0)) + # x-axis range is exactly as the lineplots
    theme(
      axis.text = element_text(size = 12, face = "bold"), # text of axis
      axis.title = element_blank(),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      legend.position = "none", # no legend
      axis.ticks.x = element_blank(),
      axis.text.x = element_blank(),
      plot.background = element_rect(fill = "transparent", color = NA)
    ) +
    easy_remove_x_axis() # no x-axis
  
  if (length(gr) > 0) {
    if (any(!is.na(G$from[gr]))) {
      if (subgenes) {
        p4 <- p4 + geom_subgene_arrow(
          aes(
            xmin = as.integer(startall), xmax = as.integer(endall),
            y = as.character(10 - as.integer(lane)), xsubmin = as.integer(from),
            xsubmax = as.integer(to)
          ),
          color = "black",
          fill = G$subcolor[gr],
          arrowhead_height = unit(lb, "mm"),
          arrowhead_width = unit(0, "mm"),
          arrow_body_height = unit(lb, "mm")
        )
      }
    }
    p4 <- p4 + geom_text(aes(x = (startall + endall) / 2, label = gene, fontface = label_type),
                         size = msize
    )
  }
  
  
  p_lab <- ggplot() + # write empty plot, with text
    annotate(
      geom = "text", x = 0, y = 0, label = "                             number of reads",
      fontface = "bold", angle = 90, size = 6
    ) +
    coord_cartesian(clip = "off") +
    theme_void() # no background
  
  p_xlab <- ggplot() + # write empty plot, with text
    annotate(geom = "text", x = mean(n), y = 0, label = "position", fontface = "bold", size = 4) +
    coord_cartesian(clip = "off") +
    theme_void()
  
  ap <- p2 %>%
    insert_top(p4, height = 1 / graph_size) %>%
    insert_top(p3, height = 1 / graph_size) %>%
    insert_top(p1, height = 1) # combine plots with each other, graph_size free variable
  ap <- ap %>% # insert_left(p_lab, width = 0.1)%>%  #combined complete plots with y-axis title
    insert_bottom(p_xlab, height = 0.15)
  
  
  
  return(ap) # return plot
}

defaultColors <- c(
  "#228b22", # forestgreen
  "#186118", # dark green
  "#4f94cd", # steelblue3
  "#95bfe1", # light blue
  "#666666", # gray40
  "#dbdbdb", # gray86
  "#e12f0a", # red
  "#ed826c", # light red
  "#01e8fe", # aquamarine
  "#018b98", # dark aquamarine
  "#d601e1", # violet
  "#96019e", # dark violet
  "#fe8601", # orange
  "#be4e0f", # brown
  "#000000", # black
  "#ffffff"
)



as_bool <- function(x) isTRUE(as.logical(toupper(x)))

x <- RNAplot(
  data,
  annotation_track,
  start = if (is.null(arguments$window)) as.integer(arguments$start) else as.integer(str_split_i(arguments$window, "-", 1)),
  end = if (is.null(arguments$window)) as.integer(arguments$end) else as.integer(str_split_i(arguments$window, "-", 2)),
  alpha = as.numeric(arguments$transparency),
  graph_size = as.numeric(arguments$map_graph_ratio),
  color = if (is.null(arguments$colors)) defaultColors else arguments$colors,
  subgenes = as_bool(arguments$display_subgenes),
  incom_genes = "_partial",
  max_read = if (is.null(arguments$max_reads)) NA else as.numeric(arguments$max_reads),
  filter = TRUE,
  rename_graphs = NULL,
  line_visible = as_bool(arguments$line_in_maps),
  arrow_body_height = as.numeric(arguments$arrowbody_height),
  arrowhead_height = as.numeric(arguments$arrow_height),
  arrowhead_width = as.numeric(arguments$arrow_width),
  Gfill = as_bool(arguments$fill_curve),
  Gsize = 1.2,
  msize = 4,
  Mwidth = 7,
  ntlength = if (is.null(arguments$skip_label_nt_cutoff)) NA else as.numeric(arguments$skip_label_nt_cutoff)
)

ggsave(arguments$output,
  plot = x,
  width = as.numeric(arguments$out_width),
  height = as.numeric(arguments$out_height),
  units = "in",
  device = arguments$out_format
)
