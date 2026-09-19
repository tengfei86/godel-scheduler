# 第四章　基于 etcd 语义的一致性容错机制

本章是全文的核心章节之一。第 3 章描述的分布式调度器架构中，多个 Scheduler 实例并发工作时不可避免地会遇到多种故障场景，如何在故障下依然维持"任一 Pod 至多绑定到一个节点"这一核心不变量，是评价一个分布式调度器正确性的最低门槛。本章将围绕四类典型故障场景展开，给出对应的四层容错机制，并从形式化的角度论证不变量的维持。

## 4.1　一致性挑战与核心不变量

### 4.1.1　系统模型

本章的讨论采用如下形式化系统模型：

```
System = { Pod, Node, Dispatcher, Scheduler_1..N, APIServer, etcd }
```

其中：
- Pod 与 Node 是 Kubernetes 集群中的资源对象，其状态最终存储于 etcd；
- Dispatcher 与 Scheduler_1..N 是本文所研究的调度器组件；
- APIServer 与 etcd 提供第 2 章 §2.5 所述的三种原子性语义（`resourceVersion` 乐观并发、Watch 一致性、Bind 子资源原子性）。

### 4.1.2　核心不变量

分布式 Kubernetes 调度器需要维持的核心不变量记为 I：

$$
\forall \; \text{Pod } p \in \text{System}: \; \left| \{ \text{node} : \text{bound}(p, \text{node}) \} \right| \leq 1
$$

即：任意 Pod 在系统中至多被绑定到一个节点。这一不变量看似简单，但在分布式调度器场景下，多个 Scheduler 实例可能同时观察到相同的候选节点、可能同时执行 Filter/Score/Bind、可能因分区归属漂移导致同一节点被两个 Scheduler 各自认为归属自己——如何在这些并发与故障场景下始终维持 I，是本章的核心目标。

违反 I 的直接后果是同一 Pod 被绑定到两个节点：Kubernetes 的资源核算失衡、kubelet 会在两个节点上同时启动该 Pod 的容器、网络与存储配置出现冲突，可能进一步引发数据错乱与服务异常。

### 4.1.3　Pod 生命周期与容错介入点

图 4-1 展示了 Pod 在本文调度器中的生命周期状态机，并标注了四层容错机制的介入点。

![图 4-1  Pod 生命周期状态机与 4 层容错机制介入点](../figures/fig4-1-pod-state-machine.png)

如图 4-1 所示，Pod 生命周期的主状态为：
`[*] → Pending → Dispatched → Assumed → Bound → [*]`

正常路径下，Pod 从新建（Pending）经 Dispatcher 分发（Dispatched）、Scheduler 决策（Assumed）、Bind API 成功（Bound）完成整个流程。图 4-1 中彩色分支展示了各层容错的介入点：

- Layer 0：Assumed → L0_Fail，节点归属校验在 Bind API 前拦截；
- Layer 1：Assumed → L1_Retry → Assumed，暂态失败的同步重试；
- Layer 2：L1_Retry → L2_Queue → Dispatched（未超 maxLocalRetries 时保留在本 Scheduler 重试），超同步重试上限后交由异步 Reconciler；
- Layer 3：L0_Fail / L2_Queue → Pending，回到最初状态触发 Dispatcher 重分发。

## 4.2　Layer 0 — Node 分区归属前置校验

### 4.2.1　故障场景 T0：节点分区归属漂移

场景：Scheduler A 通过 Filter/Score 决定将 Pod p 调度到 Node X，但在 Bind API 调用发生之前，Dispatcher 因节点负载重新平衡（`node-shuffler` 触发）将 Node X 从 Scheduler A 的分区剥离，改分给 Scheduler B。

危害：若不加拦截，Scheduler A 仍会发起对 Node X 的 Bind 尝试，与此同时 Scheduler B 也可能在自己的分区变更后开始处理与 Node X 相关的调度请求。虽然 Bind 子资源的原子性最终能防止同一 Pod 被绑定两次，但会产生大量无效的 Bind 请求、错误日志、以及 API Server 压力。更严重的是，这种"跨分区的 Bind 尝试"会破坏节点分区语义——每个 Scheduler 只应对自己分区内的节点做写操作。

### 4.2.2　Layer 0 的设计

节点分区的归属通过 Node 对象的注解 `eno.io/scheduler-name` 表达。Dispatcher 在做出分区决策后，通过 `PatchNode` 写入该注解；每个 Scheduler 只处理注解与自身名字匹配的节点。

Layer 0 的具体实现是在 Bind API 调用之前对目标节点的归属注解进行一次显式校验。校验逻辑如下：

```go
// 摘自 pkg/binder/node_validator.go
func (v *NodeValidator) Validate(nodeName string) error {
    node, err := v.nodeGetter(nodeName)
    if err != nil { return err }
    owner := node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]

    // 注解为空：节点未被分区（例如单调度器部署），允许 Bind
    if owner == "" { return nil }

    // 注解与自己一致：归属正确，允许 Bind
    if owner == v.schedulerName { return nil }

    // 注解与自己不一致：归属漂移，返回 NodeOwnershipError
    return &NodeOwnershipError{
        Node: nodeName, Expected: v.schedulerName, Actual: owner,
    }
}
```

上述实现有三个要点。节点信息通过 `nodeGetter` 抽象读取，不硬编码数据来源，由调用方决定从 Informer 缓存还是 API Server 读取，生产环境通常选择前者以降低延迟。归属状态被区分为三种：注解为空表示节点尚未分区，允许 Bind 以兼容单调度器场景；注解与自身一致表示归属正确；注解与自身不一致表示归属漂移，此时返回结构化错误。返回的错误类型为 `NodeOwnershipError`，调用方可通过 `errors.As` 判断类型，进而触发 Layer 3 全局回退。

### 4.2.3　Layer 0 的效果与作用范围

Layer 0 是四层机制中唯一的前置层——它在 Bind API 之前拦截，避免了跨分区的 API 调用。当两个 Scheduler 因分区状态视图不一致都认为自己拥有 Node X 时，Layer 0 的注解查询确保只有真实持有节点注解的那个 Scheduler 能通过前置校验，另一个会因归属不匹配而被拦截，直接进入 Layer 3 全局回退。

需要明确 Layer 0 的定位：它是应用层的降噪层，而非核心不变量 I 的最终守护者。Layer 0 通过 Informer 缓存读取节点归属注解，缓存与 etcd 的同步存在毫秒到百毫秒级的窗口期——在该窗口内 Scheduler A 可能读到旧值、通过 Layer 0 校验、并成功调用 Bind API 完成绑定。这次绑定在 apiserver 侧无法被节点归属注解拦截（Bind 子资源只检查 `spec.nodeName` 是否为空，不校验自定义注解）。

即便如此，核心不变量 I 依然由三个语义共同保护，不依赖 Layer 0：

- Bind API 的 CAS 语义（对应 P1）：一旦 Scheduler A 的 Bind 落盘，Pod p 的 `spec.nodeName` 就永久设定，任何其它 Scheduler 后续对同一 Pod 的 Bind 都会拿到 `409 Conflict`。同一 Pod 至多绑一个节点由此单点保证，与哪个 Scheduler 完成 Bind 无关；
- kubelet 的调度器无关性：Node X 上的 kubelet 只依据 `spec.nodeName` 拉起 Pod，不感知 `eno.io/scheduler-name` 这一应用层约定，Pod 的实际运行不受"跨分区 Bind"影响；
- Informer 的最终一致性：短暂窗口内 A 与 B 对 Node X 的资源核算可能出现分歧（A 因缓存尚未刷新继续按自己分区处理，B 因新注解已生效开始处理），但两侧 Informer 观察到 Pod 事件后，B 侧的资源账本自动纳入 A 已绑定的 Pod，分歧收敛。

Layer 0 的价值因此可以精确描述为：在稳定期显著减少跨分区 Bind 尝试的发生率（因为绝大部分场景 Informer 已经收敛），将残余的跨分区尝试转化为可观测事件（`NodeValidationFailure` 计数），并立即触发 Layer 3 快速回退，避免后续同一 Scheduler 再对已改归属的 Node 做写操作。它不承担、也不必承担对 I 的最终守护责任。

## 4.3　Layer 1 — 同步重试

### 4.3.1　故障场景 T1：Bind API 暂态失败

场景：Scheduler 通过 Layer 0 校验后调用 Bind API，但 API Server 因如下原因返回错误：

- `409 Conflict`：Pod 的 `resourceVersion` 已被其他修改抢先更新（例如用户 patch 了标签）；
- `429 Too Many Requests`：API Server 限流；
- 网络 timeout：临时的连接问题。

危害：若不重试，Pod 将长期停留在 Assumed 状态，可用性下降。

### 4.3.2　Layer 1 的设计

Layer 1 在 `embedded_binder.go` 的 `bindPodToNode` 函数中实现，核心逻辑是**线性退避 + 有限次同步重试**：第 n 次重试前等待 `n × 100ms`（首次 100ms、第二次 200ms、第三次 300ms），累计最多 `MaxBindRetries` 次（默认 3，由 `DefaultMaxBindRetries` 定义于 `embedded_binder_config.go`）。重试仅对 `409 Conflict`、`429 Too Many Requests`、`ServerTimeout` 三类瞬态错误生效；其他错误立即返回上层。

每次重试均在当前 goroutine 中同步执行，不涉及跨 goroutine 或跨进程通信。这样设计的原因是：

（1）暂态失败在秒级内自愈的概率很高。API Server 的限流和网络抖动通常持续时间短，一次立即重试往往就能成功；同步重试避免了将失败 Pod 塞入队列后再重新拉起的调度延迟。

（2）失败次数可控。同步重试上限为 `MaxBindRetries` 次（默认 3），保证 Scheduler 不会因反复重试单个 Pod 而阻塞后续调度决策——若三次仍失败，Layer 1 将错误返回给上层，由 `EmbeddedBinder` 主循环将失败 Pod 加入 Reconciler 队列交由 Layer 2 处理。

（3）幂等性。Bind API 本身是幂等的：若第一次 Bind 已经成功但客户端未收到响应，第二次 Bind 会因 `spec.nodeName` 已被设置而返回 `409 Conflict`，Scheduler 可将其视为成功。

## 4.4　Layer 2 — 异步 Reconciler

### 4.4.1　故障场景 T2：进程内偶发错误

场景：Scheduler 在 Reserve 阶段将 Pod 标记为 Assumed（写入 `assumed-node` 注解，同时在 SchedulerCache 中记录节点资源占用），但随后 Bind API 失败且同步重试全部耗尽——甚至在极端情况下 Scheduler 进程本身崩溃/panic。

危害：Pod 在 SchedulerCache 中的 Assumed 状态成为孤儿数据，占用节点资源核算配额但从未真正落盘。若不清理，该节点将被 Scheduler 认为已经容纳了这个 Pod，从而拒绝为其他 Pod 分配资源，导致资源永久占用。

### 4.4.2　Layer 2 的设计

Layer 2 在 `binder_reconciler.go` 中实现，其核心数据结构是 `APICallFailedTaskQueue`——基于 client-go workqueue<sup>[36]</sup> 的失败任务队列，具备去重、限流与指数退避重试能力。

流转过程如下：

（1）失败进入队列：Layer 1 在同步重试全部失败后，将 Pod（连同失败原因 `RejectFailed`）加入 `APICallFailedTaskQueue`。此前的 Bind Reject 阶段已经调用 `ForgetPod` 清理了 SchedulerCache 中的 Assumed 状态，Layer 2 只处理 etcd 侧遗留的注解清理；

（2）Worker 消费：单个 Reconciler Worker goroutine 顺序从队列拉取任务。由于每次操作只涉及一次 etcd 注解 patch，串行处理即可，也避免了并发 patch 引发的 `resourceVersion` 冲突放大；

（3）幂等注解清理：Worker 通过 `CleanupPodAnnotations` 家族函数调用 `util.PatchPod` 向 apiserver 提交注解修改，清除 etcd 中 Pod 对象上的调度相关注解（`scheduler-name`、`assumed-node` 等）。清理动作仅涉及 Pod 对象注解字段的 patch，不接触 SchedulerCache 内存态——内存态的 Assumed 记录由 Bind Reject 阶段的 `ForgetPod` 负责（见 §4.6 P2）。对已被删除的 Pod，`PatchPod` 返回 `NotFound`，Worker 直接 Forget 该任务，因此重试安全；

（4）判断后续动作。清理动作根据本地重试计数进行分支：
- 若累计本地失败次数未超过 `maxLocalRetries`，Pod 状态改回 `Dispatched` 保持在本 Scheduler 侧，等待下一轮调度重试；
- 若累计失败次数超过 `maxLocalRetries`，清除 `scheduler-name` 注解、状态改回 `Pending`、并在 `failed-schedulers` 注解中追加本 Scheduler 名——由 Dispatcher 通过 Informer 感知后重新分发到其他 Scheduler（对应 Layer 3）。

（5）`PatchPod` 失败的重试与兜底。Worker 处理注解 patch 时可能因 apiserver 短暂不可达、限流、5xx 等原因失败。`APICallFailedWorker` 主循环对失败结果做二分处理：`apierrors.IsNotFound` 表示 Pod 已被删除，清理目标消失，任务直接丢弃；其它错误一律通过 `AddRateLimited` 重新入队，由 workqueue 的指数退避机制在 5ms → 10ms → 20ms → … 最长 1000s 的间隔内持续重试，无显式次数上限。这与 Layer 1 同步重试的"次数受限、超限上抛"形成对照——Layer 2 位于异步 Worker 中，反复失败仅阻塞注解清理路径，不影响 Scheduler 主循环调度新 Pod，因此可以长时间等待 apiserver 自愈。需要强调的是，Layer 3 的触发点在 (4) 步骤中 patch 成功时依据本地失败计数判定，与 Worker 是否曾经 (5) 步骤中反复失败无关：只要 patch 最终成功，就一次性决定 Dispatched 还是 Pending。

进程崩溃恢复：需要说明的是，`APICallFailedTaskQueue` 基于 client-go 的 workqueue 实现，是内存中的限速队列而非持久化队列，因此 Scheduler 进程 panic 重启后，队列中尚未处理的任务会随之丢失，Layer 2 不能依赖队列本身提供跨崩溃的恢复能力（见 [36] 的 workqueue 说明）。真正提供恢复能力的是 etcd 中持久化的 Pod 状态：进程重启后，Scheduler 通过 Informer 从 etcd 同步 Pod 并重建 SchedulerCache，此时凡 `spec.nodeName` 仍为空、`scheduler-name` 注解指向本实例的 Pod，都会作为待调度 Pod 重新进入调度队列，再次经历 Filter/Score/Reserve 与 Bind 流程。换言之，进程内的 Assumed 状态随进程消失，而 etcd 中的注解状态使这些 Pod 可被重新发现；Layer 2 的最终一致性由 etcd 的持久化与 Informer 的重建共同保证，而不是依赖内存队列的存活。

## 4.5　Layer 3 — 跨 Scheduler 实例回退

### 4.5.1　故障场景 T3：本地重试耗尽 / 节点长期不可用

场景：一个 Pod 在 Scheduler A 中反复失败——例如 Scheduler A 分区内确实无可用节点、或者 Node X 因硬件故障从集群中移除、或者 apiserver 长期不可达。Layer 1 与 Layer 2 都无法在本实例内解决问题。

危害：若无跨 Scheduler 实例回退机制，Scheduler A 会长期卡在这个 Pod 上，本分区内其他新到达的 Pod 也会因此排队等待，最终 Scheduler A 的可用性完全丧失。

实例级失效的回收路径：除上述任务级故障外，Scheduler 实例本身失效（进程崩溃或心跳超时失活）时，其名下未完成的任务同样需要全局回收。Dispatcher 的 Scheduler Maintainer 基于实例心跳（Lease/心跳上报）进行失活判定；失效实例名下仍处于 Dispatched 状态的任务，由 PodStateReconciler 将其重置为 Pending 并清理 `scheduler-name` 等注解，随后重新进入分发流程。这是 Layer 3 回收路径在实例级故障场景下的体现，与任务级回退共用同一套"清注解 → 重分发"机制，从而保证失效实例遗留的任务不会成为孤儿数据。

### 4.5.2　Layer 3 的设计

Layer 3 的核心思想是：放弃本实例，交还给 Dispatcher 重新分发。图 4-2a 展示了 Dispatcher 侧的主分发流程；Layer 3 触发后，Pod 因 `scheduler-name` 注解被清空而被 Dispatcher 的 Informer 重新观察到，从图 4-2a 顶端的 `SortedPodsQueue` 重新进入分发。图 4-2b 单列展示 Dispatcher 分发自身失败（`PatchPod` API 调用失败）时的处理，与 Layer 3 是独立的两条错误路径。

![图 4-2a  Dispatcher 策略分发的嵌套决策路径（先按 PodGroup 分流，再由 `SupportRescheduling` FeatureGate 决定 Owner 亲和或默认负载均衡）](../figures/fig4-2a-dispatcher-main-flow.png)

![图 4-2b  Dispatcher 分发失败的处理（`PatchPod` 失败 / Pod 已删除）](../figures/fig4-2b-dispatcher-error-recovery.png)

Layer 3 的具体操作序列为：

（1）Scheduler 侧清理：Scheduler A 在决定回退时，通过一次 `PatchPod` 原子提交两个注解修改——将 `pod-state` 注解设为 `Pending`，同时删除 `scheduler-name` 注解；此外将本 Scheduler 名追加到 `failed-schedulers` 注解，避免下一轮 Dispatcher 再次分发到同一实例。

由于 `PatchPod` 通过 etcd 事务原子提交，Dispatcher 观察到的必然是 patch 完成后的最终状态，不存在"`scheduler-name` 已清但 `pod-state` 仍为 `Dispatched`"的中间态。

（2）Dispatcher 侧重分发：Dispatcher 通过 Informer 观察到 `scheduler-name` 被清除的 Pod，将其重新纳入 `SortedPodsQueue`（对应图 4-2a 顶端）参与下一轮分发。

（3）幂等重分发：Dispatcher 的 `selectScheduler` 方法是幂等的——多次调用最终会写入同一个 `scheduler-name` 注解（这一注解通过 API Server 的 Patch 语义 + `resourceVersion` 保证并发安全）。因此即使 Layer 3 触发时 Dispatcher 恰好也在处理该 Pod，也不会产生错误的分发结果。

### 4.5.3　Layer 3 与 Layer 0 的相互衔接

Layer 3 与 Layer 0 相互衔接，构成一条自我修复的回路。Layer 3 清除 `scheduler-name` 注解后，Pod 交由 Dispatcher 重新分发到另一 Scheduler B；Scheduler B 在自己的分区内独立完成 Filter/Score/Reserve，选定的候选节点在 Bind 前接受 Layer 0 校验。稳态下 Scheduler B 只从自身分区内选节点，Layer 0 校验必然通过，Bind API 完成绑定。仅当分区表处于短暂不一致的窗口——例如某节点归属刚被 Dispatcher 修改、Scheduler B 的 Informer 尚未刷新到最新注解——Layer 0 才可能拦截当次 Bind，此时再次进入 Layer 3 回退，Pod 交回 Dispatcher。这一循环受 Informer 最终一致性约束，节点归属稳定后必然终止。

这条回路保证了无论故障如何组合，Pod 最终要么被正确绑定到一个节点，要么持续处于 Pending 状态等待条件改善，不会陷入"错误绑定"或"永久卡死"的中间态。

## 4.6　一致性论证

本节给出四层容错机制维持核心不变量 I 的完整论证。图 4-3 综合展示了 4 类故障场景、4 层防御、以及 4 项证明要点的对应关系。

![图 4-3  一致性论证：核心不变量 I 及其 4 层故障场景-防御映射](../figures/fig4-3-consistency-invariant.png)

### 4.6.1　证明要点

P1【Bind 唯一性】 来自 Kubernetes 自身的原子性保证。Bind API 是 Pod 资源的子资源，kube-apiserver 通过 etcd 事务保证：当且仅当 Pod 的 `spec.nodeName` 为空时允许原子设置为目标节点；若已设置，返回 `409 Conflict`。这是 Kubernetes 集群层面的性质，本文只引用而不重新证明。

P2【Assumed 状态清理】 由 Bind Reject 阶段与 Layer 2 共同保证。Bind 失败时，SchedulerCache 中的 Assumed 状态由 Reject 阶段调用 `ForgetPod(p)` 清理（对不存在的 Pod 是 no-op，可安全重试）；etcd 中残留的调度注解由 Layer 2 的 `APICallFailedTaskQueue` Worker 通过 `CleanupPodAnnotations` 家族函数清理。进程重启后 SchedulerCache 由 Informer 从 etcd 重新构建，Assumed 状态不会作为孤儿数据永久驻留。

P3【注解清理 → 重分发的时序】 由 Layer 3 的原子 patch 保证。Layer 3 全局回退通过一次 `PatchPod` 原子提交两个注解修改——将 `pod-state` 注解设为 `Pending`，同时删除 `scheduler-name` 注解。由于 `PatchPod` 通过 etcd 事务原子提交，Dispatcher 观察到的必然是 patch 完成后的最终状态，不存在"`scheduler-name` 已清但 `pod-state` 仍为 `Dispatched`"的中间态。此外 Dispatcher 的 `selectScheduler` 幂等，因此即使多次触发也不会产生错误的分发结果。

P4【时序保证：Layer 0 前置拦截】 由 Node 归属注解的原子写入 + Layer 0 校验共同保证。当 Dispatcher `PatchNode` 修改归属注解时，Kubernetes 通过 `resourceVersion` 保证原子性；Layer 0 在 Bind API 前查询该注解，只有归属与自身匹配的 Scheduler 才能通过校验。虽然 Informer 缓存可能短暂滞后，但即使两个 Scheduler 都通过了 Layer 0，P1 的 Bind API 原子性也能保证最终只有一个 Bind 成功——第二个会因 `nodeName` 已设置而返回 `409 Conflict`，触发 Layer 1 重试，进而 Layer 2/3 清理。

### 4.6.2　组合论证

现证明 P1 ∧ P2 ∧ P3 ∧ P4 ⇒ 不变量 I 永远成立。

按图 4-1 状态机的可能路径分类讨论：

情况 1（无故障）：Pod 从 Pending → Dispatched → Assumed → Bound。只有 Layer 0 通过校验的 Scheduler 发起 Bind API，P1 保证 Bind 的原子性，任一 Pod 至多被绑定到一个节点。I 成立。

情况 2（T1 触发）：Bind 失败后 Layer 1 同步重试，仍是同一个 Scheduler 试图 Bind 同一个 Pod 到同一个节点。由 P1，重试不会绑定到第二个节点。I 保持。

情况 3（T2 触发）：Bind 存在两种子情形。子情形 (a)：Bind API 返回错误，Pod 未被绑定，$|\{node : bound(p, node)\}| = 0$；子情形 (b)：Bind API 服务端已落盘但客户端未收到响应，Pod 已被唯一绑定，$|\{node : bound(p, node)\}| = 1$。两种子情形下 I 均满足 $|\cdot| \leq 1$。Pod 在 SchedulerCache 中残留的 Assumed 状态由 P2 保证被 Bind Reject 阶段与 Layer 2 分别清理（内存态 + etcd 注解），进程崩溃场景由 Informer 从 etcd 重建 SchedulerCache 兜底。

情况 4（T0/T3 触发）：无论是节点归属漂移（T0）还是本地重试耗尽（T3），Pod 都会经 Layer 3 清除 `scheduler-name` 注解回到 Pending 状态。由 P3，操作时序正确，Dispatcher 会重新分发。分发到新 Scheduler 后走完整流程，再次遇到 Layer 0 校验（P4），归约到情况 1。I 在整个过程中不被破坏。

综上，四种情况覆盖了图 4-1 状态机的所有可能路径，且每种情况下 I 都得到维持。■

## 4.7　本章小结

本章围绕核心不变量 "任一 Pod 至多绑定到一个节点" 展开，识别了分布式调度器场景下的 4 类典型故障场景：

- T0：节点分区归属漂移；
- T1：Bind API 暂态失败；
- T2：进程内偶发错误；
- T3：本地重试耗尽 / 节点长期不可用。

分别设计了对应的 4 层容错机制：

- Layer 0：Bind 前置的节点归属校验；
- Layer 1：线性退避的同步重试；
- Layer 2：异步 Reconciler + APICallFailedTaskQueue；
- Layer 3：跨 Scheduler 实例回退，清除 `scheduler-name` 注解触发 Dispatcher 重分发。

论证过程表明，四层机制的组合能够严格维持核心不变量 I，其可靠性建立在 etcd 的原子性语义（Bind 子资源原子写入、Pod/Node 注解的 `resourceVersion` 乐观并发、Informer 的最终一致性）之上。第 5 章将在本章的一致性保证基础上，进一步优化独立 Binder 的部署形态，提出面向大规模场景的进程内 Binder 架构 ENO。
