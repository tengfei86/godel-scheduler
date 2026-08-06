# 摘要

随着云原生技术的普及，Kubernetes 已成为容器编排的事实标准，而调度器作为其核心组件，直接决定了集群资源利用率与工作负载的响应速度。当集群规模从千节点扩展到万节点、并发调度请求从百级别提升至千级别时，Kubernetes 原生的单实例调度器面临明显的吞吐量瓶颈与延迟抬升；已有的分布式改造方案（如字节跳动开源的 Gödel 调度器）通过 Dispatcher/Scheduler/Binder 三层架构实现多实例并发调度，但独立的 Binder 组件在高压场景下重新成为串行化瓶颈，且跨进程的 gRPC/API 调用与序列化开销显著。

本文以"基于 etcd 的分布式 Kubernetes 调度器研究与实现"为题，围绕多实例并发调度场景下的一致性保证与性能优化，开展如下三项工作：

**（1）分布式调度器系统架构分析。** 系统性梳理了 Dispatcher 分区调度、Scheduler 并发决策、Binder 事务写入的三层结构；明确了 etcd 通过 kube-apiserver 暴露的三种原子性语义（Pod 注解 CAS、Watch 一致性、Bind API 事务）是整个分布式调度器保持一致性的最底层依赖。

**（2）基于 etcd 语义的多层一致性容错机制。** 针对分区归属漂移、Bind API 暂态失败、进程内偶发错误、本地重试耗尽四类典型威胁，设计并实现了包含节点归属前置校验（Layer 0）、同步重试（Layer 1）、异步 Reconciler（Layer 2）、跨实例回退（Layer 3）的四层容错框架，并给出核心不变量"任一 Pod 至多绑定到一个节点"的证明要点。

**（3）面向大规模场景的进程内 Binder 架构（ENO）。** 提出将独立 Binder 合并进 Scheduler 进程的架构改造，通过 CacheAdapter 桥接层实现 SchedulerCache 的零拷贝共享，消除了跨进程 API 调用与序列化开销，并保持了向后兼容性（可通过 CLI 开关切换回独立 Binder 模式）。

在基于 KWOK 仿真的 1000 节点（s2）与 5000 节点（s3）集群、两种工作负载（w2/w3）、每组 3 次重复共 60 次实验的评估中，本文对比了 ENO、Gödel、kube-scheduler、Volcano、Koordinator 五个调度器的稳态吞吐、P90/P99 延迟、绑定成功率与资源开销。结果表明，ENO 在保持与 Gödel 相同一致性保证的前提下，取得了显著的性能与资源开销改进（具体数值详见第 6 章）。

**关键词**：Kubernetes 调度器，分布式调度，etcd 一致性，容错机制，大规模集群

---

# Abstract

TODO(英文摘要 - 待中文摘要定稿后翻译)

With the widespread adoption of cloud-native technologies, Kubernetes has become the de-facto standard for container orchestration, and its scheduler is a critical component that directly determines cluster resource utilization and workload responsiveness ...

**Keywords**: Kubernetes scheduler, distributed scheduling, etcd consistency, fault tolerance, large-scale cluster
