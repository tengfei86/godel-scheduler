#!/usr/bin/env bash
# gen-averages.sh — 批量为所有 (group, scale, workload) 组合生成 run 平均结果
#
# 遍历 results/{a,b,c,d,e}/s*/w*/ 目录，对每个同时有 run1/run2/run3 的组合，
# 调用 plot-results.py --average --std-band 生成 {workload}/avg/ 目录。
#
# 用法:
#   ./gen-averages.sh              # 直接生成
#   ./gen-averages.sh --dry-run    # 只打印将处理的组合，不实际调用 python

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

total=0
succeeded=0
skipped=0
failed=0

echo "=== 批量生成平均结果 ==="
[[ "$DRY_RUN" == "true" ]] && echo "[dry-run] 模式：不会实际调用 python"
echo ""

for group_dir in "${RESULTS_DIR}"/{a,b,c,d,e}; do
  [[ -d "$group_dir" ]] || continue
  for scale_dir in "$group_dir"/s*/; do
    [[ -d "$scale_dir" ]] || continue
    for wl_dir in "$scale_dir"w*/; do
      [[ -d "$wl_dir" ]] || continue

      # 去掉尾部斜杠，方便日志显示
      wl_dir="${wl_dir%/}"

      if [[ -d "$wl_dir/run1" && -d "$wl_dir/run2" && -d "$wl_dir/run3" ]]; then
        total=$((total+1))
        avg_dir="$wl_dir/avg"
        rel_path="${wl_dir#${RESULTS_DIR}/}"
        echo "[gen ] $rel_path -> avg/"

        if [[ "$DRY_RUN" == "false" ]]; then
          if python3 "$PLOT" \
              "$wl_dir/run1" "$wl_dir/run2" "$wl_dir/run3" \
              --average --std-band \
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
        rel_path="${wl_dir#${RESULTS_DIR}/}"
        echo "[warn] $rel_path 缺少 run1/2/3 之一，跳过"
        skipped=$((skipped+1))
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
