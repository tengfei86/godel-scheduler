# 附录

## 附录 A  完整实验数据表

本附录汇总本文全部场景下 ENO（a）与 Gödel（b）的关键指标稳态均值（口径见 §6.3：稳态窗口均值，剔除头尾 30 秒，每场景 3 次重复取均值）。原始数据与跨组对比图见仓库 `test/e2e/benchmark/results/`。

**表 A-1  ENO 与 Gödel 关键指标汇总（稳态口径）**

| 场景（实例配置） | 指标 | ENO（a） | Gödel（b） | 相对变化 |
|---|---|---|---|---|
| s2/w2（inst1） | 吞吐(pods/s) | 313.76 | 414.94 | -24.4% |
|  | 峰值吞吐 | 500.09 | 539.77 | -7.4% |
|  | P90(秒) | 0.048 | 0.060 | +20.1% |
|  | P99(秒) | 0.185 | 0.195 | +5.4% |
|  | E2E P99(秒) | 0.332 | 0.420 | +20.9% |
|  | 绑定P99(秒) | 0.036 | 0.068 | +47.0% |
|  | Pending堆积 | 0.400 | 0.167 | -140.0% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s2/w3（inst1） | 吞吐(pods/s) | 444.37 | 417.02 | +6.6% |
|  | 峰值吞吐 | 984.81 | 869.40 | +13.3% |
|  | P90(秒) | 2.69 | 15.93 | +83.1% |
|  | P99(秒) | 3.48 | 19.35 | +82.0% |
|  | E2E P99(秒) | 3.74 | 18.39 | +79.7% |
|  | 绑定P99(秒) | 0.103 | 0.097 | -6.9% |
|  | Pending堆积 | 799.40 | 4394.38 | +81.8% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s3/w2（inst1） | 吞吐(pods/s) | 314.60 | 409.66 | -23.2% |
|  | 峰值吞吐 | 632.17 | 500.62 | +26.3% |
|  | P90(秒) | 0.243 | 0.257 | +5.5% |
|  | P99(秒) | 0.582 | 0.508 | -14.4% |
|  | E2E P99(秒) | 0.912 | 1.04 | +12.0% |
|  | 绑定P99(秒) | 0.037 | 0.052 | +28.6% |
|  | Pending堆积 | 0.200 | 16.83 | +98.8% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s3/w3（inst1） | 吞吐(pods/s) | 444.44 | 409.49 | +8.5% |
|  | 峰值吞吐 | 789.33 | 686.38 | +15.0% |
|  | P90(秒) | 16.01 | 30.91 | +48.2% |
|  | P99(秒) | 19.02 | 36.21 | +47.5% |
|  | E2E P99(秒) | 20.09 | 33.86 | +40.7% |
|  | 绑定P99(秒) | 0.059 | 0.078 | +23.3% |
|  | Pending堆积 | 4956.20 | 7912.44 | +37.4% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s3/w3（inst3） | 吞吐(pods/s) | 418.22 | 414.36 | +0.9% |
|  | 峰值吞吐 | 1270.60 | 913.84 | +39.0% |
|  | P90(秒) | 0.047 | 0.058 | +17.8% |
|  | P99(秒) | 0.385 | 0.325 | -18.4% |
|  | E2E P99(秒) | 0.625 | 1.21 | +48.5% |
|  | 绑定P99(秒) | 0.065 | 0.102 | +36.3% |
|  | Pending堆积 | 2.13 | 1.19 | -79.6% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s3/w4（inst3） | 吞吐(pods/s) | 345.26 | 292.26 | +18.1% |
|  | 峰值吞吐 | 1873.83 | 1641.79 | +14.1% |
|  | P90(秒) | 7.89 | 11.62 | +32.1% |
|  | P99(秒) | 9.88 | 15.88 | +37.8% |
|  | E2E P99(秒) | 11.90 | 22.17 | +46.3% |
|  | 绑定P99(秒) | 0.162 | 0.777 | +79.1% |
|  | Pending堆积 | 1283.48 | 2291.89 | +44.0% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s3/w5（inst3） | 吞吐(pods/s) | 254.94 | 534.37 | -52.3% |
|  | 峰值吞吐 | 809.69 | 1020.68 | -20.7% |
|  | P90(秒) | 1.81 | 0.432 | -318.6% |
|  | P99(秒) | 2.79 | 1.18 | -135.3% |
|  | E2E P99(秒) | 34.22 | 7.03 | -386.9% |
|  | 绑定P99(秒) | 0.081 | 0.158 | +48.8% |
|  | Pending堆积 | 273.33 | 59.71 | -357.7% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s3/w7（inst3） | 吞吐(pods/s) | 0.000 | 368.19 | -100.0% |
|  | 峰值吞吐 | 205.33 | 520.09 | -60.5% |
|  | P90(秒) | 0.016 | 0.367 | +95.7% |
|  | P99(秒) | 0.041 | 1.17 | +96.5% |
|  | E2E P99(秒) | 32.60 | 1.76 | -1754.6% |
|  | 绑定P99(秒) | 0.026 | 0.062 | +57.9% |
|  | Pending堆积 | 0.000 | 42.00 | +100.0% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s4/w3（inst3） | 吞吐(pods/s) | 445.69 | 392.07 | +13.7% |
|  | 峰值吞吐 | 952.27 | 938.05 | +1.5% |
|  | P90(秒) | 0.059 | 4.97 | +98.8% |
|  | P99(秒) | 0.209 | 7.29 | +97.1% |
|  | E2E P99(秒) | 0.672 | 7.46 | +91.0% |
|  | 绑定P99(秒) | 0.062 | 0.095 | +34.7% |
|  | Pending堆积 | 5.13 | 605.18 | +99.2% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s4/w4（inst3） | 吞吐(pods/s) | 365.15 | 402.86 | -9.4% |
|  | 峰值吞吐 | 1453.53 | 1417.38 | +2.6% |
|  | P90(秒) | 24.14 | 29.91 | +19.3% |
|  | P99(秒) | 30.05 | 34.53 | +13.0% |
|  | E2E P99(秒) | 53.71 | 42.22 | -27.2% |
|  | 绑定P99(秒) | 0.128 | 0.350 | +63.4% |
|  | Pending堆积 | 6012.17 | 6490.92 | +7.4% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s4/w5（inst3） | 吞吐(pods/s) | 581.12 | 505.94 | +14.9% |
|  | 峰值吞吐 | 902.44 | 965.49 | -6.5% |
|  | P90(秒) | 1.33 | 1.40 | +5.4% |
|  | P99(秒) | 2.62 | 2.44 | -7.2% |
|  | E2E P99(秒) | 3.12 | 5.15 | +39.4% |
|  | 绑定P99(秒) | 0.075 | 0.095 | +20.9% |
|  | Pending堆积 | 383.17 | 241.00 | -59.0% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |
| s4/w7（inst3） | 吞吐(pods/s) | 1215.47 | 406.23 | +199.2% |
|  | 峰值吞吐 | 1520.91 | 519.10 | +193.0% |
|  | P90(秒) | 1.28 | 0.449 | -185.9% |
|  | P99(秒) | 3.85 | 1.93 | -99.6% |
|  | E2E P99(秒) | 3.72 | 2.47 | -50.8% |
|  | 绑定P99(秒) | 0.045 | 0.062 | +27.1% |
|  | Pending堆积 | 60.83 | 15.00 | -305.6% |
|  | 成功率 | 1.00 | 1.00 | +0.0% |

> 说明：相对变化一列中，吞吐类指标为正值表示 ENO 更优，延迟与堆积类指标为正值表示 ENO 更低（已统一为"正值即更优"）。标"—"的场景表示该指标未采集到有效数据。

## 附录 B  核心代码片段

以下代码摘自本文实现（仓库 `pkg/binder/`），仅保留与第 4、5 章论述直接相关的部分。

**B.1 绑定器抽象接口（`pkg/binder/binder_interface.go`）**

```go
type BinderInterface interface {
	// BindUnit performs conflict checking and binds all Pods in the given BindRequest
	// to their target node. It returns a BindResult indicating which Pods succeeded
	// and which failed.
	//
	// The caller (typically the Scheduler's unit_scheduler) invokes this after a
	// successful scheduling decision. In embedded mode, this replaces the PatchPod
	// path that was previously used to communicate with the standalone Binder.
	BindUnit(ctx context.Context, req *BindRequest) (*BindResult, error)

	// Start initialises and starts the Binder's internal workers. It must be called
	// before BindUnit. Calling Start on an already-running Binder returns an error.
	Start(ctx context.Context) error

	// Stop gracefully shuts down the Binder, draining in-flight bind operations.
	Stop()
}
```

**B.2 节点归属校验（`pkg/binder/node_validator.go`，对应第 4 章 Layer 0）**

```go
func (v *NodeValidator) Validate(nodeName string) error {
	if v.nodeGetter == nil {
		return fmt.Errorf("nodeGetter is nil in NodeValidator")
	}

	node, err := v.nodeGetter(nodeName)
	if err != nil {
		return fmt.Errorf("failed to get node %q: %w", nodeName, err)
	}

	if node == nil {
		return fmt.Errorf("node %q not found (nil)", nodeName)
	}

	owner := ""
	if node.Annotations != nil {
		owner = node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	}

	// When the annotation is absent the node has not been partitioned yet
	// (e.g., single-scheduler deployment, or Dispatcher has not assigned it).
	// In that case we allow the bind to proceed — only reject when the
	// annotation is present AND belongs to a different scheduler.
	if owner == "" {
		return nil
	}

	if owner != v.schedulerName {
		return &NodeOwnershipError{
			Node:     nodeName,
			Expected: v.schedulerName,
			Actual:   owner,
		}
	}

	return nil
}
```

**B.3 同步重试参数（`pkg/binder/embedded_binder_config.go`，对应第 4 章 Layer 1）**

```go
DefaultMaxBindRetries = 3
```

重试退避采用 client-go 的 `ItemExponentialFailureRateLimiter`，初始间隔 5 ms、上限 10 s。

## 附录 C  Prometheus recording rules 示例

实验观测栈为每组调度器定义了统一的 recording rules，将各调度器原始指标归一化为 `{group}:{metric}:{aggregation}` 形式。以组 a（ENO）为例：

```yaml
          - record: eno:binder_embedded_bind_pods:rate1m
            expr: sum(rate(binder_embedded_bind_pods_total[1m]))
          - record: eno:binder_embedded_bind_units:rate1m
            expr: sum(rate(binder_embedded_bind_total[1m]))
          - record: eno:binder_embedded_bind_duration:p50
            expr: histogram_quantile(0.50, sum by (le) (rate(binder_embedded_bind_duration_seconds_bucket[1m])))
          - record: eno:binder_embedded_bind_duration:p90
            expr: histogram_quantile(0.90, sum by (le) (rate(binder_embedded_bind_duration_seconds_bucket[1m])))
          - record: eno:binder_embedded_bind_duration:p99
            expr: histogram_quantile(0.99, sum by (le) (rate(binder_embedded_bind_duration_seconds_bucket[1m])))
          - record: eno:binder_embedded_bind_duration:avg
              sum(rate(binder_embedded_bind_duration_seconds_sum[1m]))
              sum(rate(binder_embedded_bind_duration_seconds_count[1m]))
          - record: eno:binder_embedded_bind_pod_duration:p50
```

其中吞吐类规则使用 `rate(...[1m])` 计算每秒速率，延迟类规则使用 `histogram_quantile(...)` 计算分位数，从而保证跨组对比时指标口径一致。
