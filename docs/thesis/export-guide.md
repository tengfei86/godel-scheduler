# Word 导出指南（T6）

> **用途**：把 `chapters/` 下的 Markdown 合并导出为符合北航模板的 Word 文档。
> **前置**：安装 pandoc（`brew install pandoc`），准备好学校提供的 Word 模板（`docs/standard/` 下有样例 docx）。

## 一、导出命令

```bash
cd docs/thesis
pandoc chapters/00-abstract.md \
       chapters/00b-list-of-figures-tables.md \
       chapters/00c-symbols-abbreviations.md \
       chapters/01-introduction.md \
       chapters/02-related-work.md \
       chapters/03-architecture.md \
       chapters/04-consistency.md \
       chapters/05-eno-optimization.md \
       chapters/06-evaluation.md \
       chapters/07-conclusion.md \
       chapters/97-achievements.md \
       chapters/98-appendix.md \
       chapters/99-acknowledgements.md \
  -o thesis.docx \
  --toc --toc-depth=2 \
  --reference-doc=../../docs/standard/beihang-template.docx
```

说明：

- **不要用 `chapters/*.md` 通配**：`references.bib` 与临时文件不应进入正文；按上面显式列出的顺序依次传入即可（顺序即装订顺序）；
- `--toc` 生成目录（对应规范中的"目录"，在 Word 中右键"更新域"即可刷新页码）；
- `--reference-doc` 指定学校模板；若暂无模板，先导出再用 Word 套用样式（正文小四宋体、1.5 倍行距、标题黑体等，见 AGENT-GUIDE §6）。

## 二、导出后需手工处理的事项

| 事项 | 说明 |
|---|---|
| 封面 / 题名页 / 独创性声明 | 使用学校模板填写，不进入 Markdown 流水线 |
| 目录 | 右键"更新域"刷新页码 |
| 插图和附表清单 | 由 `00b-list-of-figures-tables.md` 生成，可按需改为 Word 的图表目录域 |
| 图表编号 | 正文已按"图 X-Y / 表 X-Y"编排；若需自动编号，改用 Word 题注域 |
| 公式 | 第 4 章的核心不变量使用了 LaTeX 公式，`pandoc` 加 `--mathml` 可转 Word 公式；若失败则改为纯文本符号表达 |
| 参考文献 | `references.bib` 未直接进入正文；正文引用为 `<sup>[N]</sup>` 上标形式，导入 Word 后用"交叉引用/尾注"或手工整理为 GB/T 7714 顺序编码制 |
| 附录与致谢 | 已生成，按需补全个人信息 |

## 三、检查清单

- [ ] 目录页码正确、层级正确
- [ ] 所有图题在图下方、表题在表上方，编号连续（图 1-1 ~ 图 6-15、表 1-1 ~ 表 A-1）
- [ ] 正文无遗留的 Markdown 标记（`**`、`<sup>`、`|` 表格残留）
- [ ] 参考文献编号与正文上标一一对应
- [ ] 页边距 2.5 cm、A4、字体符合 AGENT-GUIDE §6
- [ ] 按 §7A 复查去 AI 味指标（加粗密度、列表占比）
