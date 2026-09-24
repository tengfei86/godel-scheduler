#!/usr/bin/env python3
"""make-fig6-3.py — 生成图 6-3「各场景有效吞吐对比」柱状图

数据口径（与第 6 章 §6.3 一致）：
  有效吞吐 = 名义工作量 / 该次 run 的完成时间（metadata.txt 的 total / duration），
  每条 run 独立计算，同一场景 3 次重复取中位数。
  场景清单以 test/e2e/benchmark/results/compare/ 下的目录名为准。

用法：
  MPLCONFIGDIR=<可写目录> python3 make-fig6-3.py            # 写 fig6-3-effective-throughput.png
  python3 make-fig6-3.py --out /tmp/x.png                   # 指定输出
  python3 make-fig6-3.py --legacy-values                     # 用重采前的 w6 旧值渲染（用于校验脚本与旧图一致）

图形参数（figsize/dpi/配色/边距）按原图实测标定：
  2600×1200 px = 13×6 in @ 200 dpi；轴框 x∈[133,2570]、y∈[74,1054]；
  条形色 #2E5C8A（ENO）与 #B0B0B0（Gödel）；分组柱相邻，标签 45° 旋转。
"""

from __future__ import annotations

import argparse
import statistics
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

# 中文字形：plot-venv 自带的字体集没有中文字形，须显式指定系统 CJK 字体，
# 否则标题/纵轴标签会渲染成方框（tofu）
matplotlib.rcParams["font.sans-serif"] = [
    "PingFang SC",
    "Hiragino Sans GB",
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
COMPARE_DIR = RESULTS_DIR / "compare"
OUT_DEFAULT = Path(__file__).resolve().parent / "fig6-3-effective-throughput.png"

ENO_COLOR = "#1f77b4"    # tab:blue, 与 fig6-30 统一
GODEL_COLOR = "#7f7f7f"  # tab:gray, 参照基线

# 重采前的 w6 旧值（10 000 Pod 规模），仅用于 --legacy-values 校验脚本还原度
LEGACY = {
    "s3_w6": (333.3, 263.2),
    "s3_w6_inst3": (344.8, 256.4),
    "s4_w6_inst3": (322.6, 263.2),
}


def scenario_path(name: str) -> tuple[str, str, str]:
    scale, rest = name.split("_", 1)
    if rest.endswith("_inst3"):
        return scale, rest[: -len("_inst3")], "inst3"
    return scale, rest, "inst1"


def effective_throughput(group: str, sub: str) -> float | None:
    values = []
    for run in (1, 2, 3):
        meta = RESULTS_DIR / group / sub / f"run{run}" / "metadata.txt"
        if not meta.exists():
            continue
        fields = dict(
            line.split("=", 1) for line in meta.read_text().splitlines() if "=" in line
        )
        try:
            values.append(int(fields["total"]) / int(fields["duration"]))
        except (KeyError, ValueError, ZeroDivisionError):
            continue
    return statistics.median(values) if values else None


def collect(legacy: bool = False) -> tuple[list[str], list[float], list[float]]:
    labels, eno, godel = [], [], []
    for path in sorted(COMPARE_DIR.iterdir()):
        if not path.is_dir() or path.name.startswith("."):
            continue
        scale, workload, inst = scenario_path(path.name)
        sub = f"{scale}/{workload}/{inst}"
        if legacy and path.name in LEGACY:
            a, b = LEGACY[path.name]
        else:
            a = effective_throughput("a", sub)
            b = effective_throughput("b", sub)
        if a is None or b is None:
            print(f"  [skip] {path.name}: 缺少 a/b 元数据")
            continue
        labels.append(path.name)
        eno.append(a)
        godel.append(b)
    return labels, eno, godel


def render(labels: list[str], eno: list[float], godel: list[float], out: Path) -> None:
    fig, ax = plt.subplots(figsize=(13, 6), dpi=200)
    # 轴框位置按原图实测值标定
    fig.subplots_adjust(left=0.0512, right=0.9885, top=0.9383, bottom=0.1217)

    x = range(len(labels))
    # 柱宽 0.377 与原图实测一致（每组两柱共 106 px，组距 140.5 px @2600 px 宽）
    width = 0.377
    ax.bar([i - width / 2 for i in x], eno, width, color=ENO_COLOR, label="ENO (a)")
    ax.bar([i + width / 2 for i in x], godel, width, color=GODEL_COLOR, label="Gödel (b)")

    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, rotation=45, ha="right", fontsize=10)
    ax.set_ylabel("有效吞吐 (pods/s)", fontsize=11)
    ax.set_title(
        "各场景有效吞吐对比（总工作量 / 总完成时间，3 次重复取中位数）", fontsize=12.5
    )
    ax.set_ylim(0, max(eno + godel) * 1.05)
    ax.legend(loc="upper right", frameon=False, fontsize=10)

    fig.savefig(out)
    plt.close(fig)
    print(f"已写出 {out}")


def main() -> int:
    parser = argparse.ArgumentParser(description="生成图 6-3 有效吞吐柱状图")
    parser.add_argument("--out", type=Path, default=OUT_DEFAULT)
    parser.add_argument(
        "--legacy-values",
        action="store_true",
        help="使用重采前的 w6 旧值（校验脚本与原图一致）",
    )
    args = parser.parse_args()

    if not COMPARE_DIR.is_dir():
        print(f"错误: 找不到场景目录 {COMPARE_DIR}")
        return 1
    labels, eno, godel = collect(legacy=args.legacy_values)
    print(f"场景数 {len(labels)}，ENO 中位吞吐 {min(eno):.1f}~{max(eno):.1f} pods/s")
    render(labels, eno, godel, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
