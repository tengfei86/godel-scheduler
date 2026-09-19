# 第五章　面向大规模场景的进程内 Binder 架构

第 3、4 章从架构与容错两个维度刻画了分布式 Kubernetes 调度器需要满足的功能与一致性要求。在具体的部署形态上，若沿用"独立 Binder 组件 + 跨进程通信"的经典拆分，其在超高并发场景下会重新成为整个调度流水线的性能瓶颈。本章提出 ENO——一种将绑定执行链路合并进 Scheduler 进程的嵌入式绑定器（Embedded Binder）架构，通过共享缓存零拷贝适配、消除跨进程 API 调用、在四层容错语义上重建进程内调用链等设计要点，在不牺牲一致性保证的前提下取得显著的性能提升。

## 5.1　独立 Binder 的性能开销分析

图 5-1a 展示了 Binder 作为独立 Deployment 部署时的完整跨进程流程：Binder 与 Scheduler 进程之间无直接连接，只能通过 Kubernetes API Server 间接通信。本文以这一部署形态作为第 6 章实验中 b 组的评估基线，用以量化 ENO 进程内合并方案（5.2 节）带来的性能改进。

![图 5-1a  独立 Binder：5 步跨进程流程](../figures/fig5-1a-shared-binder.png)

整条链路上有 5 次 API Server 调用。Dispatcher 首先以 `PatchPod` 写入 `scheduler-name` 注解 ①，随后 Informer 把该事件推送给 Scheduler ②；Scheduler 完成 Filter/Score/Reserve 后再以 `PatchPod` 写入 `assumed-node` 注解 ③，Informer 又将这次修改推送到独立的 Binder 进程 ④；最终由 Binder 通过 Bind API 完成绑定 ⑤。

其中步骤 ④ 是本文特别关注的开销来源：Scheduler 与 Binder 之间没有直接连接，它们通过 API Server + etcd 中转事件，每次事件都涉及序列化（Pod 对象转 protobuf）、网络传输、反序列化、Informer 索引更新等一系列开销，在超高并发场景下会累积成显著的性能损耗。

序列化 / 反序列化的 CPU 消耗最为直接：每个 Pod 对象约 3~10 KB（含 metadata、spec、status），w3 负载（1000 pods/s）稳态下 API Server + Informer 每秒完成 1000 次完整的 Pod 序列化循环，合并 Binder 后跨进程序列化次数减少约一半，对应的 Pod E2E P99 延迟改善 40.7%~91.0%（见 6.4.3 节）。Informer 事件延迟紧随其后：从 API Server 的 Watch 推送到 Binder 的 Informer 处理完成，受批处理、限流与 handler 排队影响，通常存在数十到数百毫秒的端到端延迟，直接叠加到 Pod E2E 调度延迟上；ENO 消除步骤 ④ 后，s3/w3 场景的 P99 调度延迟相较独立 Binder 基线降低 47.5%~82.0%（见 6.4.2 节表 6-5）。此外，步骤 ④ 本身是一次完整的 Watch 事件推送，仍占用 apiserver 的连接与 goroutine 资源，相当于比"Scheduler 直接调用 Bind API"多了一整个 apiserver 交互周期，高负载下形成的 pending 队列堆积可参见 6.5.3 节复杂负载对比中 ENO 与独立 Binder 基线的队列长度差异。

上述均为运行时开销；除此之外，独立 Binder 作为独立 Deployment 还带来运维层面的资源冗余——额外的 CPU / 内存配额、健康探测、日志与监控在 3~5 副本水平扩展的 Scheduler 集群中体量明显。ENO 部署下该 Deployment 被移除（详见 5.4 节图 5-3），这部分属定性收益，不进入第 6 章的定量对比。

## 5.2　ENO 架构：进程内 Binder 合并

### 5.2.1　设计目标

针对 5.1 节分析的四类开销，本文提出四项设计目标。首要目标是消除步骤 ④ 的跨进程事件传递，即由 Scheduler 进程内的 Binder 模块直接完成绑定，不再经 apiserver 中转；与之配套的是 SchedulerCache 的零拷贝共享，Binder 与 Scheduler 使用同一份内存实例，Assumed 状态无需在两个进程之间同步。第三个目标要求第 4 章的四层容错机制在新架构下完整保留，Layer 0 校验、Layer 1/2 重试与 Layer 3 全局回退都不能因部署形态合并而丢失。最后，新架构需要向后兼容，通过 CLI 开关 `--enable-embedded-binder` 即可在两种部署形态之间自由切换，不强制使用者迁移。

### 5.2.2　ENO 架构总览

图 5-1b 展示了 ENO 架构下的进程边界。

![图 5-1b  ENO 进程内 Binder（改造后）：3 步进程内流程](../figures/fig5-1b-eno-arch.png)

对比图 5-1a 与 5-1b 可见，ENO 架构下 Scheduler 与 Binder 合并为一个进程，副本数为 N，API Server 调用从 5 步减少为 3 步（① dispatching → ② Informer 事件 → ③ Bind API）。原图 5-1a 中的步骤 ④，即 Scheduler 向 Binder 的事件传递，完全消失，因为两者已是同一进程内的两个模块，通过内存直接调用；原步骤 ⑤ 的 Bind API 调用改由图 5-1b 中的步骤 ③ 承担，同样在进程内发起。

## 5.3　CacheAdapter 与零拷贝共享

将 Binder 从独立进程移入 Scheduler 进程后，一个关键的技术挑战是如何让 Binder 与 Scheduler 共享 SchedulerCache。独立 Binder 架构中，两者位于不同进程，Binder 通过 Informer 独立维护自己的资源视图；合并后，若仍采用"Binder 有自己的资源视图"的做法，则内存中会存在两份互相同步的 SchedulerCache，同步延迟与内存开销都不可接受。

本文的做法是在 ENO Binder 一侧引入 `CacheAdapter` 封装：Scheduler 仍旧直接读写 SchedulerCache，Binder 则透过 CacheAdapter 以自己熟悉的 `BinderCache` 接口访问同一份 SchedulerCache。图 5-2 给出这一数据流。

![图 5-2  ENO Binder 侧的 CacheAdapter 封装：Scheduler 直读 SchedulerCache，Binder 经 CacheAdapter 访问同一实例](../figures/fig5-2-cache-zero-copy.png)

### 5.3.1　CacheAdapter 的职责

CacheAdapter 是本文为 ENO Binder 侧设计的封装层，包裹 Scheduler 已经维护的 SchedulerCache（Scheduler 自身仍直接访问 SchedulerCache，不经过 CacheAdapter）。它对上层 ENO Binder 暴露出 Binder 熟悉的接口——例如原独立 Binder 使用的 `GetPod`、`IsAssumedPod`、`AssumePod`、`ForgetPod` 等，内部实现则全部委托给 SchedulerCache，不复制、不缓存、不同步。

CacheAdapter 的实现由三部分组成。**本地状态**包括 `assumedPods map` 与 `podMarkers map`，用于记录独属于 Binder 的额外元数据，例如已 Assumed 但尚未 Bind 的 Pod 集合与待清理的 Pod 标记；这类元数据的规模远小于 SchedulerCache 主体，独立维护的开销可以忽略。**委托方法**包括 `GetPod`、`IsAssumedPod`、`AssumePod`、`ForgetPod` 以及增删改查方法，收到调用后直接转发给 SchedulerCache 的对应方法，不做任何数据拷贝。**Binder 专属方法**则包括 `FinishBinding`、`MarkPodToDelete` 等原 Binder 特有的方法，其中一部分委托给 SchedulerCache（例如 `FinishReserving`），另一部分操作 CacheAdapter 自身的本地状态。

### 5.3.2　零拷贝的技术要点

零拷贝的关键在于 Scheduler 模块与 CacheAdapter 指向的是同一个 SchedulerCache Go 对象，即同一块内存地址。实现上，Scheduler 直接持有 `*Cache` 结构体指针进行读写，CacheAdapter 内部保存同一个指针供 Binder 使用；SchedulerCache 内部通过 `sync.RWMutex` 保护，两条访问路径的并发是安全的。这一方式同时消除了 Informer 同步延迟：独立 Binder 架构中 Binder 需要借助独立的 Informer 观察 Pod 变更，通常存在数十毫秒延迟，合并后 Scheduler 在 Reserve 阶段一旦修改缓存，Binder 立即通过 CacheAdapter 读到最新状态，延迟为零。内存占用也因此下降，整个进程只维护一份 SchedulerCache（数十 MB 到数百 MB，取决于集群规模），而不是 Scheduler 与 Binder 各持一份。

## 5.4　部署拓扑变化

图 5-3 展示了 ENO 架构下的 Kubernetes Deployment 视角。

![图 5-3  ENO 部署拓扑（Kubernetes Deployment 视角）](../figures/fig5-3-eno-deployment.png)

如图 5-3 所示，ENO 架构下 `eno-system` 命名空间内的关键 Deployment 变为：

- Dispatcher Deployment：副本数 = 1（+1 Standby），通过 Leader Election 保证单实例活跃，负责节点分区管理与 Pod 分发；
- Scheduler Deployment：副本数 = N（水平扩展），每个 Pod 内部同时运行 Scheduler 模块 + ENO Binder 模块。

相较独立 Binder 部署形态，独立的 Binder Deployment 在 ENO 下被彻底移除。这一拓扑变化带来的运维层面收益包括：

- 减少一个需要维护的 Deployment（配置、镜像、健康探测、日志、监控都少一份）；
- Scheduler 的资源规格（每 Pod requests: 2 CPU / 4G MEM，limits: 4 CPU / 8G MEM）已经预留了 Binder 合并后的资源需求，无需在合并后调整；
- 水平扩展时只需扩展 Scheduler Deployment 副本数，无需同时协调 Binder 副本数——分布式调度器的水平扩展变得更为简单直接。

## 5.5　ENO 下四层容错的进程内实现

第 4 章刻画了分布式调度器需要满足的四层容错语义（Layer 0/1/2/3）。这些语义是**行为约束**，与运行时的进程边界无关；但**具体的调用链落到哪个进程里**是部署形态的选择。独立 Binder 部署形态下调用链跨越两个进程，ENO 将其整体收敛到 Scheduler 进程内。本节按四层顺序说明 ENO 的进程内实现。

Layer 0（节点归属前置校验）由 `EmbeddedBinder` 在每次 `BindUnit` 请求进入时统一执行：对请求中出现的每个目标节点调用 `NodeValidator.Validate`（[pkg/binder/node_validator.go](pkg/binder/node_validator.go)），通过 `NodeGetter` 抽象从 Informer 缓存读取节点的 `eno.io/scheduler-name` 注解并与自身匹配。任何一个节点不属于本 Scheduler 分区，都会走 L0 失败分支——ENO 通过 `CleanupPodAnnotationsForceDispatch` 辅助函数（[pkg/binder/utils/util.go](pkg/binder/utils/util.go)）对请求中的每个 Pod 做原子清理：清 `selected-scheduler` 注解、追加 `failed-schedulers`、`pod-state` 置回 `pending`，Dispatcher 的 Informer 感知后立即重新分发。此即图 4-1 中 `L0_Fail → Pending` 的直通路径。

Layer 1（同步退避重试）在 `EmbeddedBinder.bindPodToNode` 内部落地。ENO 在此层显式约束了两点：重试仅对确认可自愈的错误类型（`409 Conflict` / `429 TooManyRequests` / `ServerTimeout`）生效，其它类型立即出口；退避策略采用线性 `n × 100ms`，上限为 `MaxBindRetries`（默认 3）。由于绑定动作与 Scheduler 决策同进程，L1 循环无需跨进程事件传递，是 ENO 下运行时开销最小的一层。为便于观测与测试，退避耗尽的失败路径会以 `ErrBindRetriesExhausted` sentinel 包裹返回错误（[pkg/binder/binder_interface.go](pkg/binder/binder_interface.go)），非可重试错误则原样返回。

Layer 2（异步 Reconciler）由 `EmbeddedBinder.reconciler` 承载，实例通过 `NewBinderTaskReconcilerWithRetry` 构造（[pkg/binder/binder_reconciler.go](pkg/binder/binder_reconciler.go)），后台单 goroutine Worker 消费 `APICallFailedTaskQueue`。任务入口在 `EmbeddedBinder.BindUnit` 的失败分支：每次 L1 出错（无论退避耗尽还是非可重试早退）都会调用 `eb.reconciler.AddFailedTask`，同时通过 `util.PatchPod` 将新增的 `eno.io/bind-failure-count` 注解持久化到 etcd，供 Worker 稍后读取。内存态与 etcd 态的清理分工与 4.4.2 节一致：SchedulerCache 中的 Assumed 状态由 Bind Reject 阶段的 `ForgetPod` 清理（ENO 下 `ForgetPod` 直接作用于 Scheduler 与 Binder 共享的 SchedulerCache 对象，无需跨进程事件）；Worker 只负责 etcd 侧调度注解的清理——通过 `CleanupPodAnnotations` 家族函数调用 `util.PatchPod` 移除调度决策注解，并根据本地失败计数选择"回到本 Scheduler 重试"或"上升至 L3"。

Layer 3（跨 Scheduler 实例回退）的执行主体是 `CleanupPodAnnotationsWithRetryCount`：一旦 L2 Worker 观察到累计失败次数达到 `MaxLocalRetries`（`EmbeddedBinderConfig` 默认为 5，见 [embedded_binder_config.go](pkg/binder/embedded_binder_config.go)），即通过一次 `util.PatchPod` 同时更新三个注解字段（清 `selected-scheduler`、`pod-state=pending`、追加 `failed-schedulers`），将 Pod 交还给 Dispatcher 重新分发到其它 Scheduler 实例。Dispatcher 侧的重分发行为与 ENO 的进程边界无关——它只依赖 `selected-scheduler` 注解的清除事件被 Informer 感知。

综合起来，ENO 在单一 Scheduler 进程内完整承载了四层容错的运行时调用链：L0 的前置校验与 L3 直通、L1 的进程内退避、L2 的失败任务异步驱动，以及 L3 的注解级重分发。这一进程内实现与 5.3 节的 CacheAdapter 零拷贝共享共同构成 ENO 完整的架构语义。第 4 章给出的核心不变量（"任一 Pod 至多绑定到一个节点"）与 P1–P4 证明要点在 ENO 下依旧成立——因为它们只依赖 Bind API 的原子性与 etcd 注解写入的 CAS 语义，与 Binder 的部署形态无关。ENO 的性能改进将在第 6 章通过 KWOK 仿真下的大规模基准测试进行定量评估。
