#!/usr/bin/env python3
"""make-slides.py — 生成硕士学位论文答辩 PPT（16:9，25 页正文 + 6 页 Backup）

数据来源：论文第 6 章与《答辩 PPT 大纲》唯一事实来源清单；所有数字原样引用，
不重绘数据图（直接嵌入 docs/thesis/figures/ 下的论文原图）。

用法：
  MPLCONFIGDIR=... tools/plot-venv/bin/python docs/thesis/defense/make-slides.py
输出：
  docs/thesis/defense/答辩PPT-基于etcd的分布式Kubernetes调度器.pptx
  docs/thesis/defense/outline.md   （逐页提要，便于校对）
"""

from __future__ import annotations

import sys
from pathlib import Path

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE
from pptx.dml.color import RGBColor
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt
from PIL import Image

HERE = Path(__file__).resolve().parent
FIG = HERE.parent / "figures"
ASSETS = HERE / "assets"
OUT_PPTX = HERE / "答辩PPT-基于etcd的分布式Kubernetes调度器.pptx"
OUT_MD = HERE / "outline.md"

# --template <pptx>：用该模板的母版/主题/配色重新出图（内容不变）
TEMPLATE_PATH: Path | None = None
_args = sys.argv[1:]
for _i, _a in enumerate(_args):
    if _a == "--template" and _i + 1 < len(_args):
        TEMPLATE_PATH = Path(_args[_i + 1])
    elif _a == "-o" and _i + 1 < len(_args):
        OUT_PPTX = Path(_args[_i + 1])

# ── 配色（设计规范） ──
C = dict(
    navy=RGBColor(0x0B, 0x2A, 0x4A),
    blue=RGBColor(0x1F, 0x5C, 0x99),
    orange=RGBColor(0xE8, 0x83, 0x3A),
    green=RGBColor(0x2E, 0x9E, 0x6B),
    red=RGBColor(0xC0, 0x39, 0x2B),
    white=RGBColor(0xFF, 0xFF, 0xFF),
    light=RGBColor(0xF5, 0xF7, 0xFA),
    text=RGBColor(0x33, 0x33, 0x33),
    muted=RGBColor(0x56, 0x64, 0x74),
    line=RGBColor(0xD8, 0xDF, 0xE8),
)
if TEMPLATE_PATH:
    # 取自模板：标题/装饰 #113E6A，强调 #0070C0，正文 #2E2C2C，浅灰 #F2F4F7
    C = dict(
        navy=RGBColor(0x11, 0x3E, 0x6A),
        blue=RGBColor(0x00, 0x70, 0xC0),
        orange=RGBColor(0x00, 0x70, 0xC0),
        green=RGBColor(0x00, 0x70, 0xC0),
        red=RGBColor(0xC0, 0x00, 0x00),
        white=RGBColor(0xFF, 0xFF, 0xFF),
        light=RGBColor(0xF2, 0xF4, 0xF7),
        light2=RGBColor(0xEA, 0xEF, 0xF4),      # 模板浅钢蓝块
        soft=RGBColor(0xD6, 0xE3, 0xF0),        # 模板浅蓝描边
        text=RGBColor(0x2E, 0x2C, 0x2C),
        muted=RGBColor(0x63, 0x63, 0x63),
        line=RGBColor(0xD9, 0xDE, 0xE5),
    )

EA_FONT = "微软雅黑"
LATIN_FONT = "Arial"
TOTAL = 25
# 页脚（左侧论文简称 + 分隔线）由作者要求关闭；如需恢复改为 True 即可
SHOW_FOOTER = False
# 右下角只保留页码（作者要求「把当前页数加上」）
SHOW_PAGE_NO = True

# ── 逐页内容 ────────────────────────────────────────────────────────────
# kind: cover / bullets / figure / twopic / stats / table / cards / thanks
SLIDES: list[dict] = [
    dict(
        n=1, kind="cover",
        title="基于 etcd 的分布式 Kubernetes 调度器研究与实现",
        core="硕士学位论文答辩",
        meta=["答辩人：[姓名]", "指导教师：[导师]", "学院：[学院]", "日期：[日期]"],
        notes="各位老师上午好。我的论文题目是《基于 etcd 的分布式 Kubernetes 调度器研究与实现》。"
              "这项工作要解决的是一个很具体的问题：分布式调度器把绑定这一环拆出去之后，吞吐上不去、"
              "一致性也守不住。我用一句话概括：把 Binder 从独立进程合并回 Scheduler，再用四层机制守住"
              "“至多绑定一次”。接下来的十八分钟，我只讲三件事——问题、方法、证据。",
        source="封面",
    ),
    dict(
        n=2, kind="stats",
        title="让分布式调度“跑得快”且“绑得对”",
        core="把 Binder 合并进 Scheduler 进程，用 etcd 原子语义守住“至多绑定一次”",
        stats=[("16", "对比场景"), ("144", "次 run"), ("100%", "绑定成功率")],
        bullets=["Q1 性能：独立 Binder 的跨进程瓶颈", "Q2 一致性：分区归属漂移下的不变量", "方法 + 四层容错 + 实证闭环"],
        notes="先给全篇一个抓手。左边是我要回答的两个问题：性能上，独立部署的 Binder 在高并发下重新变成串行瓶颈；"
              "一致性上，节点分区归属会动态漂移，必须保证任一 Pod 至多绑定一次。右边是证据规模：16 个对比场景、"
              "144 次 run、绑定成功率 100%。后面每一页都在为这三个数字服务。",
        source="第 6 章总览；表 6-1",
    ),
    dict(
        n=3, kind="cards",
        title="单实例调度器的三堵墙",
        core="吞吐见顶、尾延迟随规模抬升、Leader Election 天然单点",
        cards=[("吞吐上限", "activeQ 串行取 Pod，多核用不满"),
               ("尾延迟抬升", "Filter/Score 随节点数增长，P99 上涨"),
               ("单点故障", "Leader Election 只有一个活跃实例")],
        notes="原生 kube-scheduler 是三堵墙叠在一起。第一，调度主循环从 activeQ 串行取 Pod，CPU 核数再多也用不上。"
              "第二，Filter 与 Score 的代价随节点数增长，节点越多尾延迟越高。第三，Leader Election 保证同一时刻"
              "只有一个活跃实例，这是一致性的来源，但也意味着单点故障。所以大家才去做分布式，而分布式又带来新问题。",
        source="1.1 节；2.2 节",
    ),
    dict(
        n=4, kind="figure",
        title="分布式改造真正的难点在“绑定阶段”",
        core="Gödel 用三层解耦拿到并发，但 Binder 独立部署与分区漂移留下两个缺口",
        figure="fig5-1a-shared-binder.png",
        bullets=["Q1 独立 Binder 重新引入串行化", "Q2 归属漂移缺乏完整一致性论证", "本文定位：把绑定拉回进程内"],
        notes="Gödel 是这个方向最有代表性的开源实现：Dispatcher 分发、Scheduler 决策、Binder 落盘，再加节点分区，"
              "并发确实上来了。但它留下两个缺口。一是 Binder 独立部署，绑定阶段又变成跨进程的串行环节，"
              "高并发下成为瓶颈。二是节点分区归属会漂移，这一场景下的严格一致性缺少完整论证。本文的两个问题"
              "就直接对着这两个缺口。",
        source="1.2 节；2.3 节；图 5-1a（原文 fig5-1a）",
    ),
    dict(
        n=5, kind="figure",
        title="Dispatcher 内部流程",
        core="先校验归属、再选分区、然后入队——它不选节点，只决定 Pod 去哪",
        figure="fig3-3-dispatcher-flow.png",
        fig_geometry=(5.35, 1.82, 7.35, 4.65),
        bullets_width=4.55,
        bullets=["归属校验：把漂移的 Pod 拦住", "分区选择：按实例负载均衡", "入队：交给对应 Scheduler 实例"],
        notes="先看 Dispatcher 的内部流程。它进来先做归属校验，把分区漂移的 Pod 拦住；再按实例负载做分区选择，"
              "决定这个 Pod 交给哪个 Scheduler；然后入队。注意它不选节点，只决定 Pod 去哪，选节点是下一环的事。",
        source="3.3 节；图 3-3",
    ),
    dict(
        n=5.5, kind="figure",
        title="Scheduler 内部流程",
        core="Filter → Score → Reserve → Permit，产出目标节点后交给 Binder 落盘",
        figure="fig3-4-scheduler-flow.png",
        fig_geometry=(5.35, 1.82, 7.35, 4.65),
        bullets_width=4.55,
        bullets=["Filter：在分区内过滤候选节点", "Score：打分选出最优节点", "Reserve/Permit 后交 Binder"],
        notes="再看 Scheduler。它在自己分区内跑 Filter 过滤候选节点，Score 打分选最优，Reserve 预留资源，Permit 放行，"
              "产出目标节点后交给 Binder 落盘。落盘走 dispatching、assuming、binding 三步事务，这是后面一致性的抓手。",
        source="3.4 节；图 3-4",
    ),
    dict(
        n=6, kind="figure",
        title="三层职责：Dispatcher 管分区、Scheduler 管决策、Binder 管落盘",
        core="分区之间无锁并发，状态推进全部由 Watch 事件驱动",
        figure="fig3-1-system-arch.png",
        bullets=["Dispatcher：分区分配与回退", "Scheduler：Filter/Score/Reserve", "Binder：Bind 原子写与失败处理"],
        notes="这是系统总体架构。最上面是 Dispatcher，它只做分区怎么分、出事怎么退；中间是多个 Scheduler 实例，"
              "各自在自己的分区里跑 Filter、Score、Reserve；最下面一层负责把决策真正写进 apiserver。"
              "要注意的是，分区之间没有共享锁，状态推进靠 Watch 事件驱动，这也是后面能横向扩展的前提。",
        source="3.1 节；图 3-1",
    ),
    dict(
        n=7, kind="twopic",
        title="创新点 1：把 Binder 放进 Scheduler 进程",
        core="去掉一次跨进程绑定链路，是吞吐提升的第一性来源",
        figures=["fig5-1a-shared-binder.png", "fig5-1b-eno-arch.png"],
        bullets=["绑定与决策同域，事件传递归零", "序列化与网络往返被消除", "保留 CLI 开关，可回退"],
        notes="左边是原来的形态，Binder 是独立 Deployment，Scheduler 决策完要把任务发过去；右边是本文的形态，"
              "Binder 就在 Scheduler 进程里。这一改动去掉了三段开销：事件传递、跨进程 API 调用、以及序列化。"
              "我把它称为第一性来源，因为后面所有吞吐数字都从这一刀下来。同时保留了 CLI 开关，"
              "部署形态可以切换回去，向后兼容。",
        source="第 5 章 §5.1；图 5-1a/5-1b",
    ),
    dict(
        n=8, kind="figure",
        title="CacheAdapter：共享同一份 SchedulerCache",
        core="状态以对象引用共享，不再复制，也没有跨进程同步延迟",
        figure="fig5-2-cache-zero-copy.png",
        bullets=["对象引用而非序列化拷贝", "进程内 Binder 与 Scheduler 同视图", "为一致性校验提供同一份真相"],
        notes="难点在于缓存。以前 Binder 在另一个进程，SchedulerCache 要么复制、要么重新构建，代价高还有延迟。"
              "CacheAdapter 让进程内 Binder 直接拿到同一份 SchedulerCache 的对象引用，所以叫零拷贝。"
              "这不只是性能问题：两边看到的是同一份状态，Layer 0 的节点归属校验才有同一个真相可依。",
        source="第 5 章 §5.2；图 5-2",
    ),
    dict(
        n=9, kind="ladder",
        title="创新点 2：四层容错覆盖 Bind 前、中、后",
        core="每一层对应一类威胁，并分别依赖一种 etcd 原子语义",
        rows=[("① Layer 0 · 预防", "分区归属漂移", "resourceVersion 乐观并发"),
              ("② Layer 1 · 即时恢复", "apiserver 暂态错误", "Bind 原子写 / 409 冲突"),
              ("③ Layer 2 · 后台回收", "孤儿 Assumed 状态", "Watch 一致性视图"),
              ("④ Layer 3 · 全局回退", "实例失活、重试耗尽", "注解清理 + 全局重分发")],
        notes="四层不是并列罗列，是一条时间轴。Bind 之前，Layer 0 先校验目标节点的归属注解，把漂移拦在门外；"
              "Bind 过程中，Layer 1 用同步退避处理 apiserver 的暂态错误；Bind 失败后，Layer 2 用异步 Reconciler"
              "把孤儿 Assumed 状态收回来；本地重试耗尽，Layer 3 由 Dispatcher 清掉归属注解，让 Pod 全局重分发。"
              "四层各自依赖 resourceVersion、Watch、Bind 原子写中的一种。",
        source="第 4 章 §4.3~§4.6",
    ),
    dict(
        n=10, kind="figure",
        title="正确性根基：不变量 I 与证明思路",
        core="所有机制最终归约到“任一 Pod 至多绑定到一个节点”",
        figure="fig4-3-consistency-invariant.png",
        bullets=["Bind 原子写是最后防线", "resourceVersion 防并发覆盖", "四层机制均不破坏 I"],
        notes="所有机制最后都要回到这一条不变量 I：任一 Pod 至多绑定到一个节点。证明思路是把它拆成四个点。"
              "P1 来自 Bind 子资源的原子写：apiserver 保证只有一个写成功。P2 处理 Assumed 状态的清理。"
              "P3 是注解清理与重分发的时序。P4 是 Layer 0 的前置拦截。四层机制的每一步都不破坏 I，"
              "而且这一点可以在 apiserver 侧用断言复核，不是自说自话。",
        source="第 4 章 §4.2；图 4-3",
    ),
    dict(
        n=11, kind="table",
        title="实验设计：4 档规模 × 7 类负载 × 5 组调度器",
        core="16 个对比场景，每场景 3 次重复，共 144 次 run，n=3 取中位数",
        table=[["维度", "取值"],
               ["规模 s1–s4", "100 / 1000 / 5000 / 10000 节点"],
               ["负载 w1–w7", "w1 100 → w4 2000 pods/s（极限）；w5 突发、w6 Gang、w7 异构"],
               ["实例 inst", "inst1 = 1 个实例；inst3 = 3 个实例"],
               ["对比组", "a=ENO  b=Gödel  c=kube-scheduler  d=Volcano  e=Koordinator"],
               ["公平性", "每 Pod 2C/4G；客户端 QPS=Burst=10000"]],
        bullets=["KWOK 仿真，kind 内 K8s v1.34.8", "Prometheus 15 s 抓取 + recording rules", "warmup/cooldown 各剔除 30 s"],
        notes="先看表头这套编码：s 是规模档位，100 到 10000 节点；w 是负载强度，w2 是 500、w3 是 1000 pods per second，"
              "w4 到 2000 是极限，w5 到 w7 分别是突发、Gang 与异构；inst 是实例数。后面所有场景名都由这三段拼成。"
              "再说明三点公平性。第一，平台是 KWOK 仿真，在 kind 集群里跑，Kubernetes 版本与对照组一致。"
              "第二，五个调度器的 Pod 资源规格完全相同，客户端 QPS 与 Burst 都放到 10000，避免把客户端限流误读成能力差异。"
              "第三，每个场景重复三次取中位数，共 144 次 run；负载前 30 秒与结束前 30 秒都被剔除。",
        source="6.2 节；表 6-1~6-4",
    ),
    dict(
        n=12, kind="metricrow",
        legend=True,
        title="评估指标：为什么用“有效吞吐”作主口径",
        core="吞吐时序会“归零”，只有“总工作量 ÷ 总完成时间”跨场景可比",
        figure="fig6-throughput-s2-w3.png",
        caption="s2/w3 吞吐时序：爬升—平台—归零",
        cards=[("有效吞吐 pods/s", "名义工作量 ÷ 完成时间（主口径）"),
               ("峰值吞吐 pods/s", "过程中的最高瞬时调度速率"),
               ("P90 / P99 延迟 s", "入 activeQ 到 Bind 完成"),
               ("Pod E2E P99 s", "Dispatcher 观察到绑定完成"),
               ("绑定成功率", "Bind 成功 / Bind 尝试"),
               ("队列堆积峰值 pods", "pending_pods 最大值")],
        bullets=["三段结构：爬升—平台—归零，均值被尾段零值稀释", "时序类：3 run 逐点中位数，再去首尾各 2 点（约 30 s）", "c/d/e 单实例过载存在幸存者偏差，只与 a/b 比吞吐、队列、成功率"],
        notes="这一页是方法学核心。吞吐时序是三段结构：爬升、平台、归零，直接取平均会被尾段零值稀释，"
              "而且稀释程度取决于实验跑多久，跨调度器就不可比。所以主口径用有效吞吐：总工作量除以总完成时间，"
              "与窗口长度无关。时序类指标先对三条 run 逐点取中位数，再剔掉首尾各两个采样点。"
              "还有一个必须说清的限定：c、d、e 是单实例，过载时大量 Pod 堵在 activeQ 里，根本没进延迟直方图，"
              "存在幸存者偏差，所以它们的 P99 我只做定性说明，不做数值对齐。",
        source="6.3 节；表 6-5 口径",
    ),
    dict(
        n=13, kind="stats",
        title="绑定正确性与不变量验证",
        core="144 次 run 的 apiserver 断言全部通过：unbound = 0 且 dup = 0",
        stats=[("100%", "绑定成功率"), ("144", "次 run 全部通过"), ("0", "unbound / dup")],
        bullets=["ENO 48 次 run：绑定成功率 100%", "Layer 0 / Layer 3 故障注入各 6 项判据全过", "断言在 apiserver 侧可复核"],
        notes="在给性能数字之前，先说正确性。144 次 run，每一次跑完都在 apiserver 侧做断言：未绑定的 Pod 数为零，"
              "重复绑定的 Pod 数为零，全部通过；ENO 自己那 48 次 run 绑定成功率都是 100%。"
              "更关键的是两场故障注入，Layer 0 和 Layer 3 各 6 项判据全部通过。所谓正确，不是日志里没报错，"
              "而是外部可观测的事实对得上。",
        source="6.6 节；6.7 节",
    ),
    dict(
        n=14, kind="figure",
        legend=True,
        title="故障注入 Layer 0：归属漂移被拦住而非丢弃",
        core="10% 节点注解漂移，300 次拦截全部转为合规重排",
        figure="fig6-29a-layer0-timeseries.png",
        bullets=["拦截 300 次 / 回退 300 次", "绑定成功率 1.00；断言 50000/50000", "总耗时 683 s 对基线 680 s（+0.4%）"],
        notes="第一场注入：在 s2/w2、三实例配置下，第 30 秒把 10% 的节点、也就是约 1000 个里的 100 个，"
              "归属注解从 scheduler-0 改成 scheduler-1。结果是 NodeValidator 拦截 300 次，Dispatcher 回退 300 次，"
              "两条曲线完全重叠。要点是拦截不等于丢弃：这些 Pod 进的是回退队列，被重新分发掉了，"
              "所以绑定成功率仍是 1.00，断言 50000 全部通过，总耗时 683 秒、只比基线多 3 秒。",
        source="6.7.1 节；图 6-29a；表 15",
    ),
    dict(
        n=15, kind="figure",
        legend=True,
        title="故障注入 Layer 3：实例失活后能接管",
        core="杀掉 1/3 实例并停机 180 s，系统仍在 784 s 内完成全部绑定",
        figure="fig6-29b-layer3-timeseries.png",
        bullets=["被杀实例绑定占比 68/8407 = 0.81%", "存活实例接管 8407 pods；pending 353→2", "总耗时 784 s，较基线 +15.3%"],
        notes="第二场注入：第 10 秒直接杀掉 scheduler-0，停机 180 秒，实测中断 189 秒。被杀实例上未完成的绑定"
              "只占 68/8407，也就是 0.81%；另外两个存活实例接管了 8407 个 Pod，孤儿回收速率 77.15 每秒，"
              "队列峰值冲到 353 后回落到 2。累计绑定 49607/50000，断言 50000 仍全部通过。"
              "代价是总耗时 784 秒，比基线多 104 秒、15.3%——这个代价来自失活实例那份工作的重排，不是数据损坏。",
        source="6.7.2 节；图 6-29b；表 16",
    ),
    dict(
        n=16, kind="figure",
        legend=True,
        title="五组基线：三档差异非常清晰",
        core="ENO/Gödel 第一档，kube-scheduler 第二档，Volcano/Koordinator 低一个数量级",
        figure="fig6-3-throughput-5group.png",
        table=[["场景", "ENO", "Gödel", "k-sched", "Volcano", "Koord"],
               ["s2/w3", "352.1", "286.5", "≈297", "≈48", "≈16"],
               ["s3/w3", "297.6", "283.3", "≈292", "≈48", "≈24"]],
        bullets=["较 kube-scheduler +1.8%~+22.5%", "较 Volcano 约 6×，较 Koordinator 12× 以上", "s1/w1 低负载例外 -7.2%（未饱和）"],
        notes="五组横向对比，结论是三档。第一档是 ENO 与 Gödel，单位都是几百 pods/s。第二档是 kube-scheduler。"
              "第三档是 Volcano 与 Koordinator，只有约 48 和约 24 pods/s，而且几乎不随规模变化——这是它们"
              "批处理与 QoS 感知调度的固有开销。主评估四场景里，ENO 比 kube-scheduler 高 1.8% 到 22.5%，"
              "比 Volcano 约 6 倍、比 Koordinator 12 倍以上。唯一的例外是 s1/w1 的低负载，比 kube-scheduler 低 7.2%，"
              "因为那个场景没饱和，完成时间由注入速率决定。",
        source="6.4.1 节；图 6-3；表 6-5",
    ),
    dict(
        n=17, kind="figure",
        legend=True,
        title="ENO vs Gödel：16 个场景中 14 个领先",
        core="平均 +11.9%，高负载与多实例场景优势最大",
        figure="fig6-2-effective-throughput.png",
        bullets=["14 领先、2 持平（s1/w1、s4/w7）", "提升 +2.0%~+22.9%，平均 +11.9%", "亮点：s2/w3 +22.9%、s3/w3 inst3 +21.7%"],
        notes="和 Gödel 的逐场景对比：16 个场景里 14 个领先，2 个持平，没有落后的，提升幅度 2.0% 到 22.9%，"
              "平均 11.9%。优势最大的是高负载和多实例：s2/w3 高 22.9%，s3/w3 三实例高 21.7%，"
              "s3/w5 突发和三实例、s3/w7 异构也都超过 21%。两个持平场景都是没饱和的情况，完成时间由注入速率决定，"
              "这时候调度器再快也压不出来。",
        source="6.4.2 节；图 6-2；表 6-6",
    ),
    dict(
        n=18, kind="figure",
        legend=True,
        title="尾延迟：11 个非 Gang 场景全面领先",
        core="s2/w3 从 23.48 s 降到 4.00 s，降幅 82.9%",
        figure="fig6-4-latency-p99-all.png",
        bullets=["P99 改善 0.3%~82.9%（除 s2/w2）", "s3/w3 inst1 32.57→16.22 s（-50.2%）", "Pod E2E P99 改善 0.6%~75.3%"],
        notes="延迟这一页。除 s2/w2 之外的 11 个非 Gang 场景，ENO 的 P99 都低于 Gödel，改善 0.3% 到 82.9%。"
              "最具代表性的是 s2/w3：从 23.48 秒降到 4.00 秒。单实例的 s3/w3 从 32.57 秒降到 16.22 秒，"
              "少了一半。Pod 端到端 P99 在 12 个非 Gang 场景也都不高于 Gödel，改善 0.6% 到 75.3%。"
              "要主动说明的是 Gang 场景是反的，我放在局限里展开。",
        source="6.4.2 节；图 6-4；表 6-7/6-8",
    ),
    dict(
        n=19, kind="twopic",
        title="主场景 s3/w3 的时序形态",
        core="ENO 更早进入平台、平台更高、结束更早",
        figures=["fig6-throughput-s3-w3.png", "fig6-6-latency-p99-s3-w3.png"],
        bullets=["吞吐平台更高且更早稳定", "P99 峰值更低、回落更快", "整体完成时间更短"],
        notes="这一页是给评委看“形态”的。左边吞吐，右边 P99，共享同一条时间轴。ENO 的平台更高、更早稳定；"
              "右边的 P99 峰值更低、回落更快。这两张图放在一起的意义是：我们的优势不是某个瞬时点上的抖动，"
              "而是整段完成时间都更短——这也正好解释了为什么有效吞吐这个口径对我们有利，因为它衡量的是"
              "固定工作量做多久做完。",
        source="6.4.2 节；图 6-6、6-9",
    ),
    dict(
        n=20, kind="tablepic",
        legend=True,
        title="实例 1→3：ENO 把并发变成完成速度",
        core="ENO 有效吞吐 +17.5%，Gödel 仅 +1.4%",
        figure="fig6-16-throughput-s3-w3-inst3.png",
        caption="s3/w3 inst3 吞吐时序",
        table=[["指标（s3/w3）", "ENO inst1→inst3", "Gödel inst1→inst3"],
               ["有效吞吐", "297.6 → 349.7（+17.5%）", "283.3 → 287.4（+1.4%）"],
               ["P99 延迟", "16.22 → 0.13 s（-99.2%）", "32.57 → 0.15 s（-99.5%）"],
               ["队列堆积峰值", "14698 → 20", "22652 → 16"]],
        table_width=6.15, row_h=0.6, font=10.5, widths=[1.65, 2.3, 2.2],
        fig_geometry=(6.95, 1.98, 5.77, 2.37),
        bullets_top=4.95,
        bullets=["延迟都降约 99%，但吞吐转化率差 12 倍", "Gödel 增量被独立 Binder 串行吸收", "这是架构归因最强的一组证据"],
        notes="这是全文最强的一组归因证据。同样是实例数从 1 加到 3，两边延迟都降了约 99%，这部分大家一样。"
              "差别在吞吐：ENO 从 297.6 涨到 349.7，提升 17.5%；Gödel 从 283.3 到 287.4，只提升 1.4%。"
              "同样多的并发能力，Gödel 的增量被独立 Binder 的串行绑定吸收掉了。这正是把 Binder 放进进程内"
              "想要解决的问题，也是我认为这项工作的核心价值所在。",
        source="6.5.2 节；表 6-10",
    ),
    dict(
        n=21, kind="table",
        legend=True,
        title="规模翻倍与复杂负载下仍保持领先",
        core="s4 规模下吞吐仍 +5.6%、P99 低 33.4%；突发、极限、异构均不落后",
        table=[["场景（inst3）", "ENO vs Gödel 有效吞吐", "P99 / E2E 变化"],
               ["s3→s4（w3，实例不变）", "349.7→296.7 vs 287.4→280.9（+5.6%）", "P99 0.19 vs 0.28 s（低 33.4%）"],
               ["w4 极限（s3 / s4）", "+9.3% / +16.0%", "P99 -49.7% / -14.8%；E2E -32.6%~-35.3%"],
               ["w5 突发（s3 / s4）", "+21.3% / +2.8%", "s3 E2E -53.8%；s4 基本持平"],
               ["w7 异构（s3 / s4）", "+21.2% / 基本持平", "s3 E2E -67.6%"]],
        bullets=["s4 队列堆积峰值 9 vs 61", "规模翻倍时两者都退化（ENO -15.2%）", "s3/s4 固定 3 实例，口径需说明"],
        notes="两件事。第一，规模从 5000 翻到 10000，实例数不变，两边都退化：ENO 有效吞吐 -15.2%，Gödel -2.3%。"
              "但即使退化，ENO 仍然领先：吞吐 296.7 对 280.9，高 5.6%；P99 0.19 对 0.28 秒，低 33.4%；"
              "队列峰值 9 对 61。第二，复杂负载：极限负载高 9.3% 和 16.0%，突发高 21.3% 和 2.8%，"
              "异构在 s3 高 21.2%、s4 基本持平。需要提醒的是，s3 到 s4 是固定 3 实例的对比，"
              "规模翻倍没同步扩实例，所以这个回落不能直接读成扩展性上限。",
        source="6.5.1 节；6.5.3 节；表 6-9/6-11",
    ),
    dict(
        n=22, kind="table",
        legend=True,
        title="归因闭环：优势从哪来",
        core="去掉一次跨进程绑定链路，换来吞吐、尾延迟、队列深度的同步改善",
        table=[["机制差异", "对应指标", "实测证据"],
               ["进程内绑定，无事件传递", "Pod E2E P99", "s3/w3 inst3 0.45 vs 0.93 s（低 51.9%）"],
               ["CacheAdapter 零拷贝共享", "状态复用 / 无同步延迟", "inst3 队列峰值 20 vs 16"],
               ["无独立 Binder 串行段", "有效吞吐随实例扩展", "+17.5% vs +1.4%"],
               ["四层容错守住不变量 I", "绑定成功率 / 断言", "100%；144 次 run 全过"]],
        bullets=["相关不等于归因：峰值吞吐并非全面领先", "s3/w5、s4/w3 峰值吞吐低于 Gödel", "收益部分来自启动更快（口径权衡）"],
        notes="把机制和指标对齐，是这一页的目的。第一行，进程内绑定去掉了事件传递，对应 E2E 降低，"
              "s3/w3 三实例下 0.45 对 0.93 秒。第二行，零拷贝共享让状态复用无同步延迟。第三行最关键："
              "没有独立 Binder 那一段串行，吞吐才能随实例扩展，+17.5% 对 +1.4%。第四行是四层容错，"
              "守住不变量，成功率 100%。同时我要说明相关与归因的区别：峰值吞吐我们并非每个场景都领先，"
              "s3/w5 和 s4/w3 是低于 Gödel 的，说明有效吞吐的收益有一部分来自启动更快，这个口径权衡写在局限里。",
        source="6.4.4 节；6.8 节",
    ),
    dict(
        n=23, kind="cards",
        title="局限性与威胁效力",
        core="结论在“跨调度器相对比较”上成立，绝对数值不外推到生产",
        cards=[("KWOK 仿真", "无法反映真实资源竞争与 IO"),
               ("Gang 延迟口径", "w6 尾延迟反向，未分离计时"),
               ("固定实例数", "s3→s4 未同步扩容"),
               ("资源公平", "每 Deployment 同规格，对 ENO 略不利"),
               ("Volcano 指标", "测量对象与粒度不完全等价"),
               ("幸存者偏差", "c/d/e 的 P99 不做数值对齐")],
        notes="局限我列了六条，只讲关键。第一，KWOK 是仿真，绝对数值不能外推到生产，但跨调度器的相对比较是成立的。"
              "第二，Gang 场景即 w6，ENO 尾延迟确实更高：吞吐高 4.3% 到 19.1%，但单 Pod P99 高出 1.6 到 4.1 倍，"
              "原因是同组预留等待、绑定调用与后续决策共用一个进程和队列；这个我们没有用独立计时实验分离出来，"
              "所以如实列为局限。第三，s3 到 s4 固定三实例，退化幅度不能读成扩展性上限。"
              "另外资源公平、Volcano 指标口径、c/d/e 的幸存者偏差，论文里都给了方法学限定。",
        source="6.8 节；6.3.3 节",
    ),
    dict(
        n=24, kind="cards",
        title="结论：两个创新、三组证据、一处价值",
        core="架构创新与一致性创新都有可复现实验支撑，且实现了向后兼容的工程落地",
        cards=[("创新 1 · ENO", "Binder 进进程内 + CacheAdapter"),
               ("创新 2 · 四层容错", "不变量 I 的完整证明要点"),
               ("证据 1 · 规模", "16 场景 / 144 run / 100% 成功率"),
               ("证据 2 · 性能", "平均 +11.9%；P99 最高 -82.9%"),
               ("证据 3 · 扩展", "实例 1→3：+17.5% 对 +1.4%"),
               ("价值 · 落地", "不改 API、保留开关、基准开源")],
        notes="最后一页做收束。两个创新：一是 ENO，把 Binder 放进 Scheduler 进程并用 CacheAdapter 共享缓存；"
              "二是四层容错，给出了不变量 I 的完整证明要点。三组证据：规模上 16 个场景、144 次 run、100% 成功率；"
              "性能上平均提升 11.9%、P99 最高降 82.9%；扩展性上实例 1 到 3，吞吐 +17.5%，Gödel 只有 +1.4%。"
              "价值上，不改 API、保留开关、基准与脚本开源。未来可以做的有三件：生产灰度、多 Dispatcher 分区协同、"
              "以及在 ENO 上叠加更多调度策略。",
        source="第 7 章",
    ),
    dict(
        n=25, kind="thanks",
        title="谢谢各位老师，请批评指正",
        core="基于 etcd 的分布式 Kubernetes 调度器研究与实现",
        meta=["答辩人：[姓名]", "联系方式：[邮箱]"],
        notes="我的汇报到这里。如果只允许我用一句话总结：本文把 Binder 从独立进程合并进 Scheduler，"
              "用基于 etcd 原子语义的四层容错守住“至多绑定一次”，在 16 个场景、144 次 run 上做到了"
              "更高吞吐、更低尾延迟和 100% 绑定成功率。请各位老师批评指正，谢谢。",
        source="致谢",
    ),
]

BACKUP: list[dict] = [
    dict(
        n="B1", kind="table", title="16 场景完整数据（摘要）",
        core="有效吞吐 / P99 / Pod E2E P99 / 队列堆积峰值（n=3 中位数）",
        table=[["场景", "ENO 吞吐", "Gödel 吞吐", "ENO P99", "Gödel P99"],
               ["s2/w2", "331.1", "324.7", "0.16", "0.11"],
               ["s2/w3", "352.1", "286.5", "4.00", "23.48"],
               ["s3/w3 inst1", "297.6", "283.3", "16.22", "32.57"],
               ["s3/w3 inst3", "349.7", "287.4", "0.13", "0.15"],
               ["s4/w3 inst3", "296.7", "280.9", "0.19", "0.28"],
               ["s4/w7 inst3", "271.7", "271.7", "0.06", "0.06"]],
        bullets=["完整 16 行见论文表 6-6/6-7/6-8", "数据目录：results/compare/", "统计口径：n=3 中位数"],
        notes="备用页：抽查任意场景的原始数值。",
    ),
    dict(
        n="B2", kind="table", title="6 个指标的精确口径与来源",
        core="定义、聚合方式与对应的可复核字段",
        table=[["指标", "字段 / 定义", "聚合"],
               ["有效吞吐", "名义工作量 ÷ metadata.duration", "每 run 算再取中位数"],
               ["峰值吞吐", "scheduling_peak_throughput", "3 run 逐点中位数后取标量"],
               ["P90/P99", "activeQ 到 Bind 完成的分位", "剔首尾各 2 点后取中位数"],
               ["Pod E2E P99", "pod_e2e_latency_p99", "同上"],
               ["绑定成功率", "Bind 成功 / 尝试", "比值"],
               ["队列堆积峰值", "pending_pods 最大值", "取最大"]],
        bullets=["recording rules 归一化跨组指标名", "提取脚本：collect/latency-compare.py", "场景清单：results/compare/"],
        notes="备用页：如果评委追问某个数字怎么算出来的，用这页回答。",
    ),
    dict(
        n="B3", kind="bullets", title="为什么 c/d/e 的 P99 不能与 a/b 直接比",
        core="单实例过载 → Pod 长期堵在 activeQ → 未进入延迟直方图",
        bullets=["直方图只覆盖“已被 pop 处理”的子集", "数值对该子集准确，但样本群体不同", "故只比吞吐 / 队列 / 成功率"],
        notes="备用页：幸存者偏差的解释。过载时 Pod 根本没被处理，所以延迟看起来“很好”。",
    ),
    dict(
        n="B4", kind="table", title="Gang（w6）尾延迟反向的机理与边界",
        core="吞吐仍领先，但单 Pod 尾延迟高出 1.6~4.1 倍",
        table=[["场景", "ENO 吞吐", "Gödel 吞吐", "ENO P99", "Gödel P99"],
               ["s3/w6 inst1", "251.3", "211.0", "0.428", "0.175"],
               ["s3/w6 inst3", "215.5", "206.6", "0.892", "0.218"],
               ["s4/w6 inst3", "245.1", "206.6", "0.576", "0.353"]],
        bullets=["同组预留等待与决策共用进程与队列", "未用独立计时实验分离两段耗时", "已在论文 §6.8 列为局限"],
        notes="备用页：w6 反向结果的完整数据与解释。",
    ),
    dict(
        n="B5", kind="bullets", title="资源公平性与未量化的资源收益",
        core="每 Deployment 同规格，对 ENO 略不利",
        bullets=["Scheduler Pod 统一 2C/4G", "ENO 少一个 Binder Deployment", "集群总资源收益未量化"],
        notes="备用页：公平性与资源开销的口径说明。",
    ),
    dict(
        n="B6", kind="bullets", title="一键复现：脚本与产物目录",
        core="从零到结果的全部入口",
        bullets=["run-experiment.sh：12 步实验流程", "plot-results.py / collect/：聚合与出图", "results/compare/：16 场景产物"],
        notes="备用页：评委问可复现性时展示。",
    ),
]


# ── 基础绘制工具 ────────────────────────────────────────────────────────
def _set_ea(run, name: str = EA_FONT) -> None:
    rPr = run._r.get_or_add_rPr()
    ea = rPr.find(qn("a:ea"))
    if ea is None:
        ea = rPr.makeelement(qn("a:ea"), {})
        rPr.append(ea)
    ea.set("typeface", name)


def style_run(run, size: float, bold: bool = False, color: RGBColor = C["text"]) -> None:
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = LATIN_FONT
    _set_ea(run)


def textbox(slide, left, top, width, height, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = Emu(0)
    tf.margin_top = tf.margin_bottom = Emu(0)
    return tf


def add_text(tf, text, size, bold=False, color=C["text"], first=False, align=PP_ALIGN.LEFT,
             space_before=0, line=None) -> None:
    p = tf.paragraphs[0] if first else tf.add_paragraph()
    p.alignment = align
    if space_before:
        p.space_before = Pt(space_before)
    if line:
        p.line_spacing = line
    run = p.add_run()
    run.text = text
    style_run(run, size, bold, color)


def rect(slide, left, top, width, height, fill=None, line=None, radius=False):
    from pptx.enum.shapes import MSO_SHAPE

    shape_type = MSO_SHAPE.ROUNDED_RECTANGLE if radius else MSO_SHAPE.RECTANGLE
    shp = slide.shapes.add_shape(shape_type, Inches(left), Inches(top), Inches(width), Inches(height))
    if fill is None:
        shp.fill.background()
    else:
        shp.fill.solid()
        shp.fill.fore_color.rgb = fill
    if line is None:
        shp.line.fill.background()
    else:
        shp.line.color.rgb = line
        shp.line.width = Pt(0.75)
    shp.shadow.inherit = False
    return shp


_MARKER_EL = None
self_ns = "{http://schemas.openxmlformats.org/presentationml/2006/main}"


def _template_marker(slide) -> None:
    """把模板里的花括号标记（Freeform 5）原样克隆到当前页，保留其 custGeom 与填充"""
    global _MARKER_EL
    if _MARKER_EL is None:
        import zipfile
        from pptx.oxml import parse_xml   # 必须用 python-pptx 的解析器，否则元素没有注册类
        P = "{http://schemas.openxmlformats.org/presentationml/2006/main}"
        with zipfile.ZipFile(str(TEMPLATE_PATH)) as z:
            root = parse_xml(z.read("ppt/slides/slide4.xml"))
        for sp in root.iter(f"{P}sp"):
            if sp.find(f"{P}nvSpPr/{P}cNvPr").get("name") == "Freeform 5":
                _MARKER_EL = sp
                break
    if _MARKER_EL is None:
        return
    from copy import deepcopy
    el = deepcopy(_MARKER_EL)
    el.find(f"{self_ns}nvSpPr/{self_ns}cNvPr").set("id", str(9000 + len(slide.shapes)))
    slide.shapes._spTree.append(el)


def slide_title(slide, title: str, kicker: str | None = None) -> None:
    """标题：默认版式用橙色竖条；--template 模式用模板的深蓝标记与位置"""
    if TEMPLATE_PATH:
        _template_marker(slide)
        # 右上角校名横图（与模板一致：10.21, 0.10，2.89×0.55）
        add_picture(slide, "beihang-logo-navy.png", 10.21, 0.10, 2.89, 0.55, base=ASSETS)
        # 标题避让校名：长标题降一档字号
        _size = 30 if len(title) <= 18 else 24
        tf = textbox(slide, 1.11, 0.17, 8.75, 0.68, anchor=MSO_ANCHOR.MIDDLE)
        add_text(tf, title, _size, True, C["navy"], first=True, line=1.0)
        if kicker:
            tf2 = textbox(slide, 1.11, 0.88, 11.4, 0.3)
            add_text(tf2, kicker, 12, False, C["muted"], first=True)
        return
    rect(slide, 0.42, 0.46, 0.085, 0.52, fill=C["orange"])
    tf = textbox(slide, 0.62, 0.36, 12.1, 0.78, anchor=MSO_ANCHOR.MIDDLE)
    add_text(tf, title, 27, True, C["navy"], first=True, line=1.05)
    if kicker:
        tf2 = textbox(slide, 0.62, 1.14, 12.1, 0.3)
        add_text(tf2, kicker, 12, False, C["muted"], first=True)


def core_line(slide, core: str, top=1.42) -> None:
    if TEMPLATE_PATH:      # 与模板标题左对齐（在 1.11 缩进处）
        rect(slide, 1.11, top, 0.03, 0.34, fill=C["blue"])
        tf = textbox(slide, 1.27, top - 0.03, 11.2, 0.42, anchor=MSO_ANCHOR.MIDDLE)
        add_text(tf, core, 15.5, True, C["blue"], first=True)
        return
    rect(slide, 0.62, top, 0.03, 0.34, fill=C["blue"])
    tf = textbox(slide, 0.78, top - 0.03, 12.0, 0.42, anchor=MSO_ANCHOR.MIDDLE)
    add_text(tf, core, 15.5, True, C["blue"], first=True)


SCENE_LEGEND = ("编码：s1–s4 = 100 / 1000 / 5000 / 10000 节点；"
                "w1–w7 = 负载强度（w2 500、w3 1000、w4 2000 pods/s 极限、w5 突发、w6 Gang、w7 异构）；"
                "inst3 = 3 实例")


def scene_legend(slide) -> None:
    """在页脚上方画一行场景编码注释（小五号灰字）"""
    tf = textbox(slide, 0.62, 6.9, 11.05, 0.22)
    add_text(tf, SCENE_LEGEND, 8.5, False, C["muted"], first=True)


def page_number(slide, n, dark_bg: bool = False) -> None:
    """右下角极简页码：正文「12 / 25」，备用页「B1」；深色页用浅灰"""
    _txt = f"{n} / {TOTAL}" if isinstance(n, int) else str(n)
    _color = RGBColor(0x8F, 0xA3, 0xB8) if dark_bg else C["muted"]
    tf = textbox(slide, 11.79, 6.94, 0.93, 0.24)
    add_text(tf, _txt, 9.5, False, _color, first=True, align=PP_ALIGN.RIGHT)


def footer(slide, label: str, page: str) -> None:
    rect(slide, 0, 7.16, 13.333, 0.012, fill=C["line"])
    tf = textbox(slide, 0.62, 7.20, 9.6, 0.24)
    add_text(tf, f"{label}  |  基于 etcd 的分布式 Kubernetes 调度器", 9.5, False, C["muted"], first=True)
    tf2 = textbox(slide, 10.4, 7.20, 2.3, 0.24)
    add_text(tf2, page, 9.5, False, C["muted"], first=True, align=PP_ALIGN.RIGHT)


def bullets_block(slide, items: list[str], left=0.62, top=2.1, width=5.7, size=15.5, gap=14,
                  height: float = 1.55) -> None:
    tf = textbox(slide, left, top, width, height)
    for i, item in enumerate(items):
        add_text(tf, "▪  " + item, size, False, C["text"], first=(i == 0), space_before=(0 if i == 0 else gap), line=1.15)


def add_picture(slide, name: str, left: float, top: float, max_w: float, max_h: float,
                caption: str | None = None, alpha: int | None = None, base: Path | None = None):
    path = (base or FIG) / name
    if not path.exists():
        rect(slide, left, top, max_w, max_h * 0.75, fill=C["light"], line=C["line"])
        tf = textbox(slide, left, top + max_h * 0.32, max_w, 0.4)
        add_text(tf, f"[缺图] {name}", 11, False, C["red"], first=True, align=PP_ALIGN.CENTER)
        return
    w, h = Image.open(path).size
    scale = min(max_w / w, max_h / h)
    pw, ph = w * scale, h * scale
    pic = slide.shapes.add_picture(str(path), Inches(left + (max_w - pw) / 2), Inches(top + (max_h - ph) / 2),
                                   Inches(pw), Inches(ph))
    if alpha is not None:
        from lxml import etree

        blip = pic._element.blipFill.blip
        etree.SubElement(blip, qn("a:alphaModFix"), {"amt": str(alpha)})
    if caption:
        tf = textbox(slide, left, top + max_h + 0.04, max_w, 0.26)
        add_text(tf, caption, 9.5, False, C["muted"], first=True, align=PP_ALIGN.CENTER)


def add_table(slide, data: list[list[str]], left: float, top: float, width: float,
              row_h: float = 0.42, font: float = 12, header_font: float | None = None,
              highlight: int | None = None, widths: list[float] | None = None) -> None:
    rows, cols = len(data), len(data[0])
    tbl = slide.shapes.add_table(rows, cols, Inches(left), Inches(top), Inches(width),
                                 Inches(row_h * rows)).table
    if widths:
        for _i, _w in enumerate(widths[:cols]):
            tbl.columns[_i].width = Inches(_w)
    for r in range(rows):
        tbl.rows[r].height = Inches(row_h)
        for c in range(cols):
            cell = tbl.cell(r, c)
            cell.margin_left = cell.margin_right = Inches(0.06)
            cell.margin_top = cell.margin_bottom = Inches(0.02)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT if c == 0 else PP_ALIGN.CENTER
            run = p.add_run()
            run.text = str(data[r][c])
            if r == 0:
                style_run(run, header_font or font, True, C["white"])
                cell.fill.solid()
                cell.fill.fore_color.rgb = C["navy"]
            else:
                style_run(run, font, False, C["text"])
                cell.fill.solid()
                cell.fill.fore_color.rgb = C["white"] if r % 2 else C["light"]
    return tbl


def cards_grid(slide, cards: list[tuple[str, str]], left=0.62, top=2.15, width=12.1,
               cols=3, box_h=1.15, gap=0.28) -> None:
    rows = (len(cards) + cols - 1) // cols
    box_w = (width - gap * (cols - 1)) / cols
    for idx, (head, body) in enumerate(cards):
        r, c = divmod(idx, cols)
        x = left + c * (box_w + gap)
        y = top + r * (box_h + gap)
        if TEMPLATE_PATH:
            # 模板构件：白底卡片 + 淡蓝描边 + 左上编号圆（文字用深色保证可读）
            rect(slide, x, y, box_w, box_h, fill=C["white"], line=C.get("soft", C["line"]), radius=True)
            badge = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x + 0.16), Inches(y + 0.15),
                                           Inches(0.30), Inches(0.30))
            badge.fill.solid(); badge.fill.fore_color.rgb = C["navy"]
            badge.line.fill.background(); badge.shadow.inherit = False
            btf = badge.text_frame; btf.margin_left = btf.margin_right = Emu(0)
            btf.margin_top = btf.margin_bottom = Emu(0)
            add_text(btf, f"{idx + 1:02d}", 9, True, C["white"], first=True, align=PP_ALIGN.CENTER)
            tf = textbox(slide, x + 0.56, y + 0.15, box_w - 0.7, box_h - 0.22)
            add_text(tf, head, 13.5, True, C["navy"], first=True)
            add_text(tf, body, 11, False, C["text"], space_before=4, line=1.1)
        else:
            rect(slide, x, y, box_w, box_h, fill=C["light"], line=C["line"], radius=True)
            rect(slide, x, y, 0.055, box_h, fill=C["blue"])
            tf = textbox(slide, x + 0.18, y + 0.14, box_w - 0.3, box_h - 0.2)
            add_text(tf, head, 14, True, C["navy"], first=True)
            add_text(tf, body, 11.5, False, C["text"], space_before=4, line=1.1)
    return rows


def big_stats(slide, stats: list[tuple[str, str]], top=2.0, height=1.55) -> None:
    n = len(stats)
    gap = 0.35
    box_w = (11.9 - gap * (n - 1)) / n
    for i, (num, label) in enumerate(stats):
        x = 0.72 + i * (box_w + gap)
        if TEMPLATE_PATH:
            rect(slide, x, top, box_w, height, fill=C["white"], line=C.get("soft", C["line"]), radius=True)
            rect(slide, x, top, box_w, 0.05, fill=C["navy"])
            tf = textbox(slide, x, top + 0.14, box_w, 0.92, anchor=MSO_ANCHOR.MIDDLE)
            add_text(tf, num, 46, True, C["navy"], first=True, align=PP_ALIGN.CENTER)
        else:
            rect(slide, x, top, box_w, height, fill=C["light"], line=C["line"], radius=True)
            tf = textbox(slide, x, top + 0.12, box_w, 0.92, anchor=MSO_ANCHOR.MIDDLE)
            add_text(tf, num, 46, True, C["orange"], first=True, align=PP_ALIGN.CENTER)
        tf2 = textbox(slide, x, top + height - 0.42, box_w, 0.3)
        add_text(tf2, label, 12, False, C["muted"], first=True, align=PP_ALIGN.CENTER)


# ── 各版式渲染 ──────────────────────────────────────────────────────────
def render(slide, s: dict, page_label: str, is_backup: bool) -> None:
    kind = s["kind"]
    slide.background.fill.solid()
    slide.background.fill.fore_color.rgb = C["white"]

    if kind == "cover" and TEMPLATE_PATH:
        # 北航模板封面：白底 + 校名横图 + 双分隔线 + 标题 + 信息位 + 底边条
        add_picture(slide, "beihang-logo-navy.png", 4.14, 1.03, 4.62, 0.88, base=ASSETS)
        rect(slide, 1.31, 2.36, 10.79, 0.022, fill=C["navy"])
        rect(slide, 1.31, 3.59, 10.79, 0.022, fill=C["navy"])
        tf = textbox(slide, 0.84, 2.44, 11.73, 1.10, anchor=MSO_ANCHOR.MIDDLE)
        add_text(tf, s["title"], 28, True, C["navy"], first=True, align=PP_ALIGN.CENTER, line=1.15)
        tf2 = textbox(slide, 0.84, 3.78, 11.73, 0.45)
        add_text(tf2, s["core"], 18, False, C["blue"], first=True, align=PP_ALIGN.CENTER)
        tf3 = textbox(slide, 1.31, 5.05, 10.79, 0.9)
        add_text(tf3, "　　".join(s["meta"]), 15, False, C["muted"], first=True, align=PP_ALIGN.CENTER)
        rect(slide, 0.04, 7.38, 13.22, 0.05, fill=C["navy"])
        if SHOW_PAGE_NO:
            page_number(slide, s["n"])
        return

    if kind == "cover":
        add_picture(slide, "fig3-1-system-arch.png", 6.3, 1.05, 6.7, 5.4, alpha=18000)
        tf = textbox(slide, 0.9, 1.55, 5.4, 2.4)
        add_text(tf, s["title"], 30, True, C["navy"], first=True, line=1.15)
        tf2 = textbox(slide, 0.9, 4.15, 5.4, 0.5)
        add_text(tf2, s["core"], 17, False, C["blue"], first=True)
        tf3 = textbox(slide, 0.9, 4.95, 5.4, 1.6)
        for i, m in enumerate(s["meta"]):
            add_text(tf3, m, 12.5, False, C["muted"], first=(i == 0), space_before=(0 if i == 0 else 5))
        rect(slide, 0.04, 7.38, 13.22, 0.05, fill=C["navy"])
        if SHOW_PAGE_NO:
            page_number(slide, s["n"])
        return

    # 致谢页自带标题/核心句版式，避免与通用标题重复绘制
    if kind != "thanks":
        slide_title(slide, s["title"])
        if s.get("core"):
            core_line(slide, s["core"])

    if kind == "bullets":
        bullets_block(slide, s["bullets"], top=2.15, width=11.6, size=17, gap=18)
    elif kind in ("figure", "twopic"):
        if kind == "figure":
            # 超宽图（比例 ≥3.2，如不变量示意图 5.23:1）改为占满版心、放在要点下方，
            # 否则在右栏里会被宽度限制压成一条窄带
            _ratio = 1.0
            _fp = FIG / s["figure"]
            if _fp.exists():
                from PIL import Image as _Img
                _w, _h = _Img.open(_fp).size
                _ratio = _w / _h
            if _ratio >= 3.2 and not s.get("fig_geometry"):
                bullets_block(slide, s["bullets"], top=2.05, width=11.9, size=13.5, gap=6, height=1.25)
                add_picture(slide, s["figure"], 0.62, 3.65, 12.1, 2.85, caption=s.get("caption"))
            else:
                _g = s.get("fig_geometry", (6.35, 1.95, 6.4, 4.6))
                add_picture(slide, s["figure"], *_g)
                bullets_block(slide, s["bullets"], left=0.62, top=2.2,
                              width=s.get("bullets_width", 5.5))
            if s.get("table"):
                add_table(slide, s["table"], 0.62, 4.55, 5.5, row_h=0.34, font=10.5)
        else:
            add_picture(slide, s["figures"][0], 0.62, 2.0, 5.9, 3.5)
            add_picture(slide, s["figures"][1], 6.75, 2.0, 5.9, 3.5)
            tf = textbox(slide, 0.62, 5.62, 12.1, 1.2)
            for i, b in enumerate(s["bullets"]):
                add_text(tf, "▪  " + b, 14, False, C["text"], first=(i == 0), space_before=(0 if i == 0 else 6))
    elif kind == "ladder" and TEMPLATE_PATH:
        # 模板语言：竖向时间轴（深蓝竖线 + 节点圆 + 左侧层级名 + 右侧浅钢蓝块）
        rows = s["rows"]
        rect(slide, 2.42, 2.10, 0.028, 4.34, fill=C["navy"])
        for _i, (_t, _threat, _sem) in enumerate(rows):
            _y = 2.12 + _i * 1.07
            node = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(2.34), Inches(_y + 0.28),
                                          Inches(0.22), Inches(0.22))
            node.fill.solid(); node.fill.fore_color.rgb = C["navy"]
            node.line.color.rgb = C["white"]; node.line.width = Pt(2)
            node.shadow.inherit = False
            _main, _sub = (_t.split("·")[0].strip(), _t.split("·")[1].strip()) if "·" in _t else (_t, "")
            _main = _main.lstrip("①②③④ ")
            _tf = textbox(slide, 0.62, _y + 0.10, 1.58, 0.72)
            add_text(_tf, _main, 13.5, True, C["navy"], first=True, align=PP_ALIGN.RIGHT)
            if _sub:
                add_text(_tf, _sub, 10.5, False, C["muted"], align=PP_ALIGN.RIGHT, space_before=1)
            rect(slide, 2.68, _y, 9.80, 0.92, fill=C["white"], line=C.get("soft", C["line"]), radius=True)
            _tf2 = textbox(slide, 2.86, _y + 0.11, 9.45, 0.72)
            add_text(_tf2, "威胁：" + _threat, 11.5, False, C["text"], first=True)
            add_text(_tf2, "etcd：" + _sem, 10.5, False, C["text"], space_before=2)
    elif kind == "ladder":
        rows = s["rows"]
        _x, _y0, _w, _h, _gap = 0.62, 1.95, 12.1, 0.98, 0.1
        for _i, (_t, _threat, _sem) in enumerate(rows):
            _y = _y0 + _i * (_h + _gap)
            rect(slide, _x, _y, _w, _h, fill=C["light"], line=C["line"], radius=True)
            rect(slide, _x, _y, 0.08, _h, fill=[C["blue"], C["blue"], C["orange"], C["red"]][_i])
            _tf = textbox(slide, _x + 0.22, _y + 0.14, 2.9, _h - 0.22)
            add_text(_tf, _t, 14.5, True, C["navy"], first=True)
            _tf2 = textbox(slide, _x + 3.25, _y + 0.14, 3.9, _h - 0.22)
            add_text(_tf2, "威胁：" + _threat, 11.5, False, C["text"], first=True)
            _tf3 = textbox(slide, _x + 7.35, _y + 0.14, 4.6, _h - 0.22)
            add_text(_tf3, "etcd：" + _sem, 11, False, C["muted"], first=True)
    elif kind == "metrics":
        add_picture(slide, s["figure"], 0.62, 1.96, 4.7, 3.1,
                    caption=s.get("caption"))
        _x0, _y0, _cw, _ch, _gx, _gy = 5.58, 1.96, 3.35, 0.98, 0.16, 0.1
        for _idx, (_head, _body) in enumerate(s["cards"]):
            _r, _c = divmod(_idx, 2)
            _x = _x0 + _c * (_cw + _gx)
            _y = _y0 + _r * (_ch + _gy)
            rect(slide, _x, _y, _cw, _ch, fill=C["light"], line=C["line"], radius=True)
            _tf = textbox(slide, _x + 0.14, _y + 0.09, _cw - 0.24, _ch - 0.14)
            add_text(_tf, _head, 11.5, True, C["navy"], first=True)
            add_text(_tf, _body, 9.5, False, C["muted"], space_before=2, line=1.05)
        bullets_block(slide, s["bullets"], top=5.45, width=12.0, size=12, gap=5, height=1.15)
    elif kind == "metricrow":
        add_picture(slide, s["figure"], 0.62, 1.92, 8.05, 3.3, caption=s.get("caption"))
        bullets_block(slide, s["bullets"], left=8.9, top=2.0, width=3.8, size=11, gap=8, height=3.1)
        _n = len(s["cards"])
        _gap = 0.13
        _cw = (12.1 - _gap * (_n - 1)) / _n
        for _i, (_head, _body) in enumerate(s["cards"]):
            _x = 0.62 + _i * (_cw + _gap)
            rect(slide, _x, 5.42, _cw, 0.92, fill=C["light"], line=C["line"], radius=True)
            _tf = textbox(slide, _x + 0.1, 5.5, _cw - 0.16, 0.78)
            add_text(_tf, _head, 9.5, True, C["navy"], first=True)
            add_text(_tf, _body, 8, False, C["muted"], space_before=1, line=1.05)
    elif kind == "tablepic":
        _tw = s.get("table_width", 7.55)
        add_table(slide, s["table"], 0.62, 1.98, _tw, row_h=s.get("row_h", 0.5),
                  font=s.get("font", 10.5), widths=s.get("widths"))
        _fg = s.get("fig_geometry", (8.42, 1.98, 4.25, 3.4))
        add_picture(slide, s["figure"], *_fg, caption=s.get("caption"))
        bullets_block(slide, s["bullets"], top=s.get("bullets_top", 5.75),
                      width=12.0, size=12, gap=4, height=1.0)
    elif kind == "innov":
        cards_grid(slide, s["cards"], top=2.05, cols=2, box_h=1.5)
        big_stats(slide, s["stats"], top=4.35, height=1.4)
    elif kind == "stats":
        big_stats(slide, s["stats"], top=1.95)
        bullets_block(slide, s["bullets"], top=3.85, width=11.8, size=15.5, gap=12)
    elif kind == "cards":
        if s.get("lead"):
            _lx = 1.11 if TEMPLATE_PATH else 0.62
            _tf = textbox(slide, _lx, s.get("lead_top", 1.88), 11.0, s.get("lead_h", 1.05))
            add_text(_tf, s["lead"], 13, False, C["text"], first=True, line=1.35)
        cards_grid(slide, s["cards"], top=s.get("cards_top", 2.05),
                   box_h=s.get("box_h", 1.15), cols=s.get("cols", 3))
        if s.get("takeaway"):
            _y = s.get("takeaway_top", 3.85)
            rect(slide, 0.62, _y, 12.1, 0.95, fill=C["light"], line=C["line"], radius=True)
            rect(slide, 0.62, _y, 0.08, 0.95, fill=C["orange"])
            _tf = textbox(slide, 0.86, _y + 0.1, 11.6, 0.75, anchor=MSO_ANCHOR.MIDDLE)
            add_text(_tf, s["takeaway"], 15, True, C["navy"], first=True, line=1.15)
        if s.get("bullets"):
            tf = textbox(slide, 0.62, 6.2, 12.1, 0.85)
            for i, b in enumerate(s["bullets"]):
                add_text(tf, "▪  " + b, 12, False, C["muted"], first=(i == 0), space_before=(0 if i == 0 else 3))
    elif kind == "table":
        add_table(slide, s["table"], 0.62, 2.0, 12.1,
                  row_h=s.get("row_h", 0.46), font=s.get("font", 12),
                  widths=s.get("widths"))
        bullets_block(slide, s["bullets"], top=5.55, width=12.0, size=13, gap=6, height=1.05)
    elif kind == "thanks" and TEMPLATE_PATH:
        add_picture(slide, "beihang-logo-navy.png", 10.21, 0.10, 2.89, 0.55, base=ASSETS)
        rect(slide, 1.31, 2.42, 10.79, 0.022, fill=C["navy"])
        tf = textbox(slide, 1.0, 2.62, 11.3, 1.0, anchor=MSO_ANCHOR.MIDDLE)
        add_text(tf, s["title"], 34, True, C["navy"], first=True, align=PP_ALIGN.CENTER)
        tf2 = textbox(slide, 1.0, 3.75, 11.3, 0.5)
        add_text(tf2, s["core"], 16, False, C["muted"], first=True, align=PP_ALIGN.CENTER)
        tf3 = textbox(slide, 1.0, 4.75, 11.3, 0.8)
        for i, m in enumerate(s["meta"]):
            add_text(tf3, m, 13, False, C["muted"], first=(i == 0), align=PP_ALIGN.CENTER,
                     space_before=(0 if i == 0 else 4))
        rect(slide, 1.31, 5.55, 10.79, 0.022, fill=C["navy"])
        rect(slide, 0.04, 7.38, 13.22, 0.05, fill=C["navy"])
        if SHOW_PAGE_NO:
            page_number(slide, s["n"])
        return

    elif kind == "thanks":
        rect(slide, 1.31, 2.42, 10.79, 0.022, fill=C["navy"])
        tf = textbox(slide, 1.0, 2.62, 11.3, 1.0, anchor=MSO_ANCHOR.MIDDLE)
        add_text(tf, s["title"], 34, True, C["navy"], first=True, align=PP_ALIGN.CENTER)
        tf2 = textbox(slide, 1.0, 3.75, 11.3, 0.5)
        add_text(tf2, s["core"], 16, False, C["muted"], first=True, align=PP_ALIGN.CENTER)
        tf3 = textbox(slide, 1.0, 4.75, 11.3, 0.8)
        for i, m in enumerate(s["meta"]):
            add_text(tf3, m, 13, False, C["muted"], first=(i == 0), align=PP_ALIGN.CENTER,
                     space_before=(0 if i == 0 else 4))
        rect(slide, 1.31, 5.55, 10.79, 0.022, fill=C["navy"])
        rect(slide, 0.04, 7.38, 13.22, 0.05, fill=C["navy"])
        if SHOW_PAGE_NO:
            page_number(slide, s["n"])
        return

    if s.get("legend"):
        scene_legend(slide)
    if SHOW_FOOTER:
        footer(slide, "答辩", page_label)
    if SHOW_PAGE_NO:
        page_number(slide, s["n"])


def _strip_decor(prs) -> None:
    """去掉模板版式与母版里的背景填充、装饰图片与全屏形状，让页面真正呈白底"""
    from lxml import etree
    from pptx.oxml.ns import qn

    def clean(container) -> None:
        cSld = container.find(qn("p:cSld"))
        if cSld is None:
            return
        bg = cSld.find(qn("p:bg"))
        if bg is not None:
            cSld.remove(bg)
        spTree = cSld.find(qn("p:spTree"))
        if spTree is None:
            return
        for child in list(spTree):
            local = etree.QName(child).localname
            if local in ("pic", "graphicFrame", "grpSp", "cxnSp"):
                spTree.remove(child)
            elif local == "sp" and child.find(".//" + qn("p:ph")) is None:
                spTree.remove(child)

    for lay in prs.slide_layouts:
        clean(lay._element)
    for m in prs.slide_masters:
        clean(m._element)


def build() -> None:
    if TEMPLATE_PATH:
        prs = Presentation(str(TEMPLATE_PATH))
        _strip_decor(prs)
        # 清空模板自带的示例页，只保留母版/主题/配色
        # 注意：必须同时 drop_rel，否则旧 slide 部件仍留在包里，与新建页同名
        _sld = prs.slides._sldIdLst
        for _sid in list(_sld):
            _rid = _sid.rId
            prs.part.drop_rel(_rid)
            _sld.remove(_sid)
        blank = prs.slide_layouts[6]          # 「空白」版式
    else:
        prs = Presentation()
        prs.slide_width = Inches(13.333)
        prs.slide_height = Inches(7.5)
        blank = prs.slide_layouts[6]

    md = ["# 答辩 PPT 逐页提要", "", f"共 {len(SLIDES)} 页正文 + {len(BACKUP)} 页备用", ""]
    for s in SLIDES:
        slide = prs.slides.add_slide(blank)
        render(slide, s, f"第 {s['n']} 页 / {TOTAL}", False)
        slide.notes_slide.notes_text_frame.text = s.get("notes", "")
        md += [f"## P{s['n']} {s['title']}", "", f"- 核心信息：{s.get('core', '')}"]
        if s.get("bullets"):
            md.append("- 要点：" + "；".join(s["bullets"]))
        if s.get("figure"):
            md.append(f"- 视觉：{s['figure']}")
        if s.get("figures"):
            md.append("- 视觉：" + " + ".join(s["figures"]))
        if s.get("table"):
            md.append("- 表格：" + " | ".join(s["table"][0]))
        md += [f"- 讲稿：{s.get('notes', '')}", f"- 来源：{s.get('source', '')}", ""]

    for s in BACKUP:
        slide = prs.slides.add_slide(blank)
        render(slide, s, f"Backup {s['n']}", True)
        slide.notes_slide.notes_text_frame.text = s.get("notes", "")
        md += [f"## {s['n']} {s['title']}", "", f"- 核心信息：{s.get('core', '')}"]
        if s.get("bullets"):
            md.append("- 要点：" + "；".join(s["bullets"]))
        md.append("")

    prs.save(str(OUT_PPTX))
    OUT_MD.write_text("\n".join(md), encoding="utf-8")
    print(f"已生成 {OUT_PPTX}（{len(prs.slides._sldIdLst)} 页）")
    print(f"已生成 {OUT_MD}")



# ── 讲稿定稿（按 45~70 s/页 校准；覆盖 SLIDES 中的初稿） ────────────────
NOTES: dict[int, str] = {
    2: "先给全篇一个抓手。我要回答两个问题：性能上，独立部署的 Binder 在高并发下重新变成串行瓶颈；"
       "一致性上，节点分区归属会动态漂移，必须保证任一 Pod 至多绑定一次。中间这条线是方法：ENO 架构、四层容错、实证闭环。"
       "右边是证据规模：16 个对比场景、144 次 run、绑定成功率 100%。后面每一页都为这三个数字服务。",
    6: "这是系统总体架构。最上面 Dispatcher 只做两件事：分区怎么分、出事怎么退；中间多个 Scheduler 实例，"
       "各自在分区里跑 Filter、Score、Reserve；最下面负责把决策真正写进 apiserver。分区之间没有共享锁，"
       "状态推进靠 Watch 事件驱动，这是能横向扩展的前提。",
    8: "难点在缓存。以前 Binder 在另一个进程，SchedulerCache 要么复制、要么重建，代价高还有延迟。"
       "CacheAdapter 让进程内 Binder 直接拿到同一份 SchedulerCache 的对象引用，所以叫零拷贝。"
       "这不只是性能问题：两边看到同一份状态，Layer 0 的归属校验才有同一个真相可依。",
    9: "四层不是并列罗列，是一条时间轴。Bind 之前，Layer 0 校验目标节点的归属注解，把漂移拦在门外；"
       "Bind 过程中，Layer 1 用同步退避处理 apiserver 暂态错误；失败后，Layer 2 用异步 Reconciler 回收孤儿状态；"
       "本地重试耗尽，Layer 3 由 Dispatcher 清注解、触发全局重分发。四层各自依赖一种 etcd 原子语义。",
    12: "这一页是方法学核心。吞吐时序是爬升、平台、归零三段，直接取平均会被尾段零值稀释，稀释程度还取决于跑多久，"
        "跨调度器就不可比。所以主口径是有效吞吐：总工作量除以总完成时间。时序类指标先对三条 run 逐点取中位数，"
        "再剔首尾各两点。还有一条限定：c、d、e 是单实例，过载时大量 Pod 堵在 activeQ 没进直方图，存在幸存者偏差，"
        "所以只做定性说明，不做 P99 数值对齐。",
    14: "第一场注入：s2/w2、三实例，第 30 秒把 10% 的节点、约 1000 个里的 100 个，归属注解从 scheduler-0 改为 scheduler-1。"
        "NodeValidator 拦截 300 次，Dispatcher 回退 300 次，两条曲线完全重叠。要点是拦截不等于丢弃："
        "这些 Pod 进回退队列被重新分发，所以成功率仍是 1.00，断言 50000 全过，总耗时 683 秒、只比基线多 3 秒。",
    15: "第二场注入：第 10 秒杀掉 scheduler-0，停机 180 秒，实测中断 189 秒。被杀实例未完成的绑定只占 68/8407，"
        "即 0.81%；两个存活实例接管 8407 个 Pod，孤儿回收 77.15 每秒，队列峰值 353 后回落到 2。"
        "累计绑定 49607/50000，断言 50000 仍全过。代价是 784 秒、比基线多 104 秒，这是工作量重排的代价，不是数据损坏。",
    16: "五组横向对比，结论是三档。第一档 ENO 与 Gödel，都是几百 pods/s；第二档 kube-scheduler；第三档 Volcano 与 Koordinator，"
        "只有约 48 和约 24 pods/s，几乎不随规模变化。主评估四场景里，ENO 比 kube-scheduler 高 1.8% 到 22.5%，"
        "比 Volcano 约 6 倍、比 Koordinator 12 倍以上。唯一例外是 s1/w1 低负载低 7.2%，那个场景没饱和，完成时间由注入速率决定。",
    18: "延迟这页。除 s2/w2 外，11 个非 Gang 场景 ENO 的 P99 都低于 Gödel，改善 0.3% 到 82.9%。最典型的是 s2/w3，"
        "从 23.48 秒降到 4.00 秒；单实例 s3/w3 从 32.57 秒降到 16.22 秒，少一半。Pod 端到端 P99 在 12 个非 Gang 场景"
        "也都不高于 Gödel，改善 0.6% 到 75.3%。Gang 场景是反的，我放到局限里展开。",
    19: "这一页给评委看形态。左边吞吐，右边 P99，共享时间轴。ENO 的平台更高、更早稳定；P99 峰值更低、回落更快。"
        "两张图放一起的意义是：我们的优势不是某个瞬时点，而是整段完成时间更短。这正好解释为什么有效吞吐对我们有利——"
        "它衡量的就是固定工作量多久做完，而不是某一秒的瞬时速率。",
    21: "两件事。第一，规模从 5000 翻到 10000、实例数不变，两边都退化：ENO -15.2%，Gödel -2.3%；但即使退化，"
        "ENO 仍领先——吞吐 296.7 对 280.9 高 5.6%，P99 0.19 对 0.28 秒低 33.4%，队列峰值 9 对 61。"
        "第二，复杂负载：极限 +9.3% 和 +16.0%，突发 +21.3% 和 +2.8%，异构 s3 高 21.2%、s4 基本持平。"
        "注意 s3 到 s4 是固定三实例，回落不能读成扩展性上限。",
    22: "把机制和指标对齐是这页的目的。进程内绑定去掉事件传递，对应 E2E 降低，s3/w3 三实例 0.45 对 0.93 秒；"
        "零拷贝让状态复用无同步延迟；关键是第三行，没有独立 Binder 的串行段，吞吐才能随实例扩展，+17.5% 对 +1.4%；"
        "第四行四层容错守住不变量。同时要说明相关与归因的区别：峰值吞吐我们并非每个场景都领先，s3/w5 和 s4/w3 低于 Gödel，"
        "说明收益有一部分来自启动更快，这个口径权衡写在局限里。",
    23: "局限六条，只讲关键。KWOK 是仿真，绝对数值不外推到生产，但跨调度器相对比较成立。Gang 即 w6，ENO 尾延迟确实更高："
        "吞吐高 4.3% 到 19.1%，但单 Pod P99 高 1.6 到 4.1 倍，原因是同组预留等待、绑定调用与后续决策共用进程和队列，"
        "我们没有用独立计时实验把两段分离出来，所以如实列为局限。s3 到 s4 固定三实例，退化幅度不能读成上限。"
        "其余三条是资源公平、Volcano 指标口径和幸存者偏差。",
    24: "最后收束。两个创新：ENO 把 Binder 放进进程内并用 CacheAdapter 共享缓存；四层容错给出不变量 I 的完整证明要点。"
        "三组证据：规模上 16 场景、144 次 run、100% 成功率；性能上平均 +11.9%、P99 最高 -82.9%；"
        "扩展性上实例 1 到 3，吞吐 +17.5%，Gödel 只有 +1.4%。价值：不改 API、保留开关、基准开源。"
        "下一步做生产灰度、多 Dispatcher 分区协同、以及在 ENO 上叠加调度策略。",
    25: "我的汇报到这里。如果只允许一句话总结：本文把 Binder 从独立进程合并进 Scheduler，用基于 etcd 原子语义的四层容错"
        "守住“至多绑定一次”，在 16 个场景、144 次 run 上做到更高吞吐、更低尾延迟和 100% 绑定成功率。"
        "请各位老师批评指正，谢谢。",
}
for _s in SLIDES:
    if _s["n"] in NOTES:
        _s["notes"] = NOTES[_s["n"]]


# ── 结构调整（2026-10-19）：补「研究背景」「国内外研究现状」两页 ──────────
# 说明：先按旧编号套用上面的讲稿，再插入/移位/重编号，避免讲稿错位。
_NEW_P3 = dict(
    kind="cards",
    title="研究背景",
    core="生产集群进入万节点量级，单实例架构在吞吐与高可用上同时受制",
    lead="Kubernetes 已成为云原生的事实标准，调度器处在 Pod 生命周期的关键路径上：它的吞吐与延迟"
         "直接决定集群资源利用率与业务响应速度。千节点规模下单实例尚可支撑，集群进入万节点量级后，"
         "三个瓶颈同时显现。",
    cards=[("吞吐存在上限", "activeQ 串行处理 Pod，大规模弹性伸缩与批任务启动被拖慢"),
           ("尾延迟持续抬升", "Filter/Score 遍历节点开销随规模线性上升，5000 节点下 P99 明显恶化"),
           ("单点故障风险", "Leader 崩溃后需等待 Standby 接管，这段窗口内集群完全无法调度")],
    takeaway="分布式改造是必然选择；但多实例并发又把“任一 Pod 至多绑定一次”推到设计前台。",
    cards_top=3.10,
    box_h=1.48,
    takeaway_top=5.05,
    notes="先说为什么要做。云原生负载规模持续增长，生产集群已进入万节点量级，业务对调度器提出双重要求："
          "既要秒级承接海量 Pod，又要长期运行不因单点失效中断服务。原生 kube-scheduler 在这两头上都是瓶颈："
          "主循环从 activeQ 串行取 Pod，CPU 核再多也用不上；Filter 和 Score 的代价随节点数增长，尾延迟被抬起来；"
          "Leader Election 只允许一个活跃实例，这既是单点的来源。所以工业界都在做分布式改造，而改造又会带来新的难题。",
    source="1.1 节；2.1 节",
)
_NEW_P4 = dict(
    kind="table",
    title="国内外研究现状：国外解决决策并发，国内做到分片落地",
    core="国外从集中式走到共享状态，国内以 Gödel 分片式多实例为代表；落盘侧仍缺结构化方案",
    table=[["系统", "区域", "架构特征", "局限"],
           ["Borg", "国外", "集中式", "单点决策路径上限"],
           ["Omega", "国外", "共享状态 + 乐观并发", "冲突处理复杂"],
           ["Mesos", "国外", "两级资源调度", "多框架共享开销"],
           ["kube-scheduler", "国外", "中心式插件框架", "超大规模扩展受限"],
           ["Gödel", "国内", "分片式分布式（字节跳动）", "独立 Binder 存在瓶颈"],
           ["Volcano", "国内", "插件增强（Gang/队列）", "中心路径仍有瓶颈"],
           ["Koordinator", "国内", "插件增强（QoS/超卖）", "单实例扩展受限"]],
    row_h=0.34, font=11, widths=[2.5, 1.15, 4.75, 3.7],
    bullets=["国外：Borg→Omega→Mesos→kube-scheduler",
             "国内：Gödel（字节跳动）做分片，Volcano/Koordinator 做插件增强",
             "缺口：绑定阶段串行化、漂移下的严格一致性"],
    notes="第二章把现有工作分成国外与国内两条线。国外从集中式走到共享状态：Borg 是集中式，Omega 提出共享状态加乐观并发，"
          "Mesos 用两级资源调度支持多框架共享，kube-scheduler 是中心式插件框架。国内的代表是 Gödel，字节跳动开源，"
          "用节点分区做分片式多实例，是目前少数完整实现分布式调度的项目；Volcano 和 Koordinator 走的是插件增强，"
          "分别面向批处理和混部。共同缺口在落盘侧：绑定阶段的串行化、以及分区归属漂移时的严格一致性，都缺少结构化方案。",
    source="第 2 章 §2.1~§2.6；表 1",
)

# 1) 取出旧的「时序形态」页（旧编号 19）移到备用
_timing = [s for s in SLIDES if s["n"] == 19][0]
SLIDES = [s for s in SLIDES if s is not _timing]
_timing = dict(_timing, n="B7", title="主场景 s3/w3 的时序形态（备用）",
               notes="备用页：" + _timing["notes"])
BACKUP.append(_timing)

# 2) 在 P2 之后插入两页
SLIDES.insert(2, _NEW_P3)
SLIDES.insert(3, _NEW_P4)

# 2b) 旧的「单实例调度器的三堵墙」页已被新研究背景页吸收（内容重复），删除
SLIDES = [s for s in SLIDES if s["title"] != "单实例调度器的三堵墙"]

# 3) 重新编号（页脚「第 X 页 / 25」依赖 n）
for _i, _s in enumerate(SLIDES, 1):
    _s["n"] = _i




# ── 讲稿二次校准（按「第 6 章 ≥55% 时长」重新配比，键为新页号）──────
NOTES2: dict[int, str] = {
    1: "各位老师上午好。我汇报的题目是《基于 etcd 的分布式 Kubernetes 调度器研究与实现》。这项工作要解决的问题很具体："
       "分布式调度器把绑定这一环拆出去之后，吞吐上不去、一致性也守不住。一句话概括：把 Binder 从独立进程合并回 Scheduler，"
       "再用四层机制守住“至多绑定一次”。十八分钟，只讲问题、方法、证据。",
    2: "先给全篇一个抓手。要回答两个问题：性能上，独立部署的 Binder 在高并发下重新变成串行瓶颈；一致性上，"
       "节点分区归属会漂移，必须保证任一 Pod 至多绑定一次。中间是方法：ENO 架构、四层容错、实证闭环。"
       "右边是证据：16 个场景、144 次 run、100% 成功率。",
    3: "先说为什么要做。生产侧集群已到万节点，本文覆盖 100 到 10000 四档；负载侧峰值到 2000 pods per second；"
       "同时要求长期运行不因单点中断。原生 kube-scheduler 是三堵墙：activeQ 串行取 Pod，多核用不满；"
       "Filter 与 Score 随节点数增长，尾延迟被抬高；Leader Election 只允许一个活跃实例。",
    4: "第二章把现有工作归成三条主线。架构演进：Borg 集中式、Omega 共享状态加乐观并发、Mesos 两级资源调度、"
       "Gödel 分片式多实例，一直在解决决策侧并发。批处理与混部：Volcano 做 Gang 与队列，Koordinator 做 QoS 与超卖，"
       "都属于插件增强。第三条是大规模一致性。共同缺口在落盘侧。",
    5: "Gödel 是最有代表性的开源实现：Dispatcher 分发、Scheduler 决策、Binder 落盘，加节点分区。"
       "但它留了两个缺口：Binder 独立部署，绑定又变成跨进程串行环节；分区归属会漂移，这一场景下的严格一致性缺少完整论证。"
       "本文的两个问题就对着这两个缺口。",
    6: "技术路线：并发做在分区上，一致性做在 etcd 上。Dispatcher 统一分发，Scheduler 在分区内并行决策，"
       "落盘走 dispatching、assuming、binding 三步事务。一致性不靠加锁，靠 etcd 三种原子语义："
       "resourceVersion 乐观并发、Watch 一致性视图、Bind 子资源原子写。",
    7: "这是总体架构。Dispatcher 只做两件事：分区怎么分、出事怎么退；中间多个 Scheduler 各管一个分区，跑 Filter、Score、Reserve；"
       "最下面把决策写进 apiserver。分区之间没有共享锁，状态靠 Watch 驱动，这是能扩展的前提。",
    8: "左边是原形态，Binder 独立部署，决策完要把任务发过去；右边是本文形态，Binder 就在 Scheduler 进程里。"
       "这一刀去掉三段开销：事件传递、跨进程调用、序列化。后面所有吞吐数字都从这一刀下来，同时保留 CLI 开关可回退。",
    9: "难点在缓存。以前 Binder 在另一个进程，缓存要么复制要么重建。CacheAdapter 让进程内 Binder 直接拿到同一份 "
       "SchedulerCache 的对象引用，所以叫零拷贝。两边看到同一份状态，Layer 0 的校验才有同一个真相可依。",
    10: "四层是一条时间轴。Bind 前，Layer 0 校验归属注解，把漂移拦在门外；Bind 中，Layer 1 用同步退避处理暂态错误；"
        "失败后，Layer 2 用异步 Reconciler 回收孤儿状态；重试耗尽，Layer 3 由 Dispatcher 清注解、触发全局重分发。",
    11: "所有机制最后都回到不变量 I：任一 Pod 至多绑定到一个节点。证明拆四点：P1 来自 Bind 子资源原子写；"
        "P2 是 Assumed 状态清理；P3 是注解清理与重分发的时序；P4 是 Layer 0 前置拦截。四层都不破坏 I，且可在 apiserver 侧复核。",
    12: "实验设计说明三点公平性。第一，KWOK 仿真，kind 集群内运行，Kubernetes 版本与对照组一致。第二，五个调度器 Pod 规格相同，"
        "客户端 QPS 与 Burst 都是 10000，避免把限流误读成能力差异。第三，每场景三次取中位数，共 144 次 run。",
    13: "这一页是方法学核心。吞吐时序是爬升、平台、归零三段，直接取平均会被尾段零值稀释，稀释程度还取决于跑多久，"
        "跨调度器就不可比，所以主口径是总工作量除以总完成时间。时序类指标先对三条 run 逐点取中位数，再剔首尾各两点。"
        "还有一条限定：c、d、e 是单实例，过载时大量 Pod 堵在 activeQ 没进直方图，存在幸存者偏差，只做定性说明。",
    14: "在给性能数字之前，先说正确性。144 次 run，每次跑完都在 apiserver 侧断言：未绑定为零、重复绑定为零，全部通过；"
        "ENO 那 48 次 run 成功率都是 100%。两场故障注入各 6 项判据全过。所谓正确，不是日志没报错，而是外部事实对得上。",
    15: "第一场注入：s2/w2、三实例，第 30 秒把 10% 的节点、约 100 个，归属注解从 scheduler-0 改为 scheduler-1。"
        "NodeValidator 拦截 300 次，Dispatcher 回退 300 次，两条曲线重叠。关键是拦截不等于丢弃：Pod 进回退队列被重分发，"
        "所以成功率仍是 1.00，断言 50000 全过，总耗时 683 秒，只比基线多 3 秒。",
    16: "第二场注入：第 10 秒杀掉 scheduler-0，停机 180 秒，实测中断 189 秒。被杀实例未完成的绑定只占 68/8407，即 0.81%；"
        "两个存活实例接管 8407 个 Pod，孤儿回收 77.15 每秒，队列峰值 353 后回落到 2。累计绑定 49607/50000，断言仍全过。"
        "代价是 784 秒、多 104 秒，这是工作量重排，不是数据损坏。",
    17: "五组对比，结论是三档。第一档 ENO 与 Gödel，都是几百 pods/s；第二档 kube-scheduler；第三档 Volcano 与 Koordinator，"
        "只有约 48 和约 24 pods/s，几乎不随规模变化。主评估四场景里，ENO 比 kube-scheduler 高 1.8% 到 22.5%，"
        "比 Volcano 约 6 倍、比 Koordinator 12 倍以上。唯一例外是 s1/w1 低负载低 7.2%，那是没饱和。",
    18: "和 Gödel 逐场景对比：16 个场景 14 个领先、2 个持平，没有落后的，提升 2.0% 到 22.9%，平均 11.9%。"
        "优势最大的是高负载与多实例：s2/w3 高 22.9%，s3/w3 三实例高 21.7%，s3/w5 与 s3/w7 三实例也都超过 21%。"
        "持平场景是没饱和，完成时间由注入速率决定。",
    19: "延迟这页。除 s2/w2 外，11 个非 Gang 场景 P99 都低于 Gödel，改善 0.3% 到 82.9%。最典型是 s2/w3，23.48 秒降到 4.00 秒；"
        "单实例 s3/w3 从 32.57 秒到 16.22 秒。Pod 端到端 P99 在 12 个非 Gang 场景也都不高于 Gödel，改善 0.6% 到 75.3%。"
        "Gang 是反的，放到局限里展开。",
    20: "这是全文最强的归因证据。同样把实例从 1 加到 3，两边延迟都降约 99%，这部分一样。差别在吞吐："
        "ENO 从 297.6 到 349.7，提升 17.5%；Gödel 从 283.3 到 287.4，只提升 1.4%。同样多的并发能力，"
        "Gödel 的增量被独立 Binder 的串行绑定吸收掉了。",
    21: "两件事。第一，规模从 5000 到 10000、实例数不变，两边都退化：ENO -15.2%，Gödel -2.3%；但 ENO 仍领先——"
        "吞吐 296.7 对 280.9 高 5.6%，P99 0.19 对 0.28 秒低 33.4%，队列峰值 9 对 61。第二，复杂负载：极限 +9.3% 与 +16.0%，"
        "突发 +21.3% 与 +2.8%，异构 s3 高 21.2%、s4 持平。注意固定三实例，回落不等于扩展上限。",
    22: "把机制和指标对齐。进程内绑定去掉事件传递，对应 E2E 降低，三实例 0.45 对 0.93 秒；零拷贝让状态复用无同步延迟；"
        "关键是第三行，没有独立 Binder 的串行段，吞吐才能随实例扩展，+17.5% 对 +1.4%；第四行四层容错守住不变量。"
        "也要说明相关与归因的区别：峰值吞吐不是每个场景都领先，s3/w5 与 s4/w3 低于 Gödel。",
    23: "局限六条，只讲关键。KWOK 是仿真，绝对数值不外推，但跨调度器相对比较成立。Gang 即 w6，ENO 尾延迟确实更高："
        "吞吐高 4.3% 到 19.1%，单 Pod P99 高 1.6 到 4.1 倍，原因是同组预留等待与决策共用进程和队列，"
        "我们没用独立计时实验把两段分离。其余是固定实例数、资源公平、Volcano 口径、幸存者偏差。",
    24: "最后收束。两个创新：ENO 把 Binder 放进进程内并用 CacheAdapter 共享缓存；四层容错给出不变量 I 的证明要点。"
        "三组证据：16 场景 144 次 run 全成功、平均 +11.9%、P99 最高 -82.9%、实例扩展 +17.5% 对 +1.4%。"
        "价值：不改 API、保留开关、基准开源。",
    25: "汇报到这里。一句话总结：把 Binder 合并进 Scheduler 进程，用 etcd 原子语义上的四层容错守住“至多绑定一次”，"
        "在 16 个场景、144 次 run 上做到更高吞吐、更低尾延迟、100% 成功率。请各位老师批评指正。",
}
for _s in SLIDES:
    if _s["n"] in NOTES2:
        _s["notes"] = NOTES2[_s["n"]]

# ── 讲稿补足（把总时长拉到 18~20 分钟，并让第 6 章占比 ≥55%）──────
_EXTRA: dict[int, str] = {
    1: "今天的汇报分为问题、方案、证据三段。",
    2: "三个数字分别是场景数、run 数与绑定成功率。",
    3: "这三堵墙叠在一起，单实例架构就很难再往上走。",
    4: "三条主线的共同缺口，就是本文的切入点。",
    5: "所以本文把绑定拉回进程内，并把容错做成结构化四层。",
    6: "这三步事务，就是后面四层容错的落点。",
    7: "三层职责清晰，故障面也就容易划清。",
    8: "开关的意义是：改动可回退，部署可平滑。",
    9: "零拷贝的收益，会在扩展性实验里直接体现。",
    10: "四层之间是衔接关系，不是四个独立补丁。",
    11: "这也是后面所有实验断言的设计依据。",
    12: "所以主评估用 s2/w2、s2/w3、s3/w2、s3/w3 四个场景，扩展场景另算。",
    13: "这三条口径，是后面所有数字可比的前提。另外，跨调度器我只用吞吐、队列堆积与绑定成功率做整体比较，"
        "延迟只在 ENO 与 Gödel 之间比。",
    14: "两场注入分别是分区漂移与实例失活，正好覆盖两类威胁。判据包括成功率、断言、拦截数、回退数、耗时与队列行为，六项都要成立。",
    15: "这组数字说明 Layer 0 只是把错误前置，不是把工作丢掉，代价几乎为零。",
    16: "对比基线是同一场景下的无故障运行，680 秒；这也说明接管是可控的，代价有界。",
    17: "柱状图按场景排序，第三档几乎是一条水平线。",
    18: "四个亮点场景分别是高负载、突发、异构与多实例。平均 11.9% 这个数，是把 14 个领先场景的幅度取均值得到的。",
    19: "延迟的单位都是秒，纵轴用对数，便于跨量级比较；改善的下界 0.3% 出现在接近饱和的场景。",
    20: "扩展性实验固定负载为 s3/w3，w3 即 1000 pods per second，两组都跑三次取中位数。延迟数量级下降，"
        "说明瓶颈不在决策侧。",
    21: "s4 的退化与固定三实例有关，这写在局限里。",
    22: "四行对应四个机制，每一项都有可复核的字段；如果评委追问某个数字，备用页里有完整口径以及原始目录。",
    23: "这六条不是免责声明，而是给结论划边界；在这个边界内，跨调度器的相对结论是稳的。",
    24: "三组证据合起来，正好对应问题、方法与效果。",
    25: "如果只问一个问题，我的回答就是刚才那一句。",
}
for _s in SLIDES:
    if _s["n"] in _EXTRA:
        _s["notes"] = _s.get("notes", "") + _EXTRA[_s["n"]]


# ── 结构定稿：封面之后前三页 = 研究背景 / 国内外研究现状 / 研究内容与创新点 ──
_INNOV = dict(
    kind="cards",
    cols=2,
    box_h=2.3,
    title="研究内容与创新点：一页看懂全文",
    core="两个创新：把 Binder 放进 Scheduler 进程；用四层容错守住“至多绑定一次”",
    cards=[("创新 1 · ENO 架构",
            "单 Dispatcher、多独立 Scheduler；Binder 与决策同域；CacheAdapter 零拷贝共享 SchedulerCache"),
           ("创新 2 · 四层容错",
            "L0 归属校验 · L1 同步退避 · L2 异步回收 · L3 全局回退，全部建立在 etcd 原子语义上")],
    takeaway="两条创新指向同一目标：不改 API 的前提下，让分布式调度既跑得快，又绑得对。",
    takeaway_top=4.75,
    notes="这一页把全文压成两句。架构上，单 Dispatcher、多独立 Scheduler，Binder 合并进 Scheduler 进程，"
          "缓存用 CacheAdapter 零拷贝共享，去掉跨进程的事件传递与序列化。一致性上，四层容错，"
          "L0 到 L3 覆盖 Bind 前、中、后，每一层都建立在一类 etcd 原子语义上。两条创新指向同一个目标。",
    source="第 4、5 章",
)
_old_overview = next(s for s in SLIDES if s["title"].startswith("让分布式调度"))
_bg = next(s for s in SLIDES if s["title"].startswith("研究背景"))
_st = next(s for s in SLIDES if s["title"].startswith("国内外研究现状"))
for _s in (_old_overview, _bg, _st):
    SLIDES.remove(_s)
SLIDES.insert(1, _bg)
SLIDES.insert(2, _st)
SLIDES.insert(3, _INNOV)
for _i, _s in enumerate(SLIDES, 1):
    _s["n"] = _i

# ── 讲稿微调：把总时长压到 19.8 分钟，第 6 章占比稳在 55% 以上 ──
_SHORTEN: dict[int, str] = {
    2: "先说背景。Kubernetes 已经是云原生的事实标准，调度器在 Pod 生命周期的关键路径上，它的吞吐和延迟"
       "直接决定资源利用率与业务响应速度。千节点规模下单实例还能撑住，到了万节点量级就有三个瓶颈："
       "activeQ 串行处理 Pod，吞吐有上限；Filter 和 Score 随节点数线性增长，五千节点下 P99 明显恶化；"
       "Leader 崩溃要等 Standby 接管，这段窗口集群完全不能调度。",
    3: "现状分国外与国内两条线。国外从集中式走到共享状态：Borg、Omega、Mesos，再到 kube-scheduler 的插件框架。"
       "国内代表是 Gödel，字节跳动开源，用节点分区做分片式多实例；Volcano 与 Koordinator 走插件增强。"
       "共同缺口在落盘侧，本文正落在这个缺口上。",
}
for _s in SLIDES:
    if _s["n"] in _SHORTEN:
        _s["notes"] = _SHORTEN[_s["n"]]

# ── 标题瘦身：去掉「：」及其后的描述（结论改由标题下的核心句承载）──
import re as _re

for _s in SLIDES + BACKUP:
    _s["title"] = _re.split(r"[：:]", _s["title"])[0].strip()

# ── 讲稿补一句「编码怎么读」（P12 是第一次出现 s/w 编码的页）──
for _s in SLIDES:
    if _s["n"] == 12:
        _s["notes"] = ("先讲编码：s 是规模档位，w 是负载强度，inst 是实例数，后面场景名都由这三段拼成。" + _s["notes"])

# ── P2 讲稿：只讲背景，不展开技术细节 ──
for _s in SLIDES:
    if _s["n"] == 2:
        _s["notes"] = ("先说背景。云原生负载规模持续增长，生产集群已经进入万节点量级；业务对调度器提出双重要求，"
                       "既要秒级承接海量 Pod，又要长期运行不因单点失效中断服务。原生 kube-scheduler 是单实例架构，"
                       "这两条同时满足很吃力——这正是工业界做分布式改造的起点，也是本文要处理的问题。")

# ── 顺序：架构（三层职责）在前，内部流程在后 ──
_arch = next(s for s in SLIDES if s["title"].startswith("三层职责"))
_flow1 = next(s for s in SLIDES if s["title"].startswith("Dispatcher 内部流程"))
_flow2 = next(s for s in SLIDES if s["title"].startswith("Scheduler 内部流程"))
for _s in (_arch, _flow1, _flow2):
    SLIDES.remove(_s)
_i = next(i for i, s in enumerate(SLIDES) if s["title"].startswith("分布式改造真正的难点")) + 1
for _off, _s in enumerate((_arch, _flow1, _flow2)):
    SLIDES.insert(_i + _off, _s)
for _i2, _s in enumerate(SLIDES, 1):
    _s["n"] = _i2
TOTAL = len(SLIDES)

# ── 讲稿再平衡：新增一页流程后，压缩非实验部分，保证 ≤20 分钟且第 6 章 ≥55% ──
_FINAL: dict[int, str] = {
    1: "各位老师上午好。我汇报的题目是《基于 etcd 的分布式 Kubernetes 调度器研究与实现》。这项工作针对分布式调度器"
       "把绑定拆出去之后吞吐上不去、一致性也守不住的问题。一句话概括：把 Binder 合并回 Scheduler，"
       "用四层机制守住“至多绑定一次”。",
    4: "这一页把全文压成两句。架构上，单 Dispatcher、多独立 Scheduler，Binder 合并进 Scheduler 进程，"
       "CacheAdapter 零拷贝共享缓存，去掉跨进程的事件传递与序列化。一致性上，四层容错，L0 到 L3 覆盖 Bind 前中后，"
       "每层对应一类 etcd 原子语义。两条创新指向同一个目标：不改 API，跑得快且绑得对。",
    5: "Gödel 是最有代表性的开源实现：Dispatcher 分发、Scheduler 决策、Binder 落盘，加节点分区。"
       "但它留了两个缺口：Binder 独立部署，绑定又变成跨进程串行环节；分区归属会漂移，严格一致性缺少完整论证。"
       "本文的两个问题就对着这两个缺口。",
    7: "先看 Dispatcher 的内部流程。它进来先做归属校验，把分区漂移的 Pod 拦住；再按实例负载做分区选择，"
       "决定交给哪个 Scheduler；然后入队。注意它不选节点，只决定 Pod 去哪，选节点是下一环的事，"
       "这也是它能并行分发的原因。",
    12: "所有机制最后都要回到不变量 I：任一 Pod 至多绑定到一个节点。证明拆四点：P1 来自 Bind 子资源原子写；"
        "P2 是 Assumed 状态清理；P3 是注解清理与重分发的时序；P4 是 Layer 0 前置拦截。四层都不破坏 I，"
        "而且可以在 apiserver 侧用断言复核，不是自说自话。",
}
for _s in SLIDES:
    if _s["n"] in _FINAL:
        _s["notes"] = _FINAL[_s["n"]]

if __name__ == "__main__":
    build()
