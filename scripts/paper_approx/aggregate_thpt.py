#!/usr/bin/env python3
"""Aggregate per-client *.xstorelog (+ optional lat) into mean throughput."""
from __future__ import annotations

import argparse
import re
from pathlib import Path


def read_samples(path: Path) -> tuple[list[float], list[float]]:
    thpts: list[float] = []
    lats: list[float] = []
    for line in path.read_text().splitlines():
        s = line.strip().replace(",", "")
        if not s:
            continue
        parts = s.split()
        thpts.append(float(parts[0]))
        if len(parts) >= 2:
            lats.append(float(parts[1]))
    return thpts, lats


def mean_trimmed(vals: list[float], head: int, tail: int) -> float:
    if not vals:
        return float("nan")
    if len(vals) > head + tail:
        vals = vals[head : len(vals) - tail] if tail else vals[head:]
    return sum(vals) / len(vals)


def median(vals: list[float]) -> float:
    if not vals:
        return float("nan")
    xs = sorted(vals)
    mid = len(xs) // 2
    if len(xs) % 2:
        return xs[mid]
    return 0.5 * (xs[mid - 1] + xs[mid])


def parse_lat_from_stdout(log_path: Path) -> list[float]:
    if not log_path.is_file() or log_path.stat().st_size == 0:
        return []
    pat = re.compile(r"lat:\s*([0-9.]+)\s*us")
    out: list[float] = []
    for line in log_path.read_text(errors="ignore").splitlines():
        m = pat.search(line)
        if m:
            v = float(m.group(1))
            if v > 0:  # ignore legacy always-zero samples
                out.append(v)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--trim-head", type=int, default=5)
    ap.add_argument("--trim-tail", type=int, default=5)
    ap.add_argument("--expect", type=int, default=None, help="expected #clients")
    ap.add_argument(
        "--csv-row",
        default=None,
        help="label for first CSV column (nclients or load_id)",
    )
    args = ap.parse_args()
    d = Path(args.dir)

    logs = sorted(
        d.glob("*.xstorelog"),
        key=lambda p: int(p.stem) if p.stem.isdigit() else p.stem,
    )
    if not logs:
        raise SystemExit(f"no *.xstorelog under {d}")

    per_thpt: list[float] = []
    per_lat: list[float] = []
    for lg in logs:
        thpts, lats = read_samples(lg)
        per_thpt.append(mean_trimmed(thpts, args.trim_head, args.trim_tail))
        if lats:
            per_lat.append(median(lats[args.trim_head : len(lats) - args.trim_tail or None]))
        else:
            stdout_lats = parse_lat_from_stdout(d / f"client_{lg.stem}.log")
            if stdout_lats:
                per_lat.append(median(stdout_lats[args.trim_head :]))

    agg = sum(per_thpt)
    avg = agg / len(per_thpt)
    lat_med = median(per_lat) if per_lat else float("nan")
    n_ok = len(per_thpt)
    n_exp = args.expect if args.expect is not None else n_ok

    if args.csv_row is not None:
        # label,agg_thpt_rps,per_client_avg_rps,n_ok,n_expect,lat_us_median
        print(
            f"{args.csv_row},{agg:.6f},{avg:.6f},{n_ok},{n_exp},{lat_med:.6f}"
        )
    else:
        print(f"n_ok={n_ok}/{n_exp}")
        for i, t in enumerate(per_thpt, 1):
            print(f"  log[{i}] mean_thpt={t:.0f} rps")
        print(f"aggregate_thpt={agg:.0f} rps ({agg/1e6:.3f} Mrps)")
        if per_lat:
            print(f"lat_median_us={lat_med:.3f}")


if __name__ == "__main__":
    main()
