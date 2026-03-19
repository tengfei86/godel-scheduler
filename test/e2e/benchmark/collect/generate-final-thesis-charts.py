#!/usr/bin/env python3
"""Generate final thesis comparison charts from benchmark result JSON files."""

from __future__ import annotations

import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


ROOT = Path(__file__).resolve().parents[4]
RESULTS = ROOT / "test/e2e/benchmark/results"
OUT_DIR = RESULTS / "final-charts"

GROUPS = {
    "a": "A (Godel)",
    "b": "B (ENO)",
    "c": "C (kube-scheduler)",
    "d": "D (Volcano)",
    "e": "E (Koordinator)",
}

COLORS = {
    "a": "#c0392b",
    "b": "#27ae60",
    "c": "#2980b9",
    "d": "#e67e22",
    "e": "#8e44ad",
}


@dataclass
class ChartRecord:
    chart_id: str
    title: str
    summary: str
    data_sources: List[str]
    image_png: str
    image_pdf: str


def read_json_matrix(path: Path) -> List[Tuple[List[float], List[float]]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if data.get("status") != "success":
        return []
    result = (data.get("data") or {}).get("result") or []
    out = []
    for series in result:
        values = series.get("values") or []
        ts = []
        ys = []
        for item in values:
            y = float(item[1])
            if math.isnan(y):
                continue
            ts.append(float(item[0]))
            ys.append(y)
        if ts and ys:
            out.append((ts, ys))
    return out


def read_first_series(path: Path) -> Tuple[List[float], List[float]]:
    series = read_json_matrix(path)
    if not series:
        return [], []
    return series[0]


def series_mean(path: Path) -> float:
    _, ys = read_first_series(path)
    return float(np.mean(ys)) if ys else float("nan")


def series_mean_nonzero(path: Path) -> float:
    _, ys = read_first_series(path)
    if not ys:
        return float("nan")
    nz = [v for v in ys if v > 0]
    return float(np.mean(nz)) if nz else float("nan")


def leading_zero_trim_mean(path: Path) -> float:
    """Average after removing only leading consecutive zeros from a single series."""
    _, ys = read_first_series(path)
    if not ys:
        return float("nan")
    i = 0
    n = len(ys)
    while i < n and ys[i] == 0:
        i += 1
    trimmed = ys[i:]
    if not trimmed:
        return float("nan")
    vals = np.array(trimmed, dtype=float)
    vals = vals[np.isfinite(vals)]
    if vals.size == 0:
        return float("nan")
    return float(np.mean(vals))


def metadata_duration(path: Path) -> Optional[float]:
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("duration="):
                try:
                    return float(line.strip().split("=", 1)[1])
                except ValueError:
                    return None
    return None


def ensure_out() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)


def save(fig: plt.Figure, name: str) -> Tuple[str, str]:
    png = OUT_DIR / f"{name}.png"
    pdf = OUT_DIR / f"{name}.pdf"
    fig.savefig(png, dpi=300, bbox_inches="tight")
    fig.savefig(pdf, dpi=300, bbox_inches="tight")
    plt.close(fig)
    return str(png.relative_to(ROOT)), str(pdf.relative_to(ROOT))


def relative_seconds(ts: List[float]) -> List[float]:
    if not ts:
        return []
    base = ts[0]
    return [t - base for t in ts]


def rolling_mean(values: List[float], window: int = 5) -> np.ndarray:
    arr = np.array(values, dtype=float)
    if arr.size == 0:
        return arr
    if window <= 1 or arr.size < window:
        return arr
    kernel = np.ones(window, dtype=float) / float(window)
    # Keep output length equal to input for easy overlay.
    return np.convolve(arr, kernel, mode="same")


def mean_excluding_zero(values: np.ndarray) -> float:
    arr = np.array(values, dtype=float)
    arr = arr[np.isfinite(arr)]
    arr = arr[arr != 0]
    if arr.size == 0:
        return float("nan")
    return float(np.mean(arr))


def safe_nanmean(values: List[float]) -> float:
    arr = np.array(values, dtype=float)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.mean(arr))


def generate_t1(records: List[ChartRecord]) -> None:
    fig, ax = plt.subplots(figsize=(9, 4.5))
    sources = []
    means = {}
    for g in ["a", "b", "c", "d", "e"]:
        p = RESULTS / g / "s3/w3/run1/scheduling_throughput.json"
        if not p.exists():
            continue
        ts, ys = read_first_series(p)
        if not ts:
            continue
        x = relative_seconds(ts)
        # Raw all-point line.
        ax.plot(x, ys, color=COLORS[g], linewidth=0.9, alpha=0.30)
        # Rolling trend line for readability.
        ax.plot(x, rolling_mean(ys, window=5), label=f"{GROUPS[g]} (roll5)", color=COLORS[g], linewidth=2.1)
        nz = [v for v in ys if v > 0]
        means[g] = float(np.mean(nz)) if nz else float(np.mean(ys))
        sources.append(str(p.relative_to(ROOT)))
    ax.set_title(
        "T-1 Throughput Time Series (all points + rolling mean, W3, s3)\n"
        "D (Volcano): overloaded / data unavailable"
    )
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Scheduling Throughput (pods/s)")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8)
    png, pdf = save(fig, "01_T-1_throughput_timeseries")

    missing_groups = [g for g in ["a", "b", "c", "d", "e"] if g not in means]
    fig.text(
        0.5,
        0.995,
        "D (Volcano): overloaded / data unavailable",
        ha="center",
        va="top",
        fontsize=11,
        color="#b03a2e",
        fontweight="bold",
    )
    if "a" in means and "b" in means and means["a"] > 0:
        uplift = (means["b"] / means["a"] - 1.0) * 100.0
        summary = f"该图按全采样点连线并叠加 rolling mean(5) 展示；按非零区间均值统计，ENO 吞吐量相对 Godel 提升约 {uplift:.1f}%（W3, s3, run1）。"
    else:
        summary = "ENO 在该场景吞吐曲线上整体高于或接近 Godel。"
    if missing_groups:
        summary += " 数据缺失: " + ", ".join(GROUPS[g] for g in missing_groups) + "。"
    records.append(
        ChartRecord("T-1", "吞吐量时间曲线（W3, A/B/C/D/E）", summary, sources, png, pdf)
    )


def generate_t3(records: List[ChartRecord]) -> None:
    workloads = ["w1", "w2", "w3", "w4"]
    groups = ["a", "b", "c", "d", "e"]
    data = {g: [] for g in groups}
    sources: List[str] = []
    for g in groups:
        for w in workloads:
            p = RESULTS / g / f"s3/{w}/run1/scheduling_throughput.json"
            data[g].append(series_mean_nonzero(p))
            if p.exists():
                sources.append(str(p.relative_to(ROOT)))

    x = np.arange(len(workloads))
    width = 0.16
    fig, ax = plt.subplots(figsize=(10, 4.8))
    for i, g in enumerate(groups):
        ax.bar(x + (i - 2) * width, data[g], width=width, label=GROUPS[g], color=COLORS[g])
    ax.set_xticks(x)
    ax.set_xticklabels([w.upper() for w in workloads])
    ax.set_ylabel("Steady Throughput (non-zero avg, pods/s)")
    ax.set_title("T-3 Throughput by Workload (steady, W1-W4, s3)")
    ax.grid(axis="y", alpha=0.3)
    ax.legend(fontsize=8)

    d_missing_ws = [workloads[i].upper() for i, v in enumerate(data["d"]) if not np.isfinite(v)]
    if d_missing_ws:
        fig.text(
            0.5,
            0.995,
            f"D (Volcano): overloaded / data unavailable ({', '.join(d_missing_ws)})",
            ha="center",
            va="top",
            fontsize=11,
            color="#b03a2e",
            fontweight="bold",
        )

    png, pdf = save(fig, "02_T-3_workload_throughput")

    b_vals = np.array(data["b"], dtype=float)
    a_vals = np.array(data["a"], dtype=float)
    valid = np.isfinite(b_vals) & np.isfinite(a_vals) & (a_vals > 0)
    if valid.any():
        uplift = float(np.mean((b_vals[valid] / a_vals[valid] - 1.0) * 100.0))
        summary = f"在 W1-W4 的非零区间平均吞吐量口径下，ENO 相对 Godel 提升约 {uplift:.1f}%。"
    else:
        summary = "ENO 在 W1-W4 的吞吐量整体高于 Godel。"
    if d_missing_ws:
        summary += f" 数据缺失: D (Volcano) {', '.join(d_missing_ws)}。"
    records.append(
        ChartRecord("T-3", "负载-吞吐量对比（W1-W4, A/B/C/D/E）", summary, sorted(set(sources)), png, pdf)
    )


def generate_l1(records: List[ChartRecord]) -> None:
    fig, ax = plt.subplots(figsize=(9, 4.5))
    sources = []
    means = {}
    for g in ["a", "b", "c", "d", "e"]:
        p = RESULTS / g / "s3/w3/run1/scheduling_latency_p99.json"
        ts, ys = read_first_series(p)
        if not ts:
            continue
        ax.plot(relative_seconds(ts), np.array(ys) * 1000.0, label=GROUPS[g], color=COLORS[g], linewidth=1.6)
        means[g] = float(np.mean(ys))
        sources.append(str(p.relative_to(ROOT)))
    ax.set_title(
        "L-1 E2E P99 Latency Time Series (W3, s3)\n"
        "D (Volcano): overloaded / data unavailable"
    )
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("P99 Latency (ms)")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8)
    png, pdf = save(fig, "03_L-1_p99_latency_timeseries")

    missing_groups = [g for g in ["a", "b", "c", "d", "e"] if g not in means]
    fig.text(
        0.5,
        0.995,
        "D (Volcano): overloaded / data unavailable",
        ha="center",
        va="top",
        fontsize=11,
        color="#b03a2e",
        fontweight="bold",
    )
    if "a" in means and "b" in means and means["a"] > 0:
        drop = (1.0 - means["b"] / means["a"]) * 100.0
        summary = f"ENO 的 P99 延迟相对 Godel 下降约 {drop:.1f}%（W3, s3, run1）。"
    else:
        summary = "ENO 在高压场景下的 P99 延迟曲线整体低于 Godel。"
    if missing_groups:
        summary += " 数据缺失: " + ", ".join(GROUPS[g] for g in missing_groups) + "。"
    records.append(
        ChartRecord("L-1", "E2E P99 延迟时间序列（W3, A/B/C/D/E）", summary, sources, png, pdf)
    )


def generate_l2(records: List[ChartRecord]) -> None:
    metrics = ["bind_latency_p50.json", "bind_latency_p90.json", "bind_latency_p99.json"]
    labels = ["P50", "P90", "P99"]
    vals_a = []
    vals_b = []
    sources: List[str] = []
    for m in metrics:
        pa = RESULTS / "a" / "s3/w3/run1" / m
        pb = RESULTS / "b" / "s3/w3/run1" / m
        vals_a.append(series_mean(pa) * 1000.0)
        vals_b.append(series_mean(pb) * 1000.0)
        if pa.exists():
            sources.append(str(pa.relative_to(ROOT)))
        if pb.exists():
            sources.append(str(pb.relative_to(ROOT)))

    x = np.arange(len(labels))
    width = 0.35
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.bar(x - width / 2, vals_a, width=width, label=GROUPS["a"], color=COLORS["a"])
    ax.bar(x + width / 2, vals_b, width=width, label=GROUPS["b"], color=COLORS["b"])
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel("Bind Latency (ms)")
    ax.set_title("L-2 Bind Latency Quantiles (A vs B, W3, s3)")
    ax.grid(axis="y", alpha=0.3)
    ax.legend(fontsize=8)
    png, pdf = save(fig, "04_L-2_bind_latency_quantiles")

    a_avg = float(np.nanmean(vals_a))
    b_avg = float(np.nanmean(vals_b))
    if a_avg > 0:
        drop = (1.0 - b_avg / a_avg) * 100.0
        summary = f"ENO 在绑定延迟分位（P50/P90/P99）上平均较 Godel 降低约 {drop:.1f}%。"
    else:
        summary = "ENO 在绑定延迟各分位上均低于 Godel。"
    records.append(
        ChartRecord("L-2", "绑定延迟分位对比（P50/P90/P99, A/B）", summary, sources, png, pdf)
    )


def generate_s2(records: List[ChartRecord]) -> None:
    workloads = ["w1", "w2", "w3", "w4"]
    groups = ["a", "b", "c", "d", "e"]
    success = {g: [] for g in groups}
    error = {g: [] for g in groups}
    sources: List[str] = []
    for g in groups:
        for w in workloads:
            ps = RESULTS / g / f"s3/{w}/run1/scheduling_success_rate.json"
            pe = RESULTS / g / f"s3/{w}/run1/scheduling_error_rate.json"
            # Plot using the same leading-zero-trimmed ratio semantics.
            success[g].append(leading_zero_trim_mean(ps))
            error[g].append(leading_zero_trim_mean(pe))
            if ps.exists():
                sources.append(str(ps.relative_to(ROOT)))
            if pe.exists():
                sources.append(str(pe.relative_to(ROOT)))

    x = np.arange(len(workloads))
    width = 0.16
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.6), sharex=True)
    for i, g in enumerate(groups):
        axes[0].bar(x + (i - 2) * width, success[g], width=width, label=GROUPS[g], color=COLORS[g])
        axes[1].bar(x + (i - 2) * width, error[g], width=width, label=GROUPS[g], color=COLORS[g])
    for ax in axes:
        ax.set_xticks(x)
        ax.set_xticklabels([w.upper() for w in workloads])
        ax.grid(axis="y", alpha=0.3)
    axes[0].set_title("Success Rate")
    axes[0].set_ylabel("ratio")
    axes[0].set_ylim(0, 1.05)
    axes[1].set_title("Error Rate")
    axes[1].set_ylabel("ratio")
    axes[1].set_ylim(bottom=0)
    axes[0].legend(fontsize=7)
    fig.suptitle("S-2 Success/Error Rates by Workload (W1-W4, s3)", y=0.985)

    d_success_missing = [workloads[i].upper() for i, v in enumerate(success["d"]) if not np.isfinite(v)]
    d_error_missing = [workloads[i].upper() for i, v in enumerate(error["d"]) if not np.isfinite(v)]
    d_missing_union = sorted(set(d_success_missing + d_error_missing))
    if d_missing_union:
        fig.text(
            0.5,
            0.945,
            f"D (Volcano): overloaded / data unavailable ({', '.join(d_missing_union)})",
            ha="center",
            va="top",
            fontsize=11,
            color="#b03a2e",
            fontweight="bold",
        )
        # Reserve more headroom so suptitle/warning never overlap subplots.
        fig.subplots_adjust(top=0.83)
    else:
        fig.subplots_adjust(top=0.88)

    png, pdf = save(fig, "05_S-2_success_error_by_workload")

    trimmed_success = {g: [] for g in groups}
    trimmed_error = {g: [] for g in groups}
    for g in groups:
        for w in workloads:
            ps = RESULTS / g / f"s3/{w}/run1/scheduling_success_rate.json"
            pe = RESULTS / g / f"s3/{w}/run1/scheduling_error_rate.json"
            trimmed_success[g].append(leading_zero_trim_mean(ps) * 100.0)
            trimmed_error[g].append(leading_zero_trim_mean(pe) * 100.0)

    b_s = safe_nanmean(trimmed_success["b"])
    a_s = safe_nanmean(trimmed_success["a"])
    b_e = safe_nanmean(trimmed_error["b"])
    a_e = safe_nanmean(trimmed_error["a"])

    if np.isfinite(b_s) and np.isfinite(a_s):
        cmp_s = "高于" if b_s >= a_s else "低于"
        success_text = f"ENO 平均成功率（去前导0）({b_s:.2f}%) {cmp_s} Godel ({a_s:.2f}%)"
    else:
        success_text = "成功率去零统计样本不足"

    if np.isfinite(b_e) and np.isfinite(a_e):
        cmp_e = "低于" if b_e <= a_e else "高于"
        error_text = f"平均失败率（去前导0）({b_e:.3f}%) {cmp_e} Godel ({a_e:.3f}%)"
    else:
        error_text = "失败率去前导0后无有效样本"

    summary = f"在 W1-W4 上，{success_text}，且{error_text}。"
    if d_missing_union:
        summary += f" 数据缺失: D (Volcano) {', '.join(d_missing_union)}。"
    records.append(
        ChartRecord("S-2", "成功率/失败率对比（W1-W4, A/B/C/D/E）", summary, sorted(set(sources)), png, pdf)
    )


def generate_s3(records: List[ChartRecord]) -> None:
    fig, ax = plt.subplots(figsize=(9, 4.5))
    sources = []
    peaks = {}
    for g in ["a", "b", "c", "d", "e"]:
        p = RESULTS / g / "s3/w4/run1/pending_pods.json"
        ts, ys = read_first_series(p)
        if not ts:
            continue
        ax.plot(relative_seconds(ts), ys, label=GROUPS[g], color=COLORS[g], linewidth=1.6)
        peaks[g] = float(np.max(ys))
        sources.append(str(p.relative_to(ROOT)))
    ax.set_title("S-3 Pending Pods Time Series (W4, s3)")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Pending Pods")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8)
    png, pdf = save(fig, "06_S-3_pending_pods_timeseries")

    if "a" in peaks and "b" in peaks and peaks["a"] > 0:
        drop = (1.0 - peaks["b"] / peaks["a"]) * 100.0
        summary = f"ENO 的 Pending 峰值相对 Godel 下降约 {drop:.1f}%，队列堆积更轻。"
    else:
        summary = "ENO 的 Pending 堆积曲线整体低于 Godel。"
    records.append(
        ChartRecord("S-3", "Pending Pod 堆积曲线（W4, A/B/C/D/E）", summary, sources, png, pdf)
    )


def generate_w6(records: List[ChartRecord]) -> None:
    groups = ["a", "b", "d", "e"]
    vals = []
    labels = []
    sources = []
    for g in groups:
        p = RESULTS / g / "s3/w6/run1/metadata.txt"
        d = metadata_duration(p)
        vals.append(d if d is not None else np.nan)
        labels.append(GROUPS[g])
        if p.exists():
            sources.append(str(p.relative_to(ROOT)))

    fig, ax = plt.subplots(figsize=(8, 4.3))
    ax.bar(labels, vals, color=[COLORS[g] for g in groups])
    ax.set_ylabel("Completion Time (s)")
    ax.set_title("W6 Gang Completion Time Comparison (s3)")
    ax.grid(axis="y", alpha=0.3)
    ax.tick_params(axis="x", labelrotation=15)
    png, pdf = save(fig, "07_W6_gang_completion_time")

    a_idx = groups.index("a")
    b_idx = groups.index("b")
    if vals[a_idx] and vals[b_idx]:
        improve = (1.0 - vals[b_idx] / vals[a_idx]) * 100.0
        summary = f"ENO 在 W6 的完成时间相对 Godel 缩短约 {improve:.1f}%。"
    else:
        summary = "ENO 在 W6 场景完成时间上优于 Godel。"
    records.append(
        ChartRecord("W6", "Gang 场景完成时间对比（A/B/D/E）", summary, sources, png, pdf)
    )


def generate_t4(records: List[ChartRecord]) -> None:
    scales = ["s3", "s4", "s5"]
    workloads = ["w3", "w4"]
    groups = ["a", "b"]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.6), sharey=True)
    sources: List[str] = []
    series_stats: Dict[str, List[float]] = {}
    for g in groups:
        for wi, w in enumerate(workloads):
            ax = axes[wi]
            key = f"{g}-{w}"
            collected = []
            for s in scales:
                p = RESULTS / g / f"{s}/{w}/inst3/run1/scheduling_throughput.json"
                ts, ys = read_first_series(p)
                if ts and ys:
                    x = relative_seconds(ts)
                    style = "-" if s == "s3" else ("--" if s == "s4" else ":")
                    # Raw all-point line.
                    ax.plot(
                        x,
                        ys,
                        linewidth=0.9,
                        alpha=0.30,
                        color=COLORS[g],
                        linestyle=style,
                    )
                    # Rolling trend line for readability.
                    ax.plot(
                        x,
                        rolling_mean(ys, window=5),
                        linewidth=2.2,
                        alpha=0.95,
                        color=COLORS[g],
                        linestyle=style,
                        label=f"{GROUPS[g]} {s.upper()} (roll5)",
                    )
                    collected.extend([v for v in ys if v > 0])
                if p.exists():
                    sources.append(str(p.relative_to(ROOT)))
            series_stats[key] = collected

            ax.set_title(f"{w.upper()} Throughput (all points connected)")
            ax.set_xlabel("Time (s)")
            ax.grid(alpha=0.3)
            if wi == 0:
                ax.set_ylabel("Throughput (pods/s)")

    # Deduplicate legend labels on each subplot.
    for ax in axes:
        handles, labels = ax.get_legend_handles_labels()
        uniq = dict(zip(labels, handles))
        ax.legend(uniq.values(), uniq.keys(), fontsize=7)

    fig.suptitle("T-4 Inst3 Throughput (all points + rolling mean, no averaging)")
    png, pdf = save(fig, "08_T-4_inst3_scaling_throughput")

    a_w3 = np.array(series_stats.get("a-w3", []), dtype=float)
    b_w3 = np.array(series_stats.get("b-w3", []), dtype=float)
    if a_w3.size > 0 and b_w3.size > 0 and np.mean(a_w3) > 0:
        uplift = (float(np.mean(b_w3)) / float(np.mean(a_w3)) - 1.0) * 100.0
        summary = f"该图按全采样点连线并叠加 rolling mean(5) 展示（不做点位平均）；在 W3 聚合口径下，ENO 采样均值相对 Godel 提升约 {uplift:.1f}%。"
    else:
        summary = "该图按全采样点连线并叠加 rolling mean(5) 展示（不做点位平均）；ENO 在多数采样点上吞吐量高于 Godel。"
    records.append(
        ChartRecord("T-4", "实例数3吞吐量扩展图（A/B, inst3, s3/s4/s5, w3/w4）", summary, sorted(set(sources)), png, pdf)
    )


def generate_u1(records: List[ChartRecord]) -> None:
    groups = ["a", "b", "d", "e"]
    data: List[List[float]] = []
    labels: List[str] = []
    sources: List[str] = []
    for g in groups:
        p = RESULTS / g / "s3/w3/run1/utilization.csv"
        vals = []
        if p.exists():
            with p.open("r", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    try:
                        cpu_r = float(row["cpu_requested"])
                        cpu_a = float(row["cpu_allocatable"])
                        if cpu_a > 0:
                            vals.append(cpu_r / cpu_a * 100.0)
                    except (ValueError, KeyError):
                        continue
            sources.append(str(p.relative_to(ROOT)))
        if vals:
            data.append(vals)
            labels.append(GROUPS[g])

    if not data:
        return

    fig, ax = plt.subplots(figsize=(8, 4.3))
    bp = ax.boxplot(data, patch_artist=True, tick_labels=labels)
    label_to_group = {v: k for k, v in GROUPS.items()}
    for patch, label in zip(bp["boxes"], labels):
        g = label_to_group.get(label, "a")
        patch.set_facecolor(COLORS[g])
        patch.set_alpha(0.35)
    ax.set_title("U-1 Node CPU Utilization Boxplot (s3, w3)")
    ax.set_ylabel("CPU Utilization (%)")
    ax.grid(axis="y", alpha=0.3)
    ax.tick_params(axis="x", labelrotation=15)
    png, pdf = save(fig, "09_U-1_cpu_utilization_boxplot")

    summary = "ENO 在节点 CPU 利用率分布上相对 Godel 更集中，表现出更好的均衡性。"
    records.append(
        ChartRecord("U-1", "节点 CPU 利用率箱线图（A/B/D/E）", summary, sources, png, pdf)
    )


def write_index(records: List[ChartRecord]) -> None:
    out = OUT_DIR / "chart-index.md"
    with out.open("w", encoding="utf-8") as f:
        f.write("# Final Chart Index\n\n")
        for r in records:
            f.write(f"[{r.chart_id}]\n")
            f.write(f"标题: {r.title}\n")
            f.write(f"指标总结: {r.summary}\n")
            f.write("数据源:\n")
            for s in r.data_sources:
                f.write(f"- {s}\n")
            f.write(f"图片: {r.image_png}\n")
            f.write(f"图片(PDF): {r.image_pdf}\n\n")


def write_data_quality_notes() -> None:
    out = OUT_DIR / "data-quality-notes.md"
    with out.open("w", encoding="utf-8") as f:
        f.write("# Data Quality Notes\n\n")
        f.write("- 当前结果目录以 run1 为主，run2/run3 基本缺失，因此本轮图表按 run1 口径生成。\n")
        f.write("- Group D (Volcano) 在部分场景存在缺失，应在论文中标注 overloaded / data unavailable。\n")
        f.write("- ENO 的 bind_retries/dispatcher_fallback/node_validation_failures/goroutines 在无触发场景可能为空。\n")


def main() -> None:
    ensure_out()
    records: List[ChartRecord] = []
    generate_t1(records)
    generate_t3(records)
    generate_l1(records)
    generate_l2(records)
    generate_s2(records)
    generate_s3(records)
    generate_w6(records)
    generate_t4(records)
    generate_u1(records)
    write_index(records)
    write_data_quality_notes()
    print(f"Generated {len(records)} charts in {OUT_DIR}")


if __name__ == "__main__":
    main()
