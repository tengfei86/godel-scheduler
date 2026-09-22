# 6.6 一致性容错专项实验

本目录实现论文第 6.6 节的两个故障注入实验（Layer 0 归属漂移 / Layer 3 实例失活），与 6.5 节主实验共用运行框架。

## 一键复现

```bash
cd test/e2e/benchmark
bash faultinject/run-6.6-all.sh          # 4 phase 全跑
bash faultinject/run-6.6-all.sh --help   # 参数与幂等语义
```

[run-6.6-all.sh](run-6.6-all.sh) 是 6.6 节的**单一入口**。它把整套实验切成四个幂等 phase：

| Phase | 做什么 | 幂等策略 |
|---|---|---|
| `preflight` | 校验集群通、KWOK 节点 = 5000、组 a 三副本 Running 且实例名唯一、Prometheus by-pod recording rule 已加载、inject 脚本可执行 | 每次重跑；失败直接 exit 2 |
| `baseline` | 补跑 `a/s3/w2/inst3/run{1,2,3}` 无故障基线（供 duration 对比） | 若 `metadata.txt` 已存在则跳过 |
| `inject` | `layer0 × N` + `layer3 × N`（N 默认为 3） | 若 `run<N>/metadata.txt` 已存在则跳过 |
| `analyze` | 对每个 run 目录跑 `fault-plot.py` + `fault-summary.py` | 每次重跑（成本低） |

只跑某个 phase：`--phase preflight | baseline | inject | analyze`。

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `--phase all\|preflight\|baseline\|inject\|analyze` | `all` | 只跑指定 phase |
| `--repeats N` | 3 | inject 阶段每层跑 N 次 |
| `--skip-baseline` | 关 | 跳过 Phase 2（假设你已有基线） |
| `--fraction F` | 0.1 | Layer 0 抽取的节点比例 |
| `--from X` `--to Y` | eno-scheduler-0 → eno-scheduler-1 | Layer 0 漂移起止实例 |
| `--target POD` | 自动挑 | Layer 3 要杀的 Pod 名 |

## 手动模式（细粒度）

想跳过 orchestrator，直接调用底层脚本：

```bash
# 只跑一次 layer0
bash faultinject/run-fault-experiment.sh layer0 1

# 单次注入 + 手工画图
bash run-experiment.sh a s3 w2 1 --instances 3 --inject layer0 --inject-at 30
python3 faultinject/fault-plot.py    results/faultinject/layer0/a_s3_w2_inst3/run1
python3 faultinject/fault-summary.py results/faultinject/layer0/a_s3_w2_inst3/run1 \
  --baseline results/a/s3/w2/inst3/run1
```

## 文件清单

| 文件 | 作用 |
|---|---|
| `run-6.6-all.sh` | **主入口**：preflight → baseline → inject → analyze 四段流水线 |
| `run-fault-experiment.sh` | 只跑注入阶段，`layer0 \| layer3 \| both` |
| `inject-layer0.sh` | Layer 0 触发：将 10% 节点的 `eno.io/scheduler-name` 从 `eno-scheduler-0` 改到 `eno-scheduler-1` |
| `inject-layer3.sh` | Layer 3 触发：force-delete 一个 Running 的 Scheduler Pod |
| `assert-invariant-i.sh` | 遍历 apiserver 断言不变量 I（`spec.nodeName` 非空且无重复） |
| `fault-plot.py` | 生成双轴时序图（Layer 0 / Layer 3 各一张） |
| `fault-summary.py` | 分段计数 + per-instance 绑定量 + 不变量断言汇总 |

## 结果目录结构

```
results/faultinject/
├── layer0/a_s3_w2_inst3/run1/
│   ├── inject-manifest.json      注入元数据（起止时间、被 patch 节点清单）
│   ├── inject.log / inject.rc     inject 脚本 stdout+stderr / 退出码
│   ├── inject-events.log          单行事件日志（起、结、失败）
│   ├── invariant-i.txt            不变量 I apiserver 断言输出
│   ├── metadata.txt               实验总时长、Pod 计数等
│   ├── *.json                     Prometheus 时序（含 by-pod 分组）
│   └── plots/                     fault-plot.py / fault-summary.py 输出
└── layer3/a_s3_w2_inst3/run1/
    └── ...
```

## 前置一次性搭建

`run-6.6-all.sh preflight` 会告诉你缺什么；下面是完整的从零到就绪：

```bash
cd test/e2e/benchmark
bash setup-cluster.sh s3                             # kind + KWOK 5000 节点 + Prometheus
bash schedulers/deploy-group-a.sh                    # 部署组 a
bash schedulers/scale-schedulers.sh a 3              # 扩到 3 实例，且实例名唯一
kubectl apply -f ../../../manifests/monitoring/overlays/group-a/prometheus-config.yaml
kubectl -n monitoring rollout restart deploy/prometheus
```

## 预期观测

Layer 0：
- `eno:binder_node_validation_failures:rate1m` 在 T+30..+60s 出现峰值
- `eno:binder_dispatcher_fallback:rate1m` 与其同步上升
- `eno:binder_embedded_bind_pods:success_rate1m` 全程保持 1
- 不变量 I: bound=50000, unbound=0, dup=0

Layer 3：
- `eno:binder_dispatcher_fallback:rate1m` 在 T+30s 出现阶跃
- `sum(scheduler_pending_pods)` 明显上涨随后回落
- `eno:binder_embedded_bind_pods:success_rate1m_by_pod` 中被杀实例的曲线归零、存活实例上升
- 三实例 [inject, inject+90s] 累积 ≈ 50 000
