#!/usr/bin/env bash
# export-figures.sh — 批量将 .mmd 源码导出为 PDF/PNG/SVG
#
# 前置依赖:
#   npm install -g @mermaid-js/mermaid-cli
#   （首次运行 puppeteer 会自动下载 Chromium）
#
# 用法:
#   cd docs/performance/figures
#   bash export-figures.sh              # 导出全部 .mmd
#   bash export-figures.sh fig4-1-*     # 只导出匹配的
#
# 输出: 同目录下 <name>.pdf / <name>.png / <name>.svg 三份

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v mmdc &>/dev/null; then
  echo "错误: 未找到 mmdc。请先安装: npm install -g @mermaid-js/mermaid-cli"
  exit 1
fi

PATTERN="${1:-*.mmd}"

for src in $PATTERN; do
  [[ -f "$src" ]] || continue
  name="${src%.mmd}"
  echo "→ 导出 ${name}"

  mmdc -i "$src" -o "${name}.pdf" -b transparent 2>&1 | grep -v "^$" || true
  mmdc -i "$src" -o "${name}.png" -b white -w 1600 2>&1 | grep -v "^$" || true
  mmdc -i "$src" -o "${name}.svg" -b transparent 2>&1 | grep -v "^$" || true

  echo "  [ok] ${name}.{pdf,png,svg}"
done

echo ""
echo "完成。产物:"
ls -la *.pdf *.png *.svg 2>/dev/null | awk '{print "  " $NF " (" $5 " bytes)"}'
