# 第二章 相关工作与背景

本章围绕本文研究涉及的四个方向展开：Kubernetes 原生调度器架构、批处理调度器（Volcano）、混部调度器（Koordinator）、大规模分布式调度器（Gödel）；最后简要介绍 etcd 的一致性模型与本文所依赖的三种原子性语义。

## 2.1 Kubernetes 原生调度器

kube-scheduler 是 Kubernetes 集群中的默认调度器，也是本文其他调度器的共同基线。其核心工作流程包括三个阶段：

- **入队与排序**：待调度的 Pod 通过 Informer 事件进入调度队列 activeQ，按优先级与创建时间排序；调度失败的 Pod 进入 backoffQ 等待退避后重试；
- **调度决策**：从 activeQ 弹出 Pod 后，依次执行 PreFilter → Filter → PostFilter → PreScore → Score → Reserve → Permit 一系列插件，最终产出目标节点；
- **绑定**：将调度决策通过 Bind API 写入 kube-apiserver，Bind API 是 Pod 资源的一个子资源，Kubernetes 提供了对该操作的原子性保证。

kube-scheduler 采用**单实例串行处理**架构，虽然内部通过 goroutine 池并发执行 Filter/Score，但同一时刻仅有一个 Pod 处于绑定阶段，Bind 操作串行地写入 apiserver。这一设计的主要优势是**天然避免了多实例并发绑定同一节点的冲突**——不需要额外的一致性协议——但其吞吐上限也就此固定：官方测试<sup>[?]</sup>与本文实验均表明其稳态吞吐约在数百 pods/s 量级。

kube-scheduler 2019 年引入的 **Scheduling Framework**<sup>[?]</sup> 通过插件化机制将调度流程解耦为若干扩展点，使得第三方项目（Volcano、Koordinator 等）可以在不 fork 主线代码的前提下扩展调度能力，这也构成了本章后续调度器的技术起点。

## 2.2 批处理调度器 Volcano

Volcano 是 CNCF 孵化的 Kubernetes 批处理调度器，主要面向 AI 训练、大数据、HPC 等场景。相比 kube-scheduler，Volcano 的关键差异在于：

- **Gang 调度**：批处理任务（例如分布式训练）通常要求"要么全部 Pod 都被调度，要么全部不调度"，Volcano 通过 PodGroup 抽象与 gang 插件在决策阶段整体判断是否满足 Gang 约束；
- **Session-based 调度周期**：Volcano 将一次调度周期封装为 Session，在 Session 内维护该周期看到的资源视图与 job 队列，Session 结束时统一提交决策；
- **多维公平共享**：通过 DRF（Dominant Resource Fairness）等算法在多个租户/队列之间实现公平资源分配。

Volcano 的架构上仍然沿用了 kube-scheduler 的**单实例调度**，其扩展性主要通过 Session 内的批处理决策与插件化实现，而非水平扩展多个调度器实例。这一设计使 Volcano 在批处理场景下具备较好的策略表达能力，但在需要极高稳态吞吐的场景下同样受制于单实例的处理能力。

## 2.3 混部调度器 Koordinator

Koordinator 是阿里巴巴开源的、面向在线离线混合部署场景的 Kubernetes 调度器。其技术定位与 Volcano 有明显区别：

- **QoS 感知调度**：区分 Latency-Sensitive（LS）、Best-Effort（BE）等 QoS 等级，Best-Effort 类工作负载可以复用 Latency-Sensitive 类工作负载的空闲资源；
- **资源超卖**：基于历史使用率数据对节点资源进行合理超售，提升集群整体利用率；
- **干扰隐藏**：结合节点级 Agent（koordlet）对高优任务的实际负载进行监测，动态压制低优任务。

Koordinator 的架构上同样是**基于 kube-scheduler 的插件扩展**，属于 Scheduling Framework 之上的能力增强，而非分布式架构改造。因此在多实例并发调度、水平扩展方向上，Koordinator 与 kube-scheduler 保持一致，并不追求单纯的吞吐提升。

## 2.4 大规模分布式调度器 Gödel

字节跳动开源的 Gödel Scheduler 是目前少数完整实现了**多实例并发分布式调度**的开源项目。其核心架构包含三层：

- **Dispatcher**：单实例（通过 Leader Election 保证），负责将待调度的 Pod 分发给某个具体的 Scheduler 实例。分发依据包括 Pod 的 PodGroup 归属、Owner 亲和策略、以及 Scheduler 实例的负载均衡；同时 Dispatcher 维护一个**节点分区表**，通过 Node Partition Manager 将全集群节点划分给不同的 Scheduler 实例；
- **Scheduler**：多实例（水平扩展），每个 Scheduler 实例只负责自己分区内的节点，独立执行 Filter/Score/Reserve 完成调度决策，然后将决策通过 Kubernetes API 传递给 Binder；
- **Binder**：独立部署（Deployment 形态），从 Kubernetes API Server 通过 Informer 接收调度决策事件，负责最终的 Bind API 调用与冲突处理。

Gödel 的核心创新点在于**节点分区机制**：通过将全集群节点划分为互不相交的分区，多个 Scheduler 实例天然避免了对同一节点资源的竞争，从而实现真正意义上的并发调度。字节跳动内部报告称该架构在 3 万节点级别的生产集群中稳定运行<sup>[?]</sup>。

然而，Gödel 中 Binder 的独立部署形态在超高并发场景下会再次成为串行化瓶颈，这也是本文第 5 章 ENO 架构改造要解决的问题。此外，Gödel 公开发表的分析中缺乏对**节点分区归属动态漂移**（Dispatcher 在运行时重新分配节点归属）场景下一致性保证的完整论证，本文第 4 章将补充这一部分。

## 2.5 etcd 的一致性模型与本文关键依赖

**etcd** 是 Kubernetes 集群的核心元数据存储，采用 Raft 协议保证强一致性。所有 Kubernetes 资源对象（Pod、Node、Deployment 等）都以 key-value 的形式存储在 etcd 中，并通过 kube-apiserver 暴露 RESTful 接口对外提供访问。

本文的一致性容错机制主要依赖 etcd 通过 kube-apiserver 暴露的三种原子性语义：

**（1）Pod 资源的乐观并发控制（`resourceVersion`）。** 每个 Kubernetes 资源对象都携带一个 `resourceVersion` 字段，该值由 etcd 在每次修改时单调递增地生成。对同一资源的 Patch/Update 操作可携带 `resourceVersion` 参数，只有当当前存储的版本号与提交的版本号一致时才允许写入，否则返回 `409 Conflict`。这一机制是 Pod 注解（如 `scheduler-name`、`assumed-node`）能被多个组件安全并发修改的基础。

**（2）Watch API 的一致性视图。** 客户端可通过 `Watch` API 从某个 `resourceVersion` 开始订阅资源变更事件，etcd 保证同一 key 的事件按 `resourceVersion` 单调递增顺序推送。Kubernetes 的 Informer 机制在此基础上构建本地缓存，为调度器提供了一致的资源视图。

**（3）Pod Bind 子资源的原子性。** Bind API 是 Pod 资源的一个特殊子资源（`POST /api/v1/namespaces/{ns}/pods/{name}/binding`），kube-apiserver 通过 etcd 事务保证：若 Pod 的 `spec.nodeName` 为空，则允许原子设置为目标节点；若已经设置，则返回 `409 Conflict`。这一语义**从根本上排除了"同一 Pod 被并发绑定到两个不同节点"的可能性**——不论调度器有多少实例、并发度多高，只要最终都通过 Bind API 写入，Kubernetes 集群的这一核心不变量就得到保证。

本文第 4 章的一致性容错机制正是在上述三种 etcd 原子性语义的基础上层层构建的应用层协议，在此我们对其做出显式引用。

## 2.6 现有工作的不足与本文定位

综上，现有的开源调度器工作主要存在如下不足：

1. **单实例调度器**（kube-scheduler、Volcano、Koordinator）在超大规模场景下受限于串行处理架构，吞吐与延迟难以进一步提升；
2. **已有的分布式调度器**（Gödel）虽实现了多实例并发，但独立 Binder 部署形态引入了新的跨进程串行化瓶颈；
3. 分区调度场景下**节点归属动态变更**的一致性保证缺乏完整论证；
4. 多种调度器在大规模场景下的**系统性性能对比**较少见诸公开发表。

本文的定位是：**在 Gödel 分布式架构的基础上**，一方面通过严格的一致性容错机制填补第 3 点的空白，另一方面通过 ENO 进程内 Binder 架构解决第 2 点的性能瓶颈；同时通过公开的 KWOK 仿真评估平台补齐第 4 点的对比数据。
