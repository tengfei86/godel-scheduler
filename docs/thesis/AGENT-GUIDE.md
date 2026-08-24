# Agent Group 使用说明

> **给谁看**：接手论文工作的每一位 agent（含子 agent、并行 agent、后续 session 的 agent）。
> **上下文**：此仓库同时承载 **代码工程** 与 **北航硕士学位论文**；agent 只负责论文侧工作，不改代码。
> **写作阶段**：一版全文草稿已就位，缺口清晰（见下文§3）。

---

## 1. 项目一句话

**论文题目**：《基于 etcd 的分布式 Kubernetes 调度器研究与实现》
**格式规范**：北京航空航天大学研究生学位论文撰写规范（2025.3）
**核心贡献**：Gödel 分布式调度器上的 ENO（Embedded Native Optimizer）架构改造 + 基于 etcd 语义的四层一致性容错。
**评估**：5 组调度器（a=ENO / b=Gödel / c=kube-scheduler / d=Volcano / e=Koordinator）× 2 规模（s2=1000 节点、s3=5000 节点）× 2 负载（w2=中、w3=高）× 3 重复 = **60 次已完成实验**。

---

## 2. 工作区地图（只读时先看这三份）

| 路径 | 用途 | 何时读 |
|---|---|---|
| [docs/thesis/README.md](docs/thesis/README.md) | 工作区索引 + 章节完成度 + 北航格式速查表 | 每次入场先读 |
| [docs/thesis/figure-mapping.md](docs/thesis/figure-mapping.md) | 21 张图的规划表、来源、编号约定 | 涉及任何图表工作时读 |
| [test/e2e/benchmark/results/final-charts/chart-index.md](test/e2e/benchmark/results/final-charts/chart-index.md) | 9 张已生成的数据图 + 每张的数据源 + 关键结论数字 | 写第 6 章正文时读 |

**目录概览**

```
docs/thesis/
├─ README.md              工作区索引 + 格式速查
├─ figure-mapping.md      图表规划
├─ AGENT-GUIDE.md         ← 本文件
├─ chapters/              7 章 Markdown 草稿（00-abstract .. 07-conclusion）
└─ figures/               35 个论文图文件（原图 + mermaid 源 + 三种输出）

test/e2e/benchmark/
├─ results/               60 次实验 JSON（按 组/规模/负载/run 组织）
│   ├─ a/s2/w2/run{1,2,3}/*.json
│   ├─ ...
│   └─ final-charts/      9 张已选定的数据图（T-1..U-1）
└─ collect/
    ├─ plot-results.py               单实验/对比/平均绘图
    └─ generate-final-thesis-charts.py  final-charts 生成器
```

---

## 3. 剩余工作 — 按可独立承接的任务切分

每个 agent 认领一项，互不阻塞；完成后在该章节文件末尾追加一行 `<!-- agent: <task-id> done @ YYYY-MM-DD -->`。

### T1 · 参考文献补齐（约 15–20 处 `[?]`）
- **在哪**：`chapters/01-*.md` .. `chapters/07-*.md` 全文 `grep -n '\[?\]'`。
- **做什么**：为每处 `[?]` 查一条权威文献（会议/期刊/官方文档），在 [chapters/](docs/thesis/chapters/) 同级新建 [chapters/references.bib](docs/thesis/chapters/references.bib)（BibTeX），把 `[?]` 替换为 `[序号]`（GB/T 7714-2015 顺序编码制）。
- **交付**：一份 BibTeX + 正文中所有 `[?]` 消失。
- **验收**：`grep -rn '\[?\]' chapters/` 输出为空。

### T2 · 第 6 章数值 & 数据图映射
- **在哪**：[chapters/06-evaluation.md](docs/thesis/chapters/06-evaluation.md)，全文搜索 `TODO`。
- **背景**：现在正文用占位符描述结果；`final-charts/chart-index.md` 已列出 9 张图与关键结论百分比。
- **做什么**：
  1. 把 `final-charts/*.{png,pdf}` 按论文编号（图 6-3 ~ 图 6-10）复制/重命名到 [figures/](docs/thesis/figures/)，两侧都保留（源 + 论文用），文件名规约见§6。
  2. 在正文中把每个 `TODO(数值)` 替换为 `chart-index.md` 中已算好的百分比（ENO vs Gödel 提升 26.7% / 延迟降 23.2% 等）。
  3. 补写图注：`图 6-3  稳态吞吐量对比（s3, w3, run1）` 之类。
- **不做**：不要重跑实验；不要修改 JSON。

### T3 · 缺失图 3-2 / 6-1 / 6-2
- **图 3-2**：基于 etcd 的三步事务时序（dispatching→assuming→binding）。**mermaid `sequenceDiagram`**。
- **图 6-1**：实验环境拓扑（kind + KWOK + Prometheus + 5 组调度器）。**mermaid `flowchart`**。
- **图 6-2**：单次实验流程时序（run-experiment.sh 的阶段）。**mermaid `sequenceDiagram`**。
- **做什么**：按§6 命名规约在 `figures/` 建 `.mmd`，然后执行§6 中的导出命令产出 `.pdf/.png/.svg`。
- **验收**：三种输出齐全；`.mmd` 在 GitHub 上能直接渲染。

### T4 · 英文摘要
- **前置**：等中文摘要 `00-abstract.md` 定稿（导师批注后）再开工。
- **做什么**：翻译中文摘要为英文，保留同一份文件（一份文件两个 section），关键术语按 CS 惯例（如 dispatcher、binder、gang scheduling 不译）。
- **验收**：中英摘要长度比 1:1.1 内；关键词 3–6 个。

### T5 · 全文一致性 pass（在 T1–T4 完成后）
- **做什么**：
  - 图/表编号连续（图 3-1..图 6-10）；
  - 图引用格式统一 `图 X-Y`；
  - 术语一致（Embedded Binder / ENO / Gödel 各种大小写）；
  - 章节内交叉引用 `见§X.Y` 存在。
- **工具**：`grep`、`ripgrep`；可写脚本核对。

### T6 · Word 导出
- **前置**：T1–T5 完成。
- **做什么**：`pandoc chapters/*.md -o thesis.docx --reference-doc=beihang-template.docx`（若模板缺失，先按§7 手工套样式）。

---

## 4. 已有的实验数据字典

**结果目录形态**：`results/<组>/<规模>/<负载>/run<N>/<metric>.json`

- **组**：`a`=ENO / `b`=Gödel / `c`=kube-scheduler / `d`=Volcano / `e`=Koordinator
- **规模**：`s2`=1000 节点 / `s3`=5000 节点（论文主用）
- **负载**：`w2`=500 pods/s×50K / `w3`=1000 pods/s×100K（主用）；辅助 `w1/w4/w6`
- **run**：每组 3 次

**每个 run 目录含 JSON**（Prometheus 原始导出）：
- `scheduling_throughput.json` — 吞吐时间序列
- `scheduling_latency_p90.json` / `p99.json` — 分位延迟
- `bind_latency_p50/p90/p99.json` — 绑定延迟
- `scheduling_success_rate.json` / `error_rate.json`
- `pending_pods.json` — 队列堆积
- `goroutines.json` — 资源开销
- `utilization.csv` — 节点 CPU 利用率
- `metadata.txt` — run 起止时间等

**推荐用法**（不要每次自己 grep JSON）：
- 已算好的结论 → 直接引用 `final-charts/chart-index.md` 里的百分比。
- 需要新对比 → `python3 test/e2e/benchmark/collect/plot-results.py <dir1> <dir2> --compare --output <out>`。
- 需要多 run 平均 → `plot-results.py --average --std-band ...`。

**权威报告**：[report_2026-08-04_223015.md](test/e2e/benchmark/results/report_2026-08-04_223015.md)（60/60 成功，38h20m）。

---

## 5. 图表编号与命名硬约束

### 5.1 命名规约（figures/ 内）

```
fig{章号}-{序号}[-{子号}]-{english-slug}.{mmd,pdf,png,svg}
```

例：`fig3-2-etcd-three-step-txn.mmd` + `.pdf` + `.png` + `.svg`。

**四份产物必须齐全**：`.mmd`（源） + `.pdf`（论文用矢量） + `.png`（Markdown 预览） + `.svg`（备份）。已归档图的样板见 [figures/fig4-1-pod-state-machine.*](docs/thesis/figures/)。

### 5.2 Mermaid 导出命令

```bash
# 前置：npm i -g @mermaid-js/mermaid-cli
cd docs/thesis/figures
NAME=fig3-2-etcd-three-step-txn
mmdc -i $NAME.mmd -o $NAME.pdf
mmdc -i $NAME.mmd -o $NAME.png -w 1600 -H 900
mmdc -i $NAME.mmd -o $NAME.svg
```

### 5.3 图内文字（北航规范硬性要求）

- 所有描述性文字用**中文**（专用符号/单位可保留英文）
- 分辨率 ≥ 300 dpi（`-w 1600 -H 900` 通常够）
- 少用颜色，多用线型/形状（考虑黑白打印）

---

## 6. 北航 2025.3 格式速查（写作时必须遵守）

| 元素 | 中文 | 西文/数字 | 字号 | 其他 |
|---|---|---|---|---|
| 章标题 | 黑体 | Times New Roman | 三号 | 居中，段前/后 0.5 行 |
| 一级节 | 黑体 | TNR | 四号 | 居左 |
| 二级节 | 黑体 | TNR | 小四 | 居左 |
| 正文 | 宋体 | TNR | 小四 | 首行缩进 2 字符，1.5 倍行距 |
| 图题（图下） | 宋体加粗 | TNR | 五号 | 居中，段前 6 磅段后 12 磅 |
| 表题（表上） | 宋体加粗 | TNR | 五号 | 居中，段前 12 磅段后 6 磅 |
| 参考文献 | 宋体 | TNR | 五号 | 固定 16 磅，悬挂缩进 2 字符 |

- **页面**：A4，四边距 2.5 cm；页眉页脚距边界 1.5 cm。
- **参考文献**：GB/T 7714-2015 顺序编码制；正文用 `[序号]` **上标方括号，放句号之前**。
- **图表编号**：`图 3-1`、`表 3-1`（章-序，全篇连续，不因小节重置）；附录另编 `图A.1`。
- **分图**：`(a) (b) (c)` 半角括号。
- **图题示例**：`图 3-1  基于 etcd 的分布式 Kubernetes 调度器系统架构`（图序与标题间 **2 个半角空格**）。
- **表格**：一律**三线表**（上下 1.5 磅，中间 1 磅）。

---

## 7. Markdown 阶段的写作约定

写作停留在 Markdown，最后一次性 pandoc 转 Word。以下约定使转换与后续审阅顺滑：

1. **图引用**：正文写 `图 3-2 展示...`，Markdown 层用 `![图 3-2 xxx](../figures/fig3-2-xxx.png)`。
2. **表**：普通 Markdown 表格即可，表题写在**表上方一行**：`**表 6-1  五个对比调度器组的部署概览**`。
3. **文献占位**：未查到的写 `[?]`，查到后统一改成 `[N]`（不加上标标记，pandoc 后再统一处理）。
4. **交叉引用**：`见§4.6`、`见图 3-1`（章节号完整、图号完整）。
5. **TODO 标记**：一律 `TODO(<子任务>): <内容>` 单行注释形式，便于 `grep -n 'TODO'`。
6. **不要**在 Markdown 里手动画字体样式（`**加粗**` 例外）；样式全部交给最后的 Word 模板。

---

## 8. Agent 协作契约

### 8.1 分工原则

- **一 agent 一章 / 一任务**，不跨章修改（跨章的一致性 pass 走 T5）。
- **只读优先**：写第 6 章数值时，绝对不改 `results/` 里的 JSON。
- **图片资产**：源文件（drawio、原始 .mmd）改动前先 `cp` 一份带 `.bak.YYYYMMDD` 后缀。

### 8.2 交付清单（每个 agent 完成任务时都要写）

在自己认领的章节末尾追加：

```markdown
<!--
agent-task: T2
scope: 第 6 章数值填充 + 图 6-3..6-10 归档
did:
  - final-charts/*.pdf 复制到 figures/ 并按 fig6-N-*.pdf 命名（列 8 个文件名）
  - 6.4.1 ~ 6.6.3 内 TODO 已替换为具体百分比（列被改动的行号）
did-not:
  - 未触碰 results/**（只读）
  - 未修改代码 / 未修改 chart-index.md
verified:
  - grep 'TODO' chapters/06-evaluation.md 输出为空
agent: <你的标识> @ 2026-08-24
-->
```

### 8.3 禁止清单

- ❌ 编造实验数字（永远从 `chart-index.md` 或 JSON 引用）。
- ❌ 编造参考文献（宁可保留 `[?]` 让下一个 agent 接手）。
- ❌ 修改代码目录 `pkg/`、`cmd/` 等（本任务只涉及 `docs/thesis/` 与只读读取 `test/e2e/benchmark/results/`）。
- ❌ 用 emoji 装饰正文（论文正文一律无 emoji）。
- ❌ 越权：不确定的结构性改动（新增章节、删除小节）先在自己的交付清单里提问，不擅自动手。

---

## 9. 常用命令

```bash
# 1. 状态检查
grep -rn '\[?\]' docs/thesis/chapters/ | wc -l          # 剩余待补文献
grep -rn 'TODO' docs/thesis/chapters/                    # 剩余占位
ls docs/thesis/figures/ | wc -l                          # 图片数量

# 2. 图表导出（mermaid → pdf/png/svg）
cd docs/thesis/figures && NAME=figX-Y-slug && \
  mmdc -i $NAME.mmd -o $NAME.pdf && \
  mmdc -i $NAME.mmd -o $NAME.png -w 1600 -H 900 && \
  mmdc -i $NAME.mmd -o $NAME.svg

# 3. 生成/更新对比数据图
python3 test/e2e/benchmark/collect/plot-results.py \
  test/e2e/benchmark/results/a/s3/w3/run1 \
  test/e2e/benchmark/results/b/s3/w3/run1 \
  --compare --output test/e2e/benchmark/results/final-charts

# 4. 最终导出 Word
cd docs/thesis && pandoc chapters/*.md \
  -o thesis.docx \
  --reference-doc=beihang-template.docx \
  --toc --number-sections
```

---

## 10. 验收总清单（写完前逐项过一遍）

- [ ] `grep -rn '\[?\]' chapters/` 为空
- [ ] `grep -rn 'TODO' chapters/` 为空
- [ ] `figures/` 至少 21 个论文用图（3 张原图 + 3 张缺图 + 3+3 章 4/5 mermaid + 8 张数据图 + 其他）
- [ ] 每张 mermaid 图有 `.mmd/.pdf/.png/.svg` 四件套
- [ ] 中英摘要皆定稿；关键词 3–6 个
- [ ] 参考文献 GB/T 7714-2015 格式；正文引用为 `[N]` 上标
- [ ] pandoc 导出 `thesis.docx`；打开无警告，图/表编号连续
- [ ] 页边距 2.5 cm、A4；字体符合§6 表
- [ ] `git status` 显示只有 `docs/thesis/**` 与 `test/e2e/benchmark/results/final-charts/**` 内变更

---

**最后一句话**：本 guide 与 [README.md](docs/thesis/README.md) / [figure-mapping.md](docs/thesis/figure-mapping.md) 冲突时，以后两者为准（它们才是原始规划文档；本 guide 只是执行手册）。发现冲突请在你的 agent 交付清单里指出。
