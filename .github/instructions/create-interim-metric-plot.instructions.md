---
description: 当用户要求基于 test/e2e/benchmark/results 中 Prometheus JSON 生成论文最终对比图（8-12 张）并突出 Group B（Embedded Binder）优势时，加载此指令。
applyTo: '**/{THESIS_COMPARISON_PLAN.md,test/e2e/benchmark/results/**,test/e2e/benchmark/collect/**}'
---

# 论文最终对比图生成指令（Group B 优势版）

## 1. 目标

基于 `test/e2e/benchmark/results` 下的 Prometheus 指标 JSON，生成用于论文正文的最终对比图表，重点展示 **Group B (Embedded Binder)** 相比 A/C/D/E 的优势和特性。

输出必须包含：

- 对比指标标题（可直接放论文图注）
- 指标简要总结（每图 1-2 句，聚焦 B 的优势）
- 对应图像文件（PNG/PDF）

图表数量要求：**8-12 张**，默认产出 **10 张**。

## 2. 数据来源与范围

仅允许使用以下数据源：

- `test/e2e/benchmark/results/<group>/<scale>/<workload>/<run>/` 下的 `*.json`
- 同目录 `metadata.txt`（用于时间窗口/实验信息）
- 同目录 `utilization.csv`、`pod-distribution.csv`（若图表需要）

禁止使用手工编造数据；若某图数据缺失，必须明确标注 `data unavailable`。

## 3. 图表清单（默认 10 张）

优先使用 S3（5000 节点）。

1. `T-1` 吞吐量时间曲线（W3, A/B/C/D/E）
2. `T-3` 负载-吞吐量对比（W1-W4, A/B/C/D/E）
3. `L-1` E2E P99 延迟时间序列（W3, A/B/C/D/E）
4. `L-2` 绑定延迟分位对比（P50/P90/P99, A/B）
5. `S-2` 成功率/失败率对比（W1-W4, A/B/C/D/E）
6. `S-3` Pending Pod 堆积曲线（W4, A/B/C/D/E）
7. `W6` Gang 场景完成时间对比（A/B/D/E）
8. `T-4` 实例数-吞吐量扩展图（A/B，inst1/3，scale=s3/s4/s5，workload=w3/w4）

说明：仅 `T-4` 使用 `s3/s4/s5` 与 `w3/w4` 的独立数据集；其余图表统一使用 `s3`。

可选补充图：
9. `U-1` 节点利用率箱线图（A/B/D/E）

## 4. 每张图的强制输出格式

每张图生成后，必须输出一条结构化记录，字段不可缺失：

```text
[图编号] <例如 T-1>
标题: <中文论文标题>
指标总结: <1-2 句，必须点名 Group B 相对 A 或相对 A~E 的差异>
数据源: <json 文件路径列表，至少 2 个>
图片: <输出图片路径>
```

## 5. 统计口径（论文最终版）

- 同一实验至少聚合 `run1/run2/run3`，主值使用 **中位数**。
- 若展示误差，使用 **标准差**（error bar）。
- 延迟统一使用 `ms` 展示（源数据为秒时需转换）。
- 时间序列需对齐到相对时间（从实验开始计时）。

## 6. 数据质量与异常处理

遵循以下约束，避免误判：

- Group B 固定可能缺失 4 个指标：
	- `bind_retries.json`
	- `dispatcher_fallback.json`
	- `node_validation_failures.json`
	- `goroutines.json`
	这些在无故障/未触发场景下可视为正常。
- Group D 在 `w2/W3/w4/W6` 可能存在大面积无数据，需标注：`overloaded / data unavailable`。
- 任意图若关键数据不足，不得强制绘制错误结论图；可替换为可选图并说明原因。

## 7. 图像输出规范

- 默认输出目录：`test/e2e/benchmark/results/final-charts/`
- 文件命名：`<index>_<chart_id>_<short_name>.png`
	- 例如：`01_T-1_throughput_timeseries.png`
- 同时导出 PDF：与 PNG 同名，仅后缀改为 `.pdf`
- 分辨率：>= 300 DPI
- 颜色映射固定：
	- A: 红色系
	- B: 绿色系（突出）
	- C: 蓝色系
	- D: 橙色系
	- E: 紫色系

## 8. 推荐执行命令

先生成基础对比图，再做论文聚合图：

```bash
# 示例: W3 对比（A~E）
python3 test/e2e/benchmark/collect/plot-results.py \
	test/e2e/benchmark/results/a/s3/w3/run1 \
	test/e2e/benchmark/results/b/s3/w3/run1 \
	test/e2e/benchmark/results/c/s3/w3/run1 \
	test/e2e/benchmark/results/d/s3/w3/run1 \
	test/e2e/benchmark/results/e/s3/w3/run1 \
	--compare --format png --output test/e2e/benchmark/results/final-charts/raw
```

若需要论文最终图（run1-3 聚合、中位数/标准差、双 Y 轴），新增独立脚本处理，不修改原始 JSON。

## 9. 结论撰写要求（与图同步输出）

每张图结论需满足：

- 必须包含一个可验证比较关系（例如 `B > A`、`B 延迟低于 A 35%`）
- 若 D/E 缺失数据，必须显式写明，不得隐去
- 结论仅基于图中数据，不扩展到未观测场景

## 10. 最终交付物

最终应包含：

- `8-12` 张论文图（PNG + PDF）
- 一份图表索引清单（可为 Markdown）：逐图列出标题、总结、数据源、图片路径
- 若有缺失/降级图，附 `data-quality-notes` 说明替换原因