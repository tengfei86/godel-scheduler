# 摘要

随着云原生应用规模的持续增长，Kubernetes 集群调度系统在承载超大规模工作负载时同时面临吞吐能力受限与绑定阶段容错能力薄弱两方面的挑战。原生 kube-scheduler 的单实例串行架构决定了其调度吞吐存在明确上限；已有的分布式改造方案虽通过多层解耦架构实现了多实例并发调度，但独立部署的绑定组件重新引入了跨进程通信开销与串行化瓶颈；与此同时，分区调度场景下节点归属漂移、Bind API 暂态失败、本地重试耗尽等异常情况缺乏结构化的容错保障，威胁"任一 Pod 至多绑定到一个节点"这一分布式调度器的核心一致性不变量。

针对上述两类问题，本文提出两项架构与机制层面的创新。

其一，单 Dispatcher、多独立 Scheduler 分布式调度架构（ENO）。构建分发-执行解耦的协同模型，将 Binder 绑定执行链路与 Scheduler 决策实例同域化，消除跨组件的 gRPC/Informer 事件传递与序列化开销。吞吐随实例数增长，但并非严格线性：实测实例数由 1 增至 3 时，峰值吞吐提升 19.2%。此外设计并实现 CacheAdapter 共享缓存适配层，使 Scheduler 与进程内 Binder 通过对象引用共享同一份 SchedulerCache 内存实例，实现零拷贝、零同步延迟的状态复用。

其二，基于 etcd 语义的分层绑定容错策略。构建四层结构化容错链路，即节点分区验证（Layer 0，预防层）、同步指数退避重试（Layer 1，即时恢复层）、异步 Reconciler 队列（Layer 2，后台恢复层）与 Dispatcher 跨实例回退（Layer 3，全局恢复层），并给出核心不变量"任一 Pod 至多绑定到一个节点"的证明要点（P1~P4）。

评估在 KWOK 仿真集群上进行，覆盖 100 至 10000 节点、7 类工作负载与 1/3 两种实例配置，共 16 个对比场景，基线包括 Gödel、kube-scheduler、Volcano 与 Koordinator。吞吐采用有效吞吐口径，即总工作量除以总完成时间，以免调度器空闲期的零值稀释结果。ENO 在 16 个场景中 14 个高于 Gödel，其余 2 个持平，平均提升约 14%；各场景均完成 100% 调度，差异来自完成时间而非完成度。延迟上的收益更直接：高负载与大规模场景下 ENO 的 P99 调度延迟普遍低于 Gödel，其中 s2/w3 由 23.5 s 降至 4.0 s。当实例数由 1 增至 3 时，两者的延迟都进入亚秒级、差距收窄，此时 ENO 的有效吞吐仍在上升，Gödel 则基本不变。Gang 调度、极限负载与突发洪峰等场景下 ENO 的完成速度也有提升，但幅度因场景而异。上述结果都在第 4 章一致性容错机制保持不变的前提下取得，未观察到绑定失败。

本文的工作为大规模云原生集群下分布式 Kubernetes 调度器的架构演进与一致性保证提供了系统的设计思路、开源实现与可复现的基准评估方法。

关键词：Kubernetes 调度器，分布式调度，etcd 一致性，绑定容错，进程内绑定，大规模集群

---

# Abstract

With the continuous growth of cloud-native workloads, Kubernetes cluster scheduling systems face two challenges when supporting very large clusters: limited scheduling throughput and weak fault tolerance in the binding phase. The single-instance serial architecture of the native kube-scheduler imposes a hard upper bound on scheduling throughput. Existing distributed scheduling schemes achieve concurrent multi-instance scheduling through multi-layer decoupled architectures, yet their independently deployed binding components reintroduce cross-process communication overhead and serialization bottlenecks. Meanwhile, in partition-based scheduling scenarios, anomalies such as node ownership drift, transient Bind API failures, and exhausted local retries lack structured fault-tolerance guarantees, threatening the core consistency invariant of distributed schedulers — that each Pod is bound to at most one node.

To address these two problems, this thesis proposes two architectural and mechanism-level innovations.

First, a distributed scheduling architecture with a single Dispatcher and multiple independent Schedulers (ENO). By adopting a dispatch–execution-decoupled collaboration model and co-locating the binding path with the scheduler decision instance, ENO eliminates cross-component gRPC/Informer event passing and serialization overhead. Throughput grows with the number of scheduler instances, though the growth is sub-linear: raising the instance count from 1 to 3 improves peak throughput by 19.2%. A CacheAdapter layer additionally allows the scheduler and the in-process binder to share a single SchedulerCache instance by object reference, achieving zero-copy, zero-synchronization-latency state reuse.

Second, an etcd-semantics-based layered binding fault-tolerance strategy, comprising node partition validation (Layer 0, prevention), synchronous exponential-backoff retry (Layer 1, immediate recovery), an asynchronous reconciler queue (Layer 2, background recovery), and Dispatcher cross-instance fallback (Layer 3, global recovery), together with a proof of the core invariant (P1–P4).

Evaluation was carried out on KWOK-based simulated clusters, covering 100 to 10,000 nodes, seven workloads and two instance configurations, across 16 comparison scenarios and against Gödel, kube-scheduler, Volcano and Koordinator. Throughput is measured as effective throughput, that is, total workload divided by total completion time, so that idle periods do not dilute the average. ENO is faster than Gödel in 14 of the 16 scenarios and ties in the remaining two, with an average improvement of about 14%. Every scenario completed 100% of its scheduling, so the differences come from completion time rather than from completion rate. The latency results are more clear-cut: ENO shows lower P99 scheduling latency in the high-load and large-scale scenarios, for instance 4.0 s against 23.5 s at s2/w3. When the instance count rises from 1 to 3, both schedulers drop to sub-second latency and the gap narrows, while ENO's effective throughput keeps improving and Gödel's stays roughly flat. Improvements also appear under gang scheduling, extreme load and burst traffic, though their size varies by scenario. All of these results hold with the consistency mechanisms of Chapter 4 unchanged, and no binding failure was observed.

This work provides a systematic design rationale, an open-source implementation, and a reproducible benchmark methodology for the architectural evolution and consistency assurance of distributed Kubernetes schedulers in large-scale cloud-native clusters.

Keywords: Kubernetes scheduler; distributed scheduling; etcd consistency; binding fault tolerance; embedded binder; large-scale cluster
