#!/usr/bin/env bash
# gen-comparisons.sh — 批量生成跨调度器组的对比图（按 scale × workload × inst 组织）
#
# 依赖：gen-averages.sh 已经生成过每个组的 avg/ 目录。
#
# 数据布局：
#   a/b 组 avg 路径:  results/{a,b}/{s}/{w}/inst{1,3}/avg/
#   c/d/e 组 avg 路径: results/{c,d,e}/{s}/{w}/avg/         (无 inst 层)
#
# 生成两类对比图:
#   1. 单实例基线 (inst=1):
#      - a/b 用 inst1/avg，c/d/e 用 bare avg  → 五组横向对比
#      - 输出: results/compare/{s}_{w}/
#   2. 多实例扩展 (inst=3):
#      - 仅 a/b 用 inst3/avg (c/d/e 单调度器架构无此维度)
#      - 输出: results/compare/{s}_{w}_inst3/
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

SCALES="s1 s2 s3 s4"
WORKLOADS="w1 w2 w3 w4 w5 w6 w7"
TARGET_GROUPS="a b c d e"

total=0
succeeded=0
skipped=0
failed=0

echo "=== 批量生成跨组对比图 ==="
[[ "$DRY_RUN" == "true" ]] && echo "[dry-run] 模式：不会实际调用 python"
echo ""

# 给一个 (group, scale, wl, inst) 计算对应的 avg 路径
# inst 取 "1" (单实例基线) 或 "3" (多实例扩展)
avg_path_for_group() {
  local group="$1" scale="$2" wl="$3" inst="$4"
  case "$group" in
    a|b)
      echo "$RESULTS_DIR/$group/$scale/$wl/inst${inst}/avg"
      ;;
    c|d|e)
      # 单调度器组只在 inst=1 场景纳入基线对比 (bare 布局)
      if [[ "$inst" == "1" ]]; then
        echo "$RESULTS_DIR/$group/$scale/$wl/avg"
      fi
      ;;
  esac
}

# 处理一个 (scale, wl, inst) 组合：收集所有有效 avg，调用 plot-results.py --compare
process_comparison() {
  local scale="$1" wl="$2" inst="$3" out_suffix="$4"
  local input_dirs=()
  local groups_present=""

  for g in $TARGET_GROUPS; do
    local avg
    avg=$(avg_path_for_group "$g" "$scale" "$wl" "$inst")
    if [[ -n "$avg" && -d "$avg" ]]; then
      input_dirs+=("$avg")
      groups_present+="$g "
    fi
  done

  if (( ${#input_dirs[@]} < 2 )); then
    echo "[skip] $scale/$wl inst=$inst 只有 ${#input_dirs[@]} 组有 avg/，无法对比"
    skipped=$((skipped+1))
    return
  fi

  local out_dir="$RESULTS_DIR/compare/${scale}_${wl}${out_suffix}"
  total=$((total+1))
  echo "[gen ] $scale/$wl inst=$inst (${#input_dirs[@]} 组: ${groups_present%% }) -> compare/${scale}_${wl}${out_suffix}/"

  if [[ "$DRY_RUN" == "false" ]]; then
    if python3 "$PLOT" "${input_dirs[@]}" --compare --output "$out_dir"; then
      succeeded=$((succeeded+1))
    else
      echo "[FAIL] $scale/$wl inst=$inst" >&2
      failed=$((failed+1))
    fi
  else
    succeeded=$((succeeded+1))
  fi
}

for scale in $SCALES; do
  for wl in $WORKLOADS; do
    # 1. 单实例基线对比 (a/b inst1/avg + c/d/e bare avg)
    process_comparison "$scale" "$wl" "1" ""

    # 2. 多实例扩展对比 (仅 a/b inst3/avg)
    process_comparison "$scale" "$wl" "3" "_inst3"
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
