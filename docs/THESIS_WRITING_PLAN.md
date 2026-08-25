# 硕士论文写作规划：ENO 大规模集群调度性能研究

## Context

**背景**：基于开源 Gödel Scheduler 完成了 ENO 架构改造与全面 benchmark（vs Gödel/kube-scheduler/Volcano/Koordinator），代码已实现完毕（[pkg/binder/embedded_binder.go](../pkg/binder/embedded_binder.go) 等 8 个新文件 + 4 层容错），部分数据已跑完（当前 `test/e2e/benchmark/results/` 只有 a/b/c × s2 × w1/w2 × 3 run = 18 次）。

**任务**：写一份 60-80 页中文硕士学位论文，正文中文 + 摘要/关键词双语。三大创新点：
1. ENO 架构（进程内合并 vs 独立 binder，Cache 零拷贝共享）
2. 4 层容错机制（Node 校验 / 同步重试 / 异步 Reconciler / 跨实例回退）
3. 大规模集群性能与横向扩展性对比（含 Volcano/Koordinator）

**约束**：论文写作前需补跑核心场景数据（+s3、+w3/w4/w5），使论证具备说服力（现有 s2 + 500 pods/s 太温和，看不出瓶颈差距）。

---

## 一、数据补跑（论文写作的前提，独立于写作本身）

**优先级递减**，按机器时间可用度递减执行：

| 优先级 | 命令 | 数据用途 | 预计耗时 |
|---|---|---|---|
| P0 | `./run-all.sh --groups "a b c d e" --scales "s2 s3" --workloads "w2 w3" --setup-nodes` | 主对比表 + 五调度器 P99/P99.9 延迟 vs 规模曲线 | 中 |
| P1 | `./run-all.sh --groups "a b" --scales "s3" --workloads "w5"` | 突发洪峰恢复能力（论文 §5.3） | 短 |
| P2 | `./run-all.sh --groups "a b" --scales "s3" --workloads "w3" --instances "1 2 3 5"` | 水平扩展性曲线（论文 §5.4，直接支撑创新点 3） | 长 |
| P3 | `./run-all.sh --groups "a b" --scales "s3" --workloads "w6"` | Gang 调度场景（可选，若时间紧张可省） | 中 |

**补跑期间需并行的准备工作**：
- 数据落盘后先用 `plot-results.py --average --std-band` 生成各组均值，再 `--compare` 生成跨组对比图，直接产出论文用图
- 更新 [test/e2e/benchmark/results/final-charts/chart-index.md](../test/e2e/benchmark/results/final-charts/chart-index.md)，把新的关键百分比数据（吞吐提升 %、P99 降低 %）填进去
- 每次实验完成后立即 git commit，避免机器故障丢数据（[run-all.sh](../test/e2e/benchmark/run-all.sh) 末段已自带 auto-commit）

---

## 二、论文结构（60-80 页硕士论文标准框架）

以 GB/T 7714 中文学位论文格式为基准。章节内容规划：

### 摘要（中/英） + 关键词
- 500 字中文 + 300 词英文
- 关键词：Kubernetes 调度器、大规模集群、ENO、分区调度、性能优化

### 第 1 章 绪论（8-10 页）
- 1.1 研究背景：云原生调度器演进（K8s → Volcano → Koordinator → Gödel）
- 1.2 问题陈述：Gödel Shared Binder 单点瓶颈 + gRPC 跨进程开销（引用 [BINDER_ARCHITECTURE_REFACTORING.md](../BINDER_ARCHITECTURE_REFACTORING.md) §2.1）
- 1.3 研究目标与创新点（明确列出 3 个创新点）
- 1.4 论文组织结构

### 第 2 章 相关工作与背景（10-12 页）
- 2.1 Kubernetes 原生 kube-scheduler 架构与瓶颈
- 2.2 批处理调度器：Volcano 的 Gang 调度与 Session 机制
- 2.3 混部调度器：Koordinator 的 QoS 感知
- 2.4 大规模调度：Gödel 三层架构（Dispatcher / Scheduler / Binder）、分区调度模型
- 2.5 相关性能研究综述

**素材来源**：[docs/features/](features/)、[docs/performance/best-practice.md](performance/best-practice.md)（原 Gödel 官方性能评估，可作 2.4 节直接改写素材）；外部引用（Gödel 论文/字节跳动博客）需另行检索补齐

### 第 3 章 ENO 架构设计（12-15 页，创新点 1 核心章节）
- 3.1 现有 Shared Binder 架构分析（Deployment 拓扑图 + gRPC 通信序列图）
- 3.2 设计目标与约束（保持分区语义、向后兼容、可切换）
- 3.3 ENO 架构总览（关键图：进程边界对比图）
  - 引用已有的 [docs/performance/figures/fig4-1-consistency-cas-flow](performance/figures/)（CAS 一致性流程）
  - 引用 [docs/performance/figures/fig4-2-dispatcher-task-division](performance/figures/)（Dispatcher 任务划分）
- 3.4 关键设计决策：
  - 3.4.1 `BinderInterface` 抽象（[pkg/binder/binder_interface.go](../pkg/binder/binder_interface.go)）
  - 3.4.2 Cache 零拷贝共享（[pkg/binder/cache_adapter.go](../pkg/binder/cache_adapter.go)）
  - 3.4.3 CLI 开关与运行时切换（[cmd/scheduler/app/options/options.go](../cmd/scheduler/app/options/options.go) 的 `--enable-embedded-binder`）
- 3.5 与 Shared Binder 的复杂度对比表（进程数 / 网络往返 / 序列化开销 / 内存共享）

### 第 4 章 4 层容错机制（10-12 页，创新点 2 核心章节）
- 4.1 分区调度器场景下的一致性挑战（论文关键动机）
- 4.2 Layer 0 — Node 分区归属校验（[pkg/binder/node_validator.go](../pkg/binder/node_validator.go)）
- 4.3 Layer 1 — 同步重试（[pkg/binder/embedded_binder.go](../pkg/binder/embedded_binder.go) 中 `bindPodToNode`）
- 4.4 Layer 2 — 异步 Reconciler + WorkQueue（[pkg/binder/binder_reconciler.go](../pkg/binder/binder_reconciler.go)）
- 4.5 Layer 3 — 跨实例回退（Dispatcher 侧 [pkg/dispatcher/reconciler/podstatesyncer.go](../pkg/dispatcher/reconciler/podstatesyncer.go) + [pkg/binder/utils/retry.go](../pkg/binder/utils/retry.go)）
- 4.6 一致性论证（评审最重视的一节，详细模板见下）

#### §4.6 详细写作模板（重要）

**4.6.1 系统模型与核心不变量**（半页）
- 形式化定义系统：`System = {Pod, Node, Scheduler_1..N, Dispatcher, Binder_1..N}`
- **核心不变量 I**：
  ```
  ∀ Pod p ∈ System:  |{ node : bound(p, node) }| ≤ 1
  （任意 Pod 在系统中最多绑定到一个节点）
  ```
- 说明为什么这是正确性的最低标准（K8s 集群灾难性数据不一致的边界）
- 引用图 4-3 作为整节的可视化概览

**4.6.2 威胁模型**（1-1.5 页）
按图 4-3 顺序展开 4 个威胁：
- **T0：节点分区归属漂移**
  - 场景：Scheduler A 决策 Pod → Node X 后，Dispatcher 因负载均衡把 Node X 划给 Scheduler B（`node-shuffler` 触发）
  - 若不拦截：两个 Scheduler 都可能对 Node X 发 Bind API
- **T1：Bind API 暂态失败**
  - 场景：kube-apiserver 返回 409 Conflict（etcd 冲突）/ 429 Throttle / 网络 Timeout
  - 若不重试：Pod 长期 Pending，可用性下降
- **T2：进程内偶发错误**
  - 场景：Bind 失败后进程崩溃/panic，Pod 在 SchedulerCache 里残留 Assumed 状态
  - 若不清理：资源永久占用，死锁
- **T3：本地重试耗尽 / 节点长期不可用**
  - 场景：节点 Bind 持续失败（例如节点被删除、apiserver 长期不可达）
  - 若不回退：这个 Scheduler 卡在这个 Pod 上，其他分区的 Pod 也受影响

**4.6.3 证明要点**（2-3 页，本节核心）

**P1【Bind 唯一性】**（引用 K8s 官方语义）
- Bind API 是 `POST /api/v1/namespaces/.../pods/.../binding`，apiserver 通过 etcd 事务保证：
  - 若 `pod.spec.nodeName == ""`，允许设置，操作原子成功
  - 若已设置，返回 `409 Conflict`
- 这是 Kubernetes 自身的性质，我们的系统只需**引用**它，不需要重新证明

**P2【Assumed 状态清理】**（引用 [binder_reconciler.go](../pkg/binder/binder_reconciler.go) 5-10 行代码）
- Bind 失败时把 Pod 加入 `APICallFailedTaskQueue`
- Reconciler Worker 周期性拉取，调用 `ForgetPod(p)` 清理 SchedulerCache 中的 Assumed 状态
- **幂等性**：`ForgetPod(p)` 对不存在的 Pod 是 no-op，可安全重试
- **进程崩溃恢复**：Reconciler 重启后从 WorkQueue 拉起（WorkQueue 由 client-go 保证持久化）

**P3【注解清理 → 重分发时序】**（引用 [podstatesyncer.go](../pkg/dispatcher/reconciler/podstatesyncer.go) 关键片段）
- Layer 3 全局回退的操作序列必须是：
  1. `PodState = Pending`（先改状态）
  2. `PatchPod` 清除 `scheduler-name` 注解（再清注解）
- **反例**：若顺序反过来，Dispatcher 可能观察到"无 scheduler-name 但 PodState=Dispatched"的中间状态，跳过这个 Pod
- **Dispatcher `selectScheduler` 幂等**：多次调用最终写入同一个 `scheduler-name` 注解（apiserver 的 Patch 语义保证）

**P4【时序保证：Layer 0 前置拦截】**（最关键，引用 [node_validator.go](../pkg/binder/node_validator.go) Validate 函数）
- **关键场景**：Dispatcher 中途重分区导致节点归属漂移
- Bind API 前查节点 `godel.bytedance.com/scheduler-name` 注解：
  - `annotation == ""` → 节点未分区（单调度器场景），允许 Bind
  - `annotation == self.schedulerName` → 归属正确，允许 Bind
  - `annotation == other` → 归属漂移，返回 `NodeOwnershipError`，进入 Layer 3
- **效果**：即使两个 Scheduler 都认为自己拥有节点，Layer 0 的注解查询确保**只有一个能通过前置校验**——避免并发 Bind API

**4.6.4 组合论证**（半页）
用文字论证 P1 ∧ P2 ∧ P3 ∧ P4 ⇒ 不变量 I 永远成立：
- 情况 1（无故障）：只有 Layer 0 通过校验的那个 Scheduler 发 Bind，P1 保证唯一性 → I 成立
- 情况 2（T1 触发）：Bind 失败后 Layer 1 同步重试，仍是同一个 Scheduler 试图 Bind → 不会破坏 I
- 情况 3（T2 触发）：Bind 半失败进程崩溃 → Layer 2 Reconciler 清理 Assumed 状态 → 下次调度不受影响
- 情况 4（T0/T3 触发）：Layer 3 清 scheduler-name → Dispatcher 重新分发 → 新 Scheduler 走完整流程 → Layer 0 再次前置拦截 → 仍归约到情况 1

**注**：论文不需要写成 TLA+ 那种形式化证明，但要**用严谨自然语言 + 关键代码片段**把上述四点写清楚。评审关注的是"作者理解了并发和一致性问题的本质"，而不是形式化证明本身。

---

### 第 5 章 实验与评估（15-20 页，创新点 3 核心章节）
- 5.1 实验环境（硬件配置、KWOK 仿真、Prometheus + Grafana 观测栈）
  - 复用 [test/e2e/benchmark/README.md](../test/e2e/benchmark/README.md) 的方法学描述
  - 集群规模：s2/s3 = 1K/5K 节点（若补跑成功，可加 s4=10K）
- 5.2 workload 定义表（w1-w8 场景，直接从 [workloads/workload-matrix.sh](../test/e2e/benchmark/workloads/workload-matrix.sh) 制表）
- 5.3 单调度器性能对比（a vs b vs c vs d vs e × s2/s3 × w2/w3）
  - 主表：稳态吞吐、P50/P90/P99 延迟、成功率
  - 图 T-1：吞吐 vs 规模曲线
  - 图 L-1/L-2：P90/P99 延迟分布箱线图
- 5.4 突发场景恢复能力（w5，若跑完）
- 5.5 水平扩展性（inst=1/2/3/5 曲线，若跑完）
- 5.6 一致性容错验证（构造 Node 分区变更场景，观察 Layer 0/3 触发）
- 5.7 资源开销对比（内存/goroutines/CPU，从 `results/*/goroutines.json` 提取）

**核心图表清单**（可直接借鉴 [chart-index.md](../test/e2e/benchmark/results/final-charts/chart-index.md)）：
- 已生成 9 张 PDF：T-1（吞吐）、T-3（对比条形图）、T-4（扩展性）、L-1/L-2（延迟）、S-2/S-3（成功率）、W6（gang）、U-1（CPU 利用率）
- 数据一旦补齐，用 `plot-results.py --compare` 直接重生成

### 第 6 章 总结与展望（4-6 页）
- 6.1 工作总结
- 6.2 主要贡献重述
- 6.3 局限性讨论（诚实地写）：例如未在真实生产环境验证、Gang 调度场景数据不足等
- 6.4 未来工作：Binder 内存压力自适应、异地多活 Dispatcher 等

### 参考文献（40+ 条）
### 附录
- 附录 A：完整实验数据表（每个 metric × 每个组的三次 run 均值 + std）
- 附录 B：核心代码片段（`BinderInterface`、`EmbeddedBinder.BindUnit` 简化版）
- 附录 C：Prometheus recording rules 一览

---

## 三、写作阶段与顺序（避免堵在数据上）

**Week 1-2（数据补跑中）**：
- 第 2 章相关工作（不依赖数据，可先写）
- 第 3 章架构设计（代码和文档都齐了，最容易写）
- 第 4 章容错机制（同上）
- 收集参考文献（Google Scholar 关键词：Kubernetes scheduler / Kubernetes bulk scheduling / partitioning scheduler / Volcano / Koordinator / Omega）

**Week 3-4（数据补跑完成后）**：
- 第 5 章实验（等数据到位）
- 第 1 章绪论（等第 5 章有数字后写，能引用具体百分比）
- 第 6 章总结

**Week 5**：
- 摘要、致谢、修订全文、术语统一

---

## 四、需要重点注意的事项（避免踩坑）

### 1. 数据严谨性
- 每个 metric 至少 3 次 run 取均值 + std，图上必须画 ±1σ band（`plot-results.py --average --std-band` 已支持）
- 延迟分位数图注明"mean of P90 across runs, not combined-sample P90"（脚本已自动加）
- **不要**把不同规模的绝对数字硬比，一律用同规模同 workload 的相对提升 %

### 2. Baseline 公平性（评审最容易挑刺）
- ENO 和 Gödel 使用相同的 request/limit（[config.sh](../test/e2e/benchmark/config.sh) 中 `BENCH_SCHED_REQ_CPU=2C`、`BENCH_BINDER_REQ_CPU=2C`），必须在论文里说明这一点
- 明确声明：ENO 版本不占用独立 Binder Deployment 的资源（这是它的优势之一），因此单纯比"总吞吐"对 Gödel 略不利，需要额外补一个"归一化到调度器总资源"的对比

### 3. 术语一致性
- 全篇统一：ENO = 嵌入式绑定器（提议方案），Shared Binder = 共享绑定器（基线）
- Dispatcher = 分发器，Scheduler = 调度器，Binder = 绑定器
- 首次出现时中英对照，后续用中文

### 4. 图表规范
- 所有图表标题、坐标轴、图例统一用中文；legend 里的调度器名保留英文原名（ENO / Gödel / kube-scheduler / Volcano / Koordinator）
- 输出格式统一 PDF（矢量），字体嵌入
- 图注放在图下方，格式："图 5-3 s3 规模下 w3 负载的 P99 延迟对比（均值 ± 1σ，n=3）"

### 5. 代码引用
- 论文中不贴大段代码，只贴接口定义（`BinderInterface`）和关键循环（10-20 行）
- 完整代码放附录 B 或用脚注指向 GitHub commit hash（保证 reproducibility）

### 7. 与原 Gödel 论文的关系
- README、[docs/performance/best-practice.md](performance/best-practice.md) 里已有 Gödel 官方数据（kube-scheduler 300 pps vs Gödel 1000+ pps），可作为背景引用
- 但**必须自己重跑对比**，不能直接用官方数据（论文评审要求可复现，你的硬件环境与官方不同）

### 8. plot-results.py 的持续改进
- 已完成的工作：`--average` / `--std-band` / `--compare` X 轴对齐 / JSON 命名规范
- 论文补跑数据前，检查是否有需要新增的图表类型（如箱线图、CDF 图），需要就在 [plot-results.py](../test/e2e/benchmark/collect/plot-results.py) 中扩展

---

## 五、架构图与流程图清单（论文必备）

论文需要大量的架构/流程图配合文字说明。目前 [docs/performance/figures/](performance/figures/) 只有 2 张（fig4-1 CAS 一致性流程、fig4-2 Dispatcher 任务划分），远不够。以下按章节列出必须新增的图，均建议用 **Mermaid（.mmd）源码 + 导出 PDF/PNG/SVG** 三份，方便修改与出版。

### 第 2 章 相关工作与背景

**不画架构图**，用文字介绍 + 一张对比表即可。

- **理由**：第 2 章的作用是铺垫背景，不是详解别人的架构；kube-scheduler / Volcano / Koordinator / Gödel 都是已发表工作，读者可以直接引用原论文/官方文档
- **Gödel 三层架构**在第 3 章图 3-1a 已经充分呈现（Dispatcher/Scheduler/Binder 三进程 + kube-apiserver），无需在第 2 章重画
- 图数配额（20-25 张）留给第 3-5 章的核心贡献

**替代方案**：§2.5 结尾放一张**方案对比表**：

| 维度 | kube-scheduler | Volcano | Koordinator | Gödel | ENO（本文）|
|---|---|---|---|---|---|
| 分区调度支持 | ❌ | 部分 | 部分 | ✅ | ✅ |
| 独立 Binder | N/A | ❌ | ❌ | ✅（单点瓶颈）| ❌（合并到 Scheduler）|
| Gang 调度 | ❌ | ✅ | ✅ | ✅ | ✅ |
| 一致性保护机制 | 单进程 | 单进程 | 单进程 | Shared Binder 串行化 | 4 层容错 |
| 大规模验证 | 5K 节点 | 待验证 | 待验证 | 30K 节点（官方）| 本文 5K 节点 |

### 第 3 章 ENO 架构设计（关键章节，图密集）

| 图号 | 类型 | 内容 | 备注 |
|---|---|---|---|
| **图 3-1** | 架构对比图 | **Shared Binder vs ENO 进程边界对比**（左右并列） | 论文最核心的一张图，读者一眼看懂改造点 |
| 图 3-2 | 数据流图 | Cache 零拷贝共享：Scheduler Cache ↔ CacheAdapter ↔ ENO | §3.4.2 详解共享机制 |
| 图 3-3 | 部署拓扑图 | ENO 模式的 k8s Deployment 视角：Scheduler Deployment（N 副本，进程内含 Binder）+ Dispatcher Deployment + kube-apiserver | 展示实际部署形态 |

**取消的图**（改用文字/代码/表格表达）：
- ~~原图 3-2/3-3 序列图~~ — 图 3-1a/3-1b 用步骤编号已展示跨进程往返差异；用 §3.5 一张**性能开销对比表**（Bind 涉及进程数、apiserver 往返次数、序列化开销、Cache 同步机制）代替
- ~~BinderInterface UML 图~~ — 用 5-10 行 Go 接口定义代码片段代替，信息密度更高

### 第 4 章 4 层容错机制

第 4 章图表按小节组织，每小节 0-2 张。**核心图 3 张已全部完成**。

| 图号 | 类型 | 用途（对应章节） | 状态 |
|---|---|---|---|
| **图 4-1** | 状态机图 | §4.1 章节封面：Pod 生命周期 + 4 层容错介入点 | ✅ [fig4-1-pod-state-machine.pdf](performance/figures/fig4-1-pod-state-machine.pdf) |
| **图 4-2a** | 流程图 | §4.5 Layer 3 接收端：Dispatcher 主分发流程 | ✅ [fig4-2a-dispatcher-main-flow.pdf](performance/figures/fig4-2a-dispatcher-main-flow.pdf) |
| **图 4-2b** | 流程图 | §4.5 Layer 3 接收端：Dispatcher 分发失败重试逻辑 | ✅ [fig4-2b-dispatcher-error-recovery.pdf](performance/figures/fig4-2b-dispatcher-error-recovery.pdf) |
| **图 4-3** | 论证图 | §4.6 一致性论证：核心不变量 I + 威胁-防御-证明要点 | ✅ [fig4-3-consistency-invariant.pdf](performance/figures/fig4-3-consistency-invariant.pdf) |
| 图 4-4（可选） | 流程图 | §4.5 补充详图：ENO 完整绑定 + 4 层容错决策流程 | ⭕ [fig4-1-consistency-cas-flow.pdf](performance/figures/fig4-1-consistency-cas-flow.pdf)（图数紧张可省） |

**取消的图**（理由：文字/表格更合适）：
- ~~图：Layer 0 分区校验决策树~~ — 一段 if-else 伪代码 + 一句话说明即可，不用画图
- ~~图：Layer 1 同步重试指数退避时序~~ — 一张参数表（初始退避、上限、乘数、MaxRetries）足够
- ~~图：Layer 2 Reconciler WorkQueue 生产者-消费者~~ — 图 4-1 状态机已经在 `L2_Queue` 节点展示；正文可加 5-10 行伪代码显示 worker 拉取逻辑
- ~~图：Layer 3 跨实例回退时序（swimlane）~~ — 图 4-2a + 图 4-2b 已经充分表达，多加一张 swimlane 时序图属于重复信息

**§4.6 一致性论证**：无需图，用**不变量 + 证明文字**表达（评审最重视的一节）
- 核心不变量：`∀ Pod p: |{node: p.assumedNode == node}| ≤ 1`（Pod 最多被绑定到一个节点）
- 每一层容错在什么故障模式下如何维护这个不变量（详细论证 1-2 页文字 + 关键路径 5-10 行伪代码）

### 第 5 章 实验与评估（数据图，不是架构图）

数据图由 [plot-results.py](../test/e2e/benchmark/collect/plot-results.py) 自动生成，命名从 T-1、L-1 等按 [chart-index.md](../test/e2e/benchmark/results/final-charts/chart-index.md) 已有惯例延续。不在此列。

但需要额外补 2 张**方法学示意图**：
| 图号 | 类型 | 内容 |
|---|---|---|
| 图 5-1 | 拓扑图 | 实验环境架构：kind 集群 + KWOK 假节点 + Prometheus + 5 个调度器组的部署布局 |
| 图 5-2 | 时序图 | 单次实验流程：deploy → warmup → workload → wait → collect（对应 [run-experiment.sh](../test/e2e/benchmark/run-experiment.sh) 12 个 Step） |

---

## 六、图表制作规范与工具链

### 6.1 图源码优先原则
- **所有架构图/流程图用 Mermaid 源码**（`.mmd`），版本化管理，避免用 draw.io 的私有格式
- 导出脚本：可以直接用现有的 [docs/performance/figures/puppeteer-config.cjs](performance/figures/puppeteer-config.cjs) 批处理
- 3 份产物：`.mmd`（源码）、`.pdf`（论文用，矢量）、`.png`（演示/预览用）

### 6.2 图注与命名
- 图注格式："图 3-1  ENO 与 Shared Binder 进程边界对比"（章号-序号 + 中文标题）
- 文件命名：`fig{章号}-{序号}-{英文-短-slug}.mmd`，例如 `fig3-1-arch-comparison.mmd`

### 6.3 配色规范（供 Mermaid 主题定制）
- 进程/服务节点：蓝灰系 `#4A6FA5`
- 数据库/持久化：绿色 `#5B8C5A`
- 数据流箭头：黑色实线，跨进程箭头虚线
- 高亮/新组件（ENO 相关）：橙色 `#E67E22`
- 与已有的 fig4-1、fig4-2 保持一致（避免论文里配色跳跃）

### 6.4 图数量控制
- 总图数目标 **20-25 张**（架构图 12-15 + 数据图 8-10），过多会显得拖沓
- 每章至少 1 张、至多 6 张的原则
- 每张图必须在正文中被显式引用（"如图 3-1 所示…"）

### 6.5 制图批次建议
- **Batch 1（Week 1）**：图 3-1（架构章节主图先出）
- **Batch 2（Week 2）**：图 4-1、图 4-5（容错章节主图）
- **Batch 3（Week 2 末）**：其余细节图 + §5.1 方法学图
- 每 Batch 用 `mmdc`（mermaid CLI）批量导出，运行 [export-figures.sh](performance/figures/export-figures.sh)

### 6.6 图表制作进度追踪

**已完成（可直接入论文）**：

| 图号 | 文件 | 用途 |
|---|---|---|
| **图 3-1a** | [fig3-1a-shared-binder-arch.pdf](performance/figures/fig3-1a-shared-binder-arch.pdf) | §3.1：Shared Binder 基线架构（论文核心图之一） |
| **图 3-1b** | [fig3-1b-embedded-binder-arch.pdf](performance/figures/fig3-1b-embedded-binder-arch.pdf) | §3.1：ENO 提议架构（与 3-1a 并列对比） |
| **图 3-2** | [fig3-2-cache-zero-copy.pdf](performance/figures/fig3-2-cache-zero-copy.pdf) | §3.4.2：Cache 零拷贝共享数据流（Scheduler/CacheAdapter/Binder 三模块 + SchedulerCache 单实例） |
| **图 3-3** | [fig3-3-eno-deployment-topology.pdf](performance/figures/fig3-3-eno-deployment-topology.pdf) | §3.5：ENO Embedded 部署拓扑（k8s Deployment 视角） |
| 图 4-1 | [fig4-1-pod-state-machine.pdf](performance/figures/fig4-1-pod-state-machine.pdf) | §4.1 章节封面：Pod 状态机 + 4 层容错介入点 |
| 图 4-1'（可选） | [fig4-1-consistency-cas-flow.pdf](performance/figures/fig4-1-consistency-cas-flow.pdf) | §4.5 补充详图：ENO 绑定全流程（图数紧张时可省） |
| 图 4-2a | [fig4-2a-dispatcher-main-flow.pdf](performance/figures/fig4-2a-dispatcher-main-flow.pdf) | §3.1 或 §4.5：Dispatcher 主分发流程 |
| 图 4-2b | [fig4-2b-dispatcher-error-recovery.pdf](performance/figures/fig4-2b-dispatcher-error-recovery.pdf) | §4.5：Dispatcher 分发失败重试逻辑 |

**Batch 1 已全部完成**（第 3 章核心架构图 3-1a/3-1b + 第 4 章核心图 4-1/4-2a/4-2b 均已落盘）。

**后续批次（Batch 2/3）**：
- 图 5-1/5-2（实验环境与流程，等 §5.1 写作时同步画）

> 第 4 章图已全部完成，Layer 0/1/2 各自细节图已取消（改用伪代码/参数表表达，见 §"第 4 章 4 层容错机制"）。

---

## 七、关键文件路径速查

| 用途 | 路径 |
|---|---|
| 论文大纲雏形 | [README.md](../README.md) 尾部中文大纲段 |
| 架构设计文档 | [BINDER_ARCHITECTURE_REFACTORING.md](../BINDER_ARCHITECTURE_REFACTORING.md)、[BINDER_REFACTORING_PROGRESS.md](../BINDER_REFACTORING_PROGRESS.md) |
| 性能背景素材 | [docs/performance/best-practice.md](performance/best-practice.md) |
| 已有论文图 | [docs/performance/figures/](performance/figures/) 下 fig4-*.pdf |
| 实验方法 | [test/e2e/benchmark/README.md](../test/e2e/benchmark/README.md) |
| 关键数据表 | [test/e2e/benchmark/results/final-charts/chart-index.md](../test/e2e/benchmark/results/final-charts/chart-index.md) |
| 数据质量记录 | [test/e2e/benchmark/results/data-quality-notes.md](../test/e2e/benchmark/results/data-quality-notes.md) |
| 现有实验报告 | [test/e2e/benchmark/results/report_2026-07-24_101705.md](../test/e2e/benchmark/results/report_2026-07-24_101705.md)（最新，18 次实验） |
| 绘图脚本 | [test/e2e/benchmark/collect/plot-results.py](../test/e2e/benchmark/collect/plot-results.py) |
| Workload 定义 | [test/e2e/benchmark/workloads/workload-matrix.sh](../test/e2e/benchmark/workloads/workload-matrix.sh) |

---

## 八、验证与交付

**写作完成后的检查清单**：
- [ ] 每张图都能追溯到 `results/<group>/<scale>/<workload>/run<N>/<metric>.json`
- [ ] 参考文献 40+ 条，覆盖至少 2020 年后的 5 篇会议论文（SoCC/OSDI/EuroSys）
- [ ] 附录 A 的数据表用脚本从 `results/` 自动生成（避免手工誊抄错误），可在 `collect/` 下新增 `gen_appendix_table.py`
- [ ] 中英文摘要相互翻译，术语一致
- [ ] 全文查重 < 15%（学校要求）
- [ ] 代码在 GitHub 上打 tag（如 `thesis-v1.0`），论文首页脚注写清 commit hash

**推荐工具链**：
- 写作：LaTeX（学校模板）或 Word（如学校无强制要求）
- 图表：`plot-results.py` → PDF；架构图用 [docs/performance/figures/](performance/figures/) 已有的 mermaid 源码（`.mmd`）便于修改
- 参考文献管理：Zotero，导出 BibTeX
