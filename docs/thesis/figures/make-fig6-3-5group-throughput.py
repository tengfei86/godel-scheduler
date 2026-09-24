#!/usr/bin/env python3
"""make-fig6-3-5group-throughput.py — 生成五组调度器有效吞吐对比柱状图

用于图 6-3（新增）。数据口径与 §6.3 一致：
  有效吞吐 = 名义工作量 / 该次 run 的完成时间（metadata.txt 的 total / duration）
  每条 run 独立计算，同一场景 3 次重复取中位数。

场景固定为 §6.2.3 表 6-4 中的序号 1~5「全组基线」：
  s1/w1、s2/w2、s2/w3、s3/w2、s3/w3
调度器组包括 a=ENO / b=Gödel / c=kube-scheduler / d=Volcano / e=Koordinator。
a、b 从 inst1 子目录读取；c、d、e 无 inst 子目录，直接读 runN。

用法:
  python3 make-fig6-3-5group-throughput.py                     # 默认输出至同目录
  python3 make-fig6-3-5group-throughput.py --out /tmp/out.png  # 指定输出
"""

from __future__ import annotations

import argparse
import statistics
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

matplotlib.rcParams["font.sans-serif"] = [
    "PingFang SC",
    "Arial Unicode MS",
    "Heiti SC",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False

RESULTS_DIR = (
    Path(__file__).resolve().parent.parent.parent.parent
    / "test"
    / "e2e"
    / "benchmark"
    / "results"
)
OUT_DEFAULT = Path(__file__).resolve().parent / "fig6-3-throughput-5group.png"

SCENARIOS = ["s1_w1", "s2_w2", "s2_w3", "s3_w2", "s3_w3"]
# 统一色板 (tab10, 与 fig6-30 及其他柱状图一致)
GROUPS = [
    ("a", "ENO",            "#1f77b4"),   # tab:blue,   主 focus
    ("b", "Gödel",          "#7f7f7f"),   # tab:gray,   参照基线
    ("c", "kube-scheduler", "#ff7f0e"),   # tab:orange
    ("d", "Volcano",        "#2ca02c"),   # tab:green
    ("e", "Koordinator",    "#9467bd"),   # tab:purple
]


def scenario_sub(group: str, scenario: str) -> str:
    scale, workload = scenario.split("_", 1)
    if group in ("a", "b"):
        return f"{scale}/{workload}/inst1"
    return f"{scale}/{workload}"


def effective_throughput(group: str, sub: str) -> float | None:
    values = []
    for run in (1, 2, 3):
        meta = RESULTS_DIR / group / sub / f"run{run}" / "metadata.txt"
        if not meta.exists():
            continue
        fields = dict(
            line.split("=", 1)
            for line in meta.read_text().splitlines()
            if "=" in line
        )
        try:
            values.append(int(fields["total"]) / int(fields["duration"]))
        except (KeyError, ValueError, ZeroDivisionError):
            continue
    return statistics.median(values) if values else None


def collect() -> dict[str, list[float | None]]:
    data: dict[str, list[float | None]] = {}
    for group, _label, _color in GROUPS:
        row = []
        for scenario in SCENARIOS:
            sub = scenario_sub(group, scenario)
            row.append(effective_throughput(group, sub))
        data[group] = row
    return data


def render(data: dict[str, list[float | None]], out: Path) -> None:
    fig, ax = plt.subplots(figsize=(13, 6), dpi=200)
    fig.subplots_adjust(left=0.06, right=0.985, top=0.9383, bottom=0.1217)

    n_groups = len(GROUPS)
    width = 0.15
    x = list(range(len(SCENARIOS)))

    all_values = [v for row in data.values() for v in row if v is not None]
    y_max = max(all_values) * 1.10

    for i, (group, label, color) in enumerate(GROUPS):
        offset = (i - (n_groups - 1) / 2) * width
        positions = [xi + offset for xi in x]
        heights = [(v if v is not None else 0.0) for v in data[group]]
        bars = ax.bar(positions, heights, width, color=color, label=f"{label} ({group})")
        for bar, v in zip(bars, data[group]):
            if v is None:
                continue
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height() + y_max * 0.008,
                f"{v:.0f}",
                ha="center",
                va="bottom",
                fontsize=8,
                color="#333333",
            )

    ax.set_xticks(x)
    ax.set_xticklabels(
        [s.replace("_", "/") for s in SCENARIOS], rotation=0, fontsize=11
    )
    ax.set_ylabel("有效吞吐 (pods/s)", fontsize=11)
    ax.set_title(
        "五组调度器有效吞吐对比（全组基线场景，总工作量 / 总完成时间，n=3 中位数）",
        fontsize=12.5,
    )
    ax.set_ylim(0, y_max)
    ax.legend(loc="upper right", frameon=False, fontsize=10, ncol=5)
    ax.grid(axis="y", linestyle=":", linewidth=0.6, alpha=0.5)
    ax.set_axisbelow(True)

    fig.savefig(out)
    plt.close(fig)
    print(f"已写出 {out}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="生成图 6-3 五组调度器有效吞吐对比柱状图"
    )
    parser.add_argument("--out", type=Path, default=OUT_DEFAULT)
    args = parser.parse_args()

    data = collect()
    for group, label, _color in GROUPS:
        row = data[group]
        summary = ", ".join(
            f"{s}={v:.1f}" if v is not None else f"{s}=n/a"
            for s, v in zip(SCENARIOS, row)
        )
        print(f"  {group} ({label}): {summary}")
    render(data, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
