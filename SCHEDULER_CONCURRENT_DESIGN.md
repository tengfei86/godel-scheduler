# Scheduler 并发调度架构设计 — 现有 vs 改进对比

## 1. 现有架构（Gödel 原版 — 串行调度模型）

### 1.1 总体架构

```
                         ┌─────────────────────────────────────────────┐
                         │           Gödel Scheduler 进程              │
                         │                                             │
                         │  ┌──────────────────────────────────────┐   │
                         │  │         PriorityQueue                │   │
                         │  │  ┌─────┬─────┬─────┬─────┬─────┐    │   │
                         │  │  │Unit1│Unit2│Unit3│Unit4│ ... │    │   │
                         │  │  └─────┴─────┴─────┴─────┴─────┘    │   │
                         │  └──────────────┬───────────────────────┘   │
                         │                 │ Pop() (单个)               │
                         │                 ▼                           │
                         │  ┌──────────────────────────────────────┐   │
                         │  │    单一调度 Goroutine (主循环)         │   │
                         │  │                                      │   │
                         │  │  ┌────────────────────────────────┐  │   │
                         │  │  │ 1. UpdateSnapshot()            │  │   │
                         │  │  │    cache.mu.Lock() ← 全局写锁  │  │   │
                         │  │  │    同步所有 Node/Pod 状态       │  │   │
                         │  │  │    cache.mu.Unlock()           │  │   │
                         │  │  └────────────────────────────────┘  │   │
                         │  │                 │                    │   │
                         │  │                 ▼                    │   │
                         │  │  ┌────────────────────────────────┐  │   │
                         │  │  │ 2. Locating + Grouping         │  │   │
                         │  │  └────────────────────────────────┘  │   │
                         │  │                 │                    │   │
                         │  │                 ▼                    │   │
                         │  │  ┌────────────────────────────────┐  │   │
                         │  │  │ 3. PodGroup Pod 串行调度        │  │   │
                         │  │  │                                │  │   │
                         │  │  │  for pod in Unit.Pods:         │  │   │
                         │  │  │    PreFilter(pod)  ─┐          │  │   │
                         │  │  │    Filter(pod)      │ 串行     │  │   │
                         │  │  │    Score(pod)       │ 逐个     │  │   │
                         │  │  │    SelectHost(pod) ─┘          │  │   │
                         │  │  │    ▲                           │  │   │
                         │  │  │    │ 失败则整个模板后续 Pod     │  │   │
                         │  │  │    │ 快速失败 (break)          │  │   │
                         │  │  └────────────────────────────────┘  │   │
                         │  │                 │                    │   │
                         │  │                 ▼                    │   │
                         │  │  ┌────────────────────────────────┐  │   │
                         │  │  │ 4. applyToCache()              │  │   │
                         │  │  │    for pod in successfulPods:  │  │   │
                         │  │  │      cache.mu.Lock()           │  │   │
                         │  │  │      AssumePod(pod) ← 逐个加锁 │  │   │
                         │  │  │      cache.mu.Unlock()         │  │   │
                         │  │  └────────────────────────────────┘  │   │
                         │  │                 │                    │   │
                         │  │                 ▼                    │   │
                         │  │  ┌────────────────────────────────┐  │   │
                         │  │  │ 5. go PersistSuccessfulPods()  │  │   │
                         │  │  │    (异步 → Embedded Binder)    │  │   │
                         │  │  └────────────────────────────────┘  │   │
                         │  │                 │                    │   │
                         │  │                 ▼                    │   │
                         │  │           回到 Pop() 取下一个 Unit   │   │
                         │  └──────────────────────────────────────┘   │
                         │                                             │
                         │  ┌──────────────────────────────────────┐   │
                         │  │         Scheduler Cache               │   │
                         │  │  ┌──────────┐  ┌──────────┐          │   │
                         │  │  │NodeStore │  │PodStore  │          │   │
                         │  │  └──────────┘  └──────────┘          │   │
                         │  │  mu sync.RWMutex ← 全局单锁          │   │
                         │  └──────────────────────────────────────┘   │
                         │                                             │
                         │  ┌──────────────────────────────────────┐   │
                         │  │         Snapshot (只读副本)            │   │
                         │  │  每轮调度前从 Cache 全量同步           │   │
                         │  │  调度过程中 lock-free 读取             │   │
                         │  └──────────────────────────────────────┘   │
                         └─────────────────────────────────────────────┘
```

### 1.2 PodGroup(50 pods) 串行调度时间线

```
时间轴 ═══════════════════════════════════════════════════════════════════▶
                                                                   ~107-126ms
│◄──────────────────────────────────────────────────────────────────────►│

├── Pop+Construct ──┤── UpdateSnapshot ──┤── Locate+Group ──┤
│    0.6ms          │     1-5ms          │     0.1ms        │
│                   │  (全局写锁)         │                  │
│                                                           │
├── Pod#1: PreFilter → Filter(16线程) → Score → Select ─────┤  ~2ms
├── Pod#2: PreFilter → Filter(16线程) → Score → Select ─────┤  ~2ms
├── Pod#3: PreFilter → Filter(16线程) → Score → Select ─────┤  ~2ms
│  ... (串行，一个接一个)                                     │
├── Pod#50: PreFilter → Filter(16线程) → Score → Select ────┤  ~2ms
│                                                           │
│◄──────── 50 × 2ms ≈ 100ms (占总时间85%) ────────────────►│
│                                                           │
├── applyToCache: 50次 AssumePod (逐个加锁) ────────────────┤  5-10ms
├── go PersistSuccessfulPods (异步, 不阻塞) ────────────────┤
│                                                           │
│  ⚠️ 整个过程单 goroutine 串行，下一个 Unit 必须等待        │
```

### 1.3 核心瓶颈

| 编号 | 瓶颈                      | 代码位置                                                         | 影响                                  |
| ---- | ------------------------- | ---------------------------------------------------------------- | ------------------------------------- |
| B1   | **单 goroutine 串行调度** | `switch.go:206` `wait.UntilWithContext(…ScheduleFunc(), 0)`      | 同一时刻只调度1个Unit                 |
| B2   | **全局 Cache 写锁**       | `cache.go:97` `cache.mu.Lock()`                                  | UpdateSnapshot 阻塞所有 Informer 事件 |
| B3   | **PodGroup Pod 串行**     | `unit_framework.go:194-238` `for i, podKey := range podKeysList` | 50 pods × 2ms = 100ms                 |
| B4   | **逐个 AssumePod**        | `unit_scheduler.go:741-792` 循环中每次 `cache.AssumePod()`       | 50次加解锁                            |
| B5   | **Filter 并行度硬编码**   | `parallelism.go:27` `const parallelism = 16`                     | 不随集群规模自适应                    |

---

## 2. 改进架构（并发调度模型）

### 2.1 总体架构

```
                         ┌─────────────────────────────────────────────────────┐
                         │           Enhanced Gödel Scheduler 进程              │
                         │                                                     │
                         │  ┌──────────────────────────────────────────────┐   │
                         │  │              PriorityQueue                   │   │
                         │  │  ┌─────┬─────┬─────┬─────┬─────┬─────┐     │   │
                         │  │  │Unit1│Unit2│Unit3│Unit4│Unit5│ ... │     │   │
                         │  │  └──┬──┴──┬──┴──┬──┴─────┴─────┴─────┘     │   │
                         │  └─────┼─────┼─────┼───────────────────────────┘   │
                         │        │     │     │  多个 Unit 同时 Pop            │
                         │        ▼     ▼     ▼                               │
                         │  ┌─────────────────────────────────────────────┐   │
                         │  │     多 Worker 并发调度 (Worker Pool)         │   │
                         │  │                                             │   │
                         │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐      │   │
                         │  │  │Worker-1 │ │Worker-2 │ │Worker-N │      │   │
                         │  │  │ Unit1   │ │ Unit2   │ │ Unit3   │      │   │
                         │  │  └────┬────┘ └────┬────┘ └────┬────┘      │   │
                         │  │       │           │           │            │   │
                         │  │       ▼           ▼           ▼            │   │
                         │  │  ╔═══════════════════════════════════╗     │   │
                         │  │  ║  各 Worker 使用 私有 Snapshot     ║     │   │
                         │  │  ║  (从共享 Cache 双缓冲获取)       ║     │   │
                         │  │  ║  无锁读取，不阻塞其他 Worker     ║     │   │
                         │  │  ╚═══════════════════════════════════╝     │   │
                         │  │       │           │           │            │   │
                         │  │       ▼           ▼           ▼            │   │
                         │  │  ┌─────────────────────────────────────┐  │   │
                         │  │  │  PodGroup 内 Pod 并行调度            │  │   │
                         │  │  │                                     │  │   │
                         │  │  │  Unit1(50 pods):                    │  │   │
                         │  │  │    共享 PreFilter 结果               │  │   │
                         │  │  │    ┌─────┬─────┬─────┬─────┐       │  │   │
                         │  │  │    │Pod1 │Pod2 │Pod3 │ ... │ 并行  │  │   │
                         │  │  │    │F+S  │F+S  │F+S  │     │ 执行  │  │   │
                         │  │  │    └──┬──┴──┬──┴──┬──┴─────┘       │  │   │
                         │  │  │       └─────┼─────┘                │  │   │
                         │  │  │             ▼                       │  │   │
                         │  │  │     统一收集结果 + 冲突检测          │  │   │
                         │  │  └─────────────────────────────────────┘  │   │
                         │  │       │           │           │            │   │
                         │  │       ▼           ▼           ▼            │   │
                         │  │  ┌─────────────────────────────────────┐  │   │
                         │  │  │  批量 applyToCache                  │  │   │
                         │  │  │  cache.mu.Lock()                   │  │   │
                         │  │  │  BatchAssumePods([pod1..pod50])    │  │   │
                         │  │  │  cache.mu.Unlock()  ← 只加锁1次   │  │   │
                         │  │  └─────────────────────────────────────┘  │   │
                         │  │       │           │           │            │   │
                         │  │       ▼           ▼           ▼            │   │
                         │  │  go PersistSuccessfulPods (Embedded Binder)│   │
                         │  └─────────────────────────────────────────────┘   │
                         │                                                     │
                         │  ┌─────────────────────────────────────────────┐   │
                         │  │         Scheduler Cache (双缓冲)             │   │
                         │  │                                             │   │
                         │  │  ┌─────────────┐    ┌─────────────┐        │   │
                         │  │  │ Buffer-A    │◄──►│ Buffer-B    │        │   │
                         │  │  │ (当前读)    │    │ (后台写)    │        │   │
                         │  │  └─────────────┘    └─────────────┘        │   │
                         │  │                                             │   │
                         │  │  Informer 事件 → 写入后台 Buffer            │   │
                         │  │  调度周期开始 → 原子交换 A ↔ B              │   │
                         │  │  调度线程 → 只读 Buffer-A (无锁)            │   │
                         │  └─────────────────────────────────────────────┘   │
                         └─────────────────────────────────────────────────────┘
```

### 2.2 PodGroup(50 pods) 并行调度时间线

```
时间轴 ═══════════════════════════════════════════════════════════════════▶
                                                                    ~15-25ms
│◄──────────────────────────────────────────────────────────────────────►│

├── Pop+Construct ──┤── Snapshot交换(原子) ──┤── Locate+Group ──┤
│    0.6ms          │      ~0.01ms          │     0.1ms        │
│                   │   (无锁! 原子指针交换)  │                  │
│                                                              │
├── 共享 PreFilter (一次计算, 所有同模板Pod复用) ──────────────┤  ~0.5ms
│                                                              │
├── 并行 Filter+Score (16 线程处理 50 个 Pod) ─────────────────┤
│   ┌──────────────────────────────────────────────────────┐   │
│   │ Thread-1:  Pod#1  → Filter → Score → SelectHost      │   │
│   │ Thread-2:  Pod#2  → Filter → Score → SelectHost      │   │
│   │ Thread-3:  Pod#3  → Filter → Score → SelectHost      │   │  ~6-8ms
│   │ ...        ...                                       │   │  (50/16
│   │ Thread-16: Pod#16 → Filter → Score → SelectHost      │   │  ≈4轮)
│   │ --- 第2轮 ---                                         │   │
│   │ Thread-1:  Pod#17 → ...                              │   │
│   │ ...                                                  │   │
│   └──────────────────────────────────────────────────────┘   │
│                                                              │
│   ⚠️ 冲突检测: Pod 选了同一 Node → 重调度冲突 Pod           │  ~1-2ms
│                                                              │
├── 批量 applyToCache: BatchAssumePods(50个) ← 1次加锁 ───────┤  ~0.5ms
├── go PersistSuccessfulPods (异步, Embedded Binder) ──────────┤
│                                                              │
│  ✅ 同时 Worker-2 在调度 Unit2, Worker-3 在调度 Unit3 ...    │
```

### 2.3 对比汇总

```
                    ┌──────────────────────────────────────────────────────────┐
                    │              PodGroup(50) 调度延迟对比                    │
                    │                                                          │
                    │  现有架构:                                                │
                    │  ████████████████████████████████████████████  107-126ms │
                    │  │ Snap │         50×串行 F+S          │AssumeX50│      │
                    │                                                          │
                    │  改进架构:                                                │
                    │  ████████  15-25ms                                       │
                    │  │S│PF│并行F+S│C│BA│                                     │
                    │                                                          │
                    │  提升: 5-7x                                              │
                    │                                                          │
                    ├──────────────────────────────────────────────────────────┤
                    │              整体吞吐量对比 (N=4 Workers)                 │
                    │                                                          │
                    │  现有架构:                                                │
                    │  ──Unit1──▶──Unit2──▶──Unit3──▶──Unit4──▶  串行          │
                    │                                                          │
                    │  改进架构:                                                │
                    │  ──Unit1──▶                                              │
                    │  ──Unit2──▶     4 个 Unit 同时调度                        │
                    │  ──Unit3──▶                                              │
                    │  ──Unit4──▶                                              │
                    │                                                          │
                    │  提升: ~4x (Worker 数)                                   │
                    └──────────────────────────────────────────────────────────┘
```

---

## 3. 三层改进详细设计

### 3.1 第1层（核心，推荐必做）：PodGroup 内 Pod 并行 Filter+Score

**改动范围**: `pkg/scheduler/framework/unit_runtime/unit_framework.go`

**当前代码** (`Scheduling` 函数, 194-238行):

```go
// 现有: 串行循环
for i, podKey := range podKeysList {
    scheduled, err := f.scheduleOneUnitInstance(ctx, ...)
    if scheduled {
        result.SuccessfulPods = append(...)
    } else {
        // 失败 → break, 后续同模板 Pod 快速失败
        break
    }
}
```

**改进后**:

```go
// 改进: 并行调度同模板 Pod
type podScheduleResult struct {
    podKey    string
    scheduled bool
    nodeName  string
    err       error
}

results := make([]podScheduleResult, len(podKeysList))

// Phase 1: 共享 PreFilter — 只执行一次
sharedPreFilterState, status := f.runSharedPreFilter(ctx, unitInfo, templatePod, nodeGroup)
if !status.IsSuccess() { ... }

// Phase 2: 并行 Filter+Score+SelectHost
parallelize.Until(ctx, len(podKeysList), func(i int) {
    podKey := podKeysList[i]
    runningUnitInfo := unitInfo.DispatchedPods[podKey]
    nodeName, err := f.filterScoreSelectForPod(ctx, runningUnitInfo,
        sharedPreFilterState, nodeGroup, usr)
    results[i] = podScheduleResult{
        podKey: podKey, scheduled: err == nil,
        nodeName: nodeName, err: err,
    }
})

// Phase 3: 冲突检测 — 多个 Pod 选了同一 Node
nodeUsage := map[string]int{}
for _, r := range results {
    if r.scheduled { nodeUsage[r.nodeName]++ }
}
// 对冲突 Pod 重调度或降级到串行
```

**节点冲突解决策略**:

```
50 个 Pod 并行选 Node → 有些可能选了同一个 Node（资源冲突）

策略 1 (简单): 第一个 Pod 保留，冲突 Pod 重新串行调度
策略 2 (高效): 并行 Filter 后，Score 阶段加入"已占用节点惩罚"
策略 3 (最优): 并行 Filter 得到可行节点集，然后批量分配（贪心/匈牙利算法）

推荐策略 1 — 实现简单，实际冲突率在 5000 节点下很低（50/5000 = 1%）
```

**预期效果**: PodGroup(50) 延迟从 **100ms → ~8ms** (100/16 ≈ 6ms + 冲突处理 2ms)

**实现难度**: ⭐⭐⭐ (中等)

- 需要拆分 `scheduleOneUnitInstance` 为可并行的子函数
- 需要处理 Snapshot 中 AssumePod 的并发安全问题
- PreFilter 结果共享需要确认所有插件支持

---

### 3.2 第2层（重要）：Cache 双缓冲 / 读写分离

**改动范围**: `pkg/scheduler/cache/cache.go`, `pkg/scheduler/cache/snapshot.go`

**当前问题**:

```go
// cache.go:97 — UpdateSnapshot 持全局写锁
func (cache *schedulerCache) UpdateSnapshot(snapshot *Snapshot) error {
    cache.mu.Lock()         // ← 写锁，阻塞所有 Informer 事件处理
    defer cache.mu.Unlock()
    // ... 同步所有 Store 数据到 Snapshot
}
```

**改进设计**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    双缓冲 Snapshot 机制                          │
│                                                                 │
│   Informer 事件流                                               │
│        │                                                        │
│        ▼                                                        │
│   ┌──────────┐     原子交换      ┌──────────┐                  │
│   │ Buffer-W │ ◄══════════════► │ Buffer-R │                  │
│   │ (写缓冲) │   atomic.Pointer  │ (读缓冲) │                  │
│   └──────────┘                  └──────────┘                  │
│        ▲                              │                        │
│        │                              ▼                        │
│   后台 goroutine              调度 Worker 只读                  │
│   增量更新事件                  (完全无锁)                       │
│                                                                 │
│   交换触发条件:                                                  │
│   - 每个调度周期开始前                                           │
│   - 或: 累积事件数超阈值                                        │
│   - 或: 距上次交换超 100ms                                      │
└─────────────────────────────────────────────────────────────────┘
```

**预期效果**: UpdateSnapshot 从 1-5ms（写锁）→ ~0.01ms（原子指针交换）

**实现难度**: ⭐⭐⭐⭐ (较高)

- 需要 Snapshot 支持增量更新
- 需要保证两个 Buffer 的一致性
- Informer 事件处理路径需要改造

---

### 3.3 第3层（进阶加分）：多 Worker 并发调度

**改动范围**: `pkg/scheduler/switch.go`

**当前代码**:

```go
// switch.go:206 — 单一 goroutine 无限循环
go wait.UntilWithContext(
    context.WithValue(dataSet.Ctx(), CtxKeyScheduleDataSet, dataSet),
    dataSet.ScheduleFunc(),  // ← Schedule() 函数
    0,                       // ← 间隔=0，紧密循环
)
```

**改进设计**:

```
┌───────────────────────────────────────────────────────────────┐
│              多 Worker 并发调度模型                             │
│                                                               │
│   PriorityQueue                                               │
│   ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┐               │
│   │  U1 │  U2 │  U3 │  U4 │  U5 │  U6 │ ... │               │
│   └──┬──┴──┬──┴──┬──┴──┬──┴─────┴─────┴─────┘               │
│      │     │     │     │                                      │
│      ▼     ▼     ▼     ▼                                      │
│   ┌─────┐┌─────┐┌─────┐┌─────┐                              │
│   │ W-1 ││ W-2 ││ W-3 ││ W-4 │  (N = runtime.NumCPU() / 4) │
│   │ U1  ││ U2  ││ U3  ││ U4  │                              │
│   └──┬──┘└──┬──┘└──┬──┘└──┬──┘                              │
│      │      │      │      │                                   │
│      ▼      ▼      ▼      ▼                                   │
│   各自用私有 Snapshot (从共享 Buffer-R 获取)                    │
│      │      │      │      │                                   │
│      ▼      ▼      ▼      ▼                                   │
│   ┌─────────────────────────────┐                             │
│   │  Conflict Resolution Layer  │                             │
│   │  乐观并发: 各 Worker 独立    │                             │
│   │  调度，applyToCache 时检测   │                             │
│   │  节点冲突，冲突者重调度      │                             │
│   └─────────────────────────────┘                             │
│                                                               │
│   冲突场景:                                                    │
│   Worker-1 选了 Node-A 给 Pod-X                               │
│   Worker-2 选了 Node-A 给 Pod-Y  → Node-A 资源不足            │
│   解决: Worker-2 的 Pod-Y 重新进入队列或立即重调度              │
└───────────────────────────────────────────────────────────────┘
```

**预期效果**: 整体吞吐量提升 ~N 倍（N = Worker 数量）

**实现难度**: ⭐⭐⭐⭐⭐ (高)

- 多 Worker 共享 Cache 的并发安全
- 乐观锁冲突检测与解决机制
- Queue 需要支持并发 Pop
- 需要处理 PodGroup 跨 Worker 的依赖关系

---

## 4. 实现优先级与工作量评估

```
                    投入产出矩阵
                    ════════════

    收益(性能提升)
         ▲
    高   │  ★ 第1层: PG并行      ★ 第3层: 多Worker
         │     5-7x PG延迟          N倍吞吐量
         │     2-3周                 4-6周
         │
    中   │  ★ 第2层: 双缓冲
         │     消除锁等待
         │     3-4周
         │
    低   │
         │
         └──────────────────────────────────────▶
            低           中           高     实现难度
```

### 推荐实现路径

| 阶段        | 内容                           | 工作量     | 前置依赖 | 论文价值                               |
| ----------- | ------------------------------ | ---------- | -------- | -------------------------------------- |
| **Phase 1** | PodGroup Pod 并行 Filter+Score | **2-3 周** | 无       | ⭐⭐⭐⭐⭐ 最高 — 直接量化 PG 延迟下降 |
| Phase 2     | 批量 AssumePod                 | 1 周       | Phase 1  | ⭐⭐ 锦上添花                          |
| Phase 3     | 自适应 Filter 并行度           | 0.5 周     | 无       | ⭐⭐ 简单改动，小幅提升                |
| Phase 4     | Cache 双缓冲                   | 3-4 周     | 无       | ⭐⭐⭐ 架构亮点                        |
| Phase 5     | 多 Worker 并发                 | 4-6 周     | Phase 4  | ⭐⭐⭐⭐ 完整故事但风险高              |

### 🎯 论文最优策略: 只做 Phase 1 + Phase 2 + Phase 3

**总工作量: ~3.5-4.5 周**

理由:

1. Phase 1 单项就能产生 **5-7x PG 调度延迟改善** — 这是论文最需要的量化数据
2. Phase 2 + Phase 3 是低风险的锦上添花，使优化更完整
3. Phase 4/5 风险高，可能导致回归 bug，且论文时间有限
4. 3 个 Phase 合在一起讲"PodGroup 并行调度优化"，故事完整

---

## 5. 关键源文件修改清单 (Phase 1 只涉及 3 个文件)

| 文件                                                              | 修改类型     | 改动内容                                   |
| ----------------------------------------------------------------- | ------------ | ------------------------------------------ |
| `pkg/scheduler/framework/unit_runtime/unit_framework.go`          | **核心修改** | `Scheduling()` 函数：串行→并行 Pod 调度    |
| `pkg/util/parallelize/parallelism.go`                             | **小修改**   | 支持自适应并行度 (Phase 3)                 |
| `pkg/scheduler/core/unit_scheduler/unit_scheduler.go`             | **小修改**   | `applyToCache()`: 批量 AssumePod (Phase 2) |
| `pkg/scheduler/framework/unit_runtime/parallel_scheduler.go`      | **新增**     | 并行调度器 + 冲突检测逻辑                  |
| `pkg/scheduler/framework/unit_runtime/parallel_scheduler_test.go` | **新增**     | 单元测试                                   |

---

## 6. 与 Embedded Binder 的完整论文故事线

```
论文标题: 基于架构优化的高性能 Kubernetes 调度系统设计与实现

第1章: 绪论 — Kubernetes 调度性能挑战

第2章: 相关工作 — Gödel / Omega / Borg / Volcano / Koordinator 对比

第3章: Gödel 调度器瓶颈分析
  §3.1 三层架构分析 (Dispatcher → Scheduler → Binder)
  §3.2 Scheduler 瓶颈: PodGroup 串行调度 O(N) → 应为 O(N/P)
  §3.3 Binder 瓶颈: 跨进程绑定延迟

第4章: 创新点1 — Embedded Binder (架构创新)
  §4.1 动机: 跨进程通信开销分析
  §4.2 设计: 进程内嵌入式绑定架构
  §4.3 实现: Feature Gate 控制, 向后兼容
  §4.4 理论分析: 消除 IPC 延迟的上界

第5章: 创新点2 — PodGroup 并行调度优化 (架构+算法创新)
  §5.1 动机: PodGroup 串行瓶颈量化分析 (85%时间在串行F+S)
  §5.2 设计: 共享 PreFilter + 并行 Filter/Score + 冲突检测
  §5.3 算法: 节点冲突解决策略 (贪心分配)
  §5.4 实现: 批量 AssumePod, 自适应并行度
  §5.5 理论分析: 并行加速比 = min(P, N) / (1 + 冲突重调度开销)

第6章: 实验评估
  §6.1 实验环境 (5000 KWOK 节点, 6种工作负载)
  §6.2 对比基线 (Gödel-A, Gödel-B, kube-scheduler, Volcano, Koordinator)
  §6.3 结果:
    - Embedded Binder: bind_latency_p99 降低 X%
    - 并行调度: PG 调度延迟降低 5-7x, 吞吐量提升 Y%
    - 两者结合: E2E 调度延迟降低 Z%

第7章: 总结与展望
```

这样两个创新点分别解决调度管线的**中段 (Schedule)** 和**后段 (Bind)**，覆盖完整且互不重叠。

---

## 7. 实验准备 — 构建原始 Gödel Scheduler 基线镜像

组 A（Baseline）使用上游未修改的 godel-scheduler 二进制，确保对比公平性。

```bash
# 1. 克隆上游仓库
git clone https://github.com/kubewharf/godel-scheduler.git /tmp/godel-upstream
cd /tmp/godel-upstream

# 2. 构建 Docker 镜像
docker build -t godel-local:latest -f docker/godel-local.Dockerfile .

# 3. 加载到 kind 集群
kind load docker-image godel-local:latest --name eno-bench
```

构建完成后，`deploy-group-a.sh` 会自动使用 `godel-local:latest` 镜像部署原始架构。
