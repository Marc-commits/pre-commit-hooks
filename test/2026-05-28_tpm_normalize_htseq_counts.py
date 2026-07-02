#! /usr/bin/env -S uv run --script
#
# /// script
# dependencies = [
#     "marimo",
#     "pandas==3.0.1",
#     "tabulate==0.9.0",
# ]
# requires-python = ">=3.12"
# ///

__author__ = "Marc Broghammer"
__email__ = "marc.broghammer@biologie.uni-freiburg.de"
__version__ = "0.1.0"

import marimo

__generated_with = "0.20.2"
app = marimo.App(
    width="full",
    app_title="tpm_normalize_htseq_counts",
    auto_download=["html"],
)


@app.cell
def _():
    import pandas as pd
    import argparse as ap
    import sys
    from tabulate import tabulate

    return ap, pd, sys, tabulate


@app.cell
def _():
    # inspired by https://github.com/NCI-GDC/htseq-tool/blob/master/htseq_tools/tools/fpkm.py
    return


@app.cell
def _(ap):
    parser = ap.ArgumentParser(
        prog="TPM normalization",
        description="TPM normalization of htseq-count-generated count files",
        epilog="uv run tpm_normalize_htseq_counts.py -f counts.{tsv|csv} -o tpm_normalized_counts.{tsv|csv}",
    )
    parser.add_argument("-f", "--file", help="Input file", required=True)
    parser.add_argument(
        "-l", "--gene-lengths", help="tsv with gene lengths", required=True
    )
    parser.add_argument(
        "-o", "--output", help="output file", default="tpm_normalized_counts.tsv"
    )
    parser.add_argument("-v", "--verbose", help="verbose", action="store_true")
    parser.add_argument("-q", "--quiet", help="Quiet mode", action="store_true")
    return (parser,)


@app.cell
def _(parser):
    args = parser.parse_args()
    return (args,)


@app.cell
def _(args, sys):
    if args.verbose and not args.quiet:
        print(
            f"This is tpm_normalize_htseq_county.py running Python {sys.version}"
        )
    return


@app.cell
def _(args, pd, sys):
    counts_tsv = "test/test.tsv" if not args.file else args.file
    if args.file.endswith("tsv"):
        raw_counts = pd.read_table(counts_tsv, sep="\t", comment="#", index_col=0)
    elif args.file.endswith("csv"):
        raw_counts = pd.read_csv(counts_tsv, comment="#", index_col=0)
    else:
        print("Could not guess input file format based on ext (tsv|csv). Exit 1")
        sys.exit(1)
    return (raw_counts,)


@app.cell
def _(args):
    if args.verbose:
        print(f"Read {args.file}")
    return


@app.cell
def _(args, raw_counts, tabulate):
    counts = raw_counts.drop(
        [label for label in raw_counts.index.values if label.startswith("__")]
    )
    if args.verbose:
        print("Counts:")
        print(tabulate(counts, headers="keys", tablefmt="psql"))
    counts  # notebook return
    return (counts,)


@app.cell
def _(counts):
    assert not counts.index.has_duplicates
    return


@app.cell
def _(counts):
    (counts < 0).any(skipna=False)
    return


@app.cell
def _(args, pd, tabulate):
    gene_lengths_tsv = (
        "test/lengths.tsv" if not args.gene_lengths else args.gene_lengths
    )

    raw_lengths = pd.read_table(
        gene_lengths_tsv,
        sep="\t",
        comment="#",
        index_col=0,
        names=["gene", "length"],
    )
    if args.verbose:
        print("Gene lengths:")
        print(tabulate(raw_lengths, headers="keys", tablefmt="psql"))
    raw_lengths  # notebook return
    return (raw_lengths,)


@app.cell
def _(args):
    if args.verbose:
        print(f"Read {args.gene_lengths}")
    return


@app.cell
def _(raw_lengths):
    assert not raw_lengths.index.has_duplicates
    return


@app.cell
def _(raw_lengths):
    (raw_lengths <= 0).any(skipna=False)
    return


@app.cell
def _(counts, raw_lengths):
    assert counts.index.symmetric_difference(raw_lengths.index).empty
    return


@app.cell
def _(counts, raw_lengths):
    div_by_length = counts.div(raw_lengths.values, axis=0)
    div_by_length  # notebook return
    return (div_by_length,)


@app.cell
def _(args, div_by_length, tabulate):
    lib_size = div_by_length.sum()
    normalized_counts = div_by_length / (lib_size * 1e6)
    if args.verbose:
        print("Normalized counts:")
        print(tabulate(normalized_counts, headers="keys", tablefmt="psql"))
    normalized_counts  # notebook return
    return (normalized_counts,)


@app.cell
def _(args, normalized_counts, sys):
    if args.output.endswith("tsv"):
        normalized_counts.to_csv(args.output, sep="\t")
    elif args.output.endswith("csv"):
        normalized_counts.to_csv(args.output)
    else:
        print("Could not guess output file format based on ext (tsv|csv). Exit 1")
        sys.exit(1)
    return


@app.cell
def _(args):
    if args.verbose:
        print(f"Wrote {args.output}")
    return


if __name__ == "__main__":
    app.run()
