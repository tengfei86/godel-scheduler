#!/bin/bash
# run-all.sh — 全量实验入口（遍历 A~E × 负载场景 × 3 次重复）
#
# 用法:
#   ./run-all.sh [options]
#
# 选项:
#   --groups "a b"         指定要测试的组 (默认: "a b c d e")
#   --workloads "w1 w2"    指定要测试的负载 (默认: 按组自动选择)
#   --runs 3               重复次数 (默认: 3)
#   --skip-deploy          跳过调度器部署（假设已部署）
#   --dry-run              仅打印执行计划，不实际运行
#
# 示例:
#   ./run-all.sh                                    # 全量执行
#   ./run-all.sh --groups "a b" --workloads "w1 w2" # 仅组 A/B + W1/W2
#   ./run-all.sh --dry-run                          # 预览执行计划

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/workloads/workload-matrix.sh"

# ── 默认参数 ──
GROUPS="a b c d e"
RUNS="${EXPERIMENT_REPEATS}"
SKIP_DEPLOY=false
DRY_RUN=false
CUSTOM_WORKLOADS=""

# ── 参数解析 ──
while [[ $# -gt 0 ]]; do
  case $1 in
    --groups)      GROUPS="$2"; shift 2 ;;
    --workloads)   CUSTOM_WORKLOADS="$2"; shift 2 ;;
    --runs)        RUNS="$2"; shift 2 ;;
    --skip-deploy) SKIP_DEPLOY=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    *)             log_error "未知参数: $1"; exit 1 ;;
  esac
done

# ── 各组测试的负载场景 ──
# 组 A/B: 全部 W1-W8
# 组 C: 核心 W1-W4
# 组 D/E: W1-W4 + W6 (Gang)
get_workloads_for_group() {
  local group="$1"
  if [[ -n "$CUSTOM_WORKLOADS" ]]; then
    echo "$CUSTOM_WORKLOADS"
    return
  fi
  case "$group" in
    a|b) echo "w1 w2 w3 w4 w5 w6 w7 w8" ;;
    c)   echo "w1 w2 w3 w4" ;;
    d|e) echo "w1 w2 w3 w4 w6" ;;
    *)   echo "w1 w2 w3 w4" ;;
  esac
}

# ── 计算总实验数 ──
total_experiments=0
for group in $GROUPS; do
  workloads=$(get_workloads_for_group "$group")
  for _ in $workloads; do
    total_experiments=$((total_experiments + RUNS))
  done
done

separator "全量实验计划"
log_info "组: ${GROUPS}"
log_info "重复: ${RUNS} 次"
log_info "总实验数: ${total_experiments}"
echo ""

# ── 打印执行计划 ──
exp_index=0
for group in $GROUPS; do
  workloads=$(get_workloads_for_group "$group")
  echo "  组 ${group} (${GROUP_LABELS[$group]}):"
  for wl in $workloads; do
    desc=$(get_workload_param "$wl" "desc")
    for run in $(seq 1 "$RUNS"); do
      exp_index=$((exp_index + 1))
      printf "    [%3d/%3d] %s × %s × run%d\n" "$exp_index" "$total_experiments" "$group" "$wl" "$run"
    done
  done
  echo ""
done

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN] 以上为执行计划，未实际运行"
  exit 0
fi

# ── 确认执行 ──
if [[ "${AUTO_CONFIRM:-0}" != "1" ]]; then
  read -rp "$(echo -e "${YELLOW}开始执行 ${total_experiments} 个实验？[y/N]${NC} ")" answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    log_info "已取消"
    exit 0
  fi
fi

# ── 执行 ──
OVERALL_START=$(date +%s)
exp_index=0
failed_experiments=()

for group in $GROUPS; do
  separator "部署组 ${group} (${GROUP_LABELS[$group]})"

  # 部署调度器
  if [[ "$SKIP_DEPLOY" != "true" ]]; then
    log_step "部署组 ${group} 调度器"
    bash "${SCRIPT_DIR}/schedulers/deploy-group-${group}.sh" || {
      log_error "组 ${group} 部署失败，跳过该组"
      continue
    }
    sleep 10
  fi

  # 执行该组所有负载场景
  workloads=$(get_workloads_for_group "$group")
  for wl in $workloads; do
    for run in $(seq 1 "$RUNS"); do
      exp_index=$((exp_index + 1))
      separator "[${exp_index}/${total_experiments}] 组=${group} 负载=${wl} Run=#${run}"

      if bash "${SCRIPT_DIR}/run-experiment.sh" "$group" "$wl" "$run"; then
        log_info "✓ 实验成功: ${group}/${wl}/run${run}"
      else
        log_error "✗ 实验失败: ${group}/${wl}/run${run}"
        failed_experiments+=("${group}/${wl}/run${run}")
      fi

      echo ""
    done
  done
done

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

# ── 汇总报告 ──
separator "全量实验完成"
log_info "总耗时: $(format_duration $OVERALL_DURATION)"
log_info "实验总数: ${total_experiments}"
log_info "成功数: $((total_experiments - ${#failed_experiments[@]}))"
log_info "失败数: ${#failed_experiments[@]}"

if (( ${#failed_experiments[@]} > 0 )); then
  log_warn "失败的实验:"
  for f in "${failed_experiments[@]}"; do
    echo "  - ${f}"
  done
fi

log_info ""
log_info "结果目录: ${RESULTS_DIR}/"
log_info "下一步: 运行数据分析脚本生成图表"
