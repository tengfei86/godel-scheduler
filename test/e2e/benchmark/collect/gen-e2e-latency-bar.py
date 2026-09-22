#!/usr/bin/env python3
"""gen-e2e-latency-bar.py — ENO vs Godel Pod E2E latency P99 grouped bar chart.

Renders a single grouped bar figure covering 15 of the 16 compare scenarios
(s1/w1 excluded — its single-run duration is shorter than the trim window
and produces no valid sample under the section 6.3 median-trim convention).

The scalar per (group, scenario) follows the section 6.3 convention:
median-aggregated series in avg/pod_e2e_latency_p99.json, trim head and
tail two samples, take the median of what remains.

Y axis uses log scale to accommodate the ~1000x range across scenarios
(from ~0.05 s in low-load to ~48 s in overloaded w4).
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

_HERE = Path(__file__).resolve()
RESULTS = _HERE.parent.parent / "results"
FIGURES = _HERE.parents[4] / "docs" / "thesis" / "figures"

SCENARIOS = [
    ("s2/w2\ninst1",     "s2/w2/inst1"),
    ("s2/w3\ninst1",     "s2/w3/inst1"),
    ("s3/w2\ninst1",     "s3/w2/inst1"),
    ("s3/w3\ninst1",     "s3/w3/inst1"),
    ("s3/w6\ninst1",     "s3/w6/inst1"),
    ("s3/w3\ninst3",     "s3/w3/inst3"),
    ("s3/w4\ninst3",     "s3/w4/inst3"),
    ("s3/w5\ninst3",     "s3/w5/inst3"),
    ("s3/w6\ninst3",     "s3/w6/inst3"),
    ("s3/w7\ninst3",     "s3/w7/inst3"),
    ("s4/w3\ninst3",     "s4/w3/inst3"),
    ("s4/w4\ninst3",     "s4/w4/inst3"),
    ("s4/w5\ninst3",     "s4/w5/inst3"),
    ("s4/w6\ninst3",     "s4/w6/inst3"),
    ("s4/w7\ninst3",     "s4/w7/inst3"),
]

METRIC = "pod_e2e_latency_p99"


def _load_series_values(fp: Path) -> list[float]:
    try:
        payload = json.loads(fp.read_text())
    except (json.JSONDecodeError, OSError):
        return []
    result = payload.get("data", {}).get("result", [])
    if not result:
        return []
    values = result[0].get("values", [])
    out: list[float] = []
    for _, v in values:
        try:
            out.append(float(v))
        except (ValueError, TypeError):
            out.append(float("nan"))
    return out


def load_e2e_latency(group: str, path_suffix: str) -> float | None:
    fp = RESULTS / group / path_suffix / "avg" / f"{METRIC}.json"
    if not fp.exists():
        return None
    vals = _load_series_values(fp)
    if len(vals) < 5:
        return None
    trimmed = [v for v in vals[2:-2] if v == v]
    if not trimmed:
        return None
    return statistics.median(trimmed)


def render(labels: list[str], eno: list[float | None], godel: list[float | None],
           out_path: Path) -> None:
    x = np.arange(len(labels))
    width = 0.38

    # Log y needs strictly positive values; treat missing as tiny sentinel
    # only to render a visible "no data" marker at the bottom.
    sentinel = 1e-3
    eno_plot   = [v if v is not None and v > 0 else sentinel for v in eno]
    godel_plot = [v if v is not None and v > 0 else sentinel for v in godel]

    fig, ax = plt.subplots(figsize=(15, 5.6))
    bars_a = ax.bar(x - width / 2, eno_plot,   width, label="ENO (a)",   color="#2196F3", edgecolor="black", linewidth=0.5)
    bars_b = ax.bar(x + width / 2, godel_plot, width, label="Godel (b)", color="#FF5722", edgecolor="black", linewidth=0.5)

    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("Pod E2E latency P99 (seconds, log scale)", fontsize=12)
    ax.set_title(
        f"Pod E2E latency P99: ENO vs Godel across {len(labels)} scenarios "
        "(median-trim aggregation, n=3)",
        fontsize=12,
    )
    ax.grid(True, axis="y", which="both", alpha=0.3)
    ax.legend(loc="upper left", fontsize=10)

    # Fixed y range covering all observed values (~0.05 to ~50 s)
    ax.set_ylim(0.02, 200)

    for i, (bar_a, bar_b, a, b) in enumerate(zip(bars_a, bars_b, eno, godel)):
        for bar, val in ((bar_a, a), (bar_b, b)):
            if val is None:
                ax.text(bar.get_x() + bar.get_width() / 2, 0.03,
                        "n/a", ha="center", va="bottom", fontsize=8,
                        color="#666666", rotation=90)
            else:
                fmt = f"{val:.2f}" if val < 1 else f"{val:.1f}"
                ax.text(bar.get_x() + bar.get_width() / 2, val,
                        fmt, ha="center", va="bottom", fontsize=8)

        if a is not None and b is not None and b > 0:
            delta = (a - b) / b * 100
            sign = "+" if delta >= 0 else ""
            top = max(a, b)
            # In log scale, offset by a multiplicative factor rather than additive
            ax.text(x[i], top * 1.5, f"{sign}{delta:.1f}%",
                    ha="center", va="bottom", fontsize=8,
                    color=("#7f2704" if delta >= 0 else "#0b5394"))

    plt.tight_layout()
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    plot_labels: list[str] = []
    eno_vals: list[float | None] = []
    god_vals: list[float | None] = []

    print(f"{'scenario':20s}  {'ENO':>10s}  {'Godel':>10s}  {'delta':>10s}")
    for label, suffix in SCENARIOS:
        a = load_e2e_latency("a", suffix)
        b = load_e2e_latency("b", suffix)
        flat = label.replace("\n", " ")
        a_str = "n/a" if a is None else f"{a:.3f}"
        b_str = "n/a" if b is None else f"{b:.3f}"
        if a is not None and b is not None and b > 0:
            delta = (a - b) / b * 100
            d_str = f"{delta:+.1f}%"
        else:
            d_str = "n/a"
        print(f"{flat:20s}  {a_str:>10s}  {b_str:>10s}  {d_str:>10s}")
        plot_labels.append(label)
        eno_vals.append(a)
        god_vals.append(b)

    FIGURES.mkdir(parents=True, exist_ok=True)
    out = FIGURES / "fig6-8-e2e-latency-p99-all.png"
    render(plot_labels, eno_vals, god_vals, out)
    print(f"\nSaved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
