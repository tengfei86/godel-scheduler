# Scheduler & Dispatcher 内存优化方案

> W8 场景（800K pods, 2000 pods/s）下 Embedded Binder Scheduler OOM 的根因分析与优化措施。

---

## 1. 内存消费全景（800K pods 估算）

### 1.1 Scheduler（含 Embedded Binder）

| 消费者 | 大小 | 级别 | 说明 |
|--------|------|------|------|
| Pod Informer 缓存 | 2–4 GB | **严重** | 监听全量 Pod（含已完成），每个 2–5 KB |
| PodStates cache | 4–5 GB | **严重** | `map[string]*CachePodState`，所有 bound+assumed pod |
| Node 元数据 | 0.5–1 GB | 高 | 每节点 500 KB–1 MB（资源状态、pod 列表、镜像） |
| ImageStates | 0.5–1 GB | 高 | 每节点 ~50 张镜像 × `*ImageStateSummary` |
| 日志字符串分配（v≥4） | 20–50 MB/s | 高 | 每 pod 操作 5–10 条日志 → 持续 GC 压力 |
| AssumedPod 堆积 | 可变 | 中 | TTL 15 min → 过期 pod 驻留内存 |
| PodGroup/Unit 结构 | 50–500 MB | 中 | gang 调度 unit 的 `queuedPodInfoMap` |
| 队列（readyQ/waitingQ） | 20–50 MB | 低 | 有界，跟 pod 数线性 |
| **Embedded Scheduler 总计** | **12–16 GB** | | 旧 limits=4G → **必然 OOM** |

### 1.2 Dispatcher

| 消费者 | 大小 | 说明 |
|--------|------|------|
| Pod Informer 缓存 | 1.6–4 GB | 也监听全量 Pod |
| DispatchInfo.Pods | 120–160 MB | `map[string]*podInfo`，每条 150–200 B |
| SchedulerToPods | 40–60 MB | `map[string]sets.String` |
| UnitInfos（gang） | 300–500 MB | 每 unit 600 + N×340 B |
| QueuedPodInfo（队列） | 140–180 MB | 峰值 ~400K pods 在队列 |
| goroutine 栈 | ~210 MB | 1:1 goroutine-per-pod，~100 并发 × 2 MB |
| **Dispatcher 总计** | **2.5–5.3 GB** | 旧 limits=4G → **边界风险** |

---

## 2. 已实施的优化（5 类）

### 2.1 日志级别降到 v=2

| 组件 | 改前 | 改后 | 文件 |
|------|------|------|------|
| Scheduler (base) | `--v=4` | `--v=2` | `manifests/base/deployment/scheduler.yaml` |
| Dispatcher | `--v=5` | `--v=2` | `manifests/base/deployment/dispatcher.yaml` |
| Binder | `--v=5` | `--v=2` | `manifests/base/deployment/binder.yaml` |
| Embedded Scheduler | `--v=4` | `--v=2` | `manifests/overlays/embedded-binder/scheduler-embedded.yaml` |

**原理**：v≥4 下每秒产生 20–50 MB 字符串分配，GC 无法及时回收。v=2 保留关键信息，减少 ~30% GC 压力。

### 2.2 AssumedPod TTL 缩短 + 清理加速

| 参数 | 改前 | 改后 | 文件 |
|------|------|------|------|
| PodAssumedTTL | 15 min | 5 min | `pkg/scheduler/scheduler.go` L136 |
| Period（cleanup 间隔） | 10 s | 5 s | 同上 |

**原理**：Embedded Binder 模式下绑定延迟远低于 15 分钟，过期 assumed pod 可更快释放。

### 2.3 Go 运行时内存兜底（GOGC + GOMEMLIMIT）

| 组件 | GOGC | GOMEMLIMIT | 文件 |
|------|------|------------|------|
| Scheduler (base) | 75 | 7 GiB | `manifests/base/deployment/scheduler.yaml` |
| Dispatcher | 75 | 3500 MiB | `manifests/base/deployment/dispatcher.yaml` |
| Binder | 75 | 7 GiB | `manifests/base/deployment/binder.yaml` |
| **Embedded Scheduler** | **75** | **14 GiB** | `manifests/overlays/embedded-binder/scheduler-embedded.yaml` |

**原理**：
- `GOGC=75`：GC 在堆增长 75%（而非默认 100%）时触发，降低峰值内存。
- `GOMEMLIMIT`：Go 1.19+ 软上限，接近时主动压缩堆，避免被 cgroup OOMKilled。设为 limits 的 ~87%。

### 2.4 资源 limits/requests 提升

| 组件 | 改前 req | 改后 req | 改前 lim | 改后 lim |
|------|---------|---------|---------|---------|
| Scheduler (base) | 1 CPU / 2G | 2 CPU / 4G | 2 CPU / 4G | 4 CPU / 8G |
| Dispatcher | 1 CPU / 2G | 2 CPU / 2G | 2 CPU / 4G | 4 CPU / 4G |
| Binder | 1 CPU / 2G | 2 CPU / 4G | 2 CPU / 4G | 4 CPU / 8G |
| **Embedded Scheduler** | **1 CPU / 2G** | **4 CPU / 8G** | **2 CPU / 4G** | **8 CPU / 16G** |

**原理**：Embedded Scheduler 内嵌了 Binder，内存 ≈ Scheduler + Binder，16G limits 才能覆盖 W8 峰值。

### 2.5 Binder 日志 + 资源同步优化

Binder（组 A 独立部署时）同样从 v=5 降到 v=2，增加 GOGC/GOMEMLIMIT 和资源上限。

---

## 3. 待评估的进一步优化

### 3.1 Pod Informer FieldSelector 过滤（预估省 2–3 GB）

**位置**：`pkg/scheduler/scheduler.go` L128–130、`cmd/dispatcher/app/server.go` L135

**现状**：Scheduler 和 Dispatcher 都 watch 全量 Pod（含 Succeeded/Failed）。

**方案**：
```go
informerFactory := informers.NewSharedInformerFactoryWithOptions(client, 0,
    informers.WithTweakListOptions(func(opts *metav1.ListOptions) {
        opts.FieldSelector = "status.phase!=Succeeded,status.phase!=Failed"
    }),
)
```

**风险**：需确认 cache/event handler 不依赖已完成 Pod 的事件；PodGroup 状态计算可能需要已完成 Pod。

**优先级**：高（收益最大但影响面广，需单独 PR 充分测试）

### 3.2 Dispatcher goroutine-per-pod 改 Worker Pool（预估省 200 MB）

**位置**：`pkg/dispatcher/dispatcher.go` L320

**现状**：
```go
go d.dispatchingPod(ctx, podInfo, d.SortedPodsQueue)
```

**方案**：改为有界 worker pool（10–20 workers）。

**风险**：并发模型变化需要回归分发延迟；原代码注释 `TODO(zhangrenyu)` 已提及此问题。

**优先级**：中

### 3.3 DispatchInfo 已完成 Pod 及时清理（预估省 100–200 MB）

**位置**：`pkg/dispatcher/internal/store/dispatch.go` L107–125

**现状**：`DispatchInfo.Pods` map 持有所有已分发 pod，绑定完成后不清理。

**方案**：Pod 进入 Bound/Running 状态时从 map 中删除。

**风险**：需确认 `SchedulerToPods` 负载均衡计数不依赖已绑定 Pod。

**优先级**：中

### 3.4 Node ImageStates 精简（预估省 0.5–1 GB）

**位置**：`pkg/framework/api/nodeinfo.go` L118–200

**现状**：KWOK 模拟节点可能携带大量默认镜像。

**方案**：KWOK 节点模板中清空 `status.images`，或 NodeInfo 构建时过滤无用镜像。

**风险**：无（仅影响 KWOK 测试场景）。

**优先级**：低

### 3.5 Snapshot 增量更新（预估省 10–50 MB）

**位置**：`pkg/scheduler/cache/cache.go` L94–124

**现状**：每调度周期调用 `UpdateSnapshot()`，重建 4 个 HashSlice。

**方案**：仅在 node/pod 变更时重建受影响部分。

**风险**：复杂度高。当前实现已用浅拷贝，开销可控。

**优先级**：低

---

## 4. 关键代码位置索引

| 组件 | 文件 | 关注点 |
|------|------|--------|
| Scheduler Cache | `pkg/scheduler/cache/cache.go` | cleanAssumedPeriod, schedulerCache 结构 |
| PodStore | `pkg/scheduler/cache/commonstores/pod_store/pod_store.go` | AssumedPods map, PodStates map, CleanupExpiredAssumedPods |
| NodeStore | `pkg/scheduler/cache/commonstores/node_store/node_store.go` | generationstore.ListStore |
| Scheduler 入口 | `pkg/scheduler/scheduler.go` L120–150 | Informer 创建, PodAssumedTTL, Period |
| Scheduler Server | `cmd/scheduler/app/server.go` | Embedded Binder 初始化 |
| Dispatcher 入口 | `pkg/dispatcher/dispatcher.go` L304–320 | sortedLoop, goroutine-per-pod |
| Dispatcher Store | `pkg/dispatcher/internal/store/dispatch.go` | DispatchInfo, Pods map |
| Dispatcher Server | `cmd/dispatcher/app/server.go` | Informer factory 创建 |
| Binder CacheAdapter | `pkg/binder/cache_adapter.go` | Embedded 模式下共享 Cache |
| Binder Cache（独立） | `pkg/binder/cache/cache.go` | 独立模式的完整 Cache 副本 |

---

## 5. 验证清单

- [ ] `go build ./pkg/scheduler/...` 编译通过
- [ ] `go build ./pkg/dispatcher/...` 编译通过
- [ ] YAML 校验通过
- [ ] 组 A（共享 Binder）部署正常，Scheduler/Binder/Dispatcher 均 Running
- [ ] 组 B（Embedded Binder）部署正常，Scheduler Running，Binder replicas=0
- [ ] W4（200K pods）无 OOM
- [ ] W8（800K pods）无 OOM
- [ ] Prometheus `container_memory_working_set_bytes` 峰值 < limits 的 90%
- [ ] 调度延迟 P99 无明显退化（对比基线）
