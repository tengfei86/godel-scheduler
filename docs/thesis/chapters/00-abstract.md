# 摘要

随着云原生应用规模的持续增长，Kubernetes 集群调度系统在承载超大规模工作负载时同时面临吞吐能力受限与绑定阶段容错能力薄弱两方面的挑战。原生 kube-scheduler 的单实例串行架构决定了其调度吞吐存在明确上限；已有的分布式改造方案虽通过多层解耦架构实现了多实例并发调度，但独立部署的绑定组件重新引入了跨进程通信开销与串行化瓶颈；与此同时，分区调度场景下节点归属漂移、Bind API 暂态失败、本地重试耗尽等异常情况缺乏结构化的容错保障，威胁"任一 Pod 至多绑定到一个节点"这一分布式调度器的核心一致性不变量。

针对上述两类问题，本文提出两项架构与机制层面的创新。

其一，单 Dispatcher、多独立 Scheduler 分布式调度架构（ENO）。构建分发-执行解耦的协同模型，将 Binder 绑定执行链路与 Scheduler 决策实例同域化，消除跨组件的 gRPC/Informer 事件传递与序列化开销，使吞吐能力可随 Scheduler 实例数近线性扩展；设计并实现 CacheAdapter 共享缓存适配层，使 Scheduler 与进程内 Binder 通过对象引用共享同一份 SchedulerCache 内存实例，实现零拷贝、零同步延迟的状态复用。

其二，基于 etcd 语义的分层绑定容错策略。构建四层结构化容错链路，即节点分区验证（Layer 0，预防层）、同步指数退避重试（Layer 1，即时恢复层）、异步 Reconciler 队列（Layer 2，后台恢复层）与 Dispatcher 跨实例回退（Layer 3，全局恢复层），并给出核心不变量"任一 Pod 至多绑定到一个节点"的完整证明要点（P1~P4）。

实验评估。在基于 KWOK 的仿真集群上（覆盖 100~10000 节点共 5 档规模、7 类工作负载与 1/3 两种实例配置，共 16 个对比场景），与 Gödel、kube-scheduler、Volcano、Koordinator 四个基线进行了系统性对比。实验结果表明：在 1000 pods/s 高负载下，ENO 的稳态调度吞吐较 Gödel 提升 4.4%~42.6%、峰值吞吐提升 12.9%~15.3%，P99 调度延迟降低 34.6%~80.6%，Pod E2E 延迟降低 29.0%~77.9%；极限负载（w4）下吞吐提升 18.1%~22.7%、延迟降低约 38%；实例数由 1 增至 3 时，两者的 P99 调度延迟均下降约 99%，ENO 的稳态吞吐进一步提升 28.2%，而 Gödel 下降 6.1%；全部场景的绑定成功率均为 100%，核心一致性不变量始终得到维持。相比 kube-scheduler、Volcano、Koordinator 等单实例调度器，本文方案在大规模场景下展现出显著的水平扩展性优势。

本文的工作为大规模云原生集群下分布式 Kubernetes 调度器的架构演进与一致性保证提供了系统的设计思路、开源实现与可复现的基准评估方法。

关键词：Kubernetes 调度器，分布式调度，etcd 一致性，绑定容错，进程内绑定，大规模集群

---

# Abstract

With the continuous growth of cloud-native workloads, Kubernetes cluster scheduling systems face two challenges when supporting very large clusters: limited scheduling throughput and weak fault tolerance in the binding phase. The single-instance serial architecture of the native kube-scheduler imposes a hard upper bound on scheduling throughput. Existing distributed scheduling schemes achieve concurrent multi-instance scheduling through multi-layer decoupled architectures, yet their independently deployed binding components reintroduce cross-process communication overhead and serialization bottlenecks. Meanwhile, in partition-based scheduling scenarios, anomalies such as node ownership drift, transient Bind API failures, and exhausted local retries lack structured fault-tolerance guarantees, threatening the core consistency invariant of distributed schedulers — that each Pod is bound to at most one node.

To address these two problems, this thesis proposes two architectural and mechanism-level innovations.

First, a distributed scheduling architecture with a single Dispatcher and multiple independent Schedulers (ENO). By adopting a dispatch–execution-decoupled collaboration model and co-locating the binding path with the scheduler decision instance, ENO eliminates cross-component gRPC/Informer event passing and serialization overhead, enabling near-linear throughput scaling with the number of scheduler instances. A CacheAdapter layer allows the scheduler and the in-process binder to share a single SchedulerCache instance by object reference, achieving zero-copy, zero-synchronization-latency state reuse.

Second, an etcd-semantics-based layered binding fault-tolerance strategy, comprising node partition validation (Layer 0, prevention), synchronous exponential-backoff retry (Layer 1, immediate recovery), an asynchronous reconciler queue (Layer 2, background recovery), and Dispatcher cross-instance fallback (Layer 3, global recovery), together with a complete proof of the core invariant (P1–P4).

Evaluation was conducted on KWOK-based simulated clusters covering five scales (100–10,000 nodes), seven workloads and two instance configurations, comprising 16 comparison scenarios against Gödel, kube-scheduler, Volcano and Koordinator. Under high load (1,000 pods/s), ENO improves steady-state throughput over Gödel by 4.4%–42.6% (12.9%–15.3% for peak throughput), reduces P99 scheduling latency by 34.6%–80.6% and end-to-end Pod latency by 29.0%–77.9%; under extreme load (w4) throughput improves by 18.1%–22.7% with latency reduced by about 38%. Increasing scheduler instances from 1 to 3 lowers P99 scheduling latency by about 99% for both schedulers, while ENO's steady-state throughput improves further by 28.2% (Gödel degrades by 6.1%). The binding success rate is 100% in all scenarios and the core consistency invariant is always preserved. Compared with single-instance schedulers, the proposed scheme exhibits clear horizontal scalability advantages at large scale.

This work provides a systematic design rationale, an open-source implementation, and a reproducible benchmark methodology for the architectural evolution and consistency assurance of distributed Kubernetes schedulers in large-scale cloud-native clusters.

Keywords: Kubernetes scheduler; distributed scheduling; etcd consistency; binding fault tolerance; embedded binder; large-scale cluster
