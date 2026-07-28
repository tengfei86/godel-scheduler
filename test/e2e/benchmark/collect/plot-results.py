#!/usr/bin/env python3
"""
plot-results.py — 将 Prometheus 导出的 JSON 数据绘制为图表

用法:
  python3 plot-results.py <dir> [<dir> ...] [选项]

选项:
  --output  -o    输出目录 (默认: <results_dir>/charts 或 charts_compare/charts_average)
  --format  -f    输出格式: png|pdf|svg (默认: png)
  --compare       对比模式: 多个目录的同名指标画在同一张图，X 轴对齐到相对时间
  --average       平均模式: 多个同组 run 逐点平均，同时输出 avg_*.json 供二次对比
  --std-band      与 --average 同用，在均值曲线上绘制 ±1σ 标准差区域
  --metrics       仅绘制指定指标名（空格分隔），默认全部

示例:
  # 1. 绘制单个 run 的所有指标
  python3 plot-results.py ../results/a/s2/w1/run1

  # 2. 指定输出目录和格式
  python3 plot-results.py ../results/a/s2/w1/run1 --output ./charts --format pdf

  # 3. 直接对比多个调度器的同一 run（X 轴自动对齐到相对时间）
  python3 plot-results.py \
    ../results/a/s2/w1/run1 \
    ../results/b/s2/w1/run1 \
    ../results/c/s2/w1/run1 \
    --compare --output ../results/compare/s2_w1

  # 4. 对同一组的多次 run 做平均（附标准差 band）
  python3 plot-results.py \
    ../results/a/s2/w1/run1 \
    ../results/a/s2/w1/run2 \
    ../results/a/s2/w1/run3 \
    --average --std-band --output ../results/a/s2/w1/avg

  # 5. 两步工作流：先对各组求均值，再跨组对比
  #    步骤一：生成各组均值目录（含 avg_*.json 和 avg_*.png）
  python3 plot-results.py \
    ../results/a/s2/w1/run1 ../results/a/s2/w1/run2 ../results/a/s2/w1/run3 \
    --average --output ../results/a/s2/w1/avg
  python3 plot-results.py \
    ../results/b/s2/w1/run1 ../results/b/s2/w1/run2 ../results/b/s2/w1/run3 \
    --average --output ../results/b/s2/w1/avg
  #    步骤二：用均值 JSON 做跨组对比
  python3 plot-results.py \
    ../results/a/s2/w1/avg \
    ../results/b/s2/w1/avg \
    --compare --output ../results/compare/s2_w1_a_vs_b

  # 6. 单组：将多次 run 与其均值曲线叠加对比（验证均值是否有代表性）
  python3 plot-results.py \
    ../results/a/s2/w1/run1 \
    ../results/a/s2/w1/run2 \
    ../results/a/s2/w1/run3 \
    ../results/a/s2/w1/avg \
    --compare --output ../results/a/s2/w1/compare

  # 7. 只绘制指定指标
  python3 plot-results.py ../results/a/s2/w1/run1 \
    --metrics scheduling_throughput scheduling_latency_p90 pending_pods

结果目录结构: ../results/<group>/<scale>/<workload>/run<N>/
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

try:
    import numpy as np
except ImportError:
    print("错误: 需要安装 numpy。运行: pip3 install numpy", file=sys.stderr)
    sys.exit(1)

# ── 指标元数据: 显示名称、Y 轴标签、单位换算 ──
METRIC_META = {
    "scheduling_throughput": {"title": "Scheduling Throughput", "ylabel": "pods/s"},
    "bind_throughput_pods": {"title": "Bind Throughput (Pods)", "ylabel": "pods/s"},
    "bind_throughput_units": {"title": "Bind Throughput (Units)", "ylabel": "units/s"},
    "scheduling_latency_p50": {
        "title": "Scheduling Latency (P50)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "scheduling_latency_p90": {
        "title": "Scheduling Latency (P90)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "scheduling_latency_p99": {
        "title": "Scheduling Latency (P99)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "bind_latency_p50": {
        "title": "Bind Latency (P50)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "bind_latency_p90": {
        "title": "Bind Latency (P90)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "bind_latency_p99": {
        "title": "Bind Latency (P99)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "algorithm_latency_p90": {
        "title": "Algorithm Latency (P90)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "algorithm_latency_p99": {
        "title": "Algorithm Latency (P99)",
        "ylabel": "seconds",
        "scale": 1,
    },
    "scheduling_success_rate": {"title": "Scheduling Success Rate", "ylabel": "ratio"},
    "scheduling_error_rate": {"title": "Scheduling Error Rate", "ylabel": "ratio"},
    "bind_inflight": {"title": "Bind In-flight", "ylabel": "count"},
    "bind_retries": {"title": "Bind Retries", "ylabel": "retries/s"},
    "dispatcher_fallback": {"title": "Dispatcher Fallback", "ylabel": "fallbacks/s"},
    "node_validation_failures": {
        "title": "Node Validation Failures",
        "ylabel": "failures/s",
    },
    "goroutines": {"title": "Goroutines", "ylabel": "count"},
    "pending_pods": {"title": "Pending Pods", "ylabel": "count"},
    "queue_wait_p90": {"title": "Queue Wait (P90)", "ylabel": "seconds"},
    "scheduling_attempts_total": {
        "title": "Scheduling Attempts",
        "ylabel": "attempts/s",
    },
    # 延迟 avg
    "scheduling_latency_avg": {
        "title": "Scheduling Latency (Avg)",
        "ylabel": "seconds",
    },
    "bind_latency_avg": {"title": "Bind Latency (Avg)", "ylabel": "seconds"},
    "bind_unit_latency_p50": {"title": "Bind Unit Latency (P50)", "ylabel": "seconds"},
    "bind_unit_latency_p90": {"title": "Bind Unit Latency (P90)", "ylabel": "seconds"},
    "bind_unit_latency_p99": {"title": "Bind Unit Latency (P99)", "ylabel": "seconds"},
    "bind_unit_latency_avg": {"title": "Bind Unit Latency (Avg)", "ylabel": "seconds"},
    # Pod E2E
    "pod_e2e_latency_p50": {"title": "Pod E2E Latency (P50)", "ylabel": "seconds"},
    "pod_e2e_latency_p90": {"title": "Pod E2E Latency (P90)", "ylabel": "seconds"},
    "pod_e2e_latency_p99": {"title": "Pod E2E Latency (P99)", "ylabel": "seconds"},
    # E2E combined
    "e2e_combined_p90": {"title": "E2E Schedule+Bind Est. (P90)", "ylabel": "seconds"},
    "e2e_combined_p99": {"title": "E2E Schedule+Bind Est. (P99)", "ylabel": "seconds"},
    # SLI
    "sli_latency_p50": {"title": "SLI Scheduling Latency (P50)", "ylabel": "seconds"},
    "sli_latency_p90": {"title": "SLI Scheduling Latency (P90)", "ylabel": "seconds"},
    "sli_latency_p99": {"title": "SLI Scheduling Latency (P99)", "ylabel": "seconds"},
    "sli_latency_avg": {"title": "SLI Scheduling Latency (Avg)", "ylabel": "seconds"},
    # Peak
    "scheduling_peak_throughput": {
        "title": "Peak Scheduling Throughput (30m)",
        "ylabel": "pods/s",
    },
    # 成功率
    "bind_success_rate": {"title": "Bind Success Rate", "ylabel": "ratio"},
    "bind_unit_success_rate": {"title": "Bind Unit Success Rate", "ylabel": "ratio"},
    # 错误
    "bind_rejection_rate": {"title": "Bind Rejection Rate", "ylabel": "rejections/s"},
    "bind_failure_rate": {"title": "Bind Failure Rate", "ylabel": "failures/s"},
    # 吞吐量补充
    "scheduling_throughput_by_result": {
        "title": "Scheduling Attempts by Result",
        "ylabel": "attempts/s",
    },
    "session_throughput": {"title": "Session Throughput", "ylabel": "sessions/s"},
    # Volcano
    "unschedule_task_rate": {"title": "Unschedulable Task Rate", "ylabel": "tasks/s"},
    "unschedule_jobs": {"title": "Unschedulable Jobs", "ylabel": "count"},
    "action_latency_p90": {"title": "Action Latency (P90)", "ylabel": "seconds"},
    "action_latency_p99": {"title": "Action Latency (P99)", "ylabel": "seconds"},
    "task_latency_p90": {"title": "Task Latency (P90)", "ylabel": "seconds"},
    "task_latency_p99": {"title": "Task Latency (P99)", "ylabel": "seconds"},
    "plugin_latency_p90": {"title": "Plugin Latency (P90)", "ylabel": "seconds"},
    # kube / koord
    "extension_point_latency_p90": {
        "title": "Extension Point Latency (P90)",
        "ylabel": "seconds",
    },
    "extension_point_latency_p99": {
        "title": "Extension Point Latency (P99)",
        "ylabel": "seconds",
    },
    "pod_scheduling_attempts_p90": {
        "title": "Pod Scheduling Attempts (P90)",
        "ylabel": "attempts",
    },
    "pod_scheduling_attempts_p99": {
        "title": "Pod Scheduling Attempts (P99)",
        "ylabel": "attempts",
    },
}

# 组标签
GROUP_LABELS = {
    "a": "ENO Scheduler",
    "b": "Godel Scheduler",
    "c": "kube-scheduler",
    "d": "Volcano",
    "e": "Koordinator",
}

# 图表样式
COLORS = ["#2196F3", "#FF5722", "#4CAF50", "#9C27B0", "#FF9800", "#607D8B"]
plt.rcParams.update(
    {
        "figure.figsize": (12, 5),
        "figure.dpi": 150,
        "axes.grid": True,
        "grid.alpha": 0.3,
        "font.size": 11,
        "axes.titlesize": 14,
        "axes.labelsize": 12,
    }
)


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
            label = ", ".join(f"{k}={v}" for k, v in metric.items() if k != "__name__")
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
        ax.text(
            bar.get_width() + 0.3,
            bar.get_y() + bar.get_height() / 2,
            str(count),
            va="center",
            fontsize=7,
        )

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
            print(f"  [ok] {json_file.stem}.{fmt}")
            plotted += 1
        else:
            print(f"  [--] {json_file.stem} (无数据)")
            skipped += 1

    # CSV 文件
    for csv_file in sorted(results_dir.glob("*.csv")):
        out_path = output_dir / f"{csv_file.stem}.{fmt}"
        if plot_utilization_csv(str(csv_file), str(out_path), fmt):
            print(f"  [ok] {csv_file.stem}.{fmt}")
            plotted += 1
        else:
            print(f"  [--] {csv_file.stem} (无数据)")
            skipped += 1

    print(f"\n完成: {plotted} 张图表已导出至 {output_dir}/, {skipped} 个跳过 (空数据)")
    return plotted


def average_runs(dirs, output_dir, metric_names=None, fmt="png", std_band=False):
    """
    平均模式：将多个同组同场景 run 的时间序列在相对时间轴上对齐后逐点平均。

    按 label 字符串分组匹配，避免多 series 指标（goroutines by work、
    scheduling_throughput_by_result by result 等）跨 label 错位合并。

    同时输出 avg_<metric>.json（供 --compare 二次复用）和图片。
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
    STEP = 15  # 公共相对时间轴步长（秒）

    for metric_name in sorted(all_metrics):
        meta = METRIC_META.get(metric_name, {"title": metric_name, "ylabel": ""})
        is_quantile = "latency_p" in metric_name
        is_peak = "peak_throughput" in metric_name

        # ── 1. 收集每个 run 的 series（按 label 索引） ──
        # run_data[run_idx] = {label: (rel_t_array, vals_array)}
        run_data = []
        for d in dirs:
            filepath = Path(d) / f"{metric_name}.json"
            if not filepath.exists():
                run_data.append({})
                continue
            series_list = load_prometheus_json(str(filepath))
            entry = {}
            for label, ts, vals in series_list:
                if not ts:
                    continue
                t0 = ts[0]
                rel_t = np.array([(t - t0).total_seconds() for t in ts])
                entry[label] = (rel_t, np.array(vals))
            run_data.append(entry)

        # 跳过所有 run 都没有数据的指标
        if all(len(e) == 0 for e in run_data):
            continue

        # ── 2. 汇总所有 run 中出现过的 label ──
        all_labels = set()
        for entry in run_data:
            all_labels.update(entry.keys())

        if not all_labels:
            continue

        # ── 3 & 4. 按 label 分别计算各自的 common_t，再插值、平均、绘图 ──
        # common_t 必须在每个 label 内单独计算：不同 label 的持续时长可能差异
        # 很大（如 goroutines 中 work=scheduling 持续 500s 而 work=gc 仅 50s），
        # 若共享一个全局最小值会导致长 label 被大幅截断。
        fig, ax = plt.subplots()
        has_data = False

        # 用于写出 JSON 的中间结果（label → (common_t, mean_vals)）
        label_avg_data = {}

        for li, label in enumerate(sorted(all_labels)):
            # 计算该 label 在各 run 中的末尾相对时间，取最短覆盖为上界
            label_ends = []
            for entry in run_data:
                if label not in entry:
                    continue
                rel_t, _ = entry[label]
                if len(rel_t) > 0:
                    label_ends.append(rel_t[-1])
            if not label_ends:
                continue
            t_end = min(label_ends)
            common_t = np.arange(0, t_end, STEP)
            if len(common_t) < 2:
                continue

            per_run = []
            peak_endpoints = []

            for entry in run_data:
                if label not in entry:
                    continue
                rel_t, vals = entry[label]
                if len(rel_t) < 2:
                    continue
                interpolated = np.interp(
                    common_t, rel_t, vals, left=np.nan, right=np.nan
                )
                per_run.append(interpolated)
                if is_peak:
                    peak_endpoints.append(vals[-1])

            if len(per_run) < 1:
                continue

            stacked = np.array(per_run)
            mean_vals = np.nanmean(stacked, axis=0)
            std_vals = np.nanstd(stacked, axis=0)

            color = COLORS[li % len(COLORS)]
            display = label if label else metric_name
            ax.plot(common_t, mean_vals, label=display, color=color, linewidth=1.5)

            if std_band and len(per_run) > 1:
                ax.fill_between(
                    common_t,
                    mean_vals - std_vals,
                    mean_vals + std_vals,
                    alpha=0.2,
                    color=color,
                )

            # peak 类指标：标注末尾标量均值±std
            if is_peak and peak_endpoints:
                peak_mean = np.mean(peak_endpoints)
                peak_std = np.std(peak_endpoints)
                ax.axhline(
                    peak_mean, color=color, linestyle="--", linewidth=1, alpha=0.7
                )
                ax.text(
                    common_t[-1] * 0.02,
                    peak_mean,
                    f"peak={peak_mean:.1f}±{peak_std:.1f}",
                    color=color,
                    fontsize=8,
                    va="bottom",
                )

            label_avg_data[label] = (common_t, mean_vals)
            has_data = True

        if not has_data:
            plt.close(fig)
            continue

        title = meta["title"]
        ax.set_title(title)
        if is_quantile:
            ax.set_title(
                f"{title}\n(mean of quantile across runs, not combined-sample quantile)",
                fontsize=11,
            )
        ax.set_ylabel(meta["ylabel"])
        ax.set_xlabel("Relative Time (s)")
        if len(all_labels) > 1 or (all_labels and next(iter(all_labels))):
            ax.legend(loc="best", fontsize=9)
        fig.tight_layout()

        out_img = output_dir / f"{metric_name}.{fmt}"
        fig.savefig(str(out_img), format=fmt, bbox_inches="tight")
        plt.close(fig)

        # ── 5. 写出 avg_<metric>.json 供 --compare 复用 ──
        # 格式模拟 Prometheus query_range 响应。
        # 时间戳存为相对秒数偏移量叠加在 EPOCH_BASE 上，使 load_prometheus_json
        # 解析后 X 轴从 EPOCH_BASE 对齐，多组对比时坐标轴一致（均从 t=0 出发）。
        EPOCH_BASE = 0  # 用 Unix 时间 0（1970-01-01 UTC）作为相对时间起点
        result_series = []
        for label in sorted(all_labels):
            if label not in label_avg_data:
                continue
            common_t_l, mean_vals = label_avg_data[label]
            metric_dict = {}
            if label:
                for part in label.split(", "):
                    if "=" in part:
                        k, v = part.split("=", 1)
                        metric_dict[k] = v
            values = [
                [EPOCH_BASE + int(t), str(round(float(v), 6))]
                for t, v in zip(common_t_l, mean_vals)
                if not np.isnan(v)
            ]
            result_series.append({"metric": metric_dict, "values": values})

        avg_json = {
            "status": "success",
            "data": {"resultType": "matrix", "result": result_series},
        }
        out_json = output_dir / f"{metric_name}.json"
        with open(str(out_json), "w") as f:
            json.dump(avg_json, f)

        print(f"  [ok] {metric_name}.{fmt}")
        plotted += 1

    print(f"\n完成: {plotted} 张平均图表已导出至 {output_dir}/")
    return plotted


def compare_groups(dirs, output_dir, metric_names=None, fmt="png", label_mode="scheduler"):
    """
    对比模式: 将多个组的同名指标画在同一张图上。
    dirs: list of result directories (e.g., results/a/s2/w1/run1, results/b/s2/w1/run1)
    label_mode: "scheduler" 用 GROUP_LABELS 显示调度器名（默认），"path" 用目录路径显示
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

            # 图例标签：scheduler 模式用 GROUP_LABELS，path 模式用目录路径最后两段
            if label_mode == "path":
                parts = Path(d).parts
                group_label = "/".join(parts[-2:]) if len(parts) >= 2 else str(d)
            else:
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
                t0 = ts[0]
                rel_t = [(t - t0).total_seconds() for t in ts]
                ax.plot(rel_t, vals, label=display, color=color, linewidth=1.5)
                has_data = True

        if not has_data:
            plt.close(fig)
            continue

        ax.set_title(meta["title"])
        ax.set_ylabel(meta["ylabel"])
        ax.set_xlabel("Relative Time (s)")
        ax.legend(loc="best", fontsize=9)
        fig.tight_layout()

        out_path = output_dir / f"compare_{metric_name}.{fmt}"
        fig.savefig(str(out_path), format=fmt, bbox_inches="tight")
        plt.close(fig)
        print(f"  [ok] compare_{metric_name}.{fmt}")
        plotted += 1

    print(f"\n完成: {plotted} 张对比图表已导出至 {output_dir}/")
    return plotted


def main():
    parser = argparse.ArgumentParser(
        description="将 Prometheus 导出的 JSON 数据绘制为图表"
    )
    parser.add_argument(
        "dirs",
        nargs="+",
        help="一个或多个结果目录 (results/<group>/<scale>/<workload>/<run>)",
    )
    parser.add_argument(
        "--output", "-o", default=None, help="输出目录 (默认: <results_dir>/charts)"
    )
    parser.add_argument(
        "--format",
        "-f",
        default="png",
        choices=["png", "pdf", "svg"],
        help="输出格式 (默认: png)",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="对比模式: 多个目录的同名指标画在同一张图",
    )
    parser.add_argument(
        "--average",
        action="store_true",
        help="平均模式: 多个同组 run 的时间序列对齐后逐点平均，输出均值曲线",
    )
    parser.add_argument(
        "--std-band",
        action="store_true",
        help="在平均曲线上绘制 ±1σ 标准差区域（需与 --average 同用）",
    )
    parser.add_argument(
        "--metrics", nargs="*", default=None, help="仅绘制指定指标 (默认: 全部)"
    )
    parser.add_argument(
        "--label-mode",
        default="scheduler",
        choices=["scheduler", "path"],
        help="对比图图例标签: scheduler=调度器名 (默认), path=目录路径",
    )

    args = parser.parse_args()

    if args.compare:
        if len(args.dirs) < 2:
            parser.error("对比模式需要至少 2 个结果目录")
        out = args.output or "charts_compare"
        print(f"对比模式: {len(args.dirs)} 个目录\n")
        compare_groups(args.dirs, out, args.metrics, args.format, args.label_mode)
    elif args.average:
        if len(args.dirs) < 2:
            parser.error("平均模式需要至少 2 个结果目录")
        out = args.output or "charts_average"
        print(f"平均模式: {len(args.dirs)} 个 run\n")
        average_runs(args.dirs, out, args.metrics, args.format, args.std_band)
    else:
        for d in args.dirs:
            print(f"\n绘制: {d}")
            plot_directory(d, args.output, args.format)


if __name__ == "__main__":
    main()
