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

# (label_for_x_axis, path_suffix under results/{group})
SCENARIOS = [
    ("s2/w3\ninst1",     "s2/w3/inst1"),
    ("s3/w3\ninst1",     "s3/w3/inst1"),
    ("s3/w5\ninst3",     "s3/w5/inst3"),
    ("s3/w6\ninst3",     "s3/w6/inst3"),
    ("s4/w3\ninst3",     "s4/w3/inst3"),
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


def render(labels: list[str], eno: list[float], godel: list[float], out_path: Path) -> None:
    x = np.arange(len(labels))
    width = 0.38

    fig, ax = plt.subplots(figsize=(11, 5.2))
    bars_a = ax.bar(x - width / 2, eno,   width, label="ENO (a)",   color="#2196F3", edgecolor="black", linewidth=0.5)
    bars_b = ax.bar(x + width / 2, godel, width, label="Godel (b)", color="#FF5722", edgecolor="black", linewidth=0.5)

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=10)
    ax.set_ylabel("Peak throughput (pods/s)", fontsize=12)
    ax.set_title("Peak scheduling throughput: ENO vs Godel across 7 scenarios (median-trim aggregation, n=3)", fontsize=12)
    ax.grid(True, axis="y", alpha=0.3)
    ax.legend(loc="upper left", fontsize=10)

    ymax = max(max(eno), max(godel))
    ax.set_ylim(0, ymax * 1.22)

    for bars in (bars_a, bars_b):
        for bar in bars:
            h = bar.get_height()
            ax.text(bar.get_x() + bar.get_width() / 2, h,
                    f"{h:.0f}", ha="center", va="bottom", fontsize=9)

    # Annotate the relative difference on top of each pair.
    for i, (a, b) in enumerate(zip(eno, godel)):
        if b > 0:
            delta = (a - b) / b * 100
            sign = "+" if delta >= 0 else ""
            ax.text(x[i], max(a, b) + ymax * 0.06, f"{sign}{delta:.1f}%",
                    ha="center", va="bottom", fontsize=9,
                    color=("#0b5394" if delta >= 0 else "#7f2704"))

    plt.tight_layout()
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    labels: list[str] = []
    eno_vals: list[float] = []
    god_vals: list[float] = []

    print(f"{'scenario':20s}  {'ENO':>10s}  {'Godel':>10s}  {'delta':>10s}")
    for label, suffix in SCENARIOS:
        a = load_peak_throughput("a", suffix)
        b = load_peak_throughput("b", suffix)
        if a is None or b is None:
            print(f"{label:20s}  {'n/a' if a is None else f'{a:.1f}':>10s}  {'n/a' if b is None else f'{b:.1f}':>10s}  (skipped)")
            continue
        labels.append(label.replace("\n", " "))
        eno_vals.append(a)
        god_vals.append(b)
        delta = (a - b) / b * 100 if b > 0 else float("nan")
        print(f"{label.replace(chr(10), ' '):20s}  {a:10.1f}  {b:10.1f}  {delta:+9.1f}%")

    if not labels:
        print("no data available; nothing to render")
        return 1

    FIGURES.mkdir(parents=True, exist_ok=True)
    out = FIGURES / "fig6-19-peak-throughput-a-vs-b-all.png"
    # Restore multi-line labels for the plot
    plot_labels = [s.replace(" ", "\n", 1) if " " in s else s for s in labels]
    render(plot_labels, eno_vals, god_vals, out)
    print(f"\nSaved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
