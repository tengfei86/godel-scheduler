#!/usr/bin/env python3
"""
plot-results.py — 将 Prometheus 导出的 JSON 数据绘制为 PNG 图表

用法:
  python3 plot-results.py <results_dir> [--output <output_dir>] [--format png|pdf|svg]

示例:
  # 绘制单个 run 的结果
  python3 plot-results.py results/a/s2/w1/run1

  # 指定输出目录和格式
  python3 plot-results.py results/a/s2/w1/run1 --output ./charts --format pdf

  # 对比多个组 (同 scale/workload 下不同调度器)
  python3 plot-results.py results/a/s2/w1/run1 results/b/s2/w1/run1 results/c/s2/w1/run1 --compare

结果目录结构: results/<group>/<scale>/<workload>/<run>/
"""

import argparse
import json
import csv
import os
import sys
from datetime import datetime
from pathlib import Path

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates
except ImportError:
    print("错误: 需要安装 matplotlib。运行: pip3 install matplotlib", file=sys.stderr)
    sys.exit(1)

# ── 指标元数据: 显示名称、Y 轴标签、单位换算 ──
METRIC_META = {
    "scheduling_throughput":    {"title": "Scheduling Throughput",      "ylabel": "pods/s"},
    "bind_throughput_pods":     {"title": "Bind Throughput (Pods)",     "ylabel": "pods/s"},
    "bind_throughput_units":    {"title": "Bind Throughput (Units)",    "ylabel": "units/s"},
    "scheduling_latency_p50":  {"title": "Scheduling Latency (P50)",   "ylabel": "seconds", "scale": 1},
    "scheduling_latency_p90":  {"title": "Scheduling Latency (P90)",   "ylabel": "seconds", "scale": 1},
    "scheduling_latency_p99":  {"title": "Scheduling Latency (P99)",   "ylabel": "seconds", "scale": 1},
    "bind_latency_p50":        {"title": "Bind Latency (P50)",         "ylabel": "seconds", "scale": 1},
    "bind_latency_p90":        {"title": "Bind Latency (P90)",         "ylabel": "seconds", "scale": 1},
    "bind_latency_p99":        {"title": "Bind Latency (P99)",         "ylabel": "seconds", "scale": 1},
    "algorithm_latency_p90":   {"title": "Algorithm Latency (P90)",    "ylabel": "seconds", "scale": 1},
    "algorithm_latency_p99":   {"title": "Algorithm Latency (P99)",    "ylabel": "seconds", "scale": 1},
    "scheduling_success_rate": {"title": "Scheduling Success Rate",    "ylabel": "ratio"},
    "scheduling_error_rate":   {"title": "Scheduling Error Rate",      "ylabel": "ratio"},
    "bind_inflight":           {"title": "Bind In-flight",             "ylabel": "count"},
    "bind_retries":            {"title": "Bind Retries",               "ylabel": "retries/s"},
    "dispatcher_fallback":     {"title": "Dispatcher Fallback",        "ylabel": "fallbacks/s"},
    "node_validation_failures":{"title": "Node Validation Failures",   "ylabel": "failures/s"},
    "goroutines":              {"title": "Goroutines",                 "ylabel": "count"},
    "pending_pods":            {"title": "Pending Pods",               "ylabel": "count"},
    "queue_wait_p90":          {"title": "Queue Wait (P90)",           "ylabel": "seconds"},
    "scheduling_attempts_total": {"title": "Scheduling Attempts",      "ylabel": "attempts/s"},
}

# 组标签
GROUP_LABELS = {
    "a": "Embedded Binder (Proposed)",
    "b": "Shared Binder (Baseline)",
    "c": "kube-scheduler",
    "d": "Volcano",
    "e": "Koordinator",
}

# 图表样式
COLORS = ["#2196F3", "#FF5722", "#4CAF50", "#9C27B0", "#FF9800", "#607D8B"]
plt.rcParams.update({
    "figure.figsize": (12, 5),
    "figure.dpi": 150,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "font.size": 11,
    "axes.titlesize": 14,
    "axes.labelsize": 12,
})


def load_prometheus_json(filepath):
    """加载 Prometheus query_range JSON 文件，返回 [(series_label, timestamps, values), ...]"""
    with open(filepath, "r") as f:
        data = json.load(f)

    if data.get("status") != "success":
        return []

    results = data.get("data", {}).get("result", [])
    series_list = []

    for series in results:
        metric = series.get("metric", {})
        values = series.get("values", [])
        if not values:
            continue

        # 构建 series 标签
        if metric:
            label = ", ".join(f"{k}={v}" for k, v in metric.items()
                              if k != "__name__")
        else:
            label = ""

        timestamps = [datetime.fromtimestamp(float(v[0])) for v in values]
        vals = [float(v[1]) for v in values]
        series_list.append((label, timestamps, vals))

    return series_list


def plot_single_metric(filepath, output_path, fmt="png"):
    """绘制单个指标文件的时序图"""
    metric_name = Path(filepath).stem
    meta = METRIC_META.get(metric_name, {"title": metric_name, "ylabel": ""})

    series_list = load_prometheus_json(filepath)
    if not series_list:
        return False

    fig, ax = plt.subplots()
    for i, (label, ts, vals) in enumerate(series_list):
        color = COLORS[i % len(COLORS)]
        display_label = label if label else metric_name
        ax.plot(ts, vals, label=display_label, color=color, linewidth=1.5)

    ax.set_title(meta["title"])
    ax.set_ylabel(meta["ylabel"])
    ax.set_xlabel("Time")
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
    fig.autofmt_xdate()

    if len(series_list) > 1 or series_list[0][0]:
        ax.legend(loc="best", fontsize=9)

    fig.tight_layout()
    fig.savefig(output_path, format=fmt, bbox_inches="tight")
    plt.close(fig)
    return True


def plot_utilization_csv(filepath, output_path, fmt="png"):
    """绘制 utilization.csv 的柱状图"""
    nodes = []
    pod_counts = []

    with open(filepath, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes.append(row["node"])
            pod_counts.append(int(row["pod_count"]))

    if not pod_counts:
        return False

    # 只显示 top-30 + 汇总统计
    if len(nodes) > 30:
        sorted_pairs = sorted(zip(pod_counts, nodes), reverse=True)
        pod_counts = [p for p, _ in sorted_pairs[:30]]
        nodes = [n for _, n in sorted_pairs[:30]]
        title_suffix = f" (Top 30 / {len(sorted_pairs)} nodes)"
    else:
        title_suffix = ""

    fig, ax = plt.subplots(figsize=(14, 6))
    bars = ax.barh(range(len(nodes)), pod_counts, color="#2196F3", alpha=0.8)
    ax.set_yticks(range(len(nodes)))
    ax.set_yticklabels(nodes, fontsize=7)
    ax.set_xlabel("Pod Count")
    ax.set_title(f"Node Utilization{title_suffix}")
    ax.invert_yaxis()

    for bar, count in zip(bars, pod_counts):
        ax.text(bar.get_width() + 0.3, bar.get_y() + bar.get_height() / 2,
                str(count), va="center", fontsize=7)

    fig.tight_layout()
    fig.savefig(output_path, format=fmt, bbox_inches="tight")
    plt.close(fig)
    return True


def plot_directory(results_dir, output_dir=None, fmt="png"):
    """绘制一个结果目录下的所有指标"""
    results_dir = Path(results_dir)
    if output_dir is None:
        output_dir = results_dir / "charts"
    else:
        output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    plotted = 0
    skipped = 0

    # JSON 文件
    for json_file in sorted(results_dir.glob("*.json")):
        out_path = output_dir / f"{json_file.stem}.{fmt}"
        if plot_single_metric(str(json_file), str(out_path), fmt):
            print(f"  ✓ {json_file.stem}.{fmt}")
            plotted += 1
        else:
            print(f"  ⊘ {json_file.stem} (无数据)")
            skipped += 1

    # CSV 文件
    for csv_file in sorted(results_dir.glob("*.csv")):
        out_path = output_dir / f"{csv_file.stem}.{fmt}"
        if plot_utilization_csv(str(csv_file), str(out_path), fmt):
            print(f"  ✓ {csv_file.stem}.{fmt}")
            plotted += 1
        else:
            print(f"  ⊘ {csv_file.stem} (无数据)")
            skipped += 1

    print(f"\n完成: {plotted} 张图表已导出至 {output_dir}/, {skipped} 个跳过 (空数据)")
    return plotted


def compare_groups(dirs, output_dir, metric_names=None, fmt="png"):
    """
    对比模式: 将多个组的同名指标画在同一张图上。
    dirs: list of result directories (e.g., results/a/s2/w1/run1, results/b/s2/w1/run1)
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # 收集所有目录中出现过的指标名
    all_metrics = set()
    for d in dirs:
        for f in Path(d).glob("*.json"):
            all_metrics.add(f.stem)

    if metric_names:
        all_metrics = all_metrics & set(metric_names)

    plotted = 0
    for metric_name in sorted(all_metrics):
        meta = METRIC_META.get(metric_name, {"title": metric_name, "ylabel": ""})

        fig, ax = plt.subplots()
        has_data = False

        for i, d in enumerate(dirs):
            filepath = Path(d) / f"{metric_name}.json"
            if not filepath.exists():
                continue

            # 从路径推断组名
            parts = Path(d).parts
            group_key = None
            for p in parts:
                if p in GROUP_LABELS:
                    group_key = p
                    break
            group_label = GROUP_LABELS.get(group_key, str(d))

            series_list = load_prometheus_json(str(filepath))
            for label, ts, vals in series_list:
                color = COLORS[i % len(COLORS)]
                display = f"{group_label}"
                if label:
                    display += f" ({label})"
                ax.plot(ts, vals, label=display, color=color, linewidth=1.5)
                has_data = True

        if not has_data:
            plt.close(fig)
            continue

        ax.set_title(meta["title"])
        ax.set_ylabel(meta["ylabel"])
        ax.set_xlabel("Time")
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
        ax.legend(loc="best", fontsize=9)
        fig.autofmt_xdate()
        fig.tight_layout()

        out_path = output_dir / f"compare_{metric_name}.{fmt}"
        fig.savefig(str(out_path), format=fmt, bbox_inches="tight")
        plt.close(fig)
        print(f"  ✓ compare_{metric_name}.{fmt}")
        plotted += 1

    print(f"\n完成: {plotted} 张对比图表已导出至 {output_dir}/")
    return plotted


def main():
    parser = argparse.ArgumentParser(
        description="将 Prometheus 导出的 JSON 数据绘制为图表")
    parser.add_argument("dirs", nargs="+",
                        help="一个或多个结果目录 (results/<group>/<scale>/<workload>/<run>)")
    parser.add_argument("--output", "-o", default=None,
                        help="输出目录 (默认: <results_dir>/charts)")
    parser.add_argument("--format", "-f", default="png",
                        choices=["png", "pdf", "svg"],
                        help="输出格式 (默认: png)")
    parser.add_argument("--compare", action="store_true",
                        help="对比模式: 多个目录的同名指标画在同一张图")
    parser.add_argument("--metrics", nargs="*", default=None,
                        help="仅绘制指定指标 (默认: 全部)")

    args = parser.parse_args()

    if args.compare:
        if len(args.dirs) < 2:
            parser.error("对比模式需要至少 2 个结果目录")
        out = args.output or "charts_compare"
        print(f"对比模式: {len(args.dirs)} 个目录\n")
        compare_groups(args.dirs, out, args.metrics, args.format)
    else:
        for d in args.dirs:
            print(f"\n绘制: {d}")
            plot_directory(d, args.output, args.format)


if __name__ == "__main__":
    main()
