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
REFERENCE_DOC=""
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

# ── 预处理：上标转换 ──
rm -rf build && mkdir -p build
for f in "${FILES[@]}"; do
  python3 - "$f" <<'PY'
import re, sys
f = sys.argv[1]
t = open(f"chapters/{f}", encoding="utf-8").read()
t = re.sub(r'<sup>\[([0-9,\s]+)\]</sup>', lambda m: '^\\[' + m.group(1) + '\\]^', t)
open(f"build/{f}", "w", encoding="utf-8").write(t)
PY
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

echo "导出完成：$(pwd)/thesis-preview.docx"
rm -rf build
