# 插图和附表清单

## 插图清单

- 图 1  基于 etcd 的分布式 Kubernetes 调度器系统架构
- 图 2  基于 etcd 的三步事务写入时序（dispatching → assuming → binding）
- 图 3  Dispatcher 内部数据结构流转：Pod 从新建到分发完成的过程
- 图 4  单个 Scheduler 内部：Pod 在活跃队列与退避队列间的流动
- 图 5  Pod 生命周期状态机与 4 层容错机制介入点
- 图 6  Dispatcher 策略分发的嵌套决策路径（先按 PodGroup 分流，再由 SupportRescheduling FeatureGate 决定 Owner 亲和或默认负载均衡）
- 图 7  Dispatcher 侧的错误恢复流程（Layer 3 全局回退）
- 图 8  一致性论证：核心不变量 I 及其 4 层威胁-防御映射
- 图 9  独立 Binder（改造前）：5 步跨进程流程
- 图 10  ENO 进程内 Binder（改造后）：3 步进程内流程
- 图 11  CacheAdapter 桥接层实现 SchedulerCache 零拷贝共享
- 图 12  ENO 部署拓扑（Kubernetes Deployment 视角）
- 图 13  单次实验流程时序（run-experiment.sh 的 12 个 Step）
- 图 14  五组调度器有效吞吐对比（全组基线场景，n=3 中位数）
- 图 15  a/b/d 三组调度器 w6 有效吞吐对比（s3, inst1）
- 图 16  a/b/d 三组调度器 w6 P99 调度延迟对比（s3, inst1）
- 图 17  ENO 与 Gödel 各场景有效吞吐对比（总工作量 / 总完成时间，n=3 中位数）
- 图 18  ENO 与 Gödel 峰值吞吐 15 场景对比（scheduling_peak_throughput，n=3 中位数）
- 图 19  全场景 ENO 与 Gödel P99 调度延迟对比（scheduling_latency_p99，log 纵轴，n=3 中位数）
- 图 20  ENO 与 Gödel Pod E2E 延迟 P99 15 场景对比（pod_e2e_latency_p99，log 纵轴，n=3 中位数）
- 图 21  ENO 与 Gödel 调度吞吐时序（s3, w3, inst1，n=3 中位数）
- 图 22  P90 调度延迟时序（s3, w3, inst1，n=3 中位数）
- 图 23  P99 调度延迟时序（s3, w3, inst1，n=3 中位数）
- 图 24  ENO 与 Gödel 调度吞吐时序（s2, w3, inst1，n=3 中位数）
- 图 25  P90 调度延迟时序（s2, w3, inst1，n=3 中位数）
- 图 26  P99 调度延迟时序（s2, w3, inst1，n=3 中位数）
- 图 27  ENO 与 Gödel 调度吞吐时序（s4, w3, inst3，n=3 中位数）
- 图 28  P90 调度延迟时序（s4, w3, inst3，n=3 中位数）
- 图 29  ENO 与 Gödel P99 调度延迟时序（s4, w3, inst3，n=3 中位数）
- 图 30  ENO 与 Gödel 调度吞吐时序（s3, w3, inst3，n=3 中位数）
- 图 31  P90 调度延迟时序（s3, w3, inst3，n=3 中位数）
- 图 32  ENO 与 Gödel P99 调度延迟时序（s3, w3, inst3，n=3 中位数）
- 图 33  ENO 与 Gödel 调度吞吐时序（s3, w4 极限负载, inst3，n=3 中位数）
- 图 34  ENO 与 Gödel P99 调度延迟时序（s3, w4 极限负载, inst3，n=3 中位数）
- 图 35  ENO 与 Gödel 调度吞吐时序（s4, w4 极限负载, inst3，n=3 中位数）
- 图 36  ENO 与 Gödel P99 调度延迟时序（s4, w4 极限负载, inst3，n=3 中位数）
- 图 37  ENO 与 Gödel 调度吞吐时序（s3, w5 突发洪峰, inst3，n=3 中位数）
- 图 38  ENO 与 Gödel P99 调度延迟时序（s3, w5 突发洪峰, inst3，n=3 中位数）
- 图 39  ENO 与 Gödel 调度吞吐时序（s4, w5 突发洪峰, inst3，n=3 中位数）
- 图 40  ENO 与 Gödel P99 调度延迟时序（s4, w5 突发洪峰, inst3，n=3 中位数）
- 图 41  Layer 0 触发验证（节点归属漂移，s2/w2/inst3，n=1）
- 图 42  Layer 3 触发验证（scheduler-0 停机 180 s，s2/w2/inst3，n=1）
- 图 43  Layer 0 / Layer 3 故障注入三项定量对比（s2/w2/inst3，n=1）

## 附表清单

- 表 1  典型集群调度系统对比
- 表 2  本文关键技术与对应问题映射
- 表 3  五个对比调度器组的部署概览
- 表 4  集群规模梯度
- 表 5  评估用工作负载定义
- 表 6  16 个对比场景的参与调度器与实例配置
- 表 7  五组基线场景有效吞吐（pods/s，n=3 中位数）
- 表 8  Gang 场景（s3/w6/inst1）三组对比
- 表 9  ENO 与 Gödel 有效吞吐对比（pods/s，n=3 中位数）
- 表 10  ENO 与 Gödel 调度延迟对比（秒）
- 表 11  ENO 与 Gödel Pod E2E 延迟对比（pod_e2e_latency_p99，秒）
- 表 12  s3 → s4 规模扩展下的关键指标变化（w3, inst3）
- 表 13  inst1 → inst3 实例扩展下的关键指标变化（s3, w3）
- 表 14  复杂负载场景对比（有效吞吐单位 pods/s，延迟单位秒）
- 表 15  各对比场景关键指标汇总

> 说明：本清单由各章图题与表题自动汇总，共 43 张插图、15 张附表。
