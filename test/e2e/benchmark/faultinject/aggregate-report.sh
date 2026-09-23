#!/usr/bin/env bash
# aggregate-report.sh — 把 layer0/layer3 所有 run 的判据结果 + 关键指标聚合成
# 一份带时戳的 Markdown, 落在 results/faultinject/ 顶层, 用于论文引用。
#
# 用法:
#   aggregate-report.sh [results/faultinject]
#   ROOT=<dir> aggregate-report.sh    # 用环境变量指定根目录
#
# 输出:
#   <root>/report-YYYYMMDD-HHMMSS.md
#     ├── 元数据 (集群规模, 时刻, ENO commit, 参数)
#     ├── 每个 run 的完整 verify 结果 + fault-summary 关键行
#     └── 分层聚合统计 (通过率, 恢复时长, 不变量 I 状态)
#
# 幂等: 每次调用都写新文件, 不覆盖旧的; 便于横向对比不同实验批次。

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${BENCHMARK_DIR}/config.sh" 2>/dev/null || true

ROOT="${1:-${ROOT:-${RESULTS_DIR:-${BENCHMARK_DIR}/results}/faultinject}}"
if [[ ! -d "$ROOT" ]]; then
  echo "错误: 目录不存在: $ROOT" >&2
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT="${ROOT}/report-${TS}.md"

echo "# 故障注入实验汇总报告" > "$OUT"
{
  echo ""
  echo "- 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)  (host: $(hostname))"
  echo "- 结果根目录: \`${ROOT}\`"
  if command -v git >/dev/null 2>&1 && [[ -d "${BENCHMARK_DIR}/../../../.git" ]]; then
    local_head="$(cd "${BENCHMARK_DIR}/../../.." && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    local_dirty=""
    (cd "${BENCHMARK_DIR}/../../.." && git diff --quiet 2>/dev/null) || local_dirty=" (dirty)"
    echo "- ENO 提交: \`${local_head}${local_dirty}\`"
  fi
  echo ""
} >> "$OUT"

# ── 分层聚合: 收集每个 run 的判定结果 + 关键指标 ──
declare -a all_runs
mapfile -t all_runs < <(find "$ROOT" -mindepth 3 -maxdepth 4 -name "inject-manifest.json" 2>/dev/null | sort)

if (( ${#all_runs[@]} == 0 )); then
  echo "> 未发现任何 run 目录 (需要 \`layer<N>/<group_scale_workload_instN>/run<K>/inject-manifest.json\`)。" >> "$OUT"
  echo "写入: $OUT"
  exit 0
fi

# 汇总表 - 每 run 一行
{
  echo "## 一览"
  echo ""
  echo "| Layer | Run | Scale/Load | 不变量 I | 判据通过 | 恢复(s) | 备注 |"
  echo "|-------|-----|-----------|---------|---------|--------|------|"
} >> "$OUT"

L0_PASS=0; L0_FAIL=0; L3_PASS=0; L3_FAIL=0
for manifest in "${all_runs[@]}"; do
  run_dir="$(dirname "$manifest")"
  layer=$(python3 -c "import json; print(json.load(open('$manifest')).get('layer',''))" 2>/dev/null || echo "?")
  rel_run="${run_dir#$ROOT/}"

  # 从 metadata.txt 抓关键字段
  meta="${run_dir}/metadata.txt"
  scale=$(grep -E '^scale=' "$meta" 2>/dev/null | cut -d= -f2)
  workload=$(grep -E '^workload=' "$meta" 2>/dev/null | cut -d= -f2)
  total_pods=$(grep -E '^total=' "$meta" 2>/dev/null | cut -d= -f2)
  bound=$(grep -E '^final_scheduled_pods=' "$meta" 2>/dev/null | cut -d= -f2)
  # 恢复时长 (Layer 3): restored_ts - killed_ts
  recover=""
  if [[ "$layer" == "layer3" ]]; then
    recover=$(python3 -c "
import json
m = json.load(open('$manifest'))
r = m.get('restored_ts'); k = m.get('killed_ts')
print(r - k if r and k else '')
" 2>/dev/null || echo "")
  fi

  # 从 verify.txt 抓通过项
  verify="${run_dir}/plots/verify.txt"
  passed_line="N/A"
  invariant="?"
  if [[ -f "$verify" ]]; then
    passed_line=$(grep -oE '通过 [0-9]+ / [0-9]+ 项' "$verify" 2>/dev/null | head -1)
    passed_line="${passed_line:-N/A}"
    if grep -q 'unbound=0.*dup=0.*empty_name=0' "$verify" 2>/dev/null; then
      invariant="✅"
    else
      invariant="❌"
    fi
    if grep -q '最终判定: ✅' "$verify" 2>/dev/null; then
      case "$layer" in layer0) L0_PASS=$((L0_PASS+1));; layer3) L3_PASS=$((L3_PASS+1));; esac
    else
      case "$layer" in layer0) L0_FAIL=$((L0_FAIL+1));; layer3) L3_FAIL=$((L3_FAIL+1));; esac
    fi
  else
    invariant="?"
    case "$layer" in layer0) L0_FAIL=$((L0_FAIL+1));; layer3) L3_FAIL=$((L3_FAIL+1));; esac
  fi
  note="${bound:-?}/${total_pods:-?} bound"

  echo "| ${layer} | \`${rel_run}\` | ${scale:-?}/${workload:-?} | ${invariant} | ${passed_line} | ${recover:-} | ${note} |" >> "$OUT"
done

{
  echo ""
  echo "## 分层聚合"
  echo ""
  echo "| Layer | 通过 | 未通过 |"
  echo "|-------|------|--------|"
  echo "| Layer 0 | ${L0_PASS} | ${L0_FAIL} |"
  echo "| Layer 3 | ${L3_PASS} | ${L3_FAIL} |"
  echo ""
  echo "## 各 run 详细"
  echo ""
} >> "$OUT"

# 每个 run 一段 —— 完整 verify.txt + fault-summary.py 的头
for manifest in "${all_runs[@]}"; do
  run_dir="$(dirname "$manifest")"
  rel_run="${run_dir#$ROOT/}"
  verify="${run_dir}/plots/verify.txt"
  summary="${run_dir}/plots/summary.txt"

  {
    echo "### \`${rel_run}\`"
    echo ""
    echo "#### verify.py"
    echo ""
    echo '```text'
    if [[ -f "$verify" ]]; then cat "$verify"; else echo "(missing)"; fi
    echo '```'
    echo ""
    if [[ -f "$summary" ]]; then
      echo "#### fault-summary.py"
      echo ""
      echo '```text'
      cat "$summary"
      echo '```'
      echo ""
    fi
  } >> "$OUT"
done

echo "写入报告: $OUT"
