# Word 导出指南（T6）

> **用途**：把 `chapters/` 下的 Markdown 合并导出为 Word 文档。
> **现状**：已用 pandoc 3.11 验证可用，一键脚本为 `build-docx.sh`。

## 一、一键导出（推荐）

```bash
cd docs/thesis
bash build-docx.sh                              # 默认样式，输出 thesis-preview.docx
bash build-docx.sh --reference <学校模板.docx>   # 套用学校模板样式
```

脚本自动完成三件事：

1. **装订顺序**：摘要 → 图表清单 → 符号表/缩略语 → 第 1~7 章 → 参考文献 → 研究成果 → 附录 → 致谢（与北航规范一致，且不会把 `references.bib` 等文件混入正文）；
2. **引用上标转换**：正文中的 `<sup>[N]</sup>`（GitHub 可正常渲染）会被转换为 pandoc 上标语法 `^\[N\]^`，因为 Word 不识别 HTML 标签，直接导出会丢失上标；
3. **图片路径**：在临时 `build/` 目录中执行转换与导出，使正文的 `../figures/xxx.png` 正确解析。

pandoc 定位顺序：优先使用 `PATH` 中的 `pandoc`；否则回退到工作区内的独立二进制 `tools/pandoc/pandoc-*/bin/pandoc`（无需系统安装）。

## 二、手工导出命令

```bash
cd docs/thesis/build   # 需先按上文预处理上标
pandoc 00-abstract.md 00b-*.md 00c-*.md 01-*.md 02-*.md 03-*.md 04-*.md \
       05-*.md 06-*.md 07-*.md 96-*.md 97-*.md 98-*.md 99-*.md \
  -o ../thesis-preview.docx --toc --toc-depth=2 -M toc-title=目录
```

关键参数说明：

| 参数 | 作用 |
|---|---|
| `--toc --toc-depth=2` | 生成目录（一、二级标题），对应规范的"目录" |
| `-M toc-title=目录` | 目录标题设为中文（默认是英文 "Table of Contents"） |
| `--reference-doc` | 套用学校 Word 模板的样式；`docs/standard/` 下有规范 PDF 与样例 docx |

## 三、导出后需手工处理的事项

| 事项 | 说明 |
|---|---|
| 封面 / 题名页 / 独创性声明 | 使用学校模板填写，不进入 Markdown 流水线 |
| 目录页码 | 在 Word 中右键目录区域选择"更新域" |
| 图表清单 | 已由 `00b-list-of-figures-tables.md` 生成静态清单；如需自动编号可改用 Word 题注域 |
| 公式 | 第 4 章不变量等 6 处公式已转为 Word 公式对象（OMML），可直接编辑 |
| 附录 A 数据表 | 由脚本从 `test/e2e/benchmark/results/` 生成，数据更新后需重新生成 |

## 四、导出检查清单

- [ ] 目录层级与页码正确
- [ ] 图题在图下方、表题在表上方，编号连续（图 1-1 ~ 图 6-15、表 1-1 ~ 表 A-1）
- [ ] 正文无残留 Markdown 标记（`**`、`<sup>`、表格竖线）——已由脚本转换，导出后可用查找功能抽查
- [ ] 参考文献编号与正文上标一一对应（当前 40 条）
- [ ] 页边距 2.5 cm、A4、字体符合 AGENT-GUIDE §6
- [ ] 按 §7A 复查去 AI 味指标（加粗密度 ≤4/千字、列表占比 ≤15%）
