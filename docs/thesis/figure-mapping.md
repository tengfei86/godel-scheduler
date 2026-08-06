# 论文图表规划

**论文题目**：基于 etcd 的分布式 Kubernetes 调度器研究与实现

**主线**：多个 Scheduler 实例并发调度时的一致性挑战 → 基于 etcd 原子性的解决方案（apiserver 事务 + Pod 注解 CAS + Watch 一致性）→ 大规模场景下的架构与性能优化。

---

## 一、章节结构（草案）

| 章 | 标题 | 页数 | 主图数 |
|---|---|---|---|
| 第 1 章 | 绪论 | 6-8 | 0 |
| 第 2 章 | 相关工作与背景 | 8-10 | 0-1 |
| 第 3 章 | 分布式 Kubernetes 调度器系统架构 | 12-14 | 4-5 |
| 第 4 章 | 基于 etcd 语义的一致性容错机制 | 10-12 | 3-4 |
| 第 5 章 | 面向大规模场景的架构优化（ENO） | 10-12 | 3 |
| 第 6 章 | 实验设计与评估 | 14-18 | 2 + 8~10 数据图 |
| 第 7 章 | 总结与展望 | 4-6 | 0 |

**已确认**（2026-08-06）：
1. ✅ 采用 7 章结构，第 5 章 ENO 单独成章
2. ⏳ 第 2 章相关工作独立性（待与导师沟通后再定，暂按独立章节起草）

---

## 二、图片资产分类

### A. 你自己绘制的图（第 3 章主图，优先使用）

| 论文编号 | 用途章节 | 你的原文件 |
|---|---|---|
| **图 3-1** | §3.1 系统总体架构（**全章门面图，一图看懂全系统**）| [docs/images/arch.drawio.png](docs/images/arch.drawio.png) |
| **图 3-3** | §3.3 Dispatcher 内部：Pod 在数据结构间的流转 | [docs/images/dispatcher_flowchart.png](docs/images/dispatcher_flowchart.png) |
| **图 3-4** | §3.4 单个 Scheduler 内部：Pod 在活跃队列/退避队列间的流转 | [docs/images/scheduler_flowchart.png](docs/images/scheduler_flowchart.png) |

> **图 3-2 空位** — 建议给"基于 etcd 的三步事务写入"单独画一张时序图（dispatching→assuming→binding 三个 API 调用如何落到 etcd）。若你自己想画就画；也可以我用 mermaid 生成一张备选。

### B. Claude 之前生成的 Mermaid 图（差异化保留 vs 降级）

**保留在第 4 章（一致性容错，核心）**：

| 论文编号 | 用途章节 | 现有文件 | 保留理由 |
|---|---|---|---|
| **图 4-1** | §4.1 Pod 生命周期状态机 + 4 层容错介入点 | [fig4-1-pod-state-machine.pdf](docs/performance/figures/fig4-1-pod-state-machine.pdf) | 状态机视角与你的 dispatcher/scheduler 流程图**互补**，不重复 |
| **图 4-2** | §4.5 Layer 3 Dispatcher 错误恢复流程 | [fig4-2b-dispatcher-error-recovery.pdf](docs/performance/figures/fig4-2b-dispatcher-error-recovery.pdf) | 专门讲 Dispatcher 侧的失败重试与回退，与你的 dispatcher_flowchart.png 不重复（后者是数据结构流转视角）|
| **图 4-3** | §4.6 一致性论证：不变量 + 威胁-防御-证明 | [fig4-3-consistency-invariant.pdf](docs/performance/figures/fig4-3-consistency-invariant.pdf) | §4.6 论证章节的核心图，无法替代 |

**降级到第 5 章（ENO 优化章节，讲"改造前 vs 改造后"）**：

| 现有文件 | 新用途 |
|---|---|
| [fig3-1a-shared-binder-arch.pdf](docs/performance/figures/fig3-1a-shared-binder-arch.pdf) | §5.2 改造前：独立 Binder 的 5 步跨进程流程（论证瓶颈）|
| [fig3-1b-embedded-binder-arch.pdf](docs/performance/figures/fig3-1b-embedded-binder-arch.pdf) | §5.2 改造后：ENO 3 步进程内流程（与 fig3-1a 并列对比）|
| [fig3-2-cache-zero-copy.pdf](docs/performance/figures/fig3-2-cache-zero-copy.pdf) | §5.3 Cache 零拷贝共享机制 |
| [fig3-3-eno-deployment-topology.pdf](docs/performance/figures/fig3-3-eno-deployment-topology.pdf) | §5.4 ENO 部署拓扑（K8s Deployment 视角）|

**暂无取消项**。

> 备注：[fig4-2a-dispatcher-main-flow.pdf](docs/performance/figures/fig4-2a-dispatcher-main-flow.pdf) 与你的 dispatcher_flowchart.png 视角略有重叠，先**保留**，写作中若发现叙述重复再决定去留。可能用途：
> - 放在 §4.5 或附录，作为 Dispatcher **策略分发决策路径**的详细视图（PodGroup / Owner 亲和 / 负载均衡三分支）
> - 你的 dispatcher_flowchart.png 从"Pod 在数据结构间流转"视角画，这张从"策略选择决策树"视角画，可以互补

### C. 仍需补画的图

| 论文编号 | 用途 | 现状 | 建议来源 |
|---|---|---|---|
| 图 3-2（可选） | §3.2 基于 etcd 的三步事务时序图 | 未画 | mermaid 生成 |
| 图 6-1 | §6.1 实验环境拓扑（kind + KWOK + Prometheus + 5 组调度器）| 未画 | mermaid 生成 |
| 图 6-2 | §6.1 单次实验流程时序图 | 未画 | mermaid 生成 |

### D. 数据图（第 6 章，从实验结果自动生成）

数据源：[test/e2e/benchmark/results/](test/e2e/benchmark/results/) 60 次实验的 JSON

生成脚本：[test/e2e/benchmark/collect/plot-results.py](test/e2e/benchmark/collect/plot-results.py)

| 编号 | 内容 | 命令片段 |
|---|---|---|
| 图 6-3 | 稳态调度吞吐 vs 集群规模（a/b/c/d/e × s2/s3 × w2/w3） | `plot-results.py --compare --metric bind_throughput_pods` |
| 图 6-4 | P90 调度延迟对比（箱线图或均值±1σ） | `plot-results.py --compare --metric scheduling_latency_p90` |
| 图 6-5 | P99 调度延迟对比 | `plot-results.py --compare --metric scheduling_latency_p99` |
| 图 6-6 | 绑定成功率对比 | `plot-results.py --compare --metric bind_success_rate` |
| 图 6-7 | Pod E2E 延迟对比（Dispatcher → Bound）| `plot-results.py --compare --metric pod_e2e_latency_p99` |
| 图 6-8 | goroutines 资源开销对比 | `plot-results.py --compare --metric goroutines` |
| 图 6-9 | 单调度器 vs Gödel: bind_inflight 并发度对比（可选）| |
| 图 6-10 | 单调度器 vs Gödel: node_validation_failures / dispatcher_fallback 触发次数（Layer 0/3 触发验证）| |

---

## 三、图表规范（北航学位论文规范 2025.3）

### 3.1 编号
- 主体统一 `图{章号}-{序号}` 与 `表{章号}-{序号}`，编号在正文中连续，不因章节小节重置
- 附录另编：`图A.1`、`表B.2`
- 分图用 `(a) (b) (c)`（英文括号）

### 3.2 图题
- 位置：**图下方**，居中
- 字体：宋体加粗五号；英文和数字用 Times New Roman
- 段前 6 磅，段后 12 磅，单倍行距
- 图序与图题文字间空 2 个半角字符宽度
- 示例："图 3-1  基于 etcd 的分布式 Kubernetes 调度器系统架构"
- 英文对照可选（若给出，另起一行放在中文下方，末尾无句号）

### 3.3 表题
- 位置：**表上方**，居中
- 字体：宋体加粗五号；英文和数字用 Times New Roman
- 段前 12 磅，段后 6 磅
- 一律用**三线表**（上下线 1.5 磅，中间线 1 磅）
- 单元格：宋体五号，居中，段前段后 3 磅

### 3.4 图内文字
- 图内所有描述性文字用**中文**（专用符号/单位可保留英文）
- 图内文字字体：宋体五号，数字/字母 Times New Roman 五号
- 分辨率 ≥ 300 dpi
- 使用形状/线型/填充图案区分，尽量少用颜色（考虑复制效果）

### 3.5 图注
- 附注格式："附注1：..."（五号宋体，段前 6 磅段后 12 磅）

---

## 四、文件组织规划

### 4.1 目录结构

```
docs/thesis/
  figures/                     ← 论文用图片统一目录（本次协作产出）
    fig3-1-system-arch.png     ← 从 docs/images/arch.drawio.png 复制/重命名
    fig3-3-dispatcher-flow.png ← 从 docs/images/dispatcher_flowchart.png 复制/重命名
    fig3-4-scheduler-flow.png  ← 从 docs/images/scheduler_flowchart.png 复制/重命名
    fig4-1-pod-state-machine.{mmd,pdf,png}  ← 从 docs/performance/figures/ 复制
    fig4-2-dispatcher-error.{mmd,pdf,png}
    fig4-3-consistency-invariant.{mmd,pdf,png}
    fig5-1-shared-vs-eno.{mmd,pdf,png}  ← 由现有 3-1a/3-1b 组合
    fig5-2-cache-zero-copy.{mmd,pdf,png}
    fig5-3-eno-deployment.{mmd,pdf,png}
    fig6-1-experiment-env.{mmd,pdf,png}  ← 待画
    fig6-2-experiment-flow.{mmd,pdf,png} ← 待画
    fig6-3~fig6-10-*.pdf                 ← 数据图自动生成
  figure-mapping.md            ← 本文件
  chapters/                    ← 各章 Markdown 草稿
    01-introduction.md
    02-related-work.md
    03-architecture.md
    04-consistency.md
    05-eno-optimization.md
    06-evaluation.md
    07-conclusion.md
  bib/                         ← 参考文献 BibTeX
```

### 4.2 命名规则
- 图片文件：`fig{章号}-{序号}-{english-slug}.{ext}`
- Mermaid 源码：同名 `.mmd`
- 输出三份产物：`.mmd`（源） + `.pdf`（论文用矢量） + `.png`（预览）

### 4.3 图片归档状态（2026-08-06 完成）

已按"复制 + 论文新编号重命名"方案落盘到 [docs/thesis/figures/](docs/thesis/figures/)，原图保留在 [docs/images/](docs/images/) 和 [docs/performance/figures/](docs/performance/figures/) 便于溯源。

**目录清单**：

| 论文编号 | 来源 | 落盘文件 |
|---|---|---|
| 图 3-1 | docs/images/arch.drawio.png | fig3-1-system-arch.png |
| 图 3-3 | docs/images/dispatcher_flowchart.png | fig3-3-dispatcher-flow.png |
| 图 3-4 | docs/images/scheduler_flowchart.png | fig3-4-scheduler-flow.png |
| 图 4-1 | docs/performance/figures/fig4-1-pod-state-machine.* | 同名（mmd/pdf/png/svg 全套） |
| 图 4-2a | docs/performance/figures/fig4-2a-dispatcher-main-flow.* | 同名（mmd/pdf/png/svg 全套） |
| 图 4-2b | docs/performance/figures/fig4-2b-dispatcher-error-recovery.* | 同名（mmd/pdf/png/svg 全套） |
| 图 4-3 | docs/performance/figures/fig4-3-consistency-invariant.* | 同名（mmd/pdf/png/svg 全套） |
| 图 5-1a | docs/performance/figures/fig3-1a-shared-binder-arch.* | fig5-1a-shared-binder.* |
| 图 5-1b | docs/performance/figures/fig3-1b-embedded-binder-arch.* | fig5-1b-eno-arch.* |
| 图 5-2 | docs/performance/figures/fig3-2-cache-zero-copy.* | fig5-2-cache-zero-copy.* |
| 图 5-3 | docs/performance/figures/fig3-3-eno-deployment-topology.* | fig5-3-eno-deployment.* |

**待补**：
- 图 3-2 基于 etcd 三步事务时序图（**暂缓** — 写到 §3.2 时再决定是否画；如不画则正文用文字 + 代码片段说明）
- 图 6-1 实验环境拓扑（待第 6 章写作时画）
- 图 6-2 单次实验流程时序（待第 6 章写作时画）
- 图 6-3 ~ 6-10 数据图（等 §6 写作时用 plot-results.py 生成）

---

## 五、图表清单（按章节最终排布）

### 第 3 章 分布式调度器系统架构

| 图号 | 标题 | 来源 |
|---|---|---|
| 图 3-1 | 基于 etcd 的分布式 Kubernetes 调度器系统架构 | 你的 arch.drawio.png |
| 图 3-2 | 基于 etcd 的三步事务时序（dispatching / assuming / binding）| **待画（mermaid）**|
| 图 3-3 | Dispatcher 内部数据结构流转：Pod 从新建到分发完成 | 你的 dispatcher_flowchart.png |
| 图 3-4 | 单个 Scheduler 内部数据结构流转：Pod 在活跃/退避队列间的流动 | 你的 scheduler_flowchart.png |

### 第 4 章 基于 etcd 语义的一致性容错机制

| 图号 | 标题 | 来源 |
|---|---|---|
| 图 4-1 | Pod 生命周期状态机与 4 层容错介入点 | 已有 fig4-1-pod-state-machine |
| 图 4-2a | Dispatcher 策略分发决策路径 | 已有 fig4-2a-dispatcher-main-flow（保留待定，视写作是否与图 3-3 叙述重复决定去留）|
| 图 4-2b | Dispatcher 侧的错误恢复流程（Layer 3 全局回退）| 已有 fig4-2b-dispatcher-error-recovery |
| 图 4-3 | 一致性论证：核心不变量 + 4 层威胁-防御映射 | 已有 fig4-3-consistency-invariant |

### 第 5 章 面向大规模场景的架构优化（ENO）

| 图号 | 标题 | 来源 |
|---|---|---|
| 图 5-1 | 独立 Binder（改造前） vs ENO 进程内合并（改造后） | 由 fig3-1a + fig3-1b 组合，或分成 图 5-1a / 图 5-1b |
| 图 5-2 | Cache 零拷贝共享数据流 | 已有 fig3-2-cache-zero-copy（含刚才 Embedded Binder → ENO Binder 的修改）|
| 图 5-3 | ENO 部署拓扑（Kubernetes Deployment 视角）| 已有 fig3-3-eno-deployment-topology |

### 第 6 章 实验设计与评估

| 图号 | 标题 | 来源 |
|---|---|---|
| 图 6-1 | 实验环境拓扑 | **待画（mermaid）**|
| 图 6-2 | 单次实验流程时序 | **待画（mermaid）**|
| 图 6-3 ~ 图 6-10 | 各类数据对比图 | plot-results.py 自动生成 |

**图表合计**：约 21 张（10 主图 + 2 待画 + 1-2 组合图 + 8 数据图），符合北航规范中"图数适度、每章 1-6 张"的建议。

---

## 六、下一步行动清单

### 立即可做（无需你确认）
- [x] 建立本规划文档
- [ ] 建立 `docs/thesis/figures/` 目录并复制/重命名图片
- [ ] 复制第 4 章的 3 张现有 mermaid 图到新目录

### 待你确认后执行
1. **章节结构**：接受第 1 节的 7 章草案吗？ENO 是否单独成第 5 章？
2. **图 3-2**：是否让我用 mermaid 画一张"基于 etcd 三步事务时序图"？
3. **文件组织**：图片复制到 `docs/thesis/figures/` 还是原地引用？
4. **是否开工**：图规划确认后，从第 3 章开始写正文草稿？

---

*本文档随论文写作过程持续更新。*
