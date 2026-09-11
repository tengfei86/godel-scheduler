# 主要符号表和缩略语说明

## 一、缩略语

| 缩略语 | 英文全称 | 中文含义 |
|---|---|---|
| ENO | Embedded Binder (in-process Binder) | 本文提出的进程内绑定器分布式调度架构（方案/项目名称，非首字母缩写） |
| API | Application Programming Interface | 应用程序编程接口 |
| CRD | Custom Resource Definition | 自定义资源定义 |
| CAS | Compare-And-Swap | 比较并交换（etcd 事务的原子条件更新原语） |
| MVCC | Multi-Version Concurrency Control | 多版本并发控制 |
| OCC | Optimistic Concurrency Control | 乐观并发控制 |
| RPC / gRPC | Remote Procedure Call | 远程过程调用 / 其高性能实现 |
| TTL | Time To Live | 存活时间（租约 Lease 的有效期） |
| QoS | Quality of Service | 服务质量 |
| LS / BE | Latency-Sensitive / Best-Effort | 延迟敏感型 / 尽力而为型工作负载 |
| DRF | Dominant Resource Fairness | 主导资源公平分配算法 |
| FIFO | First In First Out | 先入先出（排队策略） |
| E2E | End-to-End | 端到端（时延指标） |
| P50 / P90 / P99 | 50th / 90th / 99th Percentile | 分位延迟（50 / 90 / 99 分位） |
| KWOK | Kubernetes WithOut Kubelet | Kubernetes 节点仿真工具 |
| HPC | High Performance Computing | 高性能计算 |

## 二、主要符号

| 符号 | 含义 |
|---|---|
| $I$ | 核心一致性不变量：任一 Pod 至多绑定到一个节点 |
| $p$ | 系统中的某个 Pod |
| $N$ | Scheduler 实例数 |
| s1 ~ s5 | 集群规模代号，分别对应 100、1000、5000、10000、30000 个节点 |
| w1 ~ w8 | 工作负载代号，定义见表 6-3 |
| inst1 / inst3 | 调度器实例数配置（1 个 / 3 个实例） |
| a ~ e | 调度器组代号：a=ENO、b=Gödel、c=kube-scheduler、d=Volcano、e=Koordinator |
| Layer 0 ~ Layer 3 | 第 4 章四层绑定容错机制的四个层次 |
| T0 ~ T3 | 第 4 章识别的四类典型故障威胁 |
| P1 ~ P4 | 第 4 章不变量证明的四个要点 |

> 说明：正文中 `scheduler-name`、`assumed-node`、`resourceVersion` 等带 `code` 标记的标识符为 Kubernetes 资源字段或注解键名，首次出现处已给出中英文对照说明。
