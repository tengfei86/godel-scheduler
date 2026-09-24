#!/usr/bin/env bash
# build-docx.sh — 将 chapters/ 下的 Markdown 导出为 Word 文档
#
# 用法：
#   bash build-docx.sh                    # 生成 thesis-preview.docx（默认样式）
#   bash build-docx.sh --reference <文件>  # 指定学校模板 docx 作为样式参考
#
# 说明：
#   1. 引用上标：正文中的 <sup>[N]</sup> 会被转换为 pandoc 上标语法 ^\[N\]^，
#      否则 docx 会丢失上标（Word 不识别 HTML 标签）；
#   2. 图片路径：脚本在临时 build/ 目录中执行，使正文的 ../figures/xxx.png 正确解析；
#   3. pandoc 位置：优先使用 PATH 中的 pandoc；若不存在，回退到工作区内的独立二进制。

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
THESIS_DIR="$(pwd)"

# ── 定位 pandoc（解析为绝对路径，避免后续 cd 失效）──
if command -v pandoc >/dev/null 2>&1; then
  PANDOC="$(command -v pandoc)"
else
  PANDOC="$(ls "${THESIS_DIR}"/../../../tools/pandoc/pandoc-*/bin/pandoc 2>/dev/null | head -1 || true)"
fi
if [[ -z "${PANDOC}" || ! -x "${PANDOC}" ]]; then
  echo "错误：未找到 pandoc。请安装（brew install pandoc）或放置于工作区 tools/pandoc/" >&2
  exit 1
fi

# ── 解析参数 ──
REFERENCE_DOC="${THESIS_DIR}/beihang-reference.docx"
if [[ "${1:-}" == "--reference" ]]; then
  REFERENCE_DOC="${2:?用法: build-docx.sh --reference <模板.docx>}"
  [[ -f "${REFERENCE_DOC}" ]] || { echo "错误：模板不存在 ${REFERENCE_DOC}" >&2; exit 1; }
fi

# ── 装订顺序（与学校规范一致）──
FILES=(
  00-abstract.md
  01-introduction.md
  02-related-work.md
  03-architecture.md
  04-consistency.md
  05-eno-optimization.md
  06-evaluation.md
  07-conclusion.md
  96-references.md
  98-appendix.md
  99-acknowledgements.md
)

# ── 参考模板：不存在则自动生成 ──
if [[ ! -f "${REFERENCE_DOC}" ]]; then
  echo "参考模板不存在，正在生成：${REFERENCE_DOC}"
  python3 "${THESIS_DIR}/make-reference.py"
fi

# ── 预处理：上标转换 ──
rm -rf build && mkdir -p build
FIRST=1
for f in "${FILES[@]}"; do
  python3 - "$f" "$FIRST" <<'PY'
import re, sys
f, first = sys.argv[1], sys.argv[2] == "1"
t = open(f"chapters/{f}", encoding="utf-8").read()
# 引用上标：<sup>[N]</sup> → pandoc 上标语法
t = re.sub(r'<sup>\[([0-9,\s]+)\]</sup>', lambda m: '^\\[' + m.group(1) + '\\]^', t)
# 每章/每部分另起一页：在一级标题前插入分页符（文档第一个标题除外）
# 注意：必须跳过围栏代码块内的行——代码块里的 "# ..." 是 shell 注释而非标题，
# 若在此处插入 OpenXML 原始块，pandoc 会把它当作代码块的字面内容渲染出来
# （2026-09-24：§6.6 的 run-6.6-all.sh 示例曾被插入 ```{=openxml} 垃圾行）。
BRK = '```{=openxml}\n<w:p><w:r><w:br w:type="page"/></w:r></w:p>\n```\n\n'
lines, out = t.split('\n'), []
in_fence = False
for ln in lines:
    if ln.lstrip().startswith('```'):
        in_fence = not in_fence
        out.append(ln)
        continue
    if not in_fence and re.match(r'^# ', ln):
        if not first:
            out.append(BRK.rstrip('\n'))
        first = False
    out.append(ln)
open(f"build/{f}", "w", encoding="utf-8").write('\n'.join(out))
PY
  FIRST=0
done

# ── 导出 ──
cd build
ARGS=( "${FILES[@]}" -o ../thesis-preview.docx --toc --toc-depth=2 -M toc-title=目录 )
if [[ -n "${REFERENCE_DOC}" ]]; then
  # 统一转为绝对路径，避免相对 build/ 解析出错
  case "${REFERENCE_DOC}" in
    /*) REF_ABS="${REFERENCE_DOC}" ;;
    *)  REF_ABS="${THESIS_DIR}/${REFERENCE_DOC}" ;;
  esac
  ARGS+=( --reference-doc="${REF_ABS}" )
fi
"${PANDOC}" "${ARGS[@]}"
cd ..

# ── 后处理：北航格式（表格铺满版心、表内五号居中、分节+页眉页码）──
# 细节见 postprocess-docx.py：
#   - 表格 tblGrid/tblW 统一为版心 16.00 cm（pandoc 默认约 13.96 cm，表格没顶到页边距）
#   - 表内段落由 Compact 改 TableCell（五号宋体居中）
#   - 分节：摘要/目录 用大写罗马数字页码且无页眉；正文奇数页页眉「北京航空航天大学硕士学位论文」、
#     偶数页为章标题；参考文献/附录/致谢 不分奇偶，页眉为篇名；页码阿拉伯数字从 1 起
python3 postprocess-docx.py thesis-preview.docx

echo "导出完成：$(pwd)/thesis-preview.docx"
rm -rf build
