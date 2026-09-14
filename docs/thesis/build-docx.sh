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
  00b-list-of-figures-tables.md
  00c-symbols-abbreviations.md
  01-introduction.md
  02-related-work.md
  03-architecture.md
  04-consistency.md
  05-eno-optimization.md
  06-evaluation.md
  07-conclusion.md
  96-references.md
  97-achievements.md
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
BRK = '```{=openxml}\n<w:p><w:r><w:br w:type="page"/></w:r></w:p>\n```\n\n'
lines, out = t.split('\n'), []
for ln in lines:
    if re.match(r'^# ', ln):
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

# ── 后处理：表格内文字改为五号居中（TableCell 样式）──
python3 - <<'PY'
import re, zipfile, shutil
src = "thesis-preview.docx"
tmp = "_pp"
shutil.rmtree(tmp, ignore_errors=True)
with zipfile.ZipFile(src) as z:
    z.extractall(tmp)
p = f"{tmp}/word/document.xml"
x = open(p, encoding="utf-8").read()
def fix_tbl(m):
    return re.sub(r'<w:pStyle w:val="Compact"\s*/>', '<w:pStyle w:val="TableCell"/>', m.group(0))
x2 = re.sub(r"<w:tbl>.*?</w:tbl>", fix_tbl, x, flags=re.S)
open(p, "w", encoding="utf-8").write(x2)
with zipfile.ZipFile(src, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(__import__("pathlib").Path(tmp).rglob("*")):
        if f.is_file():
            z.write(f, f.relative_to(tmp))
shutil.rmtree(tmp, ignore_errors=True)
print("后处理完成：表格内文字已套用五号居中样式")
PY

echo "导出完成：$(pwd)/thesis-preview.docx"
rm -rf build
