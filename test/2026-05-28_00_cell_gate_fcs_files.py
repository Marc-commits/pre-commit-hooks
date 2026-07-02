import marimo

__generated_with = "0.23.6"
app = marimo.App(width="full", auto_download=["html"])


@app.cell
def _():
    import sys
    import warnings
    from pathlib import Path

    warnings.filterwarnings("ignore")
    return Path, sys


@app.cell
def _():
    import marimo as mo  # for markdown

    return (mo,)


@app.cell
def _(Path, sys):
    # Add notebooks directory to path for _config imports
    if "__file__" in dir():
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    else:
        sys.path.insert(0, str(Path.cwd().parent))
    return


@app.cell
def _():
    import numpy as np
    import pandas as pd
    import anndata as ad
    import matplotlib.pyplot as plt
    import seaborn as sns

    return (np,)


@app.cell
def _():
    # BiSCOT imports — public API
    from biscot import (
        # Core
        UniModalData,
        # Configuration
        GMMConfig,
        OTConfig,
        GateDefinition,
        # Preprocessing
        PreprocessingConfig,
        preprocess_flow_data,
        # Data loading
        load_fcs_batch,
        # Analysis
        analyze_biscot,
        AnalysisResults,
        # Similarity
        similarity_analysis,
        compute_embedding,
        # Temporal
        temporal_analysis,
        # Visualization (exported in __init__)
        plot_clusters,
        plot_transport_plan,
        plot_similarity_matrix,
        plot_temporal_tracking,
        plot_analysis_summary,
        plot_fcm_gates,
    )

    return PreprocessingConfig, load_fcs_batch


@app.cell
def _():
    # Visualization functions available via biscot.visualization
    from biscot.visualization import (
        plot_scatter,
        plot_density,
        plot_transport,
        plot_gmm_ellipses,
        plot_decision_boundary_contours,
        plot_gate_preservation,
        plot_tessellation_lines,
    )

    return


@app.cell
def _():
    from biscot.tessellation import plot_tessellation
    from biscot.visualization_simple import BiscotPlotter, plot
    from biscot.export import (
        export_results,
        list_biscot_results,
        summarize_biscot_analysis,
    )

    return


@app.cell
def _():
    print(f"biscot version: {__import__('biscot').__version__}")
    return


@app.cell
def _():
    import matplotlib.path as mpath
    import matplotlib.patches as mpatches
    from typing import Sequence

    return


@app.cell
def _():
    wt_cell_gate_raw = [
        (66.9, 9424),
        (6943, 12.6),
    ]  # (SSC_x_min, SSC_x_max, SSC_y_max, SSC_y_min
    nsiR1_cell_gate_raw = wt_cell_gate_raw
    return


@app.cell
def _():
    wt_cell_gate = [(66.9, 12.6), (9424, 12.6), (9424, 6943), (66.9, 6943)]
    nsiR1_cell_gate = wt_cell_gate
    return (wt_cell_gate,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Loading data
    """)
    return


@app.cell
def _():
    file_paths_dict_wt = {
        "wt_0": "data/Marc_Medina_data_time_course_251015/time-course experiment/wt_0h_1.fcs",
        "wt_10": "data/Marc_Medina_data_time_course_251015/time-course experiment/wt_10h_1.fcs",
        "wt_24": "data/Marc_Medina_data_time_course_251015/time-course experiment/wt_24h_1.fcs",
        "wt_48": "data/Marc_Medina_data_time_course_251015/time-course experiment/wt_48h_1.fcs",
        "wt_72": "data/Marc_Medina_data_time_course_251015/time-course experiment/wt_72h_1.fcs",
    }
    file_paths_dict_nsiR1 = {
        "nsiR1_0": "data/Marc_Medina_data_time_course_251015/time-course experiment/nsiR1_0h_1.fcs",
        "nsiR1_10": "data/Marc_Medina_data_time_course_251015/time-course experiment/nsiR1_10h_1.fcs",
        "nsiR1_24": "data/Marc_Medina_data_time_course_251015/time-course experiment/nsiR1_24h_1.fcs",
        "nsiR1_48": "data/Marc_Medina_data_time_course_251015/time-course experiment/nsiR1_48h_1.fcs",
        "nsiR1_72": "data/Marc_Medina_data_time_course_251015/time-course experiment/nsiR1_72h_1.fcs",
    }
    return file_paths_dict_nsiR1, file_paths_dict_wt


@app.cell
def _():
    time_labels_wt = {
        "wt_0": "0h",
        "wt_10": "10h",
        "wt_24": "24h",
        "wt_48": "48h",
        "wt_72": "72h",
    }
    time_labels_nsiR1 = {
        "nsiR1_0": "0h",
        "nsiR1_10": "10h",
        "nsiR1_24": "24h",
        "nsiR1_48": "48h",
        "nsiR1_72": "72h",
    }
    return time_labels_nsiR1, time_labels_wt


@app.cell
def _(
    Path,
    file_paths_dict_nsiR1,
    file_paths_dict_wt,
    time_labels_nsiR1,
    time_labels_wt,
):
    print(f"Files to load: {len(file_paths_dict_wt)}")
    for fid, fp in file_paths_dict_wt.items():
        print(f"  {fid} ({time_labels_wt.get(fid, fid)}): {Path(fp).name}")
    print(f"Files to load: {len(file_paths_dict_nsiR1)}")
    for fid, fp in file_paths_dict_nsiR1.items():
        print(f"  {fid} ({time_labels_nsiR1.get(fid, fid)}): {Path(fp).name}")
    return


@app.cell
def _():
    channels_wt = [
        "FSC [488]",
        "530/40 [488]",
        "730/45 [640]",
        "SSC [488]",
    ]
    channels_nsiR1 = [
        "FSC [488]",
        "530/40 [488]",
        "730/45 [640]",
        "SSC [488]",
    ]
    return (channels_wt,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## loading without log-transform
    """)
    return


@app.cell
def _(np, wt_cell_gate):
    np.array(wt_cell_gate)
    return


@app.cell
def _(
    PreprocessingConfig,
    channels_wt,
    file_paths_dict_wt,
    load_fcs_batch,
    np,
    wt_cell_gate,
):
    # Load all FCS files in one call
    adatas_wt, summary_df_wt = load_fcs_batch(
        file_paths=file_paths_dict_wt,
        channels=channels_wt,
        preprocessing_config=PreprocessingConfig(
            channels_to_select=channels_wt,
            apply_log_transform=True,
            log_after_filtering=True,
            polygon_coords=np.array(wt_cell_gate),
            polygon_channels=["FSC [488]", "SSC [488]"],
            # log_offset=1,
            duplicate_handling="smart",
        ),
        verbose=True,
    )

    print(f"\nLoaded {len(adatas_wt)} datasets")
    print(summary_df_wt)
    return (adatas_wt,)


@app.cell
def _(adatas_wt, np, wt_cell_gate):
    import matplotlib.pyplot as _plt

    _sample_key = "wt_0"
    _adata = adatas_wt[_sample_key]
    _ch_x, _ch_y = "FSC [488]", "SSC [488]"
    _xi = list(_adata.var_names).index(_ch_x)
    _yi = list(_adata.var_names).index(_ch_y)

    _X = np.asarray(_adata.X)
    _xs = _X[:, _xi]
    _ys = _X[:, _yi]

    # gate vertices transformed to log10(x + 1) space to match data
    _verts = np.log10(np.array(wt_cell_gate) + 1.0)
    _closed = np.vstack([_verts, _verts[0]])

    _fig, _ax = _plt.subplots(figsize=(5, 5))
    _ax.scatter(_xs, _ys, s=1, alpha=0.2, rasterized=True)
    _ax.plot(_closed[:, 0], _closed[:, 1], "r-", linewidth=1.5, label="gate")
    _ax.set_xlabel(f"log₁₀ {_ch_x}")
    _ax.set_ylabel(f"log₁₀ {_ch_y}")
    _ax.set_title(f"{_sample_key} — gate QC")
    _ax.legend(markerscale=5)
    _plt.tight_layout()
    _fig


@app.cell
def _(adatas_wt, np):
    # check scale of data
    print(f"Max: {np.max(adatas_wt['wt_0'].X)}")
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Inspect
    """)
    return


@app.cell
def _(adatas_wt):
    adatas_wt
    return


@app.cell
def _(adatas_wt):
    adatas_wt["wt_0"]
    return


@app.cell
def _(adatas_wt):
    adatas_wt["wt_0"].var_names
    return


if __name__ == "__main__":
    app.run()
