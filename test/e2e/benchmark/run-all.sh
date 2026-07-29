#!/usr/bin/env bash
# run-all.sh — 全量实验入口（遍历 A~E × 规模 × 负载场景 × 3 次重复）
#
# 用法:
#   ./run-all.sh [options]
#
# 选项:
#   --groups "a b"         指定要测试的组 (默认: "a b c d e")
#   --scales "s1 s2"       指定要测试的规模 (默认: "s3")
#   --workloads "w1 w2"    指定要测试的负载 (默认: 按组自动选择)
#   --runs 3               重复次数 (默认: 3)
#   --skip-deploy          跳过调度器部署（假设已部署）
#   --setup-nodes          自动创建/验证 KWOK 节点数量
#   --instances "1 2 3 5"  Scheduler 实例数列表，仅组 A/B 有效 (水平扩展测试)
#   --dry-run              仅打印执行计划，不实际运行
#
# 示例:
#   ./run-all.sh                                                  # 全量执行
#   ./run-all.sh --groups "a b" --scales "s2 s3" --workloads "w1 w2"
#   ./run-all.sh --dry-run                                        # 预览执行计划
#   ./run-all.sh --groups "a b" --scales "s3" --workloads "w3" --instances "1 2 3 5"  # 水平扩展测试
#   ./run-all.sh --groups "a b c d e" --scales "s2 s3" --workloads "w2 w3" --setup-nodes  # 所有调度器 × s2/s3 × w2/w3，自动创建节点

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/workloads/workload-matrix.sh"

# ── 默认参数 ──
# 注意: 不使用 Bash 内建特殊变量名 GROUPS，避免被当前用户组 ID 覆盖。
TARGET_GROUPS="a b c d e"
SCALES="s3"
RUNS="${EXPERIMENT_REPEATS}"
SKIP_DEPLOY=false
SETUP_NODES=false
DRY_RUN=false
CUSTOM_WORKLOADS=""
CUSTOM_INSTANCES=""

# ── 参数解析 ──
# --groups 会写入 TARGET_GROUPS（而不是 GROUPS）以规避 Bash 特殊变量冲突。
while [[ $# -gt 0 ]]; do
  case $1 in
    --groups)      TARGET_GROUPS="$2"; shift 2 ;;
    --scales)      SCALES="$2"; shift 2 ;;
    --workloads)   CUSTOM_WORKLOADS="$2"; shift 2 ;;
    --runs)        RUNS="$2"; shift 2 ;;
    --skip-deploy) SKIP_DEPLOY=true; shift ;;
    --setup-nodes) SETUP_NODES=true; shift ;;
    --instances)   CUSTOM_INSTANCES="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    *)             log_error "未知参数: $1"; exit 1 ;;
  esac
done

# ── 各组测试的负载场景 ──
# 组 A/B: 全部 W1-W7
# 组 C: 核心 W1-W4
# 组 D/E: W1-W4 + W6 (Gang)
get_workloads_for_group() {
  local group="$1"
  if [[ -n "$CUSTOM_WORKLOADS" ]]; then
    echo "$CUSTOM_WORKLOADS"
    return
  fi
  case "$group" in
    a|b) echo "w1 w2 w3 w4 w5 w6 w7" ;;
    c)   echo "w1 w2 w3 w4 w5" ;;
    d|e) echo "w1 w2 w3 w4 w6" ;;
    *)   echo "w1 w2 w3 w4" ;;
  esac
}

get_group_label() {
  local group="$1"
  local label="${GROUP_LABELS[$group]-}"
  if [[ -z "$label" ]]; then
    log_error "未知实验组: ${group} (可选: a b c d e)"
    exit 1
  fi
  echo "$label"
}

get_scale_nodes() {
  local scale="$1"
  local nodes="${SCALE_NODES[$scale]-}"
  if [[ -z "$nodes" ]]; then
    log_error "未知集群规模: ${scale} (可选: s1 s2 s3 s4 s5)"
    exit 1
  fi
  echo "$nodes"
}

validate_inputs() {
  local group
  local scale
  for group in $TARGET_GROUPS; do
    get_group_label "$group" >/dev/null
  done
  for scale in $SCALES; do
    get_scale_nodes "$scale" >/dev/null
  done
}

validate_inputs

# ── 计算总实验数 ──
total_experiments=0
for group in $TARGET_GROUPS; do
  workloads=$(get_workloads_for_group "$group")
  # 组 A/B 且指定了 --instances 时，每个 instance count 都算独立实验
  if [[ "$group" =~ ^[ab]$ ]] && [[ -n "$CUSTOM_INSTANCES" ]]; then
    inst_count=$(echo "$CUSTOM_INSTANCES" | wc -w | tr -d ' ')
  else
    inst_count=1
  fi
  for _ in $SCALES; do
    for _ in $workloads; do
      total_experiments=$((total_experiments + RUNS * inst_count))
    done
  done
done

separator "全量实验计划"
log_info "组: ${TARGET_GROUPS}"
log_info "规模: ${SCALES}"
if [[ -n "$CUSTOM_INSTANCES" ]]; then
  log_info "Scheduler 实例数: ${CUSTOM_INSTANCES} (仅组 A/B)"
fi
log_info "重复: ${RUNS} 次"
log_info "总实验数: ${total_experiments}"
echo ""

# ── 打印执行计划 ──
exp_index=0
for group in $TARGET_GROUPS; do
  workloads=$(get_workloads_for_group "$group")
  if [[ "$group" =~ ^[ab]$ ]] && [[ -n "$CUSTOM_INSTANCES" ]]; then
    inst_list="$CUSTOM_INSTANCES"
  else
    inst_list=""
  fi
  echo "  组 ${group} ($(get_group_label "$group")):"
  for scale in $SCALES; do
    echo "    规模 ${scale} ($(get_scale_nodes "$scale") 节点):"
    if [[ -n "$inst_list" ]]; then
      for inst in $inst_list; do
        echo "      Scheduler 实例数=${inst}:"
        for wl in $workloads; do
          for run in $(seq 1 "$RUNS"); do
            exp_index=$((exp_index + 1))
            printf "        [%3d/%3d] %s × %s × %s × inst%s × run%d\n" "$exp_index" "$total_experiments" "$group" "$scale" "$wl" "$inst" "$run"
          done
        done
      done
    else
      for wl in $workloads; do
        for run in $(seq 1 "$RUNS"); do
          exp_index=$((exp_index + 1))
          printf "      [%3d/%3d] %s × %s × %s × run%d\n" "$exp_index" "$total_experiments" "$group" "$scale" "$wl" "$run"
        done
      done
    fi
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

for group in $TARGET_GROUPS; do
  separator "部署组 ${group} ($(get_group_label "$group"))"

  # 确定该组的 instance 列表
  if [[ "$group" =~ ^[ab]$ ]] && [[ -n "$CUSTOM_INSTANCES" ]]; then
    inst_list="$CUSTOM_INSTANCES"
  else
    inst_list=""
  fi

  # ── 无 instance 变量的正常流程 ──
  if [[ -z "$inst_list" ]]; then
    if [[ "$SKIP_DEPLOY" != "true" ]]; then
      log_step "部署组 ${group} 调度器"
      bash "${SCRIPT_DIR}/schedulers/deploy-group-${group}.sh" || {
        log_error "组 ${group} 部署失败，跳过该组"
        continue
      }
      sleep 10
    fi

    workloads=$(get_workloads_for_group "$group")
    for scale in $SCALES; do
      separator "规模 ${scale} ($(get_scale_nodes "$scale") 节点)"
      for wl in $workloads; do
        for run in $(seq 1 "$RUNS"); do
          exp_index=$((exp_index + 1))
          separator "[${exp_index}/${total_experiments}] 组=${group} 规模=${scale} 负载=${wl} Run=#${run}"

          EXTRA_FLAGS=""
          [[ "$SETUP_NODES" == "true" ]] && EXTRA_FLAGS="--setup-nodes"

          if bash "${SCRIPT_DIR}/run-experiment.sh" "$group" "$scale" "$wl" "$run" $EXTRA_FLAGS; then
            log_info "✓ 实验成功: ${group}/${scale}/${wl}/run${run}"
          else
            log_error "✗ 实验失败: ${group}/${scale}/${wl}/run${run}"
            failed_experiments+=("${group}/${scale}/${wl}/run${run}")
          fi
          echo ""
        done
      done
    done
    continue
  fi

  # ── 有 instance 变量的水平扩展流程 (仅组 A/B) ──
  first_inst=true
  for inst in $inst_list; do
    separator "组 ${group} — ${inst} 个 Scheduler 实例"

    if [[ "$SKIP_DEPLOY" != "true" ]]; then
      if [[ "$first_inst" == "true" ]]; then
        log_step "部署组 ${group} 调度器 (${inst} 实例)"
        bash "${SCRIPT_DIR}/schedulers/deploy-group-${group}.sh" --instances "$inst" || {
          log_error "组 ${group} 部署失败，跳过该组"
          continue 2
        }
        first_inst=false
      else
        log_step "调整 Scheduler 实例数为 ${inst}"
        embedded_flag=""
        [[ "$group" == "a" ]] && embedded_flag="--embedded-binder"
        bash "${SCRIPT_DIR}/schedulers/scale-schedulers.sh" "$inst" $embedded_flag || {
          log_error "Scheduler 实例调整失败，跳过 inst=${inst}"
          continue
        }
      fi
      sleep 10
    fi

    workloads=$(get_workloads_for_group "$group")
    for scale in $SCALES; do
      separator "规模 ${scale} ($(get_scale_nodes "$scale") 节点) × ${inst} 实例"
      for wl in $workloads; do
        for run in $(seq 1 "$RUNS"); do
          exp_index=$((exp_index + 1))
          separator "[${exp_index}/${total_experiments}] 组=${group} 规模=${scale} 负载=${wl} inst=${inst} Run=#${run}"

          EXTRA_FLAGS="--instances $inst"
          [[ "$SETUP_NODES" == "true" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --setup-nodes"

          if bash "${SCRIPT_DIR}/run-experiment.sh" "$group" "$scale" "$wl" "$run" $EXTRA_FLAGS; then
            log_info "✓ 实验成功: ${group}/${scale}/${wl}/inst${inst}/run${run}"
          else
            log_error "✗ 实验失败: ${group}/${scale}/${wl}/inst${inst}/run${run}"
            failed_experiments+=("${group}/${scale}/${wl}/inst${inst}/run${run}")
          fi
          echo ""
        done
      done
    done
  done
done

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

# ── 汇总报告 ──
separator "全量实验完成"
success_count=$((total_experiments - ${#failed_experiments[@]}))
fail_count=${#failed_experiments[@]}

log_info "总耗时: $(format_duration $OVERALL_DURATION)"
log_info "实验总数: ${total_experiments}"
log_info "成功数: ${success_count}"
log_info "失败数: ${fail_count}"

if (( fail_count > 0 )); then
  log_warn "失败的实验:"
  for f in "${failed_experiments[@]}"; do
    echo "  - ${f}"
  done
fi

log_info ""
log_info "结果目录: ${RESULTS_DIR}/"

# ── 生成 Markdown 报告 ──
REPORT_TIME=$(date '+%Y-%m-%d_%H%M%S')
REPORT_FILE="${RESULTS_DIR}/report_${REPORT_TIME}.md"

{
  echo "# 实验报告"
  echo ""
  echo "- **生成时间**: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- **总耗时**: $(format_duration $OVERALL_DURATION)"
  echo "- **集群**: ${KIND_CLUSTER_NAME}"
  echo "- **实验总数**: ${total_experiments}"
  echo "- **成功**: ${success_count}"
  echo "- **失败**: ${fail_count}"
  echo ""

  echo "## 实验配置"
  echo ""
  echo "| 参数 | 值 |"
  echo "|------|------|"
  echo "| 实验组 | ${TARGET_GROUPS} |"
  echo "| 集群规模 | ${SCALES} |"
  echo "| 重复次数 | ${RUNS} |"
  echo "| 调度器 QPS | ${SCHEDULER_QPS} |"
  echo "| 调度器 Burst | ${SCHEDULER_BURST} |"
  echo "| 资源 requests | ${BENCH_SCHED_REQ_CPU} CPU / ${BENCH_SCHED_REQ_MEM} MEM |"
  echo "| 资源 limits | ${BENCH_SCHED_LIM_CPU} CPU / ${BENCH_SCHED_LIM_MEM} MEM |"
  echo "| Binder 资源 requests | ${BENCH_BINDER_REQ_CPU} CPU / ${BENCH_BINDER_REQ_MEM} MEM |"
  echo "| Binder 资源 limits | ${BENCH_BINDER_LIM_CPU} CPU / ${BENCH_BINDER_LIM_MEM} MEM |"
  echo "| Dispatcher 资源 requests | ${BENCH_DISPATCHER_REQ_CPU} CPU / ${BENCH_DISPATCHER_REQ_MEM} MEM |"
  echo "| Dispatcher 资源 limits | ${BENCH_DISPATCHER_LIM_CPU} CPU / ${BENCH_DISPATCHER_LIM_MEM} MEM |"
  if [[ -n "$CUSTOM_INSTANCES" ]]; then
    echo "| Scheduler 实例数 (组 A/B) | ${CUSTOM_INSTANCES} |"
  fi
  echo ""

  echo "## 实验明细"
  echo ""
  echo "| # | 组 | 规模 | 负载 | Run | 状态 |"
  echo "|---|---|------|------|-----|------|"

  detail_index=0
  for group in $TARGET_GROUPS; do
    workloads=$(get_workloads_for_group "$group")
    for scale in $SCALES; do
      for wl in $workloads; do
        for run in $(seq 1 "$RUNS"); do
          detail_index=$((detail_index + 1))
          exp_key="${group}/${scale}/${wl}/run${run}"
          status="✅ 成功"
          for f in "${failed_experiments[@]}"; do
            if [[ "$f" == "$exp_key" ]]; then
              status="❌ 失败"
              break
            fi
          done
          printf "| %d | %s (%s) | %s | %s | %d | %s |\n" \
            "$detail_index" "$group" "$(get_group_label "$group")" "$scale" "$wl" "$run" "$status"
        done
      done
    done
  done

  echo ""

  if (( fail_count > 0 )); then
    echo "## 失败列表"
    echo ""
    for f in "${failed_experiments[@]}"; do
      echo "- \`${f}\`"
    done
    echo ""
  fi

  echo "## 结果目录"
  echo ""
  echo '```'
  find "${RESULTS_DIR}" -mindepth 1 -maxdepth 3 -type d | sort | sed "s|${RESULTS_DIR}/||"
  echo '```'
  echo ""
  echo "---"
  echo "*由 run-all.sh 自动生成*"
} > "$REPORT_FILE"

log_info "报告已生成: ${REPORT_FILE}"

# ── Git 提交并推送到 dev ──
log_step "提交结果到 dev 分支"
(
  cd "${PROJECT_ROOT}"

  # 确保在 dev 分支
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" != "dev" ]]; then
    if git show-ref --verify --quiet refs/heads/dev; then
      git checkout dev
    else
      git checkout -b dev
    fi
  fi

  git add test/e2e/benchmark/results/
  git add "$REPORT_FILE"

  commit_msg="benchmark: 实验报告 ${REPORT_TIME} (${success_count}/${total_experiments} passed)"
  if git diff --cached --quiet; then
    log_info "无新变更需要提交"
  else
    git commit -m "$commit_msg"
    git push origin dev
    log_info "✓ 已推送到 origin/dev"
  fi

  # 如果之前不在 dev，切回原分支
  if [[ "$current_branch" != "dev" ]]; then
    git checkout "$current_branch"
  fi
)

log_info "下一步: 运行数据分析脚本生成图表"
