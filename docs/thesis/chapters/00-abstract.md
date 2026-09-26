# 摘要

随着云原生应用规模的持续增长，Kubernetes 集群调度系统在承载超大规模工作负载时同时面临吞吐能力受限与绑定阶段容错能力薄弱两方面的挑战。原生 kube-scheduler 的单实例串行架构决定了其调度吞吐存在明确上限；已有的分布式改造方案虽通过多层解耦架构实现了多实例并发调度，但独立部署的绑定组件重新引入了跨进程通信开销与串行化瓶颈；与此同时，分区调度场景下节点归属漂移、Bind API 暂态失败、本地重试耗尽等异常情况缺乏系统的容错处理，一旦触发可能违反"任一 Pod 至多绑定到一个节点"这一分布式调度器的核心一致性约束。

针对上述两类问题，本文分别在架构与机制两个层面提出对应创新。

在架构层面，本文提出单 Dispatcher、多独立 Scheduler 分布式调度架构（ENO）。构建分发-执行解耦的协同模型，将 Binder 绑定执行链路与 Scheduler 决策实例同域化，消除跨组件的 gRPC/Informer 事件传递与序列化开销。此外设计并实现 CacheAdapter 共享缓存适配层，使 Scheduler 与进程内 Binder 通过对象引用共享同一份 SchedulerCache 内存实例，实现零拷贝、零同步延迟的状态复用。

在机制层面，本文提出基于 etcd 语义的分层绑定容错策略。构建四层结构化容错链路，即节点分区验证（Layer 0，预防层）、同步指数退避重试（Layer 1，即时恢复层）、异步 Reconciler 队列（Layer2，后台恢复层）与 Dispatcher 跨 Scheduler 实例回退（Layer3，全局恢复层），并给出核心一致性约束"任一 Pod 至多绑定到一个节点"的证明要点（P1~P4）。

评估在 KWOK 仿真集群上进行，覆盖 100 至 10000 节点、7 类工作负载与 1/3 两种实例配置，共 16 个对比场景，基线包括 Gödel、kube-scheduler、Volcano 与 Koordinator。吞吐采用有效吞吐口径，即总工作量除以总完成时间，以免调度器空闲期的零值稀释结果。单实例场景下 ENO 的有效吞吐同样领先其他基线：较 kube-scheduler 高 2%~22%，较 Volcano 与 Koordinator 分别高约 6 倍与 12 倍以上。ENO 在 16 个场景中 14 个高于 Gödel、2 个持平（s1/w1 低负载与 s4/w7 非饱和场景），平均提升约 12%。延迟上的收益更直接：高负载与大规模场景下 ENO 的 P99 调度延迟普遍低于 Gödel，其中 s2/w3 由 23.5 s 降至 4.0 s。当实例数由 1 增至 3 时，两者的延迟都进入亚秒级、差距收窄，此时 ENO 的有效吞吐提升 17.5%，Gödel 仅提升 1.4%。Gang 调度、极限负载与突发洪峰等场景下 ENO 的完成速度也有提升，但幅度因场景而异；其中 Gang 调度是唯一方向相反的负载，ENO 的完成时间更短而单 Pod 尾延迟高于 Gödel，这与两种架构把哪一段等待计入调度延迟有关。

关键词：Kubernetes 调度器，分布式调度，etcd 一致性，绑定容错，进程内绑定，大规模集群

---

# Abstract

With the continued growth of cloud-native applications, Kubernetes cluster scheduling systems face two simultaneous challenges when serving very-large-scale workloads: constrained throughput capacity and weak fault tolerance in the binding phase. The single-instance serial architecture of the native kube-scheduler imposes a definite upper bound on scheduling throughput. Existing distributed scheduling schemes achieve concurrent multi-instance scheduling through multi-layer decoupled architectures, but their independently deployed binding components reintroduce cross-process communication overhead and a serialization bottleneck. In partitioned-scheduling scenarios, meanwhile, anomalies such as node-ownership drift, transient Bind API failures, and exhaustion of local retries are not covered by any systematic fault-tolerance treatment, and once triggered may violate the core consistency constraint that every distributed scheduler must uphold — "each Pod is bound to at most one node".

This thesis addresses the two problems above with corresponding innovations at the architectural and mechanism levels, respectively.

At the architectural level, this thesis proposes ENO — a distributed scheduling architecture with a single Dispatcher and multiple independent Schedulers. It builds a dispatch–execution-decoupled collaboration model that co-locates the Binder's binding execution path with the Scheduler decision instance, thereby eliminating cross-component gRPC/Informer event passing and serialization overhead. In addition, a CacheAdapter shared-cache adaptation layer is designed and implemented so that the Scheduler and the in-process Binder share the same SchedulerCache memory instance by object reference, achieving zero-copy, zero-synchronization-latency state reuse.

At the mechanism level, this thesis proposes an etcd-semantics-based layered binding fault-tolerance strategy. It constructs a four-layer structured fault-tolerance chain — node-partition validation (Layer 0, prevention), synchronous exponential-backoff retry (Layer 1, immediate recovery), an asynchronous Reconciler queue (Layer 2, background recovery), and Dispatcher cross-Scheduler-instance fallback (Layer 3, global recovery) — and gives the proof outline (P1–P4) of the core consistency constraint "each Pod is bound to at most one node".

Evaluation is carried out on KWOK-simulated clusters, covering 100 to 10,000 nodes, seven workload classes, and two instance configurations (1 and 3 instances), for a total of 16 comparison scenarios, with baselines including Gödel, kube-scheduler, Volcano, and Koordinator. Throughput is measured under the effective-throughput convention — total workload divided by total completion time — so that zero-valued idle periods do not dilute the result. In the single-instance case, ENO's effective throughput also leads all other baselines: 2%–22% higher than kube-scheduler, and roughly 6× and 12× higher than Volcano and Koordinator respectively. ENO exceeds Gödel in 14 of the 16 scenarios and ties in the remaining 2 (the low-load s1/w1 and the non-saturating s4/w7), with an average improvement of about 12%. The latency gains are more direct: under high-load and large-scale scenarios, ENO's P99 scheduling latency is consistently lower than Gödel's — in s2/w3 it drops from 23.5 s to 4.0 s. When the instance count is raised from 1 to 3, both schedulers' latencies enter the sub-second regime and the gap narrows; at this point ENO's effective throughput improves by 17.5% while Gödel's improves by only 1.4%. Under gang scheduling, extreme load, and burst-flood scenarios ENO also finishes faster, but the magnitude varies by scenario; gang scheduling is the only workload where the two metrics point in opposite directions — ENO finishes sooner while its per-Pod tail latency is higher than Gödel's, which reflects which segment of waiting each architecture counts as scheduling latency.

Keywords: Kubernetes scheduler; distributed scheduling; etcd consistency; binding fault tolerance; in-process binding; large-scale cluster
