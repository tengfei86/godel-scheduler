# 硕士学位论文工作区

**论文题目**：基于 etcd 的分布式 Kubernetes 调度器研究与实现

**格式规范**：北京航空航天大学研究生学位论文撰写规范（2025.3）

---

## 目录结构

```
docs/thesis/
├─ README.md                    ← 本文件（工作区索引）
├─ figure-mapping.md            ← 图表规划与规范
├─ figures/                     ← 论文用图（35 个文件）
│   ├─ fig3-1-system-arch.png       (你的原图)
│   ├─ fig3-3-dispatcher-flow.png   (你的原图)
│   ├─ fig3-4-scheduler-flow.png    (你的原图)
│   ├─ fig4-1..4-3-*.{mmd,pdf,png,svg}
│   └─ fig5-1..5-3-*.{mmd,pdf,png,svg}
└─ chapters/                    ← 各章 Markdown 草稿
    ├─ 00-abstract.md           中英文摘要
    ├─ 01-introduction.md       第 1 章 绪论
    ├─ 02-related-work.md       第 2 章 相关工作与背景
    ├─ 03-architecture.md       第 3 章 分布式 K8s 调度器系统架构
    ├─ 04-consistency.md        第 4 章 基于 etcd 语义的一致性容错机制
    ├─ 05-eno-optimization.md   第 5 章 面向大规模场景的架构优化（ENO）
    ├─ 06-evaluation.md         第 6 章 实验设计与评估
    └─ 07-conclusion.md         第 7 章 总结与展望
```

---

## 章节完成度

| 章 | 文件 | 完成度 | 备注 |
|---|---|---|---|
| 摘要（中英）| 00-abstract.md | 中文 ✅ / 英文 ⏳ | 英文摘要待中文定稿后翻译 |
| 第 1 章 | 01-introduction.md | ✅ 一版完整 | 参考文献用 `[?]` 占位 |
| 第 2 章 | 02-related-work.md | ✅ 一版完整 | 参考文献用 `[?]` 占位 |
| 第 3 章 | 03-architecture.md | ✅ 一版完整 | 用了你的 3 张原图 |
| 第 4 章 | 04-consistency.md | ✅ 一版完整 | 全篇质量担当，含完整证明 |
| 第 5 章 | 05-eno-optimization.md | ✅ 一版完整 | ENO 架构改造论述 |
| 第 6 章 | 06-evaluation.md | ⏳ 骨架完整，数值待填 | 数据图待用 plot-results.py 生成 |
| 第 7 章 | 07-conclusion.md | ✅ 一版完整 | 局限性坦诚列出 |

**整体状态**：主体章节的**结构 + 论述**全部完成，可以作为**第一版草稿**审阅；下列内容需要后续补充：

1. **参考文献**：全篇的 `[?]` 占位符（约 15-20 处）需要查文献补齐 BibTeX；
2. **第 6 章数据图 + 数值**：8 张数据图（图 6-3 ~ 6-10）需要用 `plot-results.py --compare` 生成，然后填入具体百分比替换 TODO 标记；
3. **图 3-2 / 6-1 / 6-2**：3 张待画图（是否画由你决定，见 figure-mapping.md）；
4. **英文摘要**：待中文摘要定稿后翻译。

---

## 使用指南

### 审阅第一版
建议按 `01 → 02 → 03 → 04 → 05 → 06 → 07 → 00`（摘要最后）的顺序审阅，因为摘要需要根据主体最终定稿。

### 修改建议
- 直接在 chapters/*.md 里改；
- 大的方向问题告诉我，我改完再让你复审；
- 每一节写完（比如你觉得第 3 章某节需要重写）都可以让我重写这一节，不必推倒重来。

### 导出到 Word
写作完成后有两个方式导出 Word：
1. **Pandoc**：`pandoc chapters/*.md -o thesis.docx --reference-doc=beihang-template.docx`（若有北航 Word 模板，可指定 reference-doc）；
2. **手动复制**：Markdown 内容直接粘贴到 Word，然后套用北航样式（正文小四号宋体、1.5 倍行距、标题黑体等）。

---

## 论文写作规范速查

按北航规范 2025.3，正文关键要素：

| 元素 | 中文 | 英文/数字 | 字号 | 其他 |
|---|---|---|---|---|
| 章标题 | 黑体 | Times New Roman | 三号 | 居中，段前段后 0.5 行 |
| 一级节标题 | 黑体 | Times New Roman | 四号 | 居左 |
| 二级节标题 | 黑体 | Times New Roman | 小四号 | 居左 |
| 正文 | 宋体 | Times New Roman | 小四号 | 首行缩进 2 字符，1.5 倍行距 |
| 图题（图下）| 宋体加粗 | Times New Roman | 五号 | 居中，段前 6 磅段后 12 磅 |
| 表题（表上）| 宋体加粗 | Times New Roman | 五号 | 居中，段前 12 磅段后 6 磅 |
| 参考文献 | 宋体 | Times New Roman | 五号 | 固定值 16 磅，悬挂缩进 2 字符 |

**页面**：A4，四边距 2.5 cm；页眉页脚距边界 1.5 cm

**参考文献格式**：GB/T 7714-2015 顺序编码制，正文中用 `[序号]` 上标方括号形式（放句号之前）

**图表编号**：图 3-1、表 3-1（章-序，全篇连续；附录另编 图A.1）
