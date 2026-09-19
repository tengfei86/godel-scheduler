# 附录

## 附录 A  完整实验数据表

本附录汇总 `test/e2e/benchmark/results/compare/` 下 16 个对比场景的关键指标。场景命名规则为 `{规模}_{负载}[_inst3]`：不带 `_inst3` 后缀的场景包含全部五组调度器（ENO 与 Gödel 为 1 实例，c/d/e 为单实例架构），带后缀的场景仅含 ENO 与 Gödel 两组（均为 3 实例）。

取值口径：有效吞吐 = 名义工作量 / 该次 run 的完成时间（取 3 次重复的中位数）；时序类指标先按时间点对 3 条 run 取中位数，再按 6.3 节的规则取标量——延迟分位与峰值吞吐剔除首尾各 2 个采样点后取中位数，队列堆积取处理过程中的最大值；标—表示该场景未采集到有效数据。

: 表 A-1  各对比场景关键指标汇总

| 场景 | 指标 | a(ENO) | b(Gödel) | c(kube-scheduler) | d(Volcano) | e(Koordinator) |
|---|---|---|---|---|---|---|
| s1_w1 | 有效吞吐(pods/s) | 90.09 | 90.09 | 97.09 | 48.54 | 24.33 |
| s1_w1 | 峰值吞吐(pods/s) | — | — | — | 50.64 | 14.93 |
| s1_w1 | P90 调度延迟(s) | — | 0.015 | — | 0.323 | 16.38 |
| s1_w1 | P99 调度延迟(s) | — | 0.020 | — | 0.338 | 16.38 |
| s1_w1 | Pod E2E P99(s) | 0.031 | — | — | — | — |
| s1_w1 | 队列堆积峰值(pods) | 0.000 | 0.000 | 350 | 0.000 | 0.000 |
| s1_w1 | 绑定成功率 | 1.00 | — | — | — | — |
| s2_w2 | 有效吞吐(pods/s) | 329 | 325 | 270 | 48.64 | 24.03 |
| s2_w2 | 峰值吞吐(pods/s) | 500 | 499 | 798 | 51.56 | 10.18 |
| s2_w2 | P90 调度延迟(s) | 0.034 | 0.029 | 0.017 | 1.97 | 16.38 |
| s2_w2 | P99 调度延迟(s) | 0.149 | 0.112 | 0.112 | 2.03 | 16.38 |
| s2_w2 | Pod E2E P99(s) | 0.238 | 0.240 | — | — | — |
| s2_w2 | 队列堆积峰值(pods) | 1.00 | 2.00 | 22875 | 0.000 | 36138 |
| s2_w2 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s2_w3 | 有效吞吐(pods/s) | 352 | 287 | 297 | 48.05 | 16.37 |
| s2_w3 | 峰值吞吐(pods/s) | 982 | 866 | 1014 | 76.16 | 14.69 |
| s2_w3 | P90 调度延迟(s) | 3.18 | 15.47 | 0.017 | 4.82 | 0.341 |
| s2_w3 | P99 调度延迟(s) | 4.00 | 23.48 | 0.118 | 4.98 | 0.881 |
| s2_w3 | Pod E2E P99(s) | 4.02 | 16.26 | — | — | — |
| s2_w3 | 队列堆积峰值(pods) | 4218 | 15387 | 43317 | 0.000 | 93989 |
| s2_w3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w2 | 有效吞吐(pods/s) | 329 | 273 | 270 | 48.36 | 24.47 |
| s3_w2 | 峰值吞吐(pods/s) | 457 | 432 | 746 | 133 | 11.62 |
| s3_w2 | P90 调度延迟(s) | 0.057 | 0.087 | 0.016 | 3.08 | 16.38 |
| s3_w2 | P99 调度延迟(s) | 0.204 | 0.217 | 0.094 | 3.18 | 16.38 |
| s3_w2 | Pod E2E P99(s) | 0.255 | 0.396 | — | — | — |
| s3_w2 | 队列堆积峰值(pods) | 3.00 | 1.00 | 20956 | 0.000 | 33093 |
| s3_w2 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w3 | 有效吞吐(pods/s) | 298 | 283 | 292 | 47.80 | 23.96 |
| s3_w3 | 峰值吞吐(pods/s) | 858 | 753 | 864 | 221 | 27.42 |
| s3_w3 | P90 调度延迟(s) | 14.70 | 30.78 | 0.016 | 5.00 | 16.38 |
| s3_w3 | P99 调度延迟(s) | 16.22 | 32.57 | 0.094 | 5.00 | 16.38 |
| s3_w3 | Pod E2E P99(s) | 16.22 | 32.50 | — | — | — |
| s3_w3 | 队列堆积峰值(pods) | 14698 | 22652 | 55827 | 0.000 | 92742 |
| s3_w3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w3_inst3 | 有效吞吐(pods/s) | 350 | 287 | 292 | 47.80 | 23.96 |
| s3_w3_inst3 | 峰值吞吐(pods/s) | 1023 | 1000 | 864 | 221 | 27.42 |
| s3_w3_inst3 | P90 调度延迟(s) | 0.030 | 0.046 | 0.016 | 5.00 | 16.38 |
| s3_w3_inst3 | P99 调度延迟(s) | 0.127 | 0.150 | 0.094 | 5.00 | 16.38 |
| s3_w3_inst3 | Pod E2E P99(s) | 0.450 | 0.935 | — | — | — |
| s3_w3_inst3 | 队列堆积峰值(pods) | 20.00 | 16.00 | 55827 | 0.000 | 92742 |
| s3_w3_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w4_inst3 | 有效吞吐(pods/s) | 345 | 315 | — | — | — |
| s3_w4_inst3 | 峰值吞吐(pods/s) | 1875 | 1724 | — | — | — |
| s3_w4_inst3 | P90 调度延迟(s) | 7.13 | 13.43 | — | — | — |
| s3_w4_inst3 | P99 调度延迟(s) | 8.10 | 16.09 | — | — | — |
| s3_w4_inst3 | Pod E2E P99(s) | 14.81 | 22.88 | — | — | — |
| s3_w4_inst3 | 队列堆积峰值(pods) | 12167 | 24885 | — | — | — |
| s3_w4_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w5_inst3 | 有效吞吐(pods/s) | 333 | 275 | — | — | — |
| s3_w5_inst3 | 峰值吞吐(pods/s) | 805 | 899 | — | — | — |
| s3_w5_inst3 | P90 调度延迟(s) | 0.323 | 0.420 | — | — | — |
| s3_w5_inst3 | P99 调度延迟(s) | 0.751 | 0.916 | — | — | — |
| s3_w5_inst3 | Pod E2E P99(s) | 0.932 | 2.01 | — | — | — |
| s3_w5_inst3 | 队列堆积峰值(pods) | 258 | 542 | — | — | — |
| s3_w5_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w6 | 有效吞吐(pods/s) | 251 | 211 | — | 48 | — |
| s3_w6 | 峰值吞吐(pods/s) | 510 | 503 | — | 58 | — |
| s3_w6 | P90 调度延迟(s) | 0.128 | 0.054 | — | 3.078 | — |
| s3_w6 | P99 调度延迟(s) | 0.428 | 0.175 | — | 3.182 | — |
| s3_w6 | Pod E2E P99(s) | 0.662 | 0.546 | — | — | — |
| s3_w6 | 队列堆积峰值(pods) | 7.00 | 4.00 | — | 0.000 | — |
| s3_w6 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w6_inst3 | 有效吞吐(pods/s) | 216 | 207 | — | 48 | — |
| s3_w6_inst3 | 峰值吞吐(pods/s) | 449 | 458 | — | 58 | — |
| s3_w6_inst3 | P90 调度延迟(s) | 0.204 | 0.062 | — | 3.078 | — |
| s3_w6_inst3 | P99 调度延迟(s) | 0.892 | 0.218 | — | 3.182 | — |
| s3_w6_inst3 | Pod E2E P99(s) | 1.779 | 0.800 | — | — | — |
| s3_w6_inst3 | 队列堆积峰值(pods) | 32.00 | 4.00 | — | 0.000 | — |
| s3_w6_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w7_inst3 | 有效吞吐(pods/s) | 331 | 273 | — | — | — |
| s3_w7_inst3 | 峰值吞吐(pods/s) | 542 | 500 | — | — | — |
| s3_w7_inst3 | P90 调度延迟(s) | 0.015 | 0.022 | — | — | — |
| s3_w7_inst3 | P99 调度延迟(s) | 0.050 | 0.064 | — | — | — |
| s3_w7_inst3 | Pod E2E P99(s) | 0.109 | 0.343 | — | — | — |
| s3_w7_inst3 | 队列堆积峰值(pods) | 0.000 | 3.00 | — | — | — |
| s3_w7_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w3_inst3 | 有效吞吐(pods/s) | 297 | 281 | — | — | — |
| s4_w3_inst3 | 峰值吞吐(pods/s) | 1003 | 1006 | — | — | — |
| s4_w3_inst3 | P90 调度延迟(s) | 0.036 | 0.064 | — | — | — |
| s4_w3_inst3 | P99 调度延迟(s) | 0.189 | 0.285 | — | — | — |
| s4_w3_inst3 | Pod E2E P99(s) | 0.574 | 0.923 | — | — | — |
| s4_w3_inst3 | 队列堆积峰值(pods) | 9.00 | 61.00 | — | — | — |
| s4_w3_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w4_inst3 | 有效吞吐(pods/s) | 319 | 275 | — | — | — |
| s4_w4_inst3 | 峰值吞吐(pods/s) | 1560 | 1469 | — | — | — |
| s4_w4_inst3 | P90 调度延迟(s) | 26.39 | 30.68 | — | — | — |
| s4_w4_inst3 | P99 调度延迟(s) | 32.12 | 37.69 | — | — | — |
| s4_w4_inst3 | Pod E2E P99(s) | 32.52 | 48.27 | — | — | — |
| s4_w4_inst3 | 队列堆积峰值(pods) | 37554 | 48303 | — | — | — |
| s4_w4_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w5_inst3 | 有效吞吐(pods/s) | 281 | 273 | — | — | — |
| s4_w5_inst3 | 峰值吞吐(pods/s) | 937 | 881 | — | — | — |
| s4_w5_inst3 | P90 调度延迟(s) | 2.15 | 2.26 | — | — | — |
| s4_w5_inst3 | P99 调度延迟(s) | 3.90 | 3.91 | — | — | — |
| s4_w5_inst3 | Pod E2E P99(s) | 3.97 | 3.99 | — | — | — |
| s4_w5_inst3 | 队列堆积峰值(pods) | 2355 | 2667 | — | — | — |
| s4_w5_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w6_inst3 | 有效吞吐(pods/s) | 245 | 207 | — | — | — |
| s4_w6_inst3 | 峰值吞吐(pods/s) | 893 | 532 | — | — | — |
| s4_w6_inst3 | P90 调度延迟(s) | 0.179 | 0.069 | — | — | — |
| s4_w6_inst3 | P99 调度延迟(s) | 0.576 | 0.353 | — | — | — |
| s4_w6_inst3 | Pod E2E P99(s) | 1.018 | 0.910 | — | — | — |
| s4_w6_inst3 | 队列堆积峰值(pods) | 118.50 | 5.00 | — | — | — |
| s4_w6_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w7_inst3 | 有效吞吐(pods/s) | 272 | 272 | — | — | — |
| s4_w7_inst3 | 峰值吞吐(pods/s) | 574 | 500 | — | — | — |
| s4_w7_inst3 | P90 调度延迟(s) | 0.016 | 0.020 | — | — | — |
| s4_w7_inst3 | P99 调度延迟(s) | 0.060 | 0.063 | — | — | — |
| s4_w7_inst3 | Pod E2E P99(s) | 0.141 | 0.300 | — | — | — |
| s4_w7_inst3 | 队列堆积峰值(pods) | 2639 | 1.00 | — | — | — |
| s4_w7_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |

> 说明：c（kube-scheduler）、d（Volcano）、e（Koordinator）为单实例架构，其延迟分位在过载场景下存在采样偏差（见 6.3.1 节），表中数值仅供参考，正文未据此做跨调度器延迟的等价性比较。

## 附录 B  核心代码片段

以下代码摘自本文实现（仓库 `pkg/binder/`），仅保留与第 4、5 章论述直接相关的部分。

**B.1 绑定器抽象接口（`pkg/binder/binder_interface.go`）**

```go
type BinderInterface interface {
	BindUnit(ctx context.Context, req *BindRequest) (*BindResult, error)
	Start(ctx context.Context) error
	Stop()
}
```

**B.2 节点归属校验（`pkg/binder/node_validator.go`，对应第 4 章 Layer 0）**

```go
func (v *NodeValidator) Validate(nodeName string) error {
	node, err := v.nodeGetter(nodeName)
	if err != nil {
		return fmt.Errorf("failed to get node %q: %w", nodeName, err)
	}
	owner := ""
	if node.Annotations != nil {
		owner = node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	}
	// 注解为空：节点尚未分区（单调度器场景），允许 Bind
	if owner == "" {
		return nil
	}
	// 注解非空且不属于本实例：归属漂移，返回结构化错误
	if owner != v.schedulerName {
		return &NodeOwnershipError{Node: nodeName, Expected: v.schedulerName, Actual: owner}
	}
	return nil
}
```

**B.3 同步重试参数（`pkg/binder/embedded_binder_config.go`，对应第 4 章 Layer 1）**

```go
DefaultMaxBindRetries = 3
```

重试退避基于 client-go 的 `ItemExponentialFailureRateLimiter`，初始间隔 5 ms、上限 10 s。

## 附录 C  Prometheus recording rules 示例

实验观测栈为每组调度器定义了统一的 recording rules，将各调度器原始指标归一化为 `{group}:{metric}:{aggregation}` 形式。以组 a（ENO）为例：

```yaml
- record: eno:binder_embedded_bind_pods:rate1m
  expr: sum(rate(binder_embedded_bind_pods_total[1m]))

- record: eno:binder_embedded_bind_duration:p99
  expr: histogram_quantile(0.99, sum by (le) (rate(binder_embedded_bind_duration_seconds_bucket[1m])))

- record: eno:binder_embedded_bind_duration:avg
  expr: >
    sum(rate(binder_embedded_bind_duration_seconds_sum[1m]))
    /
    sum(rate(binder_embedded_bind_duration_seconds_count[1m]))
```

其中吞吐类规则使用 `rate(...[1m])` 计算每秒速率，延迟类规则使用 `histogram_quantile(...)` 计算分位数，从而保证跨组对比时指标口径一致。
