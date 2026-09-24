#!/usr/bin/env python3
"""gen-w6-bar-charts.py — 生成 w6 (Gang) 场景下 a/b/d 三组柱状图

Two bar charts comparing ENO (a) / Gödel (b) / Volcano (d) on w6 Gang
workload at s3 scale, single-instance configuration:

  fig6-17-w6-throughput-bar.png    有效吞吐 (pods/s)
  fig6-18-w6-latency-p99-bar.png   P99 调度延迟 (s)

数据口径与 §6.3 一致：
  - 有效吞吐 = total / duration（每 run 独立计算，3 次重复取中位数）
  - P99 延迟 = avg/ 聚合序列剔除首尾各 2 采样点后取中位数；
    若剩余点数不足 1，则回退到 run_scheduling_latency_p99.json 的中位数
    （w6 单次 run 较短时依赖 run 级回退）。
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

_HERE = Path(__file__).resolve()
RESULTS = _HERE.parent.parent / "results"                    # test/e2e/benchmark/results
FIGURES = _HERE.parents[4] / "docs" / "thesis" / "figures"    # repo/docs/thesis/figures

# 三组对比：均单实例（a/b 用 inst1，d 天然单实例）
CONFIGS = [
    ("a", "ENO",     RESULTS / "a" / "s3" / "w6" / "inst1"),
    ("b", "Godel",   RESULTS / "b" / "s3" / "w6" / "inst1"),
    ("d", "Volcano", RESULTS / "d" / "s3" / "w6"),
]


def read_metadata_field(md: Path, key: str) -> float | None:
    if not md.exists():
        return None
    for line in md.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(key + "="):
            try:
                return float(line.split("=", 1)[1])
            except ValueError:
                return None
    return None


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


def _load_scalar(fp: Path) -> float | None:
    try:
        payload = json.loads(fp.read_text())
    except (json.JSONDecodeError, OSError):
        return None
    result = payload.get("data", {}).get("result", [])
    if not result:
        return None
    r0 = result[0]
    if "value" in r0:
        try:
            return float(r0["value"][1])
        except (IndexError, ValueError, TypeError):
            return None
    values = r0.get("values", [])
    if values:
        try:
            return float(values[-1][1])
        except (IndexError, ValueError, TypeError):
            return None
    return None


def load_effective_throughput(group_dir: Path) -> float:
    tputs: list[float] = []
    for r in range(1, 4):
        md = group_dir / f"run{r}" / "metadata.txt"
        total = read_metadata_field(md, "total")
        duration = read_metadata_field(md, "duration")
        if total and duration and duration > 0:
            tputs.append(total / duration)
    return statistics.median(tputs) if tputs else 0.0


def load_p99_latency(group_dir: Path) -> tuple[float, str]:
    """Return (value, source) where source ∈ {'series', 'run', 'unavailable'}"""
    avg_series = group_dir / "avg" / "scheduling_latency_p99.json"
    if avg_series.exists():
        vals = _load_series_values(avg_series)
        if len(vals) >= 5:
            trimmed = [v for v in vals[2:-2] if v == v]  # drop NaN
            if trimmed:
                return statistics.median(trimmed), "series"
    fallback: list[float] = []
    for r in range(1, 4):
        f = group_dir / f"run{r}" / "run_scheduling_latency_p99.json"
        if f.exists():
            v = _load_scalar(f)
            if v is not None:
                fallback.append(v)
    if fallback:
        return statistics.median(fallback), "run"
    return 0.0, "unavailable"


def render_bar_chart(labels, values, ylabel, title, out_path):
    fig, ax = plt.subplots(figsize=(6.4, 4.5))
    # 统一色板 (与 fig6-30 一致): a=ENO/blue, b=Godel/gray, d=Volcano/green
    # 顺序对应 CONFIGS: a, b, d
    colors = ["#1f77b4", "#7f7f7f", "#2ca02c"]
    bars = ax.bar(
        labels, values, color=colors[: len(labels)], edgecolor="black", linewidth=0.6
    )
    ax.set_ylabel(ylabel, fontsize=12)
    ax.set_title(title, fontsize=13)
    ax.grid(True, axis="y", alpha=0.3)
    for bar, val in zip(bars, values):
        text = f"{val:.1f}" if val >= 1 else f"{val:.3f}"
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            val,
            text,
            ha="center",
            va="bottom",
            fontsize=10,
        )
    plt.tight_layout()
    fig.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    labels: list[str] = []
    throughputs: list[float] = []
    latencies: list[float] = []
    lat_sources: list[str] = []

    for _gid, label, path in CONFIGS:
        labels.append(label)
        tput = load_effective_throughput(path)
        lat, src = load_p99_latency(path)
        throughputs.append(tput)
        latencies.append(lat)
        lat_sources.append(src)
        print(
            f"{label:10s}  throughput={tput:7.2f} pods/s   "
            f"p99_lat={lat:7.3f} s  (source={src})"
        )

    FIGURES.mkdir(parents=True, exist_ok=True)

    render_bar_chart(
        labels,
        throughputs,
        ylabel="Effective throughput (pods/s)",
        title="w6 (Gang scheduling, s3, inst1) — Effective throughput",
        out_path=FIGURES / "fig6-17-w6-throughput-bar.png",
    )
    render_bar_chart(
        labels,
        latencies,
        ylabel="P99 scheduling latency (s)",
        title="w6 (Gang scheduling, s3, inst1) — P99 scheduling latency",
        out_path=FIGURES / "fig6-18-w6-latency-p99-bar.png",
    )

    print(f"\nSaved:\n  {FIGURES / 'fig6-17-w6-throughput-bar.png'}")
    print(f"  {FIGURES / 'fig6-18-w6-latency-p99-bar.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
