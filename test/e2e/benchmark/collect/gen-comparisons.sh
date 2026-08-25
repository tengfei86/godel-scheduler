#!/usr/bin/env bash
# gen-comparisons.sh — 批量生成跨调度器组的对比图（按 scale × workload 组织）
#
# 依赖：gen-averages.sh 已经生成过每个 (group, scale, wl) 的 avg/ 目录。
# 遍历所有 (scale, wl) 组合，把该组合下所有存在 avg/ 的调度器组作为输入，
# 调用 plot-results.py --compare 生成跨组对比图，输出到 results/compare/{scale}_{wl}/。
#
# 用法:
#   ./gen-comparisons.sh              # 直接生成
#   ./gen-comparisons.sh --dry-run    # 只打印将处理的组合，不实际调用 python

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../results"
PLOT="${SCRIPT_DIR}/plot-results.py"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ ! -f "$PLOT" ]]; then
  echo "错误: 找不到 $PLOT" >&2
  exit 1
fi

SCALES="s2 s3"
WORKLOADS="w1 w2 w3"
TARGET_GROUPS="a b c d e"

total=0
succeeded=0
skipped=0
failed=0

echo "=== 批量生成跨组对比图 ==="
[[ "$DRY_RUN" == "true" ]] && echo "[dry-run] 模式：不会实际调用 python"
echo ""

for scale in $SCALES; do
  for wl in $WORKLOADS; do
    # 自动发现该 (scale, wl) 下哪些组已有 avg/
    input_dirs=()
    groups_present=""
    for g in $TARGET_GROUPS; do
      avg_dir="$RESULTS_DIR/$g/$scale/$wl/avg"
      if [[ -d "$avg_dir" ]]; then
        input_dirs+=("$avg_dir")
        groups_present+="$g "
      fi
    done

    # 少于 2 组则跳过（对比无意义）
    if (( ${#input_dirs[@]} < 2 )); then
      echo "[skip] $scale/$wl 只有 ${#input_dirs[@]} 组有 avg/，无法对比"
      skipped=$((skipped+1))
      continue
    fi

    out_dir="$RESULTS_DIR/compare/${scale}_${wl}"
    total=$((total+1))
    echo "[gen ] $scale/$wl (${#input_dirs[@]} 组: ${groups_present%% }) -> compare/${scale}_${wl}/"

    if [[ "$DRY_RUN" == "false" ]]; then
      if python3 "$PLOT" "${input_dirs[@]}" --compare --output "$out_dir"; then
        succeeded=$((succeeded+1))
      else
        echo "[FAIL] $scale/$wl" >&2
        failed=$((failed+1))
      fi
    else
      succeeded=$((succeeded+1))
    fi
  done
done

echo ""
echo "=== 汇总 ==="
echo "  待处理组合: $total"
echo "  成功:       $succeeded"
echo "  失败:       $failed"
echo "  跳过:       $skipped"

if (( failed > 0 )); then
  exit 1
fi
