# Final Chart Index

[T-1]
标题: 吞吐量时间曲线（W3, A/B/C/D/E）
指标总结: 该图按全采样点连线并叠加 rolling mean(5) 展示；按非零区间均值统计，Group B 吞吐量相对 Group A 提升约 26.7%（W3, s3, run1）。Group C 与 Group E 在该场景曲线整体低于 B 且更平稳；Group D 缺失该场景有效曲线（overloaded / data unavailable）。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_throughput.json
图片: test/e2e/benchmark/results/final-charts/01_T-1_throughput_timeseries.png
图片(PDF): test/e2e/benchmark/results/final-charts/01_T-1_throughput_timeseries.pdf

[T-3]
标题: 负载-吞吐量对比（W1-W4, A/B/C/D/E）
指标总结: 在 W1-W4 的非零区间平均吞吐量口径下，Group B 相对 Group A 提升约 11.0%。Group C 在中高负载下吞吐增长斜率偏缓，Group E 在 W1-W2 表现接近 C；Group D 仅 W1 可用，W2-W4 缺失（overloaded / data unavailable）。
数据源:
- test/e2e/benchmark/results/a/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s3/w4/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w4/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/c/s3/w4/run1/scheduling_throughput.json
- test/e2e/benchmark/results/d/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w1/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w2/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/e/s3/w4/run1/scheduling_throughput.json
图片: test/e2e/benchmark/results/final-charts/02_T-3_workload_throughput.png
图片(PDF): test/e2e/benchmark/results/final-charts/02_T-3_workload_throughput.pdf

[L-1]
标题: E2E P99 延迟时间序列（W3, A/B/C/D/E）
指标总结: Group B 的 P99 延迟相对 Group A 下降约 23.2%（W3, s3, run1）。Group C 与 Group E 的延迟曲线整体高于 B 但波动相对可控；Group D 在该场景缺失有效序列（overloaded / data unavailable）。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/scheduling_latency_p99.json
- test/e2e/benchmark/results/b/s3/w3/run1/scheduling_latency_p99.json
- test/e2e/benchmark/results/c/s3/w3/run1/scheduling_latency_p99.json
- test/e2e/benchmark/results/e/s3/w3/run1/scheduling_latency_p99.json
图片: test/e2e/benchmark/results/final-charts/03_L-1_p99_latency_timeseries.png
图片(PDF): test/e2e/benchmark/results/final-charts/03_L-1_p99_latency_timeseries.pdf

[L-2]
标题: 绑定延迟分位对比（P50/P90/P99, A/B）
指标总结: Group B 在绑定延迟分位（P50/P90/P99）上平均较 Group A 降低约 23.3%，说明 Embedded Binder 主要收益来自绑定路径优化；该图为 A/B 专项对比，不与 C/D/E 横向比较。
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
指标总结: 在 W1-W4 上，Group B 平均成功率（去前导0）为 100.00%，与 Group A 同为 100.00%；失败率在去前导0后基本无有效非零样本，说明 A/B/C/E 在有效调度窗口内均接近满成功。Group D 在该维度仅保留部分可用数据，W1-W4 存在显著缺失（overloaded / data unavailable）。
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
指标总结: Group B 的 Pending 峰值相对 Group A 下降约 7.4%，队列堆积更轻。Group C 与 Group E 在高压阶段的 Pending 回落速度慢于 B，反映 B 在突发压力下具备更快的排队消化能力；Group D 在该场景数据不完整。
数据源:
- test/e2e/benchmark/results/a/s3/w4/run1/pending_pods.json
- test/e2e/benchmark/results/b/s3/w4/run1/pending_pods.json
- test/e2e/benchmark/results/c/s3/w4/run1/pending_pods.json
- test/e2e/benchmark/results/e/s3/w4/run1/pending_pods.json
图片: test/e2e/benchmark/results/final-charts/06_S-3_pending_pods_timeseries.png
图片(PDF): test/e2e/benchmark/results/final-charts/06_S-3_pending_pods_timeseries.pdf

[W6]
标题: Gang 场景完成时间对比（A/B/D/E）
指标总结: Group B 在 W6 的完成时间相对 Group A 缩短约 24.2%，显示其在 Gang 场景下也有更快收敛速度。Group D 作为批调度方案在该场景具备可比性，Group E 数据完整但完成时间仍落后于 B。
数据源:
- test/e2e/benchmark/results/a/s3/w6/run1/metadata.txt
- test/e2e/benchmark/results/b/s3/w6/run1/metadata.txt
- test/e2e/benchmark/results/d/s3/w6/run1/metadata.txt
- test/e2e/benchmark/results/e/s3/w6/run1/metadata.txt
图片: test/e2e/benchmark/results/final-charts/07_W6_gang_completion_time.png
图片(PDF): test/e2e/benchmark/results/final-charts/07_W6_gang_completion_time.pdf

[T-4]
标题: 实例数3吞吐量扩展图（A/B, inst3, s3/s4/s5, w3/w4）
指标总结: 该图按全采样点连线并叠加 rolling mean(5) 展示（不做点位平均）；在 W3 聚合口径下，Group B 采样均值相对 Group A 提升约 19.3%，且在 s4/s5 阶段优势仍可保持，体现 inst3 下跨规模扩展弹性更好。
数据源:
- test/e2e/benchmark/results/a/s3/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s3/w4/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s4/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s4/w4/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s5/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/a/s5/w4/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s3/w4/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s4/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s4/w4/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s5/w3/inst3/run1/scheduling_throughput.json
- test/e2e/benchmark/results/b/s5/w4/inst3/run1/scheduling_throughput.json
图片: test/e2e/benchmark/results/final-charts/08_T-4_inst3_scaling_throughput.png
图片(PDF): test/e2e/benchmark/results/final-charts/08_T-4_inst3_scaling_throughput.pdf

[U-1]
标题: 节点 CPU 利用率箱线图（A/B/D/E）
指标总结: Group B 在节点 CPU 利用率分布上相对 Group A 更集中，表现出更好的均衡性。Group E 分布也较集中但中位利用率略低；Group D 在该场景可用样本较少，结论以趋势参考为主。
数据源:
- test/e2e/benchmark/results/a/s3/w3/run1/utilization.csv
- test/e2e/benchmark/results/b/s3/w3/run1/utilization.csv
- test/e2e/benchmark/results/e/s3/w3/run1/utilization.csv
图片: test/e2e/benchmark/results/final-charts/09_U-1_cpu_utilization_boxplot.png
图片(PDF): test/e2e/benchmark/results/final-charts/09_U-1_cpu_utilization_boxplot.pdf

