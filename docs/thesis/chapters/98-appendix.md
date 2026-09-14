# 附录

## 附录 A  完整实验数据表

本附录汇总 `test/e2e/benchmark/results/compare/` 下 16 个对比场景的关键指标。场景命名规则为 `{规模}_{负载}[_inst3]`：不带 `_inst3` 后缀的场景包含全部五组调度器，带后缀的场景仅含 ENO 与 Gödel 两组（均为 3 实例）。所有数值由同组 3 次重复实验按时间点取中位数聚合后，在剔除头尾各 30 秒的稳态窗口内求均值得到；标—表示该场景未采集到有效数据。

: 表 A-1  各对比场景关键指标汇总

| 场景 | 指标 | a(ENO) | b(Gödel) | c(kube-scheduler) | d(Volcano) | e(Koordinator) |
|---|---|---|---|---|---|---|
| s1_w1 | 稳态吞吐(pods/s) | 86.24 | — | — | — | — |
| s1_w1 | 峰值吞吐(pods/s) | — | — | — | 50.27 | 19.28 |
| s1_w1 | P90 调度延迟(s) | — | 0.015 | — | 0.330 | 16.38 |
| s1_w1 | P99 调度延迟(s) | — | 0.020 | — | 0.402 | 16.38 |
| s1_w1 | Pod E2E P99(s) | 0.031 | — | — | — | — |
| s1_w1 | 绑定延迟 P99(s) | 0.016 | — | — | — | — |
| s1_w1 | Pending 堆积(pods) | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| s1_w1 | 绑定成功率 | 1.00 | — | — | — | — |
| s2_w2 | 稳态吞吐(pods/s) | 499.07 | 499.73 | — | — | — |
| s2_w2 | 峰值吞吐(pods/s) | 500.00 | 474.38 | 797.62 | 51.32 | 24.78 |
| s2_w2 | P90 调度延迟(s) | 0.040 | 0.035 | 0.017 | 2.28 | 16.38 |
| s2_w2 | P99 调度延迟(s) | 0.161 | 0.107 | 0.112 | 2.53 | 16.38 |
| s2_w2 | Pod E2E P99(s) | 0.235 | 0.209 | — | — | — |
| s2_w2 | 绑定延迟 P99(s) | 0.049 | 0.050 | — | — | — |
| s2_w2 | Pending 堆积(pods) | 3.60 | 0.000 | 8767.62 | 0.000 | 2872.77 |
| s2_w2 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s2_w3 | 稳态吞吐(pods/s) | 455.86 | 342.00 | — | — | — |
| s2_w3 | 峰值吞吐(pods/s) | 977.29 | 865.96 | 998.82 | 74.93 | 17.77 |
| s2_w3 | P90 调度延迟(s) | 3.51 | 18.17 | 0.018 | 3.89 | 4.45 |
| s2_w3 | P99 调度延迟(s) | 4.59 | 22.65 | 0.117 | 4.01 | 4.81 |
| s2_w3 | Pod E2E P99(s) | 4.60 | 20.81 | — | — | — |
| s2_w3 | 绑定延迟 P99(s) | 0.112 | 0.092 | — | — | — |
| s2_w3 | Pending 堆积(pods) | 768.62 | 3126.47 | 15748.61 | 0.000 | 53360.52 |
| s2_w3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w2 | 稳态吞吐(pods/s) | 500.05 | 488.21 | — | — | — |
| s3_w2 | 峰值吞吐(pods/s) | 386.62 | 362.98 | 745.84 | 133.29 | 24.72 |
| s3_w2 | P90 调度延迟(s) | 0.060 | 0.631 | 0.016 | 3.15 | 16.38 |
| s3_w2 | P99 调度延迟(s) | 0.185 | 0.956 | 0.093 | 3.38 | 16.38 |
| s3_w2 | Pod E2E P99(s) | 0.304 | 0.528 | — | — | — |
| s3_w2 | 绑定延迟 P99(s) | 0.037 | 0.066 | — | — | — |
| s3_w2 | Pending 堆积(pods) | 0.500 | 0.167 | 9862.62 | 0.000 | 2988.38 |
| s3_w2 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w3 | 稳态吞吐(pods/s) | 333.40 | 319.33 | — | — | — |
| s3_w3 | 峰值吞吐(pods/s) | 779.04 | 675.70 | 857.69 | 221.20 | 27.11 |
| s3_w3 | P90 调度延迟(s) | 14.55 | 25.85 | 0.016 | 4.49 | 16.28 |
| s3_w3 | P99 调度延迟(s) | 19.73 | 30.16 | 0.094 | 4.58 | 16.32 |
| s3_w3 | Pod E2E P99(s) | 19.75 | 27.82 | — | — | — |
| s3_w3 | 绑定延迟 P99(s) | 0.075 | 0.071 | — | — | — |
| s3_w3 | Pending 堆积(pods) | 2880.61 | 5383.58 | 20245.06 | 0.000 | 32404.39 |
| s3_w3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w3_inst3 | 稳态吞吐(pods/s) | 427.57 | 299.81 | — | — | — |
| s3_w3_inst3 | 峰值吞吐(pods/s) | 889.02 | 887.82 | 857.69 | 221.20 | 27.11 |
| s3_w3_inst3 | P90 调度延迟(s) | 0.035 | 0.045 | 0.016 | 4.49 | 16.28 |
| s3_w3_inst3 | P99 调度延迟(s) | 0.127 | 0.149 | 0.094 | 4.58 | 16.32 |
| s3_w3_inst3 | Pod E2E P99(s) | 0.496 | 1.09 | — | — | — |
| s3_w3_inst3 | 绑定延迟 P99(s) | 0.070 | 0.089 | — | — | — |
| s3_w3_inst3 | Pending 堆积(pods) | 2.07 | 1.37 | 20245.06 | 0.000 | 32404.39 |
| s3_w3_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w4_inst3 | 稳态吞吐(pods/s) | 345.26 | 292.26 | — | — | — |
| s3_w4_inst3 | 峰值吞吐(pods/s) | 1873.83 | 1641.79 | — | — | — |
| s3_w4_inst3 | P90 调度延迟(s) | 7.89 | 11.62 | — | — | — |
| s3_w4_inst3 | P99 调度延迟(s) | 9.88 | 15.88 | — | — | — |
| s3_w4_inst3 | Pod E2E P99(s) | 11.90 | 22.17 | — | — | — |
| s3_w4_inst3 | 绑定延迟 P99(s) | 0.162 | 0.777 | — | — | — |
| s3_w4_inst3 | Pending 堆积(pods) | 1283.48 | 2291.89 | — | — | — |
| s3_w4_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w5_inst3 | 稳态吞吐(pods/s) | 777.41 | 372.75 | — | — | — |
| s3_w5_inst3 | 峰值吞吐(pods/s) | 631.65 | 676.35 | — | — | — |
| s3_w5_inst3 | P90 调度延迟(s) | 0.323 | 0.420 | — | — | — |
| s3_w5_inst3 | P99 调度延迟(s) | 0.751 | 0.916 | — | — | — |
| s3_w5_inst3 | Pod E2E P99(s) | 0.891 | 2.01 | — | — | — |
| s3_w5_inst3 | 绑定延迟 P99(s) | 0.112 | 0.226 | — | — | — |
| s3_w5_inst3 | Pending 堆积(pods) | 45.00 | 67.88 | — | — | — |
| s3_w5_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s3_w6 | 稳态吞吐(pods/s) | — | — | — | — | — |
| s3_w6 | 峰值吞吐(pods/s) | — | — | — | 50.93 | — |
| s3_w6 | P90 调度延迟(s) | — | — | — | 0.549 | — |
| s3_w6 | P99 调度延迟(s) | — | — | — | 0.635 | — |
| s3_w6 | Pod E2E P99(s) | — | — | — | — | — |
| s3_w6 | 绑定延迟 P99(s) | — | — | — | — | — |
| s3_w6 | Pending 堆积(pods) | — | — | — | 0.000 | — |
| s3_w6 | 绑定成功率 | — | — | — | — | — |
| s3_w6_inst3 | 稳态吞吐(pods/s) | — | — | — | — | — |
| s3_w6_inst3 | 峰值吞吐(pods/s) | — | — | — | 50.93 | — |
| s3_w6_inst3 | P90 调度延迟(s) | — | — | — | 0.549 | — |
| s3_w6_inst3 | P99 调度延迟(s) | — | — | — | 0.635 | — |
| s3_w6_inst3 | Pod E2E P99(s) | — | — | — | — | — |
| s3_w6_inst3 | 绑定延迟 P99(s) | — | — | — | — | — |
| s3_w6_inst3 | Pending 堆积(pods) | — | — | — | 0.000 | — |
| s3_w6_inst3 | 绑定成功率 | — | — | — | — | — |
| s3_w7_inst3 | 稳态吞吐(pods/s) | 532.94 | 445.01 | — | — | — |
| s3_w7_inst3 | 峰值吞吐(pods/s) | 542.11 | 396.27 | — | — | — |
| s3_w7_inst3 | P90 调度延迟(s) | 0.016 | 0.021 | — | — | — |
| s3_w7_inst3 | P99 调度延迟(s) | 0.053 | 0.063 | — | — | — |
| s3_w7_inst3 | Pod E2E P99(s) | 0.109 | 0.351 | — | — | — |
| s3_w7_inst3 | 绑定延迟 P99(s) | 0.042 | 0.056 | — | — | — |
| s3_w7_inst3 | Pending 堆积(pods) | 0.000 | 0.375 | — | — | — |
| s3_w7_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w3_inst3 | 稳态吞吐(pods/s) | 321.62 | 302.16 | — | — | — |
| s4_w3_inst3 | 峰值吞吐(pods/s) | 988.91 | 883.81 | — | — | — |
| s4_w3_inst3 | P90 调度延迟(s) | 0.037 | 0.080 | — | — | — |
| s4_w3_inst3 | P99 调度延迟(s) | 0.219 | 0.289 | — | — | — |
| s4_w3_inst3 | Pod E2E P99(s) | 0.583 | 0.920 | — | — | — |
| s4_w3_inst3 | 绑定延迟 P99(s) | 0.054 | 0.106 | — | — | — |
| s4_w3_inst3 | Pending 堆积(pods) | 1.71 | 9.16 | — | — | — |
| s4_w3_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w4_inst3 | 稳态吞吐(pods/s) | 325.80 | 265.49 | — | — | — |
| s4_w4_inst3 | 峰值吞吐(pods/s) | 1502.78 | 1413.51 | — | — | — |
| s4_w4_inst3 | P90 调度延迟(s) | 24.28 | 35.02 | — | — | — |
| s4_w4_inst3 | P99 调度延迟(s) | 26.76 | 42.90 | — | — | — |
| s4_w4_inst3 | Pod E2E P99(s) | 28.43 | 46.59 | — | — | — |
| s4_w4_inst3 | 绑定延迟 P99(s) | 0.109 | 0.324 | — | — | — |
| s4_w4_inst3 | Pending 堆积(pods) | 4210.73 | 5133.61 | — | — | — |
| s4_w4_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w5_inst3 | 稳态吞吐(pods/s) | 582.84 | 416.31 | — | — | — |
| s4_w5_inst3 | 峰值吞吐(pods/s) | 936.74 | 649.90 | — | — | — |
| s4_w5_inst3 | P90 调度延迟(s) | 2.42 | 2.44 | — | — | — |
| s4_w5_inst3 | P99 调度延迟(s) | 3.93 | 3.93 | — | — | — |
| s4_w5_inst3 | Pod E2E P99(s) | 3.96 | 3.99 | — | — | — |
| s4_w5_inst3 | 绑定延迟 P99(s) | 0.104 | 0.177 | — | — | — |
| s4_w5_inst3 | Pending 堆积(pods) | 392.50 | 335.38 | — | — | — |
| s4_w5_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |
| s4_w6_inst3 | 稳态吞吐(pods/s) | — | — | — | — | — |
| s4_w6_inst3 | 峰值吞吐(pods/s) | — | — | — | — | — |
| s4_w6_inst3 | P90 调度延迟(s) | — | — | — | — | — |
| s4_w6_inst3 | P99 调度延迟(s) | — | — | — | — | — |
| s4_w6_inst3 | Pod E2E P99(s) | — | — | — | — | — |
| s4_w6_inst3 | 绑定延迟 P99(s) | — | — | — | — | — |
| s4_w6_inst3 | Pending 堆积(pods) | — | — | — | — | — |
| s4_w6_inst3 | 绑定成功率 | — | — | — | — | — |
| s4_w7_inst3 | 稳态吞吐(pods/s) | 452.56 | 453.76 | — | — | — |
| s4_w7_inst3 | 峰值吞吐(pods/s) | 574.08 | 397.41 | — | — | — |
| s4_w7_inst3 | P90 调度延迟(s) | 1.30 | 0.020 | — | — | — |
| s4_w7_inst3 | P99 调度延迟(s) | 2.02 | 0.064 | — | — | — |
| s4_w7_inst3 | Pod E2E P99(s) | 4.09 | 0.320 | — | — | — |
| s4_w7_inst3 | 绑定延迟 P99(s) | 0.041 | 0.053 | — | — | — |
| s4_w7_inst3 | Pending 堆积(pods) | 0.167 | 0.125 | — | — | — |
| s4_w7_inst3 | 绑定成功率 | 1.00 | 1.00 | — | — | — |

> 说明：c（kube-scheduler）、d（Volcano）、e（Koordinator）为单实例架构，其延迟分位在过载场景下存在采样偏差（见 §6.3.1），表中仅列出数值供参考，正文未据此做跨调度器延迟的等价性比较。

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
