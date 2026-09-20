#!/usr/bin/env python3
"""gen-peak-throughput-bar.py — ENO vs Godel peak throughput grouped bar chart.

Renders a single grouped bar figure covering the seven scenarios discussed
in section 6.4 of the thesis (see the "若以峰值吞吐衡量" paragraph):

    scale/workload/inst        expected numbers (paper line 165)
    s2/w3         inst1        ENO 982.1 vs Godel 866.0   (+13.4%)
    s3/w3         inst1        ENO 858.2 vs Godel 752.8   (+14.0%)
    s3/w5         inst3        ENO lower (-10.4%)
    s3/w6         inst3        ENO lower (-2.0%)
    s4/w3         inst3        ENO lower (-0.3%)
    s4/w6         inst3        ENO 893.2 vs Godel 531.6   (+68.1%)
    s4/w7         inst3        ENO 574.1 vs Godel 499.7   (+14.9%)

The scalar per (group, scenario) follows the section 6.3 convention:
average-over-runs series in avg/scheduling_peak_throughput.json, trim head
and tail two samples, take the median of what remains.
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

# (label_for_x_axis, path_suffix under results/{group}) — all 16 compare
# scenarios listed under results/compare/, in natural (scale, workload, inst)
# order. Scenarios with no valid peak-throughput samples after 6.3 trim
# are rendered as zero-height bars with "n/a" markers so the reader can
# see the coverage matrix at a glance.
SCENARIOS = [
    ("s1/w1\ninst1",     "s1/w1/inst1"),
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

GROUPS = [
    ("a", "ENO",   "#2196F3"),
    ("b", "Godel", "#FF5722"),
]

METRIC = "scheduling_peak_throughput"


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


def load_peak_throughput(group: str, path_suffix: str) -> float | None:
    """Median-trim of avg/scheduling_peak_throughput.json.

    Fallback path is intentionally omitted: peak throughput is time-series-
    only, and section 6.3 says <1 sample after trim = no data.
    """
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

    # Substitute None with 0 for plotting, keep the None indicator for label rendering.
    eno_plot   = [v if v is not None else 0.0 for v in eno]
    godel_plot = [v if v is not None else 0.0 for v in godel]

    fig, ax = plt.subplots(figsize=(15, 5.6))
    bars_a = ax.bar(x - width / 2, eno_plot,   width, label="ENO (a)",   color="#2196F3", edgecolor="black", linewidth=0.5)
    bars_b = ax.bar(x + width / 2, godel_plot, width, label="Godel (b)", color="#FF5722", edgecolor="black", linewidth=0.5)

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("Peak throughput (pods/s)", fontsize=12)
    ax.set_title(
        f"Peak scheduling throughput: ENO vs Godel across {len(labels)} scenarios "
        "(median-trim aggregation, n=3)",
        fontsize=12,
    )
    ax.grid(True, axis="y", alpha=0.3)
    ax.legend(loc="upper left", fontsize=10)

    valid_vals = [v for v in eno_plot + godel_plot if v > 0]
    ymax = max(valid_vals) if valid_vals else 1.0
    ax.set_ylim(0, ymax * 1.22)

    for i, (bar_a, bar_b, a, b) in enumerate(zip(bars_a, bars_b, eno, godel)):
        # Individual bar height labels (or "n/a")
        for bar, val in ((bar_a, a), (bar_b, b)):
            if val is None:
                ax.text(bar.get_x() + bar.get_width() / 2, ymax * 0.02,
                        "n/a", ha="center", va="bottom", fontsize=8,
                        color="#666666", rotation=90)
            else:
                ax.text(bar.get_x() + bar.get_width() / 2, val,
                        f"{val:.0f}", ha="center", va="bottom", fontsize=8)

        # Relative delta only when both values are available
        if a is not None and b is not None and b > 0:
            delta = (a - b) / b * 100
            sign = "+" if delta >= 0 else ""
            top = max(a, b)
            ax.text(x[i], top + ymax * 0.06, f"{sign}{delta:.1f}%",
                    ha="center", va="bottom", fontsize=8,
                    color=("#0b5394" if delta >= 0 else "#7f2704"))

    plt.tight_layout()
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    plot_labels: list[str] = []
    eno_vals: list[float | None] = []
    god_vals: list[float | None] = []

    print(f"{'scenario':20s}  {'ENO':>10s}  {'Godel':>10s}  {'delta':>10s}")
    for label, suffix in SCENARIOS:
        a = load_peak_throughput("a", suffix)
        b = load_peak_throughput("b", suffix)
        flat = label.replace("\n", " ")
        a_str = "n/a" if a is None else f"{a:.1f}"
        b_str = "n/a" if b is None else f"{b:.1f}"
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
    out = FIGURES / "fig6-19-peak-throughput-a-vs-b-all.png"
    render(plot_labels, eno_vals, god_vals, out)
    print(f"\nSaved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
