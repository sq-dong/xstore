#!/usr/bin/env python3
"""Emit only paper-aligned figures (axes match OSDI'20 Fig.12a / 15d–e / 16a)."""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Distinct, print-friendly colors (avoid default all-black).
C_XSTORE = "#2166ac"  # steel blue
C_INLINE = "#1b9e77"  # teal
C_INDIRECT = "#d95f02"  # orange


def _style():
    plt.rcParams.update(
        {
            "font.size": 11,
            "axes.labelsize": 12,
            "axes.titlesize": 12,
            "legend.fontsize": 10,
            "figure.dpi": 150,
            "savefig.dpi": 150,
            "axes.grid": True,
            "grid.linestyle": "--",
            "grid.alpha": 0.35,
        }
    )


def save(fig: plt.Figure, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out.with_suffix(".png"))
    fig.savefig(out.with_suffix(".pdf"))
    plt.close(fig)
    print(f"wrote {out.with_suffix('.png')}")


def plot_fig12a(csv_path: Path, out_dir: Path) -> None:
    """Fig.12a: throughput–latency (X=Throughput, Y=Median Latency)."""
    xs, ys = [], []
    with csv_path.open() as f:
        for row in csv.DictReader(f):
            th = float(row["agg_thpt_rps"]) / 1e6
            lat = float(row["lat_us_median"])
            if not math.isfinite(th) or not math.isfinite(lat) or th <= 0 or lat <= 0:
                continue
            xs.append(th)
            ys.append(lat)
    if len(xs) < 2:
        print(f"skip Fig.12a: need ≥2 valid points in {csv_path}")
        return
    # sort by throughput for a proper curve
    pairs = sorted(zip(xs, ys))
    xs, ys = [p[0] for p in pairs], [p[1] for p in pairs]

    _style()
    fig, ax = plt.subplots(figsize=(5.2, 4.0))
    ax.plot(xs, ys, "o-", color=C_XSTORE, lw=1.8, markersize=6, label="XStore")
    ax.set_xlabel("Throughput (M reqs/s)")
    ax.set_ylabel("Median Latency (µs)")
    ax.set_title("Fig. 12a (approx.): YCSB-C style, Uniform")
    # Y from 0; top follows data so a real latency rise is visible.
    ax.set_ylim(bottom=0, top=max(12.0, max(ys) * 1.15))
    ax.legend(frameon=False)
    save(fig, out_dir / "fig12a_thpt_latency")


def plot_fig15(
    csv_path: Path,
    out_dir: Path,
    *,
    title_d: str = "Fig. 15d (approx.): YCSB-C style",
    title_e: str = "Fig. 15e (approx.): low-load median latency",
    out_d: str = "fig15d_thpt_vs_nmodels",
    out_e: str = "fig15e_lat_vs_nmodels",
) -> None:
    """Fig.15d/e: X=Number of models; Y=peak thpt / low-load median latency."""
    models, thpts, lats = [], [], []
    with csv_path.open() as f:
        for row in csv.DictReader(f):
            # New schema: peak_thpt_rps + low_lat_us; fall back to legacy columns.
            if "peak_thpt_rps" in row:
                raw_th = (row.get("peak_thpt_rps") or "").strip()
                raw_lat = (row.get("low_lat_us") or "").strip()
                if not raw_th or raw_th.lower() == "nan":
                    continue
                th = float(raw_th) / 1e6
                lat = float(raw_lat) if raw_lat and raw_lat.lower() != "nan" else float("nan")
            else:
                th = float(row["agg_thpt_rps"]) / 1e6
                lat = float(row["lat_us_median"])
            if not math.isfinite(th) or th <= 0:
                continue

            models.append(float(row["nmodels"]))
            thpts.append(th)
            lats.append(lat if math.isfinite(lat) and lat > 0 else float("nan"))
    if not models:
        print(f"skip Fig.15: empty {csv_path}")
        return
    order = sorted(range(len(models)), key=lambda i: models[i])
    models = [models[i] for i in order]
    thpts = [thpts[i] for i in order]
    lats = [lats[i] for i in order]

    _style()
    fig, ax = plt.subplots(figsize=(5.2, 4.0))
    ax.plot(models, thpts, "s-", color=C_XSTORE, lw=1.8, markersize=6, label="XStore")
    ax.set_xlabel("Number of models")
    ax.set_ylabel("Peak Throughput (M reqs/s)")
    ax.set_title(title_d)
    ax.set_ylim(bottom=0, top=max(20.0, max(thpts) * 1.15))
    ax.legend(frameon=False)
    save(fig, out_dir / out_d)

    valid = [(m, la) for m, la in zip(models, lats) if math.isfinite(la)]
    if valid:
        _style()
        fig, ax = plt.subplots(figsize=(5.2, 4.0))
        ax.plot(
            [v[0] for v in valid],
            [v[1] for v in valid],
            "s-",
            color=C_XSTORE,
            lw=1.8,
            markersize=6,
            label="XStore",
        )
        ax.set_xlabel("Number of models")
        ax.set_ylabel("Median Latency (µs)")
        ax.set_title(title_e)
        ax.set_ylim(bottom=0, top=max(20.0, max(v[1] for v in valid) * 1.2))
        ax.legend(frameon=False)
        save(fig, out_dir / out_e)


def plot_fig16a(csv_path: Path, out_dir: Path) -> None:
    """Fig.16a: X=Value size (Bytes); Y=Peak thpt; Inline vs Indirect."""
    inline, indirect = {}, {}
    with csv_path.open() as f:
        for row in csv.DictReader(f):
            vlen = row["vlen"].lower() in ("1", "true", "yes")
            length = int(float(row["len"]))
            th = float(row["agg_thpt_rps"]) / 1e6
            if not math.isfinite(th) or th <= 0:
                continue
            (indirect if vlen else inline)[length] = th
    if not inline and not indirect:
        print(f"skip Fig.16a: empty {csv_path}")
        return

    _style()
    fig, ax = plt.subplots(figsize=(5.2, 4.0))
    if inline:
        xs = sorted(inline)
        ax.plot(xs, [inline[x] for x in xs], "o-", color=C_INLINE, lw=1.8, label="Inline value")
    if indirect:
        xs = sorted(indirect)
        ax.plot(
            xs,
            [indirect[x] for x in xs],
            "s--",
            color=C_INDIRECT,
            lw=1.8,
            markersize=6,
            label="Indirect value",
        )
    ax.set_xscale("log", base=2)
    ax.set_xlabel("Value size (Bytes)")
    ax.set_ylabel("Peak Throughput (M reqs/s)")
    ax.set_title("Fig. 16a (approx.): inline vs indirect value")
    ymax = max(list(inline.values()) + list(indirect.values()) + [0.0])
    ax.set_ylim(bottom=0, top=max(40.0, ymax * 1.15))
    ax.legend(frameon=False)
    save(fig, out_dir / "fig16a_thpt_vs_vlen")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default=str(Path(__file__).resolve().parent / "out"))
    ap.add_argument(
        "--fig15-dist",
        action="store_true",
        help="plot fig15_dist_data.csv (OSM / file-key path) only",
    )
    args = ap.parse_args()
    d = Path(args.data_dir)

    if args.fig15_dist:
        f15d = d / "fig15_dist_data.csv"
        if f15d.is_file():
            plot_fig15(
                f15d,
                d,
                title_d="Fig. 15d (approx.): OSM keys, LR",
                title_e="Fig. 15e (approx.): OSM low-load latency",
                out_d="fig15d_dist_thpt_vs_nmodels",
                out_e="fig15e_dist_lat_vs_nmodels",
            )
        else:
            print(f"missing {f15d}")
        return

    f12 = d / "fig12_data.csv"
    if f12.is_file():
        plot_fig12a(f12, d)
    else:
        print(f"missing {f12}")

    f15 = d / "fig15_data.csv"
    if f15.is_file():
        plot_fig15(f15, d)

    f15d = d / "fig15_dist_data.csv"
    if f15d.is_file():
        plot_fig15(
            f15d,
            d,
            title_d="Fig. 15d (approx.): OSM keys, LR",
            title_e="Fig. 15e (approx.): OSM low-load latency",
            out_d="fig15d_dist_thpt_vs_nmodels",
            out_e="fig15e_dist_lat_vs_nmodels",
        )

    f16 = d / "fig16_data.csv"
    if f16.is_file():
        plot_fig16a(f16, d)


if __name__ == "__main__":
    main()
