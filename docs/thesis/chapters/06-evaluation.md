# 第六章 实验设计与评估

本章通过大规模仿真基准测试评估本文提出的 ENO 架构与四层容错机制。§6.1 介绍实验环境与观测栈，§6.2 定义评估用的工作负载与规模梯度，§6.3 给出评估指标，§6.4 展示单调度器对比结果，§6.5 讨论规模扩展性，§6.6 分析资源开销，§6.7 对一致性容错机制进行专项验证，§6.8 讨论威胁与局限。

## 6.1 实验环境

### 6.1.1 硬件与仿真栈

出于成本与可复现性考虑，本文的评估基于 **KWOK（Kubernetes WithOut Kubelet）**仿真环境，而非真实的物理集群。KWOK 通过在 kind 集群中运行"假 kubelet"控制器，模拟真实节点的 Pod 生命周期，能够以极低的资源成本模拟千至万节点级别的集群。这一环境的**优势**在于：

- **可复现性强**：任何研究者可以在中等规格的开发机（例如 32 GB 内存 + 16 CPU 核心）上重现本文的实验；
- **成本低**：无需真实的物理服务器，也不需要云资源开支；
- **消除了 kubelet 与容器运行时的干扰**：所测指标聚焦于**调度器本身的性能**，而非容器启动、镜像拉取等下游开销。

**已知的局限**：KWOK 仿真环境无法完全反映真实节点上的资源竞争、网络延迟、磁盘 IO 等干扰因素，因此本文的绝对数值不能直接外推到生产环境。但**在跨调度器对比这一相对场景下**，KWOK 提供了公平的评估基准。

### 6.1.2 观测栈

图 6-1（待补）展示了本文实验的观测栈拓扑。

**TODO(图 6-1)**：待第 6 章定稿时用 mermaid 画一张实验环境拓扑图（kind 集群 + KWOK 假节点 + Prometheus + Grafana + 5 个调度器组）。

关键组件包括：

- **Prometheus**：每 15 秒从各调度器抓取一次指标，本文实验期间 Prometheus 部署为独立 Deployment，配备 2Gi 内存限制、2h 数据保留、WAL 压缩，避免 OOM；
- **调度器组自定义 recording rules**：每个调度器组（a/b/c/d/e）在自己的 Prometheus 中定义了统一的 recording rules，将各调度器的原始指标（如 `scheduler_pod_scheduling_attempts` / `volcano_task_scheduling_latency_milliseconds`）归一化为跨组可比的记录（`{group}:{metric}:{aggregation}`）；
- **Grafana**：为每个调度器组配置了独立 dashboard，用于实时观察实验进展并事后审阅。

### 6.1.3 五组调度器部署

本文对比了 5 个调度器组（表 6-1）：

**表 6-1  五个对比调度器组的部署概览**

| 组 | 调度器 | 定位 | 版本 / 特点 |
|---|---|---|---|
| a | ENO（本文提议）| Gödel 的进程内 Binder 改造 | 本文 |
| b | Gödel（原生）| 分布式调度器基线 | 上游 v0.x |
| c | kube-scheduler | K8s 原生单调度器 | v1.28.x |
| d | Volcano | CNCF 批处理调度器 | v1.9.x |
| e | Koordinator | 阿里混部调度器 | v1.5.x |

**部署公平性说明**：为保证跨组公平，本文对所有调度器组的关键组件配置了相同的资源规格——每个 Pod 的 requests 为 2 CPU / 4 GB 内存，limits 为 4 CPU / 8 GB 内存，Scheduler 客户端 QPS 与 Burst 均设为 10000。这一配置定义在 `config.sh` 中通过 `BENCH_SCHED_REQ_CPU` 等环境变量统一注入。ENO 与 Gödel 使用完全相同的镜像基线，唯一差异是启动参数中的 `--enable-embedded-binder=true/false`。

## 6.2 工作负载与规模梯度

### 6.2.1 集群规模梯度

**表 6-2  集群规模梯度**

| 代号 | 节点数 | 用途 |
|---|---|---|
| s1 | 100 | 快速验证（本文实验不使用）|
| **s2** | **1000** | **本文实验主用规模** |
| **s3** | **5000** | **本文实验主用规模** |
| s4 | 10000 | 未来扩展（本文实验暂不涉及）|
| s5 | 30000 | Gödel 官方场景（本文实验暂不涉及）|

s2 与 s3 覆盖了从中等到较大规模的集群场景，能够充分展现调度器在不同规模下的行为差异。

### 6.2.2 工作负载

**表 6-3  评估用工作负载定义**

| 代号 | 到达速率 | Pod 总数 | 每 Pod 资源 | 类型 |
|---|---|---|---|---|
| w1 | 100 pods/s | 10,000 | 100m CPU / 128Mi | 低负载稳态 |
| **w2** | **500 pods/s** | **50,000** | **100m / 128Mi** | **中负载稳态（主用）** |
| **w3** | **1000 pods/s** | **100,000** | **100m / 128Mi** | **高负载稳态（主用）** |
| w4 | 2000 pods/s | 200,000 | 100m / 128Mi | 极限负载 |
| w5 | 0→2000→0 pods/s | 50,000 | 100m / 128Mi | 突发洪峰 |
| w6 | 200 groups × 5 pods/s | 10,000 | 100m / 128Mi | Gang 调度 |
| w7 | 500 pods/s | 50,000 | 混合 | 异构资源 |
| w8 | 2000 pods/s | 800,000 | 100m / 128Mi | 大规模集群参照 |

本文实验主用 **w2（中负载）与 w3（高负载）**两组，分别代表在线服务的常规峰值与批量任务发起的压测场景。工作负载 w1（低负载）用于组 a/b/c 的额外辅助验证；w4-w8 因资源与时间成本较高，留作未来工作。

### 6.2.3 实验矩阵

本文的主评估实验共 5 组 × 2 规模 × 2 负载 × 3 重复 = **60 次实验**，全部成功完成（见 [test/e2e/benchmark/results/report_2026-08-04_223015.md](test/e2e/benchmark/results/report_2026-08-04_223015.md)，总耗时约 38 小时）。

图 6-2（待补）展示了单次实验的完整流程。

**TODO(图 6-2)**：待第 6 章定稿时用 mermaid 画单次实验的时序图（deploy → warmup → workload → wait → collect 五个阶段）。

## 6.3 评估指标

本文从**性能**、**稳定性**、**资源开销**三个维度共 8 类指标评估各调度器：

**性能指标（4 项）**：

- **稳态调度吞吐**（pods/s）：`bind_throughput_pods`。工作负载稳态期间 Pod 绑定成功的速率；
- **P90 调度延迟**（秒）：`scheduling_latency_p90`。从 Pod 进入 activeQ 到完成 Bind 的端到端 90 分位延迟；
- **P99 调度延迟**（秒）：`scheduling_latency_p99`。同上但为 99 分位；
- **Pod E2E 延迟**（秒）：`pod_e2e_latency_p99`。从 Pod 被 Dispatcher 观察到直至绑定完成的完整 E2E 延迟（**唯一能公平反映 Dispatcher 分布式调度整体性能**的指标）。

**稳定性指标（2 项）**：

- **绑定成功率**：`bind_success_rate`。Bind 成功次数 / 总 Bind 尝试次数；
- **绑定重试率**：`bind_retries`。累积重试次数（越低越好）。

**资源开销指标（2 项）**：

- **goroutines 数量**：`goroutines`。调度器进程持有的 goroutines 数（反映并发结构复杂度）；
- **绑定并发度**：`bind_inflight`。同时处于 Bind 调用中的操作数。

所有指标每 15 秒采样一次；每次实验取工作负载稳态期间（去除头尾 30 秒 warmup / cooldown）的均值与 P90/P99 分位；每组 3 次重复实验取均值 ± 1σ。

## 6.4 单调度器性能对比

### 6.4.1 稳态吞吐

**图 6-3（数据图，待生成）**  五调度器稳态吞吐 vs 集群规模 × 负载

生成命令：
```bash
python plot-results.py --compare --metric bind_throughput_pods \
  --groups a b c d e --scales s2 s3 --workloads w2 w3
```

**TODO(数值)**：待生成图与数据表后填入具体百分比。预期结论方向（待验证）：

- **ENO vs Gödel**：ENO 因消除跨进程通信开销，稳态吞吐提升约 X%（w3-s3 场景最明显）；
- **Gödel vs kube-scheduler**：Gödel 分布式架构在 s3-w3 场景吞吐显著高于 kube-scheduler；
- **Volcano/Koordinator vs kube-scheduler**：因两者均为单实例架构，吞吐上限接近 kube-scheduler。

### 6.4.2 调度延迟分布

**图 6-4（数据图，待生成）** P90 调度延迟对比（均值 ± 1σ）

**图 6-5（数据图，待生成）** P99 调度延迟对比

**TODO(数值)**：延迟对比的预期方向：

- **P90**：五调度器在 s2-w2 场景差异较小（都在合理范围内）；s3-w3 场景差异开始拉大；
- **P99**：ENO / Gödel 因分布式并发调度，长尾延迟明显好于单实例调度器；
- **ENO vs Gödel**：ENO 因消除 apiserver 中转，Pod E2E 长尾延迟应有明显改善（**这是 ENO 的核心宣称**）。

### 6.4.3 Pod E2E 延迟（Dispatcher → Bound）

**图 6-7（数据图，待生成）** Pod E2E 延迟 P99

**TODO(数值)**：ENO vs Gödel 的 E2E 延迟差异是本文架构改造的核心量化证据。预期 ENO 在这一指标上取得的相对改进最为显著（因为 ENO 消除的正是 Scheduler → Binder 之间的 Informer 事件传递环节，直接反映在 E2E 延迟上）。

### 6.4.4 绑定成功率

**图 6-6（数据图，待生成）** 绑定成功率对比

**TODO(数值)**：绑定成功率主要用于**验证正确性而非性能**——若某调度器成功率明显低于 100%，说明其在高压场景下出现了错误重试甚至丢失请求。预期 ENO 与 Gödel 在测试规模下均保持接近 100% 的成功率。

## 6.5 规模扩展性讨论

s2 与 s3 之间是 5x 的规模差距，可以初步观察各调度器在扩展性上的行为：

**TODO(数值)**：预期结论方向：

- **kube-scheduler / Volcano / Koordinator**：从 s2 到 s3，稳态吞吐几乎不变（受限于单实例上限），P99 延迟显著恶化（Filter/Score 阶段线性遍历更多节点）；
- **Gödel / ENO**：稳态吞吐随规模线性提升（分布式并发调度分摊了工作量），P99 延迟基本稳定；
- **ENO 相对 Gödel 的规模优势**：在 s3 规模下，ENO 因消除跨进程开销，吞吐提升相对幅度大于 s2 规模。

## 6.6 资源开销对比

**图 6-8（数据图，待生成）** goroutines 数量对比

**图 6-9（数据图，待生成）** bind_inflight 并发度对比

**TODO(数值)**：

- **goroutines**：ENO 因合并了 Binder 进程，单个 Scheduler 进程的 goroutines 数量应略高于 Gödel Scheduler；但 ENO **省去了 Binder Deployment 的独立 goroutines**，全系统总 goroutines 应低于 Gödel。（**这一点需要 goroutines 数据横跨 Scheduler + Binder 两个 Deployment 累加才能得到公平对比结论，第 §6.8 会讨论**。）
- **bind_inflight**：ENO 在稳态下的 bind_inflight 应明显高于 Gödel（因为消除了 apiserver 中转开销，Scheduler 端更快地驱动 Bind 调用）——这一指标从另一角度反映了 ENO 的性能优势。

## 6.7 一致性容错机制的专项验证

除性能对比外，本文还对第 4 章设计的 4 层容错机制进行了专项验证。

### 6.7.1 Layer 0 触发验证

通过 `node_validation_failures` 指标观察：

**TODO(实验)**：设计如下故障注入场景验证 Layer 0：

- 触发 Dispatcher 的 `node-shuffler` 强制重分区，观察在 shuffle 前后 Scheduler A 的 Bind 尝试是否被 Layer 0 拦截（`node_validation_failures` 计数上升）；
- 验证 Layer 0 拦截的 Pod 是否被 Layer 3 正确回收并重新分发。

### 6.7.2 Layer 3 触发验证

通过 `dispatcher_fallback` 指标观察：

**TODO(实验)**：

- 通过 kill 某个 Scheduler 实例，强制其 Pod 触发 Layer 3 回退，观察 Dispatcher 是否将这些 Pod 重新分发到其他实例；
- 验证被回退的 Pod 最终能够被绑定，且没有出现"同一 Pod 绑定到两个节点"的情况（后者可通过 kube-apiserver 直接查询验证）。

## 6.8 讨论：局限性与威胁效力

本文实验存在如下局限，均在诚实汇报的原则下明确列出：

**（1）KWOK 仿真的真实性差距**：KWOK 未模拟真实节点上的资源压力（例如 kubelet 与容器运行时的 CPU/内存开销、磁盘 IO 排队）。因此本文的绝对数值不能直接外推到生产环境。

**（2）规模上限止于 s3**：受本文实验资源与时间约束，未能覆盖 s4（10K 节点）与 s5（30K 节点）场景。Gödel 官方报告在 30K 节点下运行良好，但本文暂无独立数据支撑该规模。

**（3）工作负载类型受限**：本文主用 w2/w3 稳态负载，未覆盖 w5（突发洪峰）、w6（Gang 调度）、w7（异构资源）等场景。ENO 在这些复杂场景下的表现留作未来工作。

**（4）ENO 与 Gödel 的资源公平性**：ENO 因合并 Binder，单个 Scheduler Pod 的负载可能高于原 Gödel 的 Scheduler Pod；但同时 ENO 集群整体少了 Binder Deployment。为公平对比，本文采用**每 Deployment 的资源规格保持一致**这一策略，即两者的 Scheduler Pod 均按 2 CPU / 4 GB 分配。这一策略对 ENO 略不利（ENO 单个 Pod 要同时跑 Scheduler + Binder），但确保了单 Pod 层面的对比公平；ENO 由于不需要额外的 Binder Deployment，在**集群总资源开销**层面的优势本文未展开量化。

**（5）Volcano 指标口径的差异**：Volcano 的 `volcano_task_scheduling_latency_milliseconds` 与其他调度器的 `scheduler_scheduling_attempt_duration_seconds` 在语义上并不完全等价，本文在 §6.1.2 中通过 recording rules 尽力对齐了口径，但仍难以做到 100% 严格等价的对比。这在结论中会予以说明。

## 6.9 本章小结

本章通过 KWOK 仿真下的 60 次基准实验，对 ENO 与四种主流调度器（Gödel、kube-scheduler、Volcano、Koordinator）在稳态吞吐、调度延迟、绑定成功率、资源开销四个维度进行了系统性对比。核心结论（待具体数据填入后 finalize）预期为：

- **ENO 在 s3-w3 场景下相对 Gödel 取得显著的吞吐提升与延迟改善**（TODO：填入具体百分比）；
- **两种分布式调度器（ENO / Gödel）相对单实例调度器（kube-scheduler / Volcano / Koordinator）在大规模场景下具有明显的扩展性优势**；
- **ENO 在保持第 4 章一致性容错机制的前提下取得性能改进，验证了本文架构改造的正确性与实用性**。

具体数值将在数据图生成完毕后填入本章各处 TODO 标记的位置。
