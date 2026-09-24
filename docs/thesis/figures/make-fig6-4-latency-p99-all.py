#!/usr/bin/env python3
"""make-fig6-4-latency-p99-all.py — 生成全 15 场景 a/b P99 调度延迟对比柱状图

用于图 6-4（新增，鸟瞰图）。数据与 §6.4.2 表 6-6 一致，通过 latency-compare.py
的 JSON 输出读取，保证与表值同源。

场景顺序与表 6-6 一致（跳过 s1/w1，因为 a 侧 P99 数据点不足）：
  s2/w2, s2/w3, s3/w2, s3/w3, s3/w3_inst3, s3/w4_inst3, s3/w5_inst3,
  s3/w6, s3/w6_inst3, s3/w7_inst3, s4/w3_inst3, s4/w4_inst3, s4/w5_inst3,
  s4/w6_inst3, s4/w7_inst3

纵轴采用 log 刻度（延迟从 0.015 s 到 32 s，跨 2000 倍）。

用法:
  python3 make-fig6-4-latency-p99-all.py
  python3 make-fig6-4-latency-p99-all.py --out /tmp/x.png
"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import matplotlib.ticker as mticker  # noqa: E402

matplotlib.rcParams["font.sans-serif"] = [
    "PingFang SC",
    "Arial Unicode MS",
    "Heiti SC",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False

ROOT = Path(__file__).resolve().parent.parent.parent.parent
LATENCY_COMPARE = ROOT / "test" / "e2e" / "benchmark" / "collect" / "latency-compare.py"
OUT_DEFAULT = Path(__file__).resolve().parent / "fig6-4-latency-p99-all.png"

ENO_COLOR = "#1f77b4"    # tab:blue, 与 fig6-30 统一
GODEL_COLOR = "#7f7f7f"  # tab:gray, 参照基线

# 表 6-6 场景顺序（跳过 s1/w1，因为 a 侧 P99 数据点不足）
SCENARIOS = [
    ("s2_w2",        "s2/w2\ninst1"),
    ("s2_w3",        "s2/w3\ninst1"),
    ("s3_w2",        "s3/w2\ninst1"),
    ("s3_w3",        "s3/w3\ninst1"),
    ("s3_w3_inst3",  "s3/w3\ninst3"),
    ("s3_w4_inst3",  "s3/w4\ninst3"),
    ("s3_w5_inst3",  "s3/w5\ninst3"),
    ("s3_w6",        "s3/w6\ninst1"),
    ("s3_w6_inst3",  "s3/w6\ninst3"),
    ("s3_w7_inst3",  "s3/w7\ninst3"),
    ("s4_w3_inst3",  "s4/w3\ninst3"),
    ("s4_w4_inst3",  "s4/w4\ninst3"),
    ("s4_w5_inst3",  "s4/w5\ninst3"),
    ("s4_w6_inst3",  "s4/w6\ninst3"),
    ("s4_w7_inst3",  "s4/w7\ninst3"),
]


def collect() -> tuple[list[str], list[float], list[float]]:
    with tempfile.NamedTemporaryFile("w+", suffix=".json") as fp:
        subprocess.run(
            ["python3", str(LATENCY_COMPARE), "--json", fp.name],
            check=True,
            capture_output=True,
        )
        data = json.loads(Path(fp.name).read_text())

    lookup: dict[str, tuple[float | None, float | None]] = {}
    for row in data["results"]:
        if row["metric"] != "scheduling_latency_p99":
            continue
        lookup[row["scenario"]] = (row["a_value"], row["b_value"])

    labels, eno, godel = [], [], []
    for scenario, label in SCENARIOS:
        a, b = lookup.get(scenario, (None, None))
        if a is None or b is None:
            print(f"  [skip] {scenario}: a={a} b={b}")
            continue
        labels.append(label)
        eno.append(a)
        godel.append(b)
    return labels, eno, godel


def render(labels: list[str], eno: list[float], godel: list[float], out: Path) -> None:
    fig, ax = plt.subplots(figsize=(14, 6.5), dpi=200)
    fig.subplots_adjust(left=0.06, right=0.985, top=0.9383, bottom=0.15)

    x = list(range(len(labels)))
    width = 0.4
    bars_a = ax.bar(
        [i - width / 2 for i in x], eno, width, color=ENO_COLOR, label="ENO (a)"
    )
    bars_b = ax.bar(
        [i + width / 2 for i in x], godel, width, color=GODEL_COLOR, label="Gödel (b)"
    )

    ax.set_yscale("log")
    ax.set_ylim(0.01, 100)
    ax.yaxis.set_major_locator(mticker.LogLocator(base=10, numticks=6))
    ax.yaxis.set_major_formatter(mticker.FormatStrFormatter("%.2g"))
    ax.set_ylabel("P99 调度延迟 (秒，log 刻度)", fontsize=11)

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_title(
        "全场景 ENO 与 Gödel P99 调度延迟对比（scheduling_latency_p99，n=3 中位数）",
        fontsize=12.5,
    )
    ax.legend(loc="upper right", frameon=False, fontsize=10)
    ax.grid(axis="y", which="both", linestyle=":", linewidth=0.5, alpha=0.5)
    ax.set_axisbelow(True)

    # 每根柱顶端标注具体数值
    for bar_group, values in ((bars_a, eno), (bars_b, godel)):
        for bar, v in zip(bar_group, values):
            if v is None:
                continue
            fmt = f"{v:.3f}" if v < 1 else (f"{v:.2f}" if v < 10 else f"{v:.1f}")
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                v * 1.08,
                fmt,
                ha="center",
                va="bottom",
                fontsize=7.5,
                color="#333333",
            )

    fig.savefig(out)
    plt.close(fig)
    print(f"已写出 {out}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="生成图 6-4 全场景 ENO/Gödel P99 调度延迟对比柱状图"
    )
    parser.add_argument("--out", type=Path, default=OUT_DEFAULT)
    args = parser.parse_args()

    labels, eno, godel = collect()
    print(f"  场景数 {len(labels)}, ENO {min(eno):.3f}~{max(eno):.3f} s, "
          f"Gödel {min(godel):.3f}~{max(godel):.3f} s")
    render(labels, eno, godel, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
