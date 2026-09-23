#!/usr/bin/env python3
"""图 6-30：Layer 0 与 Layer 3 故障注入的三项对比 (完成时间 / 恢复延时 / 分实例接管)."""
from pathlib import Path
import matplotlib
import matplotlib.pyplot as plt
import numpy as np

# 中文字体：macOS 优先 PingFang, Linux 优先 Noto CJK; 找不到就退回默认（会有 warning 但仍能出图）
for f in ["PingFang SC", "Arial Unicode MS", "Heiti SC", "Songti SC",
          "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei"]:
    try:
        matplotlib.font_manager.findfont(f, fallback_to_default=False)
        plt.rcParams["font.sans-serif"] = [f]
        break
    except Exception:
        continue
plt.rcParams["axes.unicode_minus"] = False

# 直接把测得的关键值硬编码, 避免脚本依赖 run 目录 (数据来源: report-20260923-213422.md)
BASELINE_DUR = 680  # a/s2/w2/inst3 无故障
L0_DUR = 683        # Layer 0 单次注入
L3_DUR = 784        # Layer 3 单次注入 (含 180s outage)
L3_OUTAGE = 189     # restored_ts - killed_ts

L0_NVF = 300        # Layer 0 90s 拦截数
L0_DFB = 300
L0_PATCHED = 100

# Layer 3 per-scheduler bind rate over [inject, inject+90s]
L3_PODS = {
    "scheduler-0 (killed)": 68,
    "scheduler-0 (replaced)": 0,     # 复活后 90s 内还没充分接管
    "scheduler-1 (survivor)": 6234,
    "scheduler-2 (survivor)": 2172,
}

OUT = Path(__file__).resolve().parents[1] / "fig6-30-fault-recovery-comparison.png"

fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.2))

# ── 左：完成时间对比 (baseline / Layer 0 / Layer 3) ──
ax = axes[0]
labels = ["baseline\n无故障", "Layer 0\n(node 归属漂移)", "Layer 3\n(实例失活)"]
values = [BASELINE_DUR, L0_DUR, L3_DUR]
colors = ["#7f7f7f", "#1f77b4", "#d62728"]
bars = ax.bar(labels, values, color=colors, width=0.55)
for bar, v in zip(bars, values):
    pct = 100 * (v - BASELINE_DUR) / BASELINE_DUR
    label = f"{v}s"
    if pct != 0:
        label += f"\n({pct:+.1f}%)"
    ax.text(bar.get_x() + bar.get_width() / 2, v + 15, label,
            ha="center", va="bottom", fontsize=9)
ax.set_ylabel("总耗时 (s)")
ax.set_title("(a) 完成时间 vs 无故障基线")
ax.set_ylim(0, max(values) * 1.15)
ax.grid(axis="y", alpha=0.3)

# ── 中：Layer 0 拦截规模 vs patched 节点 ──
ax = axes[1]
labels = ["patched\n节点数",
          "Layer 0\n拦截次数",
          "Dispatcher\n回退次数"]
values = [L0_PATCHED, L0_NVF, L0_DFB]
colors = ["#8c564b", "#1f77b4", "#ff7f0e"]
bars = ax.bar(labels, values, color=colors, width=0.55)
for bar, v in zip(bars, values):
    ax.text(bar.get_x() + bar.get_width() / 2, v + 8, f"{v}",
            ha="center", va="bottom", fontsize=9)
ax.set_ylabel("事件数 (inject 后 90s 累计)")
ax.set_title("(b) Layer 0 拦截规模")
ax.set_ylim(0, max(values) * 1.2)
ax.grid(axis="y", alpha=0.3)

# ── 右：Layer 3 分实例接管量 (inject 后 90s) ──
ax = axes[2]
pods = list(L3_PODS.keys())
binds = list(L3_PODS.values())
colors3 = ["#d62728", "#ff9896", "#2ca02c", "#98df8a"]
bars = ax.barh(range(len(pods)), binds, color=colors3, height=0.6)
for bar, v in zip(bars, binds):
    ax.text(v + 60, bar.get_y() + bar.get_height() / 2, f"{v} pods",
            va="center", fontsize=9)
ax.set_yticks(range(len(pods)))
ax.set_yticklabels(pods, fontsize=9)
ax.set_xlabel("绑定量 (pods, inject 后 90s 累计)")
ax.set_title("(c) Layer 3 分实例接管")
ax.set_xlim(0, max(binds) * 1.25)
ax.grid(axis="x", alpha=0.3)
ax.invert_yaxis()
# 图注：90s 窗口只覆盖接管初期, 剩余 pod 在 180s outage 结束后被 Reconciler
# 唤醒重排; 全 run 合计 ≈ 49607/50000 (差额来自 Prom counter 采样漂移),
# apiserver 不变量 I 严格 50000/50000。
ax.text(0.5, -0.28,
        f"窗口小计 {sum(binds)} pods (≈ workload {sum(binds)/500:.0f}% ). "
        "余下 pod 在 outage 结束后经 Reconciler 唤醒重排完成; "
        "全 run 合计 ≈ 49607/50000 (差额为 Prom counter 采样漂移, "
        "不变量 I 由 apiserver 严格断言 50000/50000)",
        transform=ax.transAxes, fontsize=7, ha="center", va="top",
        color="#555555", wrap=True)

fig.suptitle("图 6-30  Layer 0 / Layer 3 故障注入三项定量对比 (s2/w2/inst3, n=1)",
             fontsize=11)
plt.tight_layout(rect=[0, 0.04, 1, 0.94])

fig.savefig(OUT, dpi=160)
print(f"写入 {OUT}")
