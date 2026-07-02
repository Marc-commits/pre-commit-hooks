#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "marimo",
#     "matplotlib==3.10.8",
#     "openpyxl==3.1.5",
#     "pandas==3.0.1",
#     "pingouin==0.6.0",
#     "seaborn==0.13.2",
#     "statannotations==0.7.2",
#     "tabulate==0.10.0",
# ]
# ///

__author__ = "Marc Broghammer"
__email__ = "marc.broghammer@biologie.uni-freiburg.de"
__version__ = "0.0.5"

import marimo

__generated_with = "0.21.1"
app = marimo.App(width="medium", auto_download=["html"])


@app.cell
def _():
    import pandas as pd
    import seaborn as sns
    import matplotlib.pyplot as plt
    import argparse as ap
    from tabulate import tabulate
    import sys
    import pprint
    import re
    from pathlib import Path

    return ap, pd, plt, pprint, re, Path, sns, sys, tabulate


@app.function
def list_of_strs(arg):
    return arg.split(",")


@app.cell
def _(ap):
    parser = ap.ArgumentParser(prog="", description="", epilog="")
    parser.add_argument("-f", "--file", help="Input file", required=True)
    parser.add_argument(
        "--skiprows",
        help="number rows to skip until header",
        required=True,
        type=int,
    )
    parser.add_argument(
        "-r",
        "--row",
        "--rows",
        help="row for parsing metabolite names",
        required=True,
        type=int,
    )
    parser.add_argument(
        "-n",
        "--number-samples",
        help="Number of samples (= rows to be parsed)",
        type=int,
        required=True,
    )
    parser.add_argument("--sheet-name", help="Name of sheet to be read")
    parser.add_argument(
        "--samples-headers",
        "--sample-headers",
        help="Header columns of sample sheet",
        type=list_of_strs,
    )
    parser.add_argument(
        "--sheets-headers",
        "--sheet-headers",
        help="Header columns of metabolite sheets",
        type=list_of_strs,
    )
    parser.add_argument(
        "--column-ranges",
        help="Columns that define metabolite sheets, e.g. A:O",
        type=list_of_strs,
        required=True,
    )
    parser.add_argument("-o", "--output", help="output file", default="out.xlsx")
    parser.add_argument(
        "-p", "--plot", help="Plot output. Default: conc_vs_metabolites.svg"
    )
    parser.add_argument("--correlation-matrix", default="corr_matrix.csv")
    parser.add_argument("--correlation-heatmap", default="corr_matrix.svg")
    parser.add_argument("-v", "--verbose", help="verbose", action="store_true")
    parser.add_argument("-q", "--quiet", help="Quiet mode", action="store_true")
    parser.add_argument(
        "--plot-per",
        action="append",
        default=[],
        dest="plot_per",
        metavar="COLUMN",
        help="Generate a split boxplot+swarmplot for COLUMN (repeatable)",
    )
    parser.add_argument(
        "--outdir",
        default=".",
        help="Output directory for all generated files (default: current directory)",
    )
    return (parser,)


@app.cell
def _(Path, parser):
    args = parser.parse_args()
    _outdir = Path(args.outdir)
    _outdir.mkdir(parents=True, exist_ok=True)
    args.output = str(_outdir / Path(args.output).name)
    args.correlation_matrix = str(_outdir / Path(args.correlation_matrix).name)
    args.correlation_heatmap = str(_outdir / Path(args.correlation_heatmap).name)
    args.plot = str(_outdir / (Path(args.plot).name if args.plot else "conc_vs_metabolites.svg"))
    return (args,)


@app.cell
def _(args):
    ROW = args.row  # for metabolites names
    SKIPROWS = args.skiprows
    N_SAMPLES = args.number_samples
    SAMPLES_HEADERS = (
        [
            "ID",
            "name",
            "strain",
            "N-stress / h",
            "replicate",
            "amount / OD",
        ]
        if not args.samples_headers
        else args.samples_headers
    )
    SHEETS_HEADERS = (
        [
            "Data#",
            "Data Filename",
            "Ret. Time",
            "Peak area undiluted",
            "Total volume of the sample",
            "Peak area per total sample",
            "Factor IT",
            "Peak area per total sample normalized to IT",
            "Peak area per total sample normalized to Std (ng)",
            "Normalized to OD*Vol (ng*mL-1*OD750 nm)",
        ]
        if not args.sheets_headers
        else args.sheets_headers
    )
    return N_SAMPLES, ROW, SAMPLES_HEADERS, SHEETS_HEADERS, SKIPROWS


@app.cell
def _(args, sys):
    if args.verbose and not args.quiet:
        print(f"This is clean_metabolites_xlsx.py running Python {sys.version}")
    return


@app.cell
def _(args):
    file = (
        "test/01292026_AG Hess Marc Summary.xlsx" if not args.file else args.file
    )
    return (file,)


@app.cell
def _(N_SAMPLES, SAMPLES_HEADERS, SKIPROWS, args, file, pd, tabulate):
    samples = pd.read_excel(
        file,
        sheet_name=args.sheet_name,
        skiprows=SKIPROWS,
        nrows=N_SAMPLES + 1,
        index_col="ID",
        usecols=SAMPLES_HEADERS,
    )
    if args.verbose:
        print("Samples:")
        print(tabulate(samples, headers="keys", tablefmt="psql"))
    return (samples,)


@app.cell
def _(N_SAMPLES, SKIPROWS, args, file, pd, tabulate):
    carnitine = pd.read_excel(
        file,
        sheet_name=args.sheet_name,
        skiprows=SKIPROWS,
        index_col="Data#",
        nrows=N_SAMPLES,
        usecols="I:O",
    )
    carnitine = carnitine.drop(
        ["Data Filename", "Ret. Time", "Area", "Area/whole sample"], axis=1
    )
    if args.verbose:
        print("Carnitine standard:")
        print(tabulate(carnitine, headers="keys", tablefmt="psql"))
    return


@app.cell(hide_code=True)
def _():
    column_ranges = args.column_ranges
    return (column_ranges,)


@app.cell(hide_code=True)
def _(pd):
    def read_single_cell(file, sheet, col, row):
        return pd.read_excel(
            file,
            sheet_name=sheet,
            header=row - 1,
            nrows=1,
            index_col=None,
            usecols=col,
        ).columns.values[0]

    return (read_single_cell,)


@app.cell
def _(ROW, args, column_ranges, file, pprint, read_single_cell):
    metabolite_names = [
        read_single_cell(file, args.sheet_name, k, ROW)
        for k in [j[0] for j in [i.split(":") for i in column_ranges]]
    ]
    if args.verbose:
        print("Metabolite names:")
        pprint.pprint(metabolite_names)
    return (metabolite_names,)


@app.cell
def _(
    N_SAMPLES,
    SHEETS_HEADERS,
    SKIPROWS,
    args,
    column_ranges,
    file,
    pd,
    tabulate,
):
    sheets = [
        pd.read_excel(
            file,
            sheet_name=args.sheet_name,
            skiprows=SKIPROWS,
            nrows=N_SAMPLES + 1,
            index_col="Data#",
            names=SHEETS_HEADERS,
            usecols=rng,
        )
        for rng in column_ranges
    ]
    if args.verbose:
        print("Sheets:")
        print(tabulate(sheets, headers="keys", tablefmt="psql"))
    return (sheets,)


@app.cell
def _(metabolite_names, sheets):
    metabolites_dict = dict(
        zip(
            metabolite_names,  # names as keys
            [
                sheet.drop(
                    [
                        "Data Filename",
                        "Ret. Time",
                        "Peak area undiluted",
                        "Total volume of the sample",
                    ],
                    axis=1,
                )
                for sheet in sheets
            ],  # dfs as values
        )
    )
    # metabolites_dict  # dict with Asparagine: df.columns=['Peak area per total sample', 'Factor IT',       'Peak area per total sample normalized to IT',       'Peak area per total sample normalized to Std (ng)',       'Normalized to OD*Vol (ng*mL-1*OD750 nm)']
    return (metabolites_dict,)


@app.cell
def _(metabolites_dict):
    renamed_and_only_normalized_col = [
        df.drop(
            [
                "Peak area per total sample",
                "Factor IT",
                "Peak area per total sample normalized to IT",
                "Peak area per total sample normalized to Std (ng)",
            ],
            axis=1,
        ).rename(
            columns={
                "Normalized to OD*Vol (ng*mL-1*OD750 nm)": f"{metabolite} / ng*mL-1*OD750 nm"
            }
        )
        for metabolite, df in metabolites_dict.items()
    ]
    # renamed_and_only_normalized_col
    return (renamed_and_only_normalized_col,)


@app.cell
def _(args, renamed_and_only_normalized_col, samples, tabulate):
    metabolites = samples.join(renamed_and_only_normalized_col)
    if args.verbose:
        print("Joined:")
        print(tabulate(metabolites, headers="keys", tablefmt="psql"))
    return (metabolites,)


@app.cell
def _(args, metabolite_names, metabolites, mets, tabulate):
    corr_matrix = (
        "corr_matrix.csv"
        if not args.correlation_matrix
        else args.correlation_matrix
    )
    correlation_matrix = (
        metabolites[mets]
        .rename(columns=dict(zip(mets, metabolite_names)))
        .corr()
        .round(2)
    )
    if args.verbose:
        print("Correlations:")
        print(tabulate(correlation_matrix, headers="keys", tablefmt="psql"))
    correlation_matrix.to_csv(corr_matrix)
    return


@app.cell
def _(args, metabolite_names, metabolites, mets, plt, sns):
    corr_heatmap = (
        "corr_heatmap.svg"
        if not args.correlation_heatmap
        else args.correlation_heatmap
    )
    sns.heatmap(
        metabolites[mets].rename(columns=dict(zip(mets, metabolite_names))).corr(),
        cmap=sns.diverging_palette(230, 20, as_cmap=True),
    )
    plt.savefig(corr_heatmap, bbox_inches="tight", pad_inches=0.3)
    return


@app.cell
def _(args, metabolites):
    out_file = "test/out.xlsx" if not args.output else args.output
    metabolites.to_excel(out_file)
    return


@app.cell(hide_code=True)
def _(metabolites):
    mets = metabolites.drop(
        ["name", "strain", "N-stress / h", "replicate", "amount / OD"], axis=1
    ).columns.values.tolist()
    return (mets,)


@app.cell
def _(args, metabolite_names, metabolites, mets, plt, sns):
    plot = "conc_vs_metabolites.svg" if not args.plot else args.plot
    ax = sns.boxplot(
        metabolites[mets].rename(columns=dict(zip(mets, metabolite_names)))
    )
    ax.set_xticklabels(ax.get_xticklabels(), rotation=90)
    ax.set_yscale("log")
    ax.set_ylabel("log(Conc / ng*mL-1*OD750 nm)")
    plt.savefig(plot, bbox_inches="tight", pad_inches=0.3)
    return


@app.cell
def _(Path, args, metabolite_names, metabolites, mets, plt, re, sns):
    if args.plot_per:
        stem = Path(args.plot).stem
        suffix = Path(args.plot).suffix
        parent = Path(args.plot).parent
        for col in args.plot_per:
            for val in sorted(metabolites[col].unique()):
                _filtered = metabolites[metabolites[col] == val]
                _melted = (
                    _filtered[mets]
                    .rename(columns=dict(zip(mets, metabolite_names)))
                    .melt(var_name="metabolite", value_name="concentration")
                )
                _safe_val = re.sub(r"[^\w\-.]", "_", str(val))
                _out_path = str(parent / f"{stem}_{_safe_val}{suffix}")
                _fig, _ax = plt.subplots(figsize=(max(8, len(mets) * 0.5), 6))
                sns.boxplot(data=_melted, x="metabolite", y="concentration", ax=_ax, fill=False)
                sns.swarmplot(
                    data=_melted, x="metabolite", y="concentration",
                    ax=_ax, color="black", size=3,
                )
                _ax.set_xticklabels(_ax.get_xticklabels(), rotation=90)
                _ax.set_yscale("log")
                _ax.set_ylabel("log(Conc / ng*mL-1*OD750 nm)")
                _ax.set_title(f"{col} = {val}")
                plt.savefig(_out_path, bbox_inches="tight", pad_inches=0.3)
                plt.close(_fig)
    return


if __name__ == "__main__":
    app.run()
