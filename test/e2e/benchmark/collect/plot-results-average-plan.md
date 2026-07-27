# 计划：plot-results.py 增加多 run 平均功能

## Context

benchmark 实验每个场景跑多次（run1/run2/run3），目前 `plot-results.py` 只能绘制单个 run 或叠加不同组，无法对同一组同一场景的多次重复实验做平均。

添加 `--average` 模式：传入多个同组同场景的 run 目录，将每个 metric 的时间序列在**相对时间轴**上对齐后逐点平均，输出代表性曲线（附带可选的标准差 band）。

---

## Metric 可平均性评估

| 类型 | 代表指标 | 逐点平均有意义？ | 备注 |
|------|----------|----------------|------|
| 吞吐量（rate） | `scheduling_throughput`、`bind_throughput_pods` | ✅ 完全合法 | rate 结果线性可加 |
| 延迟分位数（histogram_quantile） | `scheduling_latency_p90`、`bind_latency_p90` | ⚠️ 近似有意义 | 均值是"各 run P90 的均值"，非"合并样本 P90"，需在图注说明 |
| 成功率（比率） | `bind_success_rate` | ✅ 完全合法 | 无量纲比率可直接平均 |
| Peak（max_over_time） | `scheduling_peak_throughput` | ⚠️ 有限意义 | 推荐只报告各 run 末尾标量的均值±std，而非时序平均 |
| Gauge | `pending_pods`、`goroutines`、`bind_inflight` | ✅ 完全合法 | 瞬时量线性可加 |
| 错误/重试（rate） | `bind_retries`、`bind_rejection_rate` | ✅ 完全合法 | 与吞吐量类同 |

**核心前提**：所有 run 的时间序列必须按**相对时间**（t=0 = 实验开始）对齐，不能按绝对 datetime 对齐。

---

## 实现方案

### 新增函数：`average_runs(dirs, output_dir, metric_names, fmt, std_band)`

**文件：** `plot-results.py`

**核心逻辑（包含多 series 支持）：**

1. **相对时间对齐**：从每个 run 的第一个时间戳起算，将 `datetime` 转换为相对秒数（`t - t0`），建立统一的相对时间轴

2. **按 label 匹配分组**：对于每个 metric，先汇总所有 run 中出现过的 label 字符串（`union_of_labels`）。然后**按 label 分别对齐和平均**，避免多 series 指标（如 `goroutines by (work)`、`scheduling_throughput_by_result by (result)`）跨 label 错位合并

   ```python
   # 伪代码
   all_labels = set()
   for run_dir in dirs:
       series_list = load_prometheus_json(filepath)
       for label, ts, vals in series_list:
           all_labels.add(label)

   for label in sorted(all_labels):
       per_run_arrays = []
       for run_dir in dirs:
           # 找到该 run 中对应 label 的 series
           matched = [(ts, vals) for l, ts, vals in series_list if l == label]
           if not matched:
               continue  # 某个 run 缺失该 label，跳过
           ts, vals = matched[0]
           rel_t = [(t - t[0]).total_seconds() for t in ts]
           interpolated = numpy.interp(common_t, rel_t, vals)
           per_run_arrays.append(interpolated)

       mean_vals = numpy.mean(per_run_arrays, axis=0)
       std_vals  = numpy.std(per_run_arrays, axis=0)  # 用于 std_band
   ```

3. **公共时间网格**：以所有 run 中覆盖范围最小的 run 为上界，固定 15s step，建立 `common_t` 数组

4. **标准差 band（可选）**：`numpy.std(per_run_arrays, axis=0)`，用 `ax.fill_between(common_t, mean-std, mean+std, alpha=0.2)` 绘制 ±1σ 半透明区域

5. **同时输出 JSON + 图片**：
   - 写出 `avg_<metric_name>.json`（格式模拟 Prometheus query_range 响应，status=success），供后续 `--compare` 模式复用
   - 写出 `avg_<metric_name>.<fmt>` 图片
   - 输出文件命名前缀 `avg_` 区别于单 run 图表

**对 peak 类指标的特殊处理**：名称含 `peak_throughput` 的指标，额外在图上用 `ax.axhline` + `ax.text` 标注各 run 末尾值的均值±std，提供标量汇报。

**对延迟分位数的图注**：检测 metric 名含 `latency_p`，在 subtitle 添加 `"(mean of PXX across runs, not combined-sample PXX)"`。

### numpy 依赖引入（与 matplotlib 同样保护）

```python
try:
    import numpy as np
except ImportError:
    print("错误: 需要安装 numpy。运行: pip3 install numpy", file=sys.stderr)
    sys.exit(1)
```

### 新增命令行参数

```python
parser.add_argument("--average", action="store_true",
    help="平均模式: 多个同组 run 的时间序列对齐后逐点平均，输出均值曲线")
parser.add_argument("--std-band", action="store_true",
    help="在平均曲线上绘制 ±1σ 标准差区域（需与 --average 同用）")
```

### `main()` 新增分支

```python
elif args.average:
    if len(args.dirs) < 2:
        parser.error("平均模式需要至少 2 个结果目录")
    out = args.output or "charts_average"
    print(f"平均模式: {len(args.dirs)} 个 run\n")
    average_runs(args.dirs, out, args.metrics, args.format, args.std_band)
```

### 扩充 `METRIC_META`（补全缺失 key）

当前 `METRIC_META` 缺少 `export-prometheus.sh` 中新增的若干 key，会 fallback 到空 ylabel。需补全（去掉 export-prometheus.sh 中不存在的 `queue_incoming_pods`）：

```python
# 延迟 avg
"scheduling_latency_avg":          {"title": "Scheduling Latency (Avg)",            "ylabel": "seconds"},
"bind_latency_avg":                {"title": "Bind Latency (Avg)",                  "ylabel": "seconds"},
"bind_unit_latency_p50":           {"title": "Bind Unit Latency (P50)",             "ylabel": "seconds"},
"bind_unit_latency_p90":           {"title": "Bind Unit Latency (P90)",             "ylabel": "seconds"},
"bind_unit_latency_p99":           {"title": "Bind Unit Latency (P99)",             "ylabel": "seconds"},
"bind_unit_latency_avg":           {"title": "Bind Unit Latency (Avg)",             "ylabel": "seconds"},
# Pod E2E
"pod_e2e_latency_p50":             {"title": "Pod E2E Latency (P50)",               "ylabel": "seconds"},
"pod_e2e_latency_p90":             {"title": "Pod E2E Latency (P90)",               "ylabel": "seconds"},
"pod_e2e_latency_p99":             {"title": "Pod E2E Latency (P99)",               "ylabel": "seconds"},
# E2E combined
"e2e_combined_p90":                {"title": "E2E Schedule+Bind Est. (P90)",        "ylabel": "seconds"},
"e2e_combined_p99":                {"title": "E2E Schedule+Bind Est. (P99)",        "ylabel": "seconds"},
# SLI
"sli_latency_p50":                 {"title": "SLI Scheduling Latency (P50)",        "ylabel": "seconds"},
"sli_latency_p90":                 {"title": "SLI Scheduling Latency (P90)",        "ylabel": "seconds"},
"sli_latency_p99":                 {"title": "SLI Scheduling Latency (P99)",        "ylabel": "seconds"},
"sli_latency_avg":                 {"title": "SLI Scheduling Latency (Avg)",        "ylabel": "seconds"},
# Peak
"scheduling_peak_throughput":      {"title": "Peak Scheduling Throughput (30m)",    "ylabel": "pods/s"},
# 成功率
"bind_success_rate":               {"title": "Bind Success Rate",                   "ylabel": "ratio"},
"bind_unit_success_rate":          {"title": "Bind Unit Success Rate",              "ylabel": "ratio"},
"scheduling_success_rate":         # 已在现有 METRIC_META 中
# 错误
"bind_rejection_rate":             {"title": "Bind Rejection Rate",                 "ylabel": "rejections/s"},
"bind_failure_rate":               {"title": "Bind Failure Rate",                   "ylabel": "failures/s"},
# 吞吐量补充
"scheduling_throughput_by_result": {"title": "Scheduling Attempts by Result",       "ylabel": "attempts/s"},
"session_throughput":              {"title": "Session Throughput",                  "ylabel": "sessions/s"},
# Volcano
"unschedule_task_rate":            {"title": "Unschedulable Task Rate",             "ylabel": "tasks/s"},
"unschedule_jobs":                 {"title": "Unschedulable Jobs",                  "ylabel": "count"},
"action_latency_p90":              {"title": "Action Latency (P90)",                "ylabel": "seconds"},
"action_latency_p99":              {"title": "Action Latency (P99)",                "ylabel": "seconds"},
"task_latency_p90":                {"title": "Task Latency (P90)",                  "ylabel": "seconds"},
"task_latency_p99":                {"title": "Task Latency (P99)",                  "ylabel": "seconds"},
"plugin_latency_p90":              {"title": "Plugin Latency (P90)",                "ylabel": "seconds"},
# kube / koord
"extension_point_latency_p90":     {"title": "Extension Point Latency (P90)",       "ylabel": "seconds"},
"extension_point_latency_p99":     {"title": "Extension Point Latency (P99)",       "ylabel": "seconds"},
"pod_scheduling_attempts_p90":     {"title": "Pod Scheduling Attempts (P90)",       "ylabel": "attempts"},
"pod_scheduling_attempts_p99":     {"title": "Pod Scheduling Attempts (P99)",       "ylabel": "attempts"},
```

---

## 用法示例

> `plot-results.py` 位于 `test/e2e/benchmark/collect/`，结果目录在 `test/e2e/benchmark/results/`，
> 因此从 `collect/` 目录运行时路径前缀为 `../results/`。

```bash
# 进入脚本目录
cd test/e2e/benchmark/collect

# 对同一组同一场景的 3 次 run 做平均（附标准差 band）
python3 plot-results.py \
  ../results/a/s2/w1/run1 \
  ../results/a/s2/w1/run2 \
  ../results/a/s2/w1/run3 \
  --average --std-band \
  --output ../results/a/s2/w1/avg

# 两步工作流：先对各组做平均，再跨组对比
# 步骤1: 生成均值目录（含 avg_*.json 和 avg_*.png）
python3 plot-results.py \
  ../results/a/s2/w1/run1 \
  ../results/a/s2/w1/run2 \
  ../results/a/s2/w1/run3 \
  --average --output ../results/a/s2/w1/avg

python3 plot-results.py \
  ../results/b/s2/w1/run1 \
  ../results/b/s2/w1/run2 \
  ../results/b/s2/w1/run3 \
  --average --output ../results/b/s2/w1/avg

# 步骤2: 复用 --compare 读取 avg_*.json 进行跨组对比
python3 plot-results.py \
  ../results/a/s2/w1/avg \
  ../results/b/s2/w1/avg \
  --compare --output ../results/compare/s2_w1_a_vs_b
```

> **注意**：`--average` 会同时输出 `avg_<metric>.json` 和 `avg_<metric>.<fmt>`，步骤2的 `--compare` 会自动读取 json 文件，无需额外操作。

---

## 需要修改的文件

**`test/e2e/benchmark/collect/plot-results.py`**（唯一修改目标）：

1. 文件头添加 `import numpy as np`（带 try/except 保护）
2. 扩充 `METRIC_META` 字典（补全上述缺失 key）
3. 新增 `average_runs(dirs, output_dir, metric_names, fmt, std_band)` 函数（含多 series label 匹配）
4. `main()` 添加 `--average` / `--std-band` 参数及对应分支

---

## 验证步骤

1. **基本平均**：手动创建 3 个 run 目录，各放一个 `scheduling_throughput.json`（单 series，数值不同），运行 `--average`，确认输出均值曲线正确
2. **std band**：用方差不为零的测试数据，确认图上有半透明 ±1σ 区域
3. **多 series 指标**：用含 `result=scheduled / result=error` 多 series 的 `scheduling_throughput_by_result.json`，确认两条曲线各自独立平均，无错位
4. **两步对比工作流**：运行步骤1生成 `avg_a/`，确认目录中有 `avg_*.json`；再运行步骤2 `--compare`，确认对比图生成
5. **延迟分位数图注**：对 `scheduling_latency_p90` 确认 subtitle 含 "mean of P90" 文字
6. **peak 类指标**：对 `scheduling_peak_throughput` 确认末尾标量标注出现在图上
7. **METRIC_META 补全**：对新增 key 的 JSON 文件执行 `plot_directory`，确认 ylabel 不为空字符串
