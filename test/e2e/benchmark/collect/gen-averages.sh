#!/usr/bin/env bash
# gen-averages.sh — 批量为所有 (group, scale, workload[, inst]) 组合生成 run 聚合结果
#
# 目录布局:
#   a/b 组 (分布式，有 scheduler 实例数维度):
#     results/{a,b}/{s}/{w}/inst{1,3}/run{1,2,3}/  →  results/{a,b}/{s}/{w}/inst{1,3}/avg/
#   c/d/e 组 (单调度器，无实例数维度):
#     results/{c,d,e}/{s}/{w}/run{1,2,3}/          →  results/{c,d,e}/{s}/{w}/avg/
#
# 逻辑：对每个 {s}/{w} 目录，若含 inst<N>/ 子目录则遍历每个 inst 层生成 avg；
# 否则退化到 bare run<N>/ 布局生成。
#
# 用法:
#   ./gen-averages.sh              # 用 mean 聚合 (默认，向后兼容)
#   ./gen-averages.sh --median     # 用 median 聚合 (推荐 benchmark 用；抗离群点)
#   ./gen-averages.sh --dry-run    # 只打印将处理的组合，不实际调用 python
#   ./gen-averages.sh --median --dry-run

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../results"
PLOT="${SCRIPT_DIR}/plot-results.py"

DRY_RUN=false
STAT="mean"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --median)  STAT="median" ;;
    --mean)    STAT="mean" ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$PLOT" ]]; then
  echo "错误: 找不到 $PLOT" >&2
  exit 1
fi

total=0
succeeded=0
skipped=0
failed=0

echo "=== 批量生成聚合结果 (stat=${STAT}) ==="
[[ "$DRY_RUN" == "true" ]] && echo "[dry-run] 模式：不会实际调用 python"
echo ""

# 处理一个"含 run1/2/3 的父目录"（无论是 wl_dir 本身还是 wl_dir/instN）
process_run_group() {
  local run_parent="$1"
  local rel_path="${run_parent#${RESULTS_DIR}/}"

  if [[ -d "$run_parent/run1" && -d "$run_parent/run2" && -d "$run_parent/run3" ]]; then
    total=$((total+1))
    local avg_dir="$run_parent/avg"
    echo "[gen ] $rel_path -> avg/"

    if [[ "$DRY_RUN" == "false" ]]; then
      if python3 "$PLOT" \
          "$run_parent/run1" "$run_parent/run2" "$run_parent/run3" \
          --average --std-band --stat "$STAT" \
          --output "$avg_dir"; then
        succeeded=$((succeeded+1))
      else
        echo "[FAIL] $rel_path" >&2
        failed=$((failed+1))
      fi
    else
      succeeded=$((succeeded+1))
    fi
  else
    echo "[warn] $rel_path 缺少 run1/2/3 之一，跳过"
    skipped=$((skipped+1))
  fi
}

for group_dir in "${RESULTS_DIR}"/{a,b,c,d,e}; do
  [[ -d "$group_dir" ]] || continue
  for scale_dir in "$group_dir"/s*/; do
    [[ -d "$scale_dir" ]] || continue
    for wl_dir in "$scale_dir"w*/; do
      [[ -d "$wl_dir" ]] || continue
      wl_dir="${wl_dir%/}"

      # 优先处理 inst<N>/ 子目录 (a/b 组)
      inst_found=false
      for inst_dir in "$wl_dir"/inst*/; do
        [[ -d "$inst_dir" ]] || continue
        inst_dir="${inst_dir%/}"
        process_run_group "$inst_dir"
        inst_found=true
      done

      # 无 inst<N>/ 时退化到 bare 布局 (c/d/e 组)
      if [[ "$inst_found" == "false" ]]; then
        process_run_group "$wl_dir"
      fi
    done
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
