# Final Chart Index

[T-1]
标题: 吞吐量时间曲线（W3, A/B/C/D/E）
指标总结: 该图按全采样点连线并叠加 rolling mean(5) 展示；按非零区间均值统计，ENO 吞吐量相对 Godel 提升约 26.7%（W3, s3, run1）。同时，C 在单点吞吐量（瞬时峰值）上最高。 数据缺失: D (Volcano)。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_throughput.json
图片: test/e2e/benchmark/results/final-charts/01_T-1_throughput_timeseries.png
图片(PDF): test/e2e/benchmark/results/final-charts/01_T-1_throughput_timeseries.pdf

[T-3]
标题: 负载-吞吐量对比（W1-W3, A/B/C/D/E）
指标总结: 在 W1-W3 的非零区间平均吞吐量口径下，ENO 相对 Godel 提升约 14.0%。 数据缺失: D (Volcano) W2, W3。
数据源:
- test/e2e/benchmark/results/a/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/d/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_throughput.json
图片: test/e2e/benchmark/results/final-charts/02_T-3_workload_throughput.png
图片(PDF): test/e2e/benchmark/results/final-charts/02_T-3_workload_throughput.pdf

[L-1]
标题: E2E P99 延迟时间序列（W3, A/B/C/D/E）
指标总结: ENO 的 P99 延迟相对 Godel 下降约 23.2%（W3, s3, run1）。 数据缺失: D (Volcano)。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_latency_p99.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_latency_p99.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_latency_p99.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_latency_p99.json
图片: test/e2e/benchmark/results/final-charts/03_L-1_p99_latency_timeseries.png
图片(PDF): test/e2e/benchmark/results/final-charts/03_L-1_p99_latency_timeseries.pdf

[L-2]
标题: 绑定延迟分位对比（P50/P90/P99, A/B）
指标总结: ENO 在绑定延迟分位（P50/P90/P99）上平均较 Godel 降低约 23.3%。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/bind_latency_p50.json
- test/e2e/benchmark/results/b/s3/w3/run1/bind_latency_p50.json
- test/e2e/benchmark/results/a/s3/w3/run1/bind_latency_p90.json
- test/e2e/benchmark/results/b/s3/w3/run1/bind_latency_p90.json
- test/e2e/benchmark/results/a/s3/w3/run1/bind_latency_p99.json
- test/e2e/benchmark/results/b/s3/w3/run1/bind_latency_p99.json
图片: test/e2e/benchmark/results/final-charts/04_L-2_bind_latency_quantiles.png
图片(PDF): test/e2e/benchmark/results/final-charts/04_L-2_bind_latency_quantiles.pdf

[S-2]
标题: 成功率/失败率对比（W1-W4, A/B/C/D/E）
指标总结: 在 W1-W4 上，ENO 平均成功率（去前导0）(100.00%) 高于 Godel (100.00%)，且失败率去前导0后无有效样本。 数据缺失: D (Volcano) W1, W2, W3, W4。
数据源:
- test/e2e/benchmark/results/a/s3/w1/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/a/s3/w1/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/a/s3/w2/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/a/s3/w2/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/a/s3/w4/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/a/s3/w4/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/b/s3/w1/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/b/s3/w1/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/b/s3/w2/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/b/s3/w2/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/b/s3/w4/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/b/s3/w4/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/c/s3/w1/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/c/s3/w1/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/c/s3/w2/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/c/s3/w2/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/c/s3/w4/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/c/s3/w4/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/d/s3/w1/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/d/s3/w1/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/e/s3/w1/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/e/s3/w1/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/e/s3/w2/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/e/s3/w2/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_success_rate.json
- test/e2e/benchmark/results/e/s3/w4/run1/scheduling_error_rate.json
- test/e2e/benchmark/results/e/s3/w4/run1/scheduling_success_rate.json
图片: test/e2e/benchmark/results/final-charts/05_S-2_success_error_by_workload.png
图片(PDF): test/e2e/benchmark/results/final-charts/05_S-2_success_error_by_workload.pdf

[S-3]
标题: Pending Pod 堆积曲线（W4, A/B/C/D/E）
指标总结: ENO 的 Pending 峰值相对 Godel 下降约 7.4%，队列堆积更轻。
数据源:
- test/e2e/benchmark/results/a/s3/w4/run1/pending_pods.json
- test/e2e/benchmark/results/b/s3/w4/run1/pending_pods.json
- test/e2e/benchmark/results/c/s3/w4/run1/pending_pods.json
- test/e2e/benchmark/results/e/s3/w4/run1/pending_pods.json
图片: test/e2e/benchmark/results/final-charts/06_S-3_pending_pods_timeseries.png
图片(PDF): test/e2e/benchmark/results/final-charts/06_S-3_pending_pods_timeseries.pdf

[W6]
标题: Gang 场景完成时间对比（A/B/D/E）
指标总结: ENO 在 W6 的完成时间相对 Godel 缩短约 24.2%。
数据源:
- test/e2e/benchmark/results/a/s3/w6/run1/metadata.txt
- test/e2e/benchmark/results/b/s3/w6/run1/metadata.txt
- test/e2e/benchmark/results/d/s3/w6/run1/metadata.txt
- test/e2e/benchmark/results/e/s3/w6/run1/metadata.txt
图片: test/e2e/benchmark/results/final-charts/07_W6_gang_completion_time.png
图片(PDF): test/e2e/benchmark/results/final-charts/07_W6_gang_completion_time.pdf

[T-4]
标题: 实例数3吞吐量扩展图（A/B, inst3, s3/s4/s5, w3）
指标总结: 该图按全采样点连线并叠加 rolling mean(5) 展示（不做点位平均）；在 W3 聚合口径下，ENO 采样均值相对 Godel 提升约 19.3%。
数据源:
- test/e2e/benchmark/results/a/s3/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s4/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s5/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s4/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s5/w3/inst3/run1/scheduling_throughput.json
图片: test/e2e/benchmark/results/final-charts/08_T-4_inst3_scaling_throughput.png
图片(PDF): test/e2e/benchmark/results/final-charts/08_T-4_inst3_scaling_throughput.pdf

[U-1]
标题: 节点 CPU 利用率箱线图（A/B/C/D/E）
指标总结: ENO 在节点 CPU 利用率分布上相对 Godel 更集中，表现出更好的均衡性。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/utilization.csv
- test/e2e/benchmark/results/b/s3/w3/run1/utilization.csv
- test/e2e/benchmark/results/c/s3/w3/run1/utilization.csv
- test/e2e/benchmark/results/e/s3/w3/run1/utilization.csv
图片: test/e2e/benchmark/results/final-charts/09_U-1_cpu_utilization_boxplot.png
图片(PDF): test/e2e/benchmark/results/final-charts/09_U-1_cpu_utilization_boxplot.pdf

